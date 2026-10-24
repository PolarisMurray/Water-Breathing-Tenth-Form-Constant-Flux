import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var bridge: ArtifactBridge
    @Environment(\.horizontalSizeClass) private var hSize
    @Binding var date: String
    @Binding var userNav: Bool

    @State private var layer: Layer = .actual
    @State private var brush = "@plan"
    @State private var draft: [String?]?
    @State private var selected: Int?
    @State private var now = Date()
    @State private var showPicker = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                let d = store.day(date)
                let ctx = TimeCtx.of(date, at: now)
                let plan = layer == .plan ? (draft ?? d.plan) : d.plan
                let actual = layer == .actual ? (draft ?? d.actual) : d.actual
                let m = Metrics(d, plan: plan, actual: actual, elapsed: ctx.elapsed)

                VStack(alignment: .leading, spacing: 18) {
                    SyncBanner()
                    header(d, m)
                    DialView(day: d, plan: plan, actual: actual, ctx: ctx, m: m) { selected = $0 }
                        .padding(8)
                        .glassCard(padding: 12)
                    QuoteCard(m: m, ctx: ctx, date: date)
                    MetricsCard(m: m, ctx: ctx, xp: Exp.series(store.days).last?.total ?? 0, dayXp: Exp.gain(d))
                    timeline(d, plan: plan, actual: actual, ctx: ctx)
                    TasksCard(day: d, m: m, date: date)
                    StrategyCard(day: d, m: m, ctx: ctx)
                    NoteCard(date: date)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { bridge.reload() }
            .background { SkyBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showPicker) {
                DatePicker("日期", selection: Binding(get: { Dates.date(date) }, set: { go(Dates.key($0)); showPicker = false }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .presentationDetents([.medium])
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    now = Date()
                }
            }
        }
    }

    private func go(_ d: String) { date = d; userNav = true; draft = nil; selected = nil }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { go(Dates.add(date, -1)) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("前一天")
            Button { go(Dates.add(date, 1)) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("后一天")
        }
        ToolbarItem(placement: .principal) {
            Button { showPicker = true } label: {
                Text(Dates.label(date)).font(.headline)
            }
            .buttonStyle(.plain)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if date != Dates.today {
                Button("今天") { go(Dates.today) }
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { bridge.openWebFeature("compose") } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel("写计划")
        }
    }

    // MARK: header

    private func header(_ d: DayDoc, _ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(Dates.label(date))
                if let rel = Dates.relative(date) { Text("·"); Text(rel).foregroundStyle(Theme.accent) }
                if m.planWork > 0 { Text("· 工作 \(Dates.hours(m.planWork))") }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(d.title.isEmpty ? (d.hasPlan ? "未命名的一天" : "这一天还空着") : d.title)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.primary, Theme.accent.mix(with: .primary, by: 0.35)], startPoint: .leading, endPoint: .trailing))
            Text(d.focus.isEmpty ? (d.hasPlan ? "" : "点右上角的笔写计划，或者在 Claude Code 里告诉我。") : d.focus)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: timeline

    private var brushes: [(id: String, label: String, color: Color?)] {
        let d = store.day(date)
        var out: [(id: String, label: String, color: Color?)] = []
        if layer == .actual { out.append(("@plan", "✓ 按计划", nil)) }
        for t in d.tasks { out.append((t.id, t.short, d.info(t.id)?.color)) }
        for k in Builtin.order where layer == .actual || k != "_slack" { if let b = Builtin.all[k] { out.append((k, b.title, b.cat.color)) } }
        out.append(("@erase", "⌫ 橡皮", nil))
        return out
    }

    private func timeline(_ d: DayDoc, plan: [String?], actual: [String?], ctx: TimeCtx) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("48 格时间轴").sectionTitle()
                Spacer()
                Picker("图层", selection: $layer) { ForEach(Layer.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).frame(maxWidth: 190)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(brushes, id: \.id) { b in
                        let on = b.id == brush
                        Button { brush = b.id } label: {
                            HStack(spacing: 6) {
                                if let c = b.color { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10) }
                                Text(b.label).font(.footnote.weight(on ? .bold : .medium))
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Capsule().fill(on ? (b.color ?? Theme.accent).opacity(0.28) : Color.primary.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(on ? (b.color ?? Theme.accent) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: layer) { if !brushes.contains(where: { $0.id == brush }) { brush = brushes.first?.id ?? "@erase" } }

            TokenGrid(day: d, plan: plan, actual: actual, ctx: ctx, layer: layer, cols: hSize == .regular ? 12 : 6,
                      paint: { i in paintCell(i, d) }, commit: commitPaint)

            Group {
                if let i = selected {
                    let p = d.info(plan[i]), a = d.info(actual[i])
                    Text("\(Slot.range(i)) · 计划 \(p?.title ?? "空") · 实际 \(a?.title ?? "未记录")")
                } else {
                    Text("点按涂一格；按住再拖动，连续涂。")
                }
            }
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()

            HStack(spacing: 8) {
                Button("当前格按计划") {
                    var a = d.actual; a[ctx.now] = d.plan[ctx.now]; store.setActual(date, a)
                }
                .disabled(ctx.mode != .today || d.plan[ctx.now] == nil)
                Button("补齐到现在") {
                    var a = d.actual, n = 0
                    for i in 0..<ctx.elapsed where a[i] == nil && d.plan[i] != nil { a[i] = d.plan[i]; n += 1 }
                    if n > 0 { store.setActual(date, a); store.toast = "按计划补齐了 \(n) 格" } else { store.toast = "没有需要补齐的格子" }
                }
                .disabled(ctx.elapsed == 0)
                Button("清空实际", role: .destructive) { confirmClear = true }
                    .confirmationDialog("清空这一天的实际记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("清空", role: .destructive) { store.setActual(date, Array(repeating: nil, count: 48)) }
                    }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote)
        }
        .glassCard()
    }

    private func paintCell(_ i: Int, _ d: DayDoc) {
        var arr = draft ?? (layer == .plan ? d.plan : d.actual)
        arr[i] = brush == "@erase" ? nil : brush == "@plan" ? d.plan[i] : brush
        draft = arr
        selected = i
    }

    private func commitPaint() {
        guard let arr = draft else { return }
        draft = nil
        let d = store.day(date)
        if layer == .plan { if arr != d.plan { store.setPlan(date, arr) } }
        else if arr != d.actual { store.setActual(date, arr) }
    }
}

// MARK: - Sync banner

struct SyncBanner: View {
    @EnvironmentObject private var bridge: ArtifactBridge
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        switch bridge.state {
        case .ready:
            EmptyView()
        case .connecting:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在连接 claude.ai 数据库…").font(.footnote)
                Spacer()
            }
            .glassCard(18, padding: 12)
        case .needsSignIn:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("登录 claude.ai 以同步").font(.subheadline.weight(.semibold))
                    Text("建议用邮箱验证码登录；现在显示的是本机缓存。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("登录") { bridge.showWeb = true }.buttonStyle(.glassProminent)
            }
            .glassCard(18, padding: 14)
        case .stalled(let why):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("没连上数据库").font(.subheadline.weight(.semibold))
                    Text(why).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重试") { bridge.reload() }.buttonStyle(.glass)
                Button("网页") { bridge.showWeb = true }.buttonStyle(.glass)
            }
            .glassCard(18, padding: 14)
        }
    }
}

