import SwiftUI

// Mirrors the artifact database schema (see index.html): days/<YYYY-MM-DD> and memory/profile.
// Decoding is lenient because documents are written by the web page, the app and Claude.

enum Cat: String, CaseIterable, Codable {
    case algo, build, learn, career, school, sleep, life, rest, buffer, review, slack

    var name: String {
        switch self {
        case .algo: return "算法"
        case .build: return "项目"
        case .learn: return "学习"
        case .career: return "求职"
        case .school: return "课业"
        case .sleep: return "睡眠"
        case .life: return "生活"
        case .rest: return "休息"
        case .buffer: return "机动"
        case .review: return "复盘"
        case .slack: return "摸鱼"
        }
    }
    var isWork: Bool { [.algo, .build, .learn, .career, .school].contains(self) }
    static let work: [Cat] = [.algo, .build, .learn, .career, .school]

    /// Same validated palette as the web app (dark / light).
    var color: Color {
        let pair: (UInt32, UInt32)
        switch self {
        case .algo: pair = (0x00a2ce, 0x0796c9)
        case .build: pair = (0x9769dc, 0x7b4fe0)
        case .learn: pair = (0xc8800d, 0xd9821a)
        case .career: pair = (0xd65c88, 0xe04f86)
        case .school: pair = (0x68a63f, 0x5f9e1b)
        case .sleep: pair = (0x5965cd, 0x4f5bd5)
        case .life: pair = (0xb7684c, 0xc27a3a)
        case .rest: pair = (0x19aa8e, 0x1fae7f)
        case .buffer: pair = (0x7d8299, 0x8a90a6)
        case .review: pair = (0xa9aecb, 0x5d6483)
        case .slack: pair = (0xe5484d, 0xd93a3f)
        }
        return Color(dark: pair.0, light: pair.1)
    }
}

struct PlanTask: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var short: String
    var cat: Cat
    var load: Int
    var tokens: Int
    var detail: String
    var steps: [String]

    enum CodingKeys: String, CodingKey { case id, title, short, cat, load, tokens, detail, steps }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        short = (try? c.decode(String.self, forKey: .short)) ?? String(title.prefix(4))
        let rawCat = (try? c.decode(String.self, forKey: .cat)) ?? "learn"
        cat = Cat(rawValue: rawCat).flatMap { $0.isWork ? $0 : nil } ?? .learn
        let l = (try? c.decode(Int.self, forKey: .load)) ?? 2
        load = (1...3).contains(l) ? l : 2
        tokens = (try? c.decode(Int.self, forKey: .tokens)) ?? 0
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        steps = (try? c.decode([String].self, forKey: .steps)) ?? []
        if short.isEmpty { short = String(title.prefix(4)) }
    }
}

struct Advice: Codable, Hashable {
    var level: String
    var text: String
    init(level: String, text: String) { self.level = level; self.text = text }
    init(from d: Decoder) throws {
        if let s = try? d.singleValueContainer().decode(String.self) { level = "tip"; text = s; return }
        let c = try d.container(keyedBy: CodingKeys.self)
        level = (try? c.decode(String.self, forKey: .level)) ?? "tip"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }
}

struct AIReview: Codable, Hashable { var text: String; var at: String? }

struct DayDoc: Codable {
    var date: String
    var title = ""
    var focus = ""
    var tasks: [PlanTask] = []
    var plan: [String?] = Array(repeating: nil, count: 48)
    var actual: [String?] = Array(repeating: nil, count: 48)
    var done: [String: Bool] = [:]
    var stepDone: [String: Bool] = [:]
    var note = ""
    var advice: [Advice] = []
    var aiReview: AIReview?
    var source: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey { case date, title, focus, tasks, plan, actual, done, stepDone, note, advice, aiReview, source, updatedAt }

