import Foundation

/// Where "now" sits relative to a given day.
struct TimeCtx {
    enum Mode { case past, today, future }
    let mode: Mode
    let elapsed: Int   // tokens fully in the past
    let now: Int       // current token, -1 if not today
    let minutes: Int   // minutes since midnight (today only)

    static func of(_ date: String, at d: Date = Date()) -> TimeCtx {
        let t = Dates.key(d)
        if date < t { return TimeCtx(mode: .past, elapsed: 48, now: -1, minutes: 0) }
        if date > t { return TimeCtx(mode: .future, elapsed: 0, now: -1, minutes: 0) }
        let c = Dates.cal.dateComponents([.hour, .minute], from: d)
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let now = min(47, mins / 30)
        return TimeCtx(mode: .today, elapsed: now, now: now, minutes: mins)
    }
}

/// Same formulas as the web app, so both clients show identical numbers.
struct Metrics {
    var planCat: [Cat: Int] = [:], actCat: [Cat: Int] = [:]
    var planWork = 0, planLoad = 0, planSleep = 0
    var actWork = 0, actLoad = 0, actSleep = 0
    var recorded = 0, recWaking = 0, slack = 0, missing = 0, buffer = 0, lateHeavy = 0, switches = 0
    var matchPts = 0.0, matchN = 0
    var elapsedPlanWork = 0, elapsedActWork = 0
    var perTask: [String: (plan: Int, act: Int)] = [:]

    init(_ day: DayDoc, plan: [String?]? = nil, actual: [String?]? = nil, elapsed: Int) {
        let plan = plan ?? day.plan, actual = actual ?? day.actual
        for t in day.tasks { perTask[t.id] = (0, 0) }
        var prevWork: String?
        for i in 0..<48 {
            let p = day.info(plan[i]), a = day.info(actual[i])
            if let p {
                planCat[p.cat, default: 0] += 1
                if p.cat == .sleep { planSleep += 1 }
                if p.id == "_buffer" { buffer += 1 }
                if p.isWork {
                    planWork += 1; planLoad += p.load
                    if i < elapsed { elapsedPlanWork += 1 }
                    if p.load >= 3 && i >= 42 { lateHeavy += 1 }
                    if let pw = prevWork, pw != p.id { switches += 1 }
                    prevWork = p.id
                }
                if perTask[p.id] != nil { perTask[p.id]!.plan += 1 }
            }
            if let a {
                recorded += 1; actCat[a.cat, default: 0] += 1
                if a.cat == .sleep { actSleep += 1 } else { recWaking += 1 }
                if a.cat == .slack { slack += 1 }
                if a.isWork { actWork += 1; actLoad += a.load; if i < elapsed { elapsedActWork += 1 } }
                if perTask[a.id] != nil { perTask[a.id]!.act += 1 }
                if let p { matchN += 1; matchPts += a.id == p.id ? 1 : a.cat == p.cat ? 0.5 : 0 }
            } else if i < elapsed { missing += 1 }
        }
    }

    var planIntensity: Int { planWork == 0 ? 0 : min(100, Int((Double(planLoad) / Double(max(1, 48 - planSleep)) * 50).rounded())) }
    var actIntensity: Int? { recWaking >= 4 ? min(100, Int((Double(actLoad) / Double(recWaking) * 50).rounded())) : nil }
    var match: Double? { matchN >= 2 ? matchPts / Double(matchN) : nil }
    var lag: Int { elapsedPlanWork - elapsedActWork }
}

enum Level {
    static func of(_ s: Int?) -> (rank: Int, name: String)? {
        guard let s else { return nil }
        if s < 40 { return (0, "轻松") }
        if s < 60 { return (1, "稳态") }
        if s < 80 { return (2, "高压") }
        return (3, "冲刺")
    }
}

struct History {
    var days = 0
    var overCat: (cat: Cat, avg: Double)?
    var avgSleep: Double?
    var prevHigh = false