// MARK: - Quote

struct QuoteCard: View {
    let m: Metrics
    let ctx: TimeCtx
    let date: String
    @State private var idx = Int.random(in: 0..<Quotes.all.count)
    @State private var current: Quote = Quotes.all[0]
    @State private var lastContext = ""
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(contextLine).foregroundStyle(Theme.accent)
                Spacer()
                Text("点按换一句").foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.semibold)).monospacedDigit()
            RevealText(text: current.text)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .italic()
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .bottomLeading)
                .id(current.text)
            Text(current.source.map { "—— \(current.who)《\($0)》" } ?? "—— \(current.who)")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { SpeedLines().clipShape(.rect(cornerRadius: 26)) }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .contentShape(.rect)
        .onTapGesture { next() }
        .onAppear {
            guard !started else { return }
            started = true
            current = Quotes.context(m, ctx) ?? Quotes.all[idx]
        }
        .onChange(of: Quotes.context(m, ctx)?.text ?? "") { _, new in
            if !new.isEmpty, new != lastContext, let q = Quotes.context(m, ctx) { lastContext = new; withAnimation { current = q } }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(26))
                next()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("点按换一句")
    }

    private func next() { idx = (idx + 1) % Quotes.all.count; withAnimation { current = Quotes.all[idx] } }

    private var contextLine: String {
        switch ctx.mode {
        case .today: return "\(Slot.time(ctx.now)) · 第 \(ctx.now + 1) 格"
        case .future: return "\(Dates.relative(date) ?? Dates.label(date)) · \(Level.of(m.planWork > 0 ? m.planIntensity : nil).map { $0.name + "日" } ?? "待排程")"
        case .past: return "\(Dates.label(date)) · 吻合度 \(m.match.map { "\(Int($0 * 100))%" } ?? "—")"
        }
    }
}

