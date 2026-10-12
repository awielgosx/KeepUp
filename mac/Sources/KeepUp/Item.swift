import Foundation

/// One to-do / deadline / event. Field names match the Supabase `items`
/// table (see supabase/schema.sql) and the phone web app, so the same JSON
/// moves between all three unchanged.
struct Item: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var due: Date? = nil
    var allDay: Bool = false
    var place: String = ""
    var course: String = ""
    var kind: Kind = .todo
    var notes: String = ""
    var done: Bool = false
    var deleted: Bool = false
    var updatedAt: Date = Date()

    enum Kind: String, Codable, CaseIterable {
        case todo, assignment, exam, event

        var label: String {
            switch self {
            case .todo: return "To-do"
            case .assignment: return "Assignment"
            case .exam: return "Exam"
            case .event: return "Event"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, due, place, course, kind, notes, done, deleted
        case allDay = "all_day"
        case updatedAt = "updated_at"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        course = try c.decodeIfPresent(String.self, forKey: .course) ?? ""
        kind = Kind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .todo
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(due, forKey: .due) // explicit null so clearing a date syncs
        try c.encode(allDay, forKey: .allDay)
        try c.encode(place, forKey: .place)
        try c.encode(course, forKey: .course)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(notes, forKey: .notes)
        try c.encode(done, forKey: .done)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - JSON

enum KeepUpJSON {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Accepts both `2026-10-16T21:59:00.000Z` (browsers) and
    /// `2026-10-16T21:59:00+00:00` (Postgres), with or without fractions
    /// (Postgres sends microseconds, which ISO8601DateFormatter can't
    /// parse, so extra digits are trimmed to milliseconds first).
    static func parseDate(_ s: String) -> Date? {
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let afterDot = s[s.index(after: dot)...]
        let digits = afterDot.prefix { $0.isNumber }
        let rest = String(afterDot.dropFirst(digits.count))
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return withFraction.date(from: String(s[..<dot]) + "." + millis + rest)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
            }
            return date
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(withFraction.string(from: date))
        }
        return e
    }()
}

// MARK: - Due dates, buckets, labels

enum Due {
    /// All-day items live at 23:59 local so they sort after timed items
    /// on the same day — same convention as the web app.
    static func make(day: Date, time: Date?) -> (Date, Bool) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        if let time {
            let t = cal.dateComponents([.hour, .minute], from: time)
            comps.hour = t.hour
            comps.minute = t.minute
            return (cal.date(from: comps) ?? day, false)
        }
        comps.hour = 23
        comps.minute = 59
        return (cal.date(from: comps) ?? day, true)
    }

    /// Parses Claude's "YYYY-MM-DD" + "HH:MM" strings.
    static func make(dateString: String, timeString: String) -> (Date?, Bool) {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return (nil, false) }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        let hm = timeString.split(separator: ":").compactMap { Int($0) }
        if hm.count == 2 {
            comps.hour = hm[0]
            comps.minute = hm[1]
            return (Calendar.current.date(from: comps), false)
        }
        comps.hour = 23
        comps.minute = 59
        return (Calendar.current.date(from: comps), true)
    }

    enum Bucket: String, CaseIterable {
        case overdue = "Overdue", today = "Today", tomorrow = "Tomorrow"
        case thisWeek = "This week", later = "Later", noDate = "No date"
    }

    static func dayOffset(_ date: Date, from now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func bucket(_ item: Item, now: Date = Date()) -> Bucket {
        guard let due = item.due else { return .noDate }
        if due < now { return .overdue }
        switch dayOffset(due, from: now) {
        case 0: return .today
        case 1: return .tomorrow
        case 2..<7: return .thisWeek
        default: return .later
        }
    }

    enum Tone { case normal, today, overdue }

    static func label(_ item: Item, now: Date = Date()) -> (text: String, tone: Tone) {
        guard let due = item.due else { return ("", .normal) }
        let days = dayOffset(due, from: now)
        let time = item.allDay ? "" : " " + format(due, "HH:mm")
        let text: String
        switch days {
        case 0: text = "Today" + time
        case 1: text = "Tomorrow" + time
        case -1: text = "Yesterday" + time
        case 2..<7: text = format(due, "EEE") + time
        default: text = format(due, "d MMM") + time
        }
        let tone: Tone = (!item.done && due < now) ? .overdue : (days == 0 ? .today : .normal)
        return (text, tone)
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

extension Array where Element == Item {
    /// Open items, soonest first; undated ones last, newest first.
    func openSorted() -> [Item] {
        filter { !$0.deleted && !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, nil): return a.updatedAt > b.updatedAt
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}
