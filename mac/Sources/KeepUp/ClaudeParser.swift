import Foundation

/// Turns chatbox text ("strategy essay due fri 23:59", or a whole pasted
/// syllabus) into items via the Claude API. Swift has no official
/// Anthropic SDK, so this is a plain HTTPS call. Mirrors `parseWithClaude`
/// in web/app.js — keep the prompt and schema in step.
enum ClaudeParser {
    struct Parsed: Decodable, Identifiable {
        let id = UUID()
        var title: String
        var dueDate: String
        var dueTime: String
        var place: String
        var course: String
        var kind: String
        var notes: String

        enum CodingKeys: String, CodingKey {
            case title, place, course, kind, notes
            case dueDate = "due_date"
            case dueTime = "due_time"
        }

        func toItem() -> Item {
            var item = Item()
            item.title = title
            item.place = place
            item.course = course
            item.kind = Item.Kind(rawValue: kind) ?? .todo
            item.notes = notes
            (item.due, item.allDay) = Due.make(dateString: dueDate, timeString: dueTime)
            return item
        }
    }

    private struct Envelope: Decodable { let items: [Parsed] }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct APIError: Decodable { let message: String }
        let content: [Block]?
        let stopReason: String?
        let error: APIError?

        enum CodingKeys: String, CodingKey {
            case content, error
            case stopReason = "stop_reason"
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "due_date": ["type": "string"],
                        "due_time": ["type": "string"],
                        "place": ["type": "string"],
                        "course": ["type": "string"],
                        "kind": ["type": "string", "enum": ["assignment", "exam", "event", "todo"]],
                        "notes": ["type": "string"],
                    ],
                    "required": ["title", "due_date", "due_time", "place", "course", "kind", "notes"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["items"],
        "additionalProperties": false,
    ]

    private static func systemPrompt(knownCourses: [String]) -> String {
        let now = Date()
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_GB")
        day.dateFormat = "EEEE d MMMM yyyy"
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let courseHint = knownCourses.isEmpty ? ""
            : " — reuse one of these exact names when it matches: \(knownCourses.joined(separator: ", "))"
        return """
        You turn quick notes, or text pasted from a course page, into to-do items for a student at HEC Paris.

        Right now it is \(day.string(from: now)), \(time.string(from: now)) (\(TimeZone.current.identifier)).

        - A short note is one item. Pasted course material (syllabus, assignment list, announcement) can contain many: return one item per deadline, exam, presentation or deliverable. Skip anything dated before today and general information that is not something to do or attend.
        - title: short and concrete, at most about 6 words (e.g. "Corporate Finance case write-up"). No dates in the title.
        - due_date: YYYY-MM-DD. Resolve relative dates ("fri", "next Tuesday", "in 2 weeks") to the next matching future date. Empty string if there is no date.
        - due_time: 24h HH:MM if a time is given, else empty string.
        - place: room or location if mentioned, else empty string.
        - course: the course name if one is identifiable\(courseHint); else empty string.
        - kind: assignment (graded deliverable), exam (exam, quiz, midterm, test), event (meeting, class, social), or todo.
        - notes: one line of useful detail (weight, format, submission method, who to bring), else empty string.
        """
    }

    static func parse(_ text: String, knownCourses: [String]) async throws -> [Parsed] {
        let apiKey = Pref.string(Pref.claudeKey)
        guard !apiKey.isEmpty else {
            throw Failure("Add your Claude API key in Settings (⌘,) first.")
        }

        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "system": systemPrompt(knownCourses: knownCourses),
            "messages": [["role": "user", "content": text]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        guard (200..<300).contains(status) else {
            throw Failure(decoded?.error?.message ?? "Claude error \(status)")
        }
        switch decoded?.stopReason {
        case "refusal": throw Failure("Claude declined to parse that text.")
        case "max_tokens": throw Failure("That was too long to parse in one go — try pasting less.")
        default: break
        }
        guard let text = decoded?.content?.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8) else {
            throw Failure("Claude returned no result.")
        }
        return try JSONDecoder().decode(Envelope.self, from: json).items
    }
}