/// Glyph-by-glyph entrance, drawn by a TextRenderer so it costs one layer.
struct RevealText: View {
    let text: String
    @State private var elapsed = 0.0
    var body: some View {
        let total = Double(text.count) * 0.03 + 0.4
        Text(text)
            .textRenderer(RevealRenderer(elapsed: elapsed))
            .onAppear { withAnimation(.linear(duration: total)) { elapsed = total } }
    }
}

struct RevealRenderer: TextRenderer, Animatable {
    var elapsed: Double
    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var i = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let k = max(0, min(1, (elapsed - Double(i) * 0.03) / 0.35))
                    var c = ctx
                    c.opacity = k
                    c.translateBy(x: 0, y: (1 - k) * 10)
                    c.draw(slice)
                    i += 1
                }
            }
        }
    }
}

/// Manga focus lines, slowly rotating behind the quote.
struct SpeedLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { tl in
            let rot = tl.date.timeIntervalSinceReferenceDate * 0.07
            Canvas { c, size in
                let ctr = CGPoint(x: size.width / 2, y: size.height / 2), R = hypot(size.width, size.height)
                for k in 0..<64 {
                    let a = Double(k) / 64 * 2 * .pi + rot, w = 0.009
                    var p = Path()
                    p.move(to: CGPoint(x: ctr.x + cos(a) * R * 0.18, y: ctr.y + sin(a) * R * 0.18))
                    p.addLine(to: CGPoint(x: ctr.x + cos(a - w) * R, y: ctr.y + sin(a - w) * R))
                    p.addLine(to: CGPoint(x: ctr.x + cos(a + w) * R, y: ctr.y + sin(a + w) * R))
                    p.closeSubpath()
                    c.fill(p, with: .radialGradient(Gradient(colors: [.primary.opacity(0), .primary.opacity(0.09)]), center: ctr, startRadius: R * 0.12, endRadius: R * 0.5))
                }
            }
        }
    }
}

// MARK: - Metrics

struct MetricsCard: View {
    let m: Metrics
    let ctx: TimeCtx
    let xp: Double
    let dayXp: Int