    init(before date: String, days all: [String: DayDoc]) {
        if let y = all[Dates.add(date, -1)] {
            let m = Metrics(y, elapsed: 48)
            prevHigh = (m.actIntensity ?? m.planIntensity) >= 80
        }
        var over: [Cat: Int] = [:], sl = 0, sn = 0
        for k in 1...7 {
            guard let d = all[Dates.add(date, -k)] else { continue }
            let m = Metrics(d, elapsed: 48)
            guard m.recorded >= 16 else { continue }
            days += 1
            for c in Cat.work { over[c, default: 0] += (m.actCat[c] ?? 0) - (m.planCat[c] ?? 0) }
            if m.actSleep > 0 { sl += m.actSleep; sn += 1 }
        }
        if days >= 2 {
            for (c, v) in over {
                let avg = Double(v) / Double(days)
                if avg >= 1, avg > (overCat?.avg ?? 0) { overCat = (c, avg) }
            }
        }
        if sn >= 2 { avgSleep = Double(sl) / Double(sn) }
    }
}

struct Strategy: Identifiable, Hashable {
    enum Lv: Int { case bad, warn, tip, good
        var label: String { ["风险", "注意", "建议", "不错"][rawValue] }
        var symbol: String { ["xmark.octagon.fill", "exclamationmark.triangle.fill", "lightbulb.fill", "checkmark.seal.fill"][rawValue] }
    }
    let lv: Lv, title: String, detail: String
    var id: String { title }

    static func build(_ day: DayDoc, _ m: Metrics, _ ctx: TimeCtx, all: [String: DayDoc]) -> [Strategy] {
        guard day.hasPlan else { return [Strategy(lv: .tip, title: "这一天还没有计划", detail: "点「写计划」让 Claude 排程，或者在 Claude Code 里说「明天计划：……」。")] }
        var out: [Strategy] = []
        let hist = History(before: day.date, days: all)
        if m.planSleep < 14 { out.append(.init(lv: .bad, title: "睡眠只排了 \(Dates.hours(m.planSleep))", detail: "低于 7 小时，第二天能专注的格数会明显变少。从低负荷任务里挪 1–2 格给睡眠。")) }
        if m.planIntensity >= 80 {
            out.append(.init(lv: .warn, title: "冲刺日 · 强度 \(m.planIntensity)", detail: hist.prevHigh ? "前一天也是高强度。连续冲刺会掉效率，今天砍掉一个低优先级任务。" : "偶尔一天可以。第二天把强度压到 60 左右恢复。"))
        } else if m.planIntensity < 40 && m.planWork > 0 {
            out.append(.init(lv: .tip, title: "强度 \(m.planIntensity)，偏轻松", detail: "还有余力的话，给项目或手写模型这类长期任务多排 2 格。"))
        }
        if m.buffer == 0 { out.append(.init(lv: .warn, title: "没有机动格", detail: "任何任务超时都会直接挤压睡眠。至少留 1 格机动。")) }
        if m.lateHeavy > 0 { out.append(.init(lv: .tip, title: "\(m.lateHeavy) 格高负荷任务排在 21:00 之后", detail: "深夜做重任务效率低。和晚上的轻任务（视频课、投简历）对调。")) }
        if m.switches > 10 { out.append(.init(lv: .tip, title: "任务切换 \(m.switches) 次", detail: "太碎了。同类任务合并成连续块，每块至少 2 格。")) }
        if ctx.mode == .today && m.missing >= 3 { out.append(.init(lv: .tip, title: "\(m.missing) 格还没记录", detail: "先点「补齐到现在」按计划补上，再改掉实际不一样的格子。")) }
        if ctx.mode == .today && m.missing <= 2 && m.elapsedPlanWork > 0 {
            if m.lag >= 2 {
                let rest = day.tasks.filter { day.done[$0.id] != true && day.plan[ctx.now...].contains($0.id) }.sorted { $0.load < $1.load }
                out.append(.init(lv: .warn, title: "落后 \(m.lag) 格", detail: rest.first.map { "先用机动格追。还不够就把「\($0.title)」挪到明天，别动睡眠。" } ?? "先用机动格追，别动睡眠。"))
            } else if m.lag <= -2 {
                out.append(.init(lv: .good, title: "领先 \(-m.lag) 格", detail: "节奏很好。多出来的时间可以提前开始下一个重任务，或者早点睡。"))
            }
        }
        for t in day.tasks {
            if let pt = m.perTask[t.id], pt.plan > 0, pt.act > pt.plan {
                out.append(.init(lv: .warn, title: "「\(t.title)」超出 \(pt.act - pt.plan) 格", detail: "下次给它多排 1 格，或者拆成更小的步骤。"))
            }
        }
        if m.slack >= 2 { out.append(.init(lv: .warn, title: "摸鱼 \(m.slack) 格（\(Dates.hours(m.slack))）", detail: "摸鱼大多出现在任务切换之后。开始下一格前，先写下这一格要交付的具体东西。")) }
        if let match = m.match, m.recorded >= 8 {
            let pct = Int((match * 100).rounded())
            if pct >= 80 { out.append(.init(lv: .good, title: "吻合度 \(pct)%", detail: "计划和执行几乎一致，说明估时准确，保持。")) }
            else if pct < 50 { out.append(.init(lv: .warn, title: "吻合度只有 \(pct)%", detail: "计划和实际差距大，多半是排得太满或顺序不顺手。看偏差最大的任务，明天少排 1–2 个。")) }
        }
        if let oc = hist.overCat { out.append(.init(lv: .tip, title: "最近 \(hist.days) 天「\(oc.cat.name)」平均超时 \(String(format: "%.1f", oc.avg)) 格", detail: "排这类任务时多留缓冲，或者缩小范围。")) }
        if let s = hist.avgSleep, s < 14 { out.append(.init(lv: .warn, title: "最近平均只睡 \(Dates.hours(s))", detail: "睡眠债会让第二天的吻合度下降。今晚优先保睡眠。")) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.title).inserted }.sorted { $0.lv.rawValue < $1.lv.rawValue }.prefix(8).map { $0 }
    }
}

