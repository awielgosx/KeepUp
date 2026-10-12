import AppKit
import Foundation

/// User settings, stored in UserDefaults on this Mac only.
enum Pref {
    static let claudeKey = "claudeKey"
    static let supaUrl = "supaUrl"
    static let supaAnon = "supaAnon"
    static let syncKey = "syncKey"
    static let theme = "theme"            // "auto" | "dark" | "light"
    static let widgetOn = "widgetOn"

    static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Owns the item list: local JSON cache in Application Support plus
/// Supabase sync (push dirty items, then pull everything; last write wins
/// on `updated_at`) — the same algorithm the web app uses.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var items: [Item] = []
    @Published private(set) var syncState: SyncState = .off

    enum SyncState: Equatable {
        case off, ok(Date), failed(String)

        var description: String {
            switch self {
            case .off: return "Sync not configured"
            case .ok(let d): return "Synced \(d.formatted(date: .omitted, time: .shortened))"
            case .failed(let m): return "Sync failed: \(m)"
            }
        }
    }

    private var dirty: Set<UUID> = []
    private var syncing = false
    private var timer: Timer?
    private var pendingSync: DispatchWorkItem?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeepUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("items.json")
    }()

    private struct Snapshot: Codable {
        var items: [Item]
        var dirty: [UUID]
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? KeepUpJSON.decoder.decode(Snapshot.self, from: data) {
            items = snap.items
            dirty = Set(snap.dirty)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in Store.shared.sync() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in Store.shared.sync() }
        }
    }

    // MARK: Queries

    var openItems: [Item] { items.openSorted() }

    var doneItems: [Item] {
        items.filter { !$0.deleted && $0.done }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var courses: [String] {
        Array(Set(items.filter { !$0.deleted }.map(\.course).filter { !$0.isEmpty })).sorted()
    }

    // MARK: Mutations

    func upsert(_ item: Item) {
        var item = item
        item.updatedAt = Date()
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        dirty.insert(item.id)
        persist()
        scheduleSync(after: 0.8)
    }

    func add(_ newItems: [Item]) {
        for var item in newItems {
            item.updatedAt = Date()
            items.append(item)
            dirty.insert(item.id)
        }
        persist()
        scheduleSync(after: 0.3)
    }

    func toggleDone(_ item: Item) {
        var copy = item
        copy.done.toggle()
        upsert(copy)
    }

    func delete(_ item: Item) {
        var copy = item
        copy.deleted = true
        upsert(copy)
    }

    /// After (re)configuring sync, push everything we have so a fresh
    /// database starts out with this Mac's items.
    func markAllDirty() {
        dirty = Set(items.map(\.id))
        persist()
        scheduleSync(after: 0)
    }

    private func persist() {
        let snap = Snapshot(items: items, dirty: Array(dirty))
        if let data = try? KeepUpJSON.encoder.encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Sync

    func scheduleSync(after seconds: Double) {
        pendingSync?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in Store.shared.sync() } }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func sync() {
        let base = Pref.string(Pref.supaUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let anon = Pref.string(Pref.supaAnon)
        let key = Pref.string(Pref.syncKey)
        guard !base.isEmpty, !anon.isEmpty, !key.isEmpty, let url = URL(string: base + "/rest/v1/items") else {
            syncState = .off
            return
        }
        guard !syncing else { return }
        syncing = true

        let toPush = items.filter { dirty.contains($0.id) }
        Task {
            defer { syncing = false }
            do {
                if !toPush.isEmpty {
                    var req = Self.request(url.appending(queryItems: [URLQueryItem(name: "on_conflict", value: "id")]), anon: anon, key: key)
                    req.httpMethod = "POST"
                    req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
                    req.httpBody = try KeepUpJSON.encoder.encode(toPush)
                    try await Self.send(req)
                    // Only clear what we pushed and hasn't changed again since.
                    for pushed in toPush where items.first(where: { $0.id == pushed.id })?.updatedAt == pushed.updatedAt {
                        dirty.remove(pushed.id)
                    }
                }
                let pullReq = Self.request(url.appending(queryItems: [URLQueryItem(name: "select", value: "*")]), anon: anon, key: key)
                let data = try await Self.send(pullReq)
                let remote = try KeepUpJSON.decoder.decode([Item].self, from: data)
                merge(remote)
                syncState = .ok(Date())
            } catch {
                syncState = .failed(error.localizedDescription)
            }
        }
    }

    private func merge(_ remote: [Item]) {
        var byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote {
            if let local = byId[r.id] {
                if !dirty.contains(r.id) && r.updatedAt > local.updatedAt { byId[r.id] = r }
            } else {
                byId[r.id] = r
            }
        }
        let merged = Array(byId.values)
        if merged != items {
            items = merged
            persist()
        }
    }

    private static func request(_ url: URL, anon: String, key: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.setValue(key, forHTTPHeaderField: "x-keepup-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        return req
    }

    @discardableResult
    private static func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "KeepUp", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(status) \(body.prefix(120))"])
        }
        return data
    }
}