    var body: some View {
        let lv = Level.of(m.planWork > 0 ? m.planIntensity : nil), alv = Level.of(m.actIntensity)
        let xl = Exp.level(xp)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("经验").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Lv.\(xl.n)").font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing))
                    Text("\(Int(xp.rounded())) EXP · 这一天 +\(dayXp)").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
                LevelBar(progress: xl.progress)
                Text("距 Lv.\(xl.n + 1) 还差 \(Int((xl.hi - xp).rounded())) · 每晚蒸发 5%").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("生活强度").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.planWork > 0 ? "\(m.planIntensity)" : "—").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    if let lv { Pill(text: lv.name, color: Theme.level(lv.rank)) }
                    Text(m.actIntensity.map { "实际 \($0) · \(alv?.name ?? "")" } ?? "实际 —").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                IntensityGauge(plan: m.planWork > 0 ? m.planIntensity : nil, actual: m.actIntensity)
                Text("\(Text("▮").foregroundStyle(.primary)) 计划  \(Text("▮").foregroundStyle(Theme.accent)) 实际 · Σ负荷×格 ÷ 清醒格 × 50")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                GridRow {
                    stat("计划吻合度", m.match.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "已记录 \(m.recorded) / 48 格")
                    stat(ctx.mode == .past ? "完成量" : "节奏", pace.0, pace.1)
                }
                GridRow {
                    stat("工作", Dates.hours(m.planWork), m.recorded > 0 ? "实际 \(Dates.hours(m.actWork))" : "\(m.planWork) 格")
                    stat("睡眠", Dates.hours(m.planSleep), m.actSleep > 0 ? "实际 \(Dates.hours(m.actSleep))" : (m.planSleep >= 15 ? "达标" : m.planSleep > 0 ? "低于 7.5h 目标" : "未安排"))
                }
            }
        }
        .glassCard()
    }

    private var pace: (String, String) {
        switch ctx.mode {
        case .future: return ("—", "还没开始")
        case .past: return ("\(m.actWork)/\(m.planWork)", "实际 / 计划工作格")
        case .today:
            if m.elapsedPlanWork == 0 { return ("热身", "工作格还没开始") }
            if m.missing > 2 { return ("\(m.missing) 格", "还没记录") }
            if m.lag >= 1 { return ("-\(m.lag) 格", "落后计划") }
            if m.lag <= -1 { return ("+\(-m.lag) 格", "领先计划") }
            return ("准点", "和计划同步")
        }
    }

    private func stat(_ k: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(s).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct IntensityGauge: View {
        let plan: Int?, actual: Int?
        var body: some View {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(.primary.opacity(0.1)).frame(width: w * 0.4 - 2)
                        Capsule().fill(Theme.accent2.opacity(0.35)).frame(width: w * 0.2 - 2)
                        Capsule().fill(Theme.warn.opacity(0.4)).frame(width: w * 0.2 - 2)
                        Capsule().fill(Theme.bad.opacity(0.45))
                    }
                    .frame(height: 8)
                    if let plan { marker(.primary).offset(x: w * CGFloat(plan) / 100 - 2) }
                    if let actual { marker(Theme.accent).offset(x: w * CGFloat(actual) / 100 - 2) }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            .animation(.spring(duration: 0.5), value: plan)
            .animation(.spring(duration: 0.5), value: actual)
        }
        private func marker(_ c: Color) -> some View { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 4, height: 16) }
    }
}

// MARK: - Tasks

