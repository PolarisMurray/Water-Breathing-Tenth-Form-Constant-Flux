import SwiftUI

/// Single source of truth for the UI. Mirrors the artifact database, keeps an offline cache,
/// applies edits optimistically and queues writes until the bridge is ready.
@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var days: [String: DayDoc] = [:]
    @Published private(set) var profile = Profile()
    @Published private(set) var lastSync: Date?
    @Published var toast: String?
    @Published var burst: PlanTask?

    let bridge = ArtifactBridge()

    private struct PendingWrite: Codable { let date: String?; let path: String; let op: String; let json: String? }
    private struct Cache: Codable { var days: [String: DayDoc]; var profile: Profile; var pending: [PendingWrite]; var serverDates: [String]; var lastSync: Date? }

    private var pending: [PendingWrite] = []
    private var serverDates = Set<String>()
    private var profileOnServer = false
    private var flushing = false
    private var saveTask: Task<Void, Never>?

    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FortyEight", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "cache.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            days = c.days; profile = c.profile; pending = c.pending; serverDates = Set(c.serverDates); lastSync = c.lastSync
            profileOnServer = !c.profile.about.isEmpty || !c.profile.notes.isEmpty
        }
        bridge.onDays = { [weak self] docs, _ in self?.applyServerDays(docs) }
        bridge.onProfile = { [weak self] data in self?.applyServerProfile(data) }
        bridge.onReady = { [weak self] in Task { await self?.flush() } }
        bridge.start()
    }

    var pendingCount: Int { pending.count }

    func day(_ date: String) -> DayDoc { days[date] ?? DayDoc(date: date) }

    // MARK: - server → local

    private func applyServerDays(_ docs: [(id: String, data: Data)]) {
        let dirty = Set(pending.compactMap(\.date))
        var next: [String: DayDoc] = [:]
        for d in docs {
            guard var doc = try? JSONDecoder().decode(DayDoc.self, from: d.data) else { continue }
            if doc.date.isEmpty { doc.date = d.id }
            next[d.id] = doc
        }
        serverDates = Set(next.keys)
        // Keep local edits that have not reached the server yet.
        for k in dirty { if let local = days[k] { next[k] = local } }
        days = next
        lastSync = Date()
        scheduleSave()
    }

    private func applyServerProfile(_ data: Data?) {
        if let data, let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profileOnServer = true
            if !pending.contains(where: { $0.path == "memory/profile" }) { profile = p }
        } else { profileOnServer = false }
        scheduleSave()
    }

    // MARK: - local edits

    /// Applies `mutate` locally, then sends only the changed fields (or the whole doc if it is new).
    private func edit(_ date: String, fields: [String], _ mutate: (inout DayDoc) -> Void) {
        var d = day(date)
        mutate(&d)
        d.updatedAt = ISO8601DateFormatter().string(from: Date())
        days[date] = d
        let full = Self.json(d)
        let exists = serverDates.contains(date) || pending.contains { $0.date == date && $0.op == "set" }
        let body: [String: Any] = exists ? full.filter { (fields + ["updatedAt"]).contains($0.key) } : full
        enqueue(PendingWrite(date: date, path: "days/\(date)", op: exists ? "update" : "set", json: Self.string(body)))
    }

    func setActual(_ date: String, _ arr: [String?]) { edit(date, fields: ["actual"]) { $0.actual = arr } }
    func setPlan(_ date: String, _ arr: [String?]) {
        edit(date, fields: ["plan", "tasks"]) { d in
            d.plan = arr
            for i in d.tasks.indices { d.tasks[i].tokens = arr.filter { $0 == d.tasks[i].id }.count }
        }
    }
    func toggleDone(_ date: String, _ t: PlanTask) {
        let now = !(day(date).done[t.id] ?? false)
        edit(date, fields: ["done"]) { $0.done[t.id] = now }
        if now { burst = t }
    }
    func toggleStep(_ date: String, _ key: String) { edit(date, fields: ["stepDone"]) { $0.stepDone[key] = !($0.stepDone[key] ?? false) } }
    func setNote(_ date: String, _ text: String) {
        guard day(date).note != text else { return }
        edit(date, fields: ["note"]) { $0.note = text }
    }

    func addMemoryNote(_ text: String) {
        profile.notes.append(MemNote(text: text, at: ISO8601DateFormatter().string(from: Date())))
        saveProfile(fields: ["notes"])
    }
    func deleteMemoryNote(_ n: MemNote) {
        profile.notes.removeAll { $0 == n }
        saveProfile(fields: ["notes"])
    }
    private func saveProfile(fields: [String]) {
        let full = Self.json(profile)
        let exists = profileOnServer || pending.contains { $0.path == "memory/profile" && $0.op == "set" }
        let body = exists ? full.filter { fields.contains($0.key) } : full
        enqueue(PendingWrite(date: nil, path: "memory/profile", op: exists ? "update" : "set", json: Self.string(body)))
    }

    // MARK: - write queue

    private func enqueue(_ w: PendingWrite) {
        pending.append(w)
        scheduleSave()
        Task { await flush() }
    }

    func flush() async {
        guard !flushing, bridge.state == .ready else { return }
        flushing = true
        defer { flushing = false }
        while let w = pending.first {
            if let code = await bridge.write(path: w.path, op: w.op, json: w.json) {
                switch code {
                case "invalid_argument":
                    toast = "没有写入权限，这次修改没有同步"
                    pending.removeFirst()
                case "quota_exceeded":
                    toast = "数据库满了，修改没有同步"
                    pending.removeFirst()
                default:
                    scheduleSave()
                    return   // keep it queued; retried on the next ready / edit
                }
            } else {
                pending.removeFirst()
                if let d = w.date { serverDates.insert(d) } else { profileOnServer = true }
            }
            scheduleSave()
        }
    }

    // MARK: - cache

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let c = Cache(days: self.days, profile: self.profile, pending: self.pending, serverDates: Array(self.serverDates), lastSync: self.lastSync)
            if let data = try? JSONEncoder().encode(c) { try? data.write(to: Self.cacheURL, options: .atomic) }
        }
    }

    private static func json<T: Encodable>(_ v: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(v), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }
    private static func string(_ obj: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