struct Quote: Hashable { let text: String; let who: String; let source: String? }

enum Quotes {
    static let all: [Quote] = [
        Quote(text: "现在放弃的话，比赛就结束了。", who: "安西教练", source: "灌篮高手"),
        Quote(text: "说到做到，这就是我的忍道！", who: "漩涡鸣人", source: "火影忍者"),
        Quote(text: "燃烧你的心吧！", who: "炼狱杏寿郎", source: "鬼灭之刃"),
        Quote(text: "相信你自己，相信那个相信着你的我！", who: "卡米那", source: "天元突破"),
        Quote(text: "人不付出牺牲，就什么也得不到。", who: "等价交换", source: "钢之炼金术师"),
        Quote(text: "不战斗就赢不了！", who: "艾伦", source: "进击的巨人"),
        Quote(text: "每天一百个俯卧撑、一百个仰卧起坐、一百个深蹲，再跑十公里。", who: "埼玉", source: "一拳超人"),
        Quote(text: "人类的赞歌就是勇气的赞歌！", who: "齐贝林", source: "JOJO 的奇妙冒险"),
        Quote(text: "我是要成为海贼王的男人！", who: "路飞", source: "海贼王"),
        Quote(text: "放心吧，我最强。", who: "五条悟", source: "咒术回战"),
    ]

    /// Original lines that react to the day's state.
    static func context(_ m: Metrics, _ ctx: TimeCtx) -> Quote? {
        let me = "四十八格"
        if ctx.mode == .today {
            if m.lag >= 2 && m.missing <= 2 { return Quote(text: "落后 \(m.lag) 格。逆转的剧本，从下一格开始写。", who: me, source: nil) }
            if m.lag <= -2 { return Quote(text: "领先 \(-m.lag) 格。别松手，保持这个帧率。", who: me, source: nil) }
            if ctx.now >= 45 { return Quote(text: "今天的冒险到这里。存档，睡觉，明天继续升级。", who: me, source: nil) }
            if (15...21).contains(ctx.now) { return Quote(text: "黄金时段。先打最难的那一场。", who: me, source: nil) }
        }
        if ctx.mode == .future && m.planIntensity >= 80 { return Quote(text: "明天是冲刺日。今晚早点睡，就是最好的预习。", who: me, source: nil) }
        return nil
    }
}