struct TasksCard: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var bridge: ArtifactBridge
    let day: DayDoc
    let m: Metrics
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("任务").sectionTitle()
                if !day.tasks.isEmpty {
                    Text("\(day.tasks.filter { day.done[$0.id] == true }.count) / \(day.tasks.count) 完成").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if day.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("这一天还没有任务。").foregroundStyle(.secondary)
                    Button("写计划") { bridge.openWebFeature("compose") }.buttonStyle(.glassProminent)
                }
            }
            ForEach(day.tasks) { t in TaskRow(task: t, day: day, pt: m.perTask[t.id] ?? (0, 0), date: date) }
        }
        .glassCard()
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: PlanStore
    let task: PlanTask
    let day: DayDoc
    let pt: (plan: Int, act: Int)
    let date: String
    @State private var open = false

    var body: some View {
        let done = day.done[task.id] == true
        let color = day.info(task.id)?.color ?? task.cat.color
        HStack(alignment: .top, spacing: 6) {
            Button { store.toggleDone(date, task) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(color, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 9).fill(color).opacity(done ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).opacity(done ? 1 : 0).scaleEffect(done ? 1 : 0.4)
                }
                .frame(width: 28, height: 28)
                .padding(6)
                .contentShape(.rect)
                .animation(.spring(duration: 0.35, bounce: 0.5), value: done)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "取消完成：\(task.title)" : "标记完成：\(task.title)")

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title).font(.subheadline.weight(.semibold)).padding(.top, 6)
                        .strikethrough(done, color: color).foregroundStyle(done ? .secondary : .primary)
                    Text(task.cat.name).font(.caption2.weight(.bold)).foregroundStyle(color)
                    Text(String(repeating: "●", count: task.load) + String(repeating: "○", count: 3 - task.load)).font(.caption2).foregroundStyle(.secondary)
                }
                if !task.detail.isEmpty { Text(task.detail).font(.footnote).foregroundStyle(.secondary) }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.08))
                        Capsule().fill(pt.act > pt.plan ? Theme.bad : color)
                            .frame(width: pt.plan == 0 ? 0 : g.size.width * min(1, CGFloat(pt.act) / CGFloat(pt.plan)))
                    }
                }
                .frame(height: 5)
                Text("计划 \(pt.plan) 格\(day.ranges(of: task.id).isEmpty ? "" : " · " + day.ranges(of: task.id).joined(separator: "，")) · 已用 \(pt.act) 格")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if !task.steps.isEmpty {
                    DisclosureGroup(isExpanded: $open) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(task.steps.enumerated()), id: \.offset) { i, s in
                                let key = "\(task.id)#\(i)", on = day.stepDone[key] == true
                                Button { store.toggleStep(date, key) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? color : .secondary)
                                        Text(s).strikethrough(on).foregroundStyle(on ? .secondary : .primary).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.footnote)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("拆解 · \(task.steps.indices.filter { day.stepDone["\(task.id)#\($0)"] == true }.count)/\(task.steps.count)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 12, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.primary.opacity(0.05)))
    }
}

// MARK: - Strategies

struct StrategyCard: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var bridge: ArtifactBridge
    let day: DayDoc
    let m: Metrics
    let ctx: TimeCtx

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("优化策略").sectionTitle()
                Spacer()
                Button(day.aiReview == nil ? "让 Claude 复盘" : "重新复盘") { bridge.openWebFeature("review") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if let r = day.aiReview, !r.text.isEmpty {
                Text(r.text)
                    .font(.footnote).lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Theme.accent.opacity(0.14), Theme.accent2.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            if !day.advice.isEmpty {
                Text("CLAUDE 的排程说明").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                ForEach(day.advice, id: \.self) { a in
                    row(a.level == "warn" ? .warn : a.level == "good" ? .good : .tip, a.text, nil)
                }
                Text("实时检测").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            }
            ForEach(Strategy.build(day, m, ctx, all: store.days)) { s in row(s.lv, s.title, s.detail) }
        }
        .glassCard()
    }

    private func row(_ lv: Strategy.Lv, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Pill(text: lv.label, symbol: lv.symbol, color: Theme.strategy(lv))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.05)))
    }
}

// MARK: - Note

struct NoteCard: View {
    @EnvironmentObject private var store: PlanStore
    let date: String
    @State private var text = ""
    @State private var loadedFor = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("复盘笔记").sectionTitle()
            TextField("今天哪里卡住了？哪一格最有成就感？", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .focused($focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.05)))
        }
        .glassCard()
        .onAppear { load() }
        .onChange(of: date) { load() }
        .onChange(of: store.day(date).note) { if !focused { load() } }
        .task(id: text) {
            guard loadedFor == date else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { store.setNote(date, text) }
        }
    }

    private func load() { text = store.day(date).note; loadedFor = date }
}