    init(date: String) { self.date = date }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        focus = (try? c.decode(String.self, forKey: .focus)) ?? ""
        tasks = (try? c.decode([Lenient<PlanTask>].self, forKey: .tasks))?.compactMap(\.value) ?? []
        plan = DayDoc.fix((try? c.decode([String?].self, forKey: .plan)) ?? [])
        actual = DayDoc.fix((try? c.decode([String?].self, forKey: .actual)) ?? [])
        done = (try? c.decode([String: Bool].self, forKey: .done)) ?? [:]
        stepDone = (try? c.decode([String: Bool].self, forKey: .stepDone)) ?? [:]
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        advice = ((try? c.decode([Advice].self, forKey: .advice)) ?? []).filter { !$0.text.isEmpty }
        aiReview = try? c.decode(AIReview.self, forKey: .aiReview)
        source = try? c.decode(String.self, forKey: .source)
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
    }

    static func fix(_ a: [String?]) -> [String?] {
        var o = Array(a.prefix(48)).map { $0?.isEmpty == true ? nil : $0 }
        while o.count < 48 { o.append(nil) }
        return o
    }

    var hasPlan: Bool { plan.contains { $0 != nil } }
    func task(_ id: String) -> PlanTask? { tasks.first { $0.id == id } }

    /// Shade index of a task among tasks of the same category, so LC and CF read apart.
    func shade(of t: PlanTask) -> Int {
        var n = 0
        for x in tasks { if x.id == t.id { return n % 3 }; if x.cat == t.cat { n += 1 } }
        return 0
    }

    func info(_ id: String?) -> TokenInfo? {
        guard let id else { return nil }
        if let b = Builtin.all[id] { return TokenInfo(id: id, title: b.title, short: b.short, cat: b.cat, load: 0, shade: 0) }
        if let t = task(id) { return TokenInfo(id: id, title: t.title, short: t.short, cat: t.cat, load: t.load, shade: shade(of: t)) }
        return TokenInfo(id: id, title: id, short: String(id.prefix(4)), cat: .buffer, load: 0, shade: 0)
    }

    func ranges(of id: String) -> [String] {
        var out: [String] = [], st = -1
        for i in 0...48 {
            if i < 48, plan[i] == id { if st < 0 { st = i } }
            else if st >= 0 { out.append("\(Slot.time(st))–\(i == 48 ? "24:00" : Slot.time(i))"); st = -1 }
        }
        return out
    }
}

struct TokenInfo: Hashable {
    let id: String, title: String, short: String, cat: Cat, load: Int, shade: Int
    var isWork: Bool { cat.isWork && !id.hasPrefix("_") }
    var color: Color {
        switch shade {
        case 1: return cat.color.mix(with: .primary, by: 0.26)
        case 2: return cat.color.mix(with: Color(.systemBackground), by: 0.3)
        default: return cat.color
        }
    }
}

enum Builtin {
    struct B { let title: String, short: String, cat: Cat }
    static let order = ["_sleep", "_wash", "_meal", "_commute", "_rest", "_move", "_fun", "_buffer", "_review", "_slack"]
    static let all: [String: B] = [
        "_sleep": B(title: "睡眠", short: "睡", cat: .sleep),
        "_wash": B(title: "洗漱整理", short: "洗漱", cat: .life),
        "_meal": B(title: "吃饭", short: "饭", cat: .life),
        "_commute": B(title: "通勤", short: "通勤", cat: .life),
        "_rest": B(title: "休息", short: "休", cat: .rest),
        "_move": B(title: "运动", short: "运动", cat: .rest),
        "_fun": B(title: "娱乐", short: "娱乐", cat: .rest),
        "_buffer": B(title: "机动", short: "机动", cat: .buffer),
        "_review": B(title: "复盘", short: "复盘", cat: .review),
        "_slack": B(title: "摸鱼", short: "摸鱼", cat: .slack),
    ]
}

struct MemNote: Codable, Hashable { var text: String; var at: String? }

struct Profile: Codable {
    var about: [String] = []
    var rules: [String] = []
    var goals: [String] = []
    var notes: [MemNote] = []
    enum CodingKeys: String, CodingKey { case about, rules, goals, notes }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        about = (try? c.decode([String].self, forKey: .about)) ?? []
        rules = (try? c.decode([String].self, forKey: .rules)) ?? []
        goals = (try? c.decode([String].self, forKey: .goals)) ?? []
        notes = (try? c.decode([Lenient<MemNote>].self, forKey: .notes))?.compactMap(\.value) ?? []
    }
}

/// Decodes an element if it can, otherwise yields nil instead of failing the whole array.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

// MARK: - Time helpers

enum Slot {
    static func time(_ i: Int) -> String { String(format: "%02d:%@", i / 2, i % 2 == 1 ? "30" : "00") }
    static func range(_ i: Int) -> String { "\(time(i))–\(i == 47 ? "24:00" : time(i + 1))" }
}

enum Dates {
    static let cal = Calendar.current
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ k: String) -> Date { fmt.date(from: k) ?? Date() }
    static var today: String { key(Date()) }
    static func add(_ k: String, _ n: Int) -> String { key(cal.date(byAdding: .day, value: n, to: date(k)) ?? Date()) }
    static func label(_ k: String) -> String {
        let d = date(k), w = "日一二三四五六"
        let wd = cal.component(.weekday, from: d) - 1
        return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日 周\(Array(w)[wd])"
    }
    static func relative(_ k: String) -> String? {
        let t = today
        if k == t { return "今天" }
        if k == add(t, 1) { return "明天" }
        if k == add(t, -1) { return "昨天" }
        if k == add(t, 2) { return "后天" }
        return nil
    }
    static func hours(_ tokens: Int) -> String { tokens % 2 == 0 ? "\(tokens / 2)h" : String(format: "%.1fh", Double(tokens) / 2) }
    static func hours(_ tokens: Double) -> String { String(format: tokens.truncatingRemainder(dividingBy: 2) == 0 ? "%.0fh" : "%.1fh", tokens / 2) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    init(dark: UInt32, light: UInt32) {
        self.init(UIColor { t in
            let h = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: 1)
        })
    }
}
