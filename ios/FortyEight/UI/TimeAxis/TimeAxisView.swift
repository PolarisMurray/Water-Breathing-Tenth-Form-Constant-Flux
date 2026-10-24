import SwiftUI

enum Layer: String, CaseIterable { case actual = "记录实际", plan = "调整计划" }

/// Presented full screen over a clear background: plays the cut-in, then shows the page underneath it.
struct TimeAxisScreen: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var date: String
    @Binding var userNav: Bool
    let focus: Int?
    var onClose: () -> Void

    private struct Cut: Equatable { let kind: AxisCutIn.Kind; let start: Date }
    @State private var cut: Cut?
    @State private var revealed = false
    @State private var closing = false

    var body: some View {
        ZStack {
            if revealed {
                AxisPage(date: $date, userNav: $userNav, focus: focus, close: close)
            }
            if let cut {
                let d = store.day(date)
                AxisCutIn(kind: cut.kind, title: "TIME AXIS", dateLine: Self.stamp(date),
                          subtitle: d.title.isEmpty ? "48 格时间轴" : d.title,
                          stats: "PLAN \(d.plan.compactMap { $0 }.count) · LOGGED \(d.actual.compactMap { $0 }.count)",
                          onCue: { cue(cut.kind, $0) })
                    .id(cut.start)
                if cut.kind == .enter {
                    Color.clear.contentShape(.rect).ignoresSafeArea()
                        .onTapGesture { revealed = true; self.cut = nil }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("跳过动画")
                }
            }
        }
        .statusBarHidden(cut != nil)
        .presentationBackground(.clear)
        .task { await enter() }
    }

    private func enter() async {
        if reduceMotion { withAnimation(.easeOut(duration: 0.25)) { revealed = true }; return }
        cut = Cut(kind: .enter, start: .now)
        Haptics.impact(.heavy)
    }

    private func close() {
        guard !closing else { return }
        closing = true
        if reduceMotion { onClose(); return }
        cut = Cut(kind: .exit, start: .now)
        Haptics.impact(.medium)
    }

    /// The page is swapped while the bars cover the screen; a skipped cut-in has already been cleared.
    private func cue(_ kind: AxisCutIn.Kind, _ c: AxisCutIn.Cue) {
        guard cut?.kind == kind else { return }
        switch (kind, c) {
        case (.enter, .strike): Haptics.impact(.rigid)
        case (.enter, .covered): revealed = true
        case (.enter, .done): cut = nil
        case (.exit, .covered): revealed = false
        case (.exit, .done): onClose()
        default: break
        }
    }

    static func stamp(_ k: String) -> String {
        let d = Dates.date(k), wd = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][Dates.cal.component(.weekday, from: d) - 1]
        return String(format: "%02d.%02d %@", Dates.cal.component(.month, from: d), Dates.cal.component(.day, from: d), wd)
    }
}

/// Press-and-hold then drag, as a UIKit long press: if the finger moves before the press registers,
/// the scroll view takes over, so a swipe that starts on the lane still scrolls. A SwiftUI drag would swallow it.
struct PressDrag: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var action: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.25
        g.allowableMovement = 12
        return g
    }
    func updateUIGestureRecognizer(_ g: UILongPressGestureRecognizer, context: Context) { g.isEnabled = enabled }
    func handleUIGestureRecognizerAction(_ g: UILongPressGestureRecognizer, context: Context) {
        action(g.state, context.converter.localLocation)
    }
}

/// Column widths shared by the pinned headings and the lanes, so they line up. The lane being edited is wider.
struct LaneLayout {
    let gutter: CGFloat = 44, gap: CGFloat = 8
    let plan: CGFloat, actual: CGFloat
    init(_ width: CGFloat, _ layer: Layer) {
        let rest = max(0, width - gutter - gap * 2), wide = (rest * 0.64).rounded()
        plan = layer == .plan ? wide : rest - wide
        actual = rest - plan
    }
}

struct AxisPage: View {
    @EnvironmentObject private var store: PlanStore
    @Binding var date: String
    @Binding var userNav: Bool
    let focus: Int?
    var close: () -> Void

    struct Drag: Equatable {
        var anchor: Int, current: Int
        var range: ClosedRange<Int> { min(anchor, current)...max(anchor, current) }
    }
    private struct Undo { let layer: Layer, date: String, arr: [String?] }
    private struct Brush: Identifiable { let id: String, title: String, short: String, color: Color?, symbol: String? }

    @State private var layer: Layer = .actual
    @State private var brush = "@plan"
    @State private var undo: [Undo] = []
    @State private var info: String?
    @State private var appeared = false
    @State private var target = 16
    @State private var now = Date()
    @State private var ticks = 0
    @State private var confirmClear = false
    @State private var drag: Drag?

    static let rowH: CGFloat = 46

    var body: some View {
        let d = store.day(date), ctx = TimeCtx.of(date, at: now)
        let plan = shown(.plan, d), actual = shown(.actual, d)
        let m = Metrics(d, plan: plan, actual: actual, elapsed: ctx.elapsed)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                        hero(d, m)
                        Section {
                            lanes(d, plan: plan, actual: actual, ctx: ctx)
                        } header: {
                            controls(d, plan: plan, actual: actual, ctx: ctx, proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDisabled(drag != nil)
                .onAppear { start(proxy) }
            }
            .background { StormBackground().ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { dock(d) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar(d, ctx) }
            .confirmationDialog("清空这一天的实际记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { commit(.actual, Array(repeating: nil, count: 48), note: "已清空实际记录") }
            }
        }
        .overlay(alignment: .top) { ToastView() }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: ticks)
        .sensoryFeedback(.selection, trigger: drag?.current)
        .sensoryFeedback(.impact(weight: .medium), trigger: drag != nil) { _, new in new }
        .onChange(of: layer) { fixBrush() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                now = Date()
            }
        }
    }

    private func start(_ proxy: ScrollViewProxy) {
        let d = store.day(date), ctx = TimeCtx.of(date)
        layer = ctx.mode == .future ? .plan : .actual
        fixBrush()
        target = focus ?? (ctx.mode == .today ? ctx.now : d.plan.firstIndex { $0 != nil && $0 != "_sleep" } ?? 16)
        proxy.scrollTo(target, anchor: .center)
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .center)
            appeared = true
        }
    }

    // MARK: painting

    private func value(_ i: Int, _ d: DayDoc) -> String? { brush == "@erase" ? nil : brush == "@plan" ? d.plan[i] : brush }

    /// What a lane shows: the stored array, with the range being dragged already painted.
    private func shown(_ kind: Layer, _ d: DayDoc) -> [String?] {
        var arr = kind == .plan ? d.plan : d.actual
        if kind == layer, let drag { for i in drag.range { arr[i] = value(i, d) } }
        return arr
    }

    private var brushName: String {
        if brush == "@plan" { return "按计划" }
        if brush == "@erase" { return "清除" }
        return store.day(date).info(brush)?.title ?? brush
    }

    private func tap(_ i: Int) {
        let d = store.day(date)
        var arr = layer == .plan ? d.plan : d.actual
        let v = value(i, d)
        if arr[i] == v { info = describe(i, d); return }
        arr[i] = v
        commit(layer, arr, note: "\(Slot.range(i)) → \(brushName)")
    }

    private func commitRange(_ g: Drag) {
        let d = store.day(date)
        var arr = layer == .plan ? d.plan : d.actual
        for i in g.range { arr[i] = value(i, d) }
        commit(layer, arr, note: "\(Slot.time(g.range.lowerBound))–\(Self.end(g.range.upperBound)) · \(g.range.count) 格 → \(brushName)")
    }

    private func commit(_ kind: Layer, _ arr: [String?], note: String) {
        let d = store.day(date), prev = kind == .plan ? d.plan : d.actual
        guard arr != prev else { return }
        undo.append(Undo(layer: kind, date: date, arr: prev))
        if kind == .plan { store.setPlan(date, arr) } else { store.setActual(date, arr) }
        info = note
        ticks += 1
    }

    private func undoLast() {
        guard let u = undo.popLast(), u.date == date else { return }
        if u.layer == .plan { store.setPlan(date, u.arr) } else { store.setActual(date, u.arr) }
        info = "已撤销"
        ticks += 1
    }

    private func describe(_ i: Int, _ d: DayDoc) -> String {
        "\(Slot.range(i)) · 计划 \(d.info(d.plan[i])?.title ?? "空") · 实际 \(d.info(d.actual[i])?.title ?? "未记录")"
    }

    private func shift(_ n: Int) {
        date = Dates.add(date, n)
        userNav = true
        undo.removeAll()
        info = nil
        layer = TimeCtx.of(date).mode == .future ? .plan : .actual
    }

    private func brushes(_ d: DayDoc) -> [Brush] {
        var out: [Brush] = []
        if layer == .actual { out.append(Brush(id: "@plan", title: "按计划", short: "按计划", color: nil, symbol: "checkmark")) }
        for t in d.tasks { out.append(Brush(id: t.id, title: t.title, short: t.short, color: d.info(t.id)?.color, symbol: nil)) }
        for k in Builtin.order where layer == .actual || k != "_slack" {
            if let b = Builtin.all[k] { out.append(Brush(id: k, title: b.title, short: b.title, color: b.cat.color, symbol: nil)) }
        }
        out.append(Brush(id: "@erase", title: "橡皮", short: "橡皮", color: nil, symbol: "eraser"))
        return out
    }

    private func fixBrush() {
        let list = brushes(store.day(date))
        if !list.contains(where: { $0.id == brush }) { brush = layer == .plan ? (list.first { !$0.id.hasPrefix("@") }?.id ?? "_buffer") : "@plan" }
    }

    static func end(_ i: Int) -> String { i == 47 ? "24:00" : Slot.time(i + 1) }

    // MARK: hero

    private func hero(_ d: DayDoc, _ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("TIME AXIS").font(.system(size: 12, weight: .heavy)).tracking(4).foregroundStyle(Storm.lilac)
                Slant(k: 3).fill(Storm.crimson).frame(width: 22, height: 4)
                Text([Dates.label(date), Dates.relative(date)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(d.title.isEmpty ? (d.hasPlan ? "未命名的一天" : "这一天还空着") : d.title)
                .font(.system(size: 30, weight: .black)).italic()
                .lineLimit(2).minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                StatPlate(label: "计划", value: "\(d.plan.compactMap { $0 }.count)", unit: "/48", color: Storm.violet)
                StatPlate(label: "已记录", value: "\(m.recorded)", unit: "/48", color: Storm.crimson)
                StatPlate(label: "吻合度", value: m.match.map { "\(Int(($0 * 100).rounded()))" } ?? "—", unit: m.match == nil ? "" : "%", color: Storm.lilac)
            }
        }
        .padding(.top, 4)
        .offset(x: appeared ? 0 : -40)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.55, bounce: 0.2), value: appeared)
    }

    // MARK: pinned controls

    private func controls(_ d: DayDoc, plan: [String?], actual: [String?], ctx: TimeCtx, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("模式", selection: $layer.animation(.snappy)) { ForEach(Layer.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented)
                if ctx.mode == .today {
                    Button { withAnimation(.snappy) { proxy.scrollTo(ctx.now, anchor: .center) } } label: {
                        Image(systemName: "scope").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("回到现在")
                }
            }
            Minimap(day: d, plan: plan, actual: actual, ctx: ctx) { i in proxy.scrollTo(i, anchor: .center) }
                .frame(height: 27)
            GeometryReader { g in
                let L = LaneLayout(g.size.width, layer)
                HStack(spacing: L.gap) {
                    Color.clear.frame(width: L.gutter)
                    heading("计划", .plan).frame(width: L.plan, alignment: .leading)
                    heading("实际", .actual).frame(width: L.actual, alignment: .leading)
                }
            }
            .frame(height: 16)
        }
        .padding(12)
        .glassEffect(.regular.tint(Storm.ink.opacity(0.35)), in: .rect(cornerRadius: 22))
        .padding(.horizontal, -4)
        .offset(y: appeared ? 0 : 24)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.05), value: appeared)
    }

    private func heading(_ t: String, _ kind: Layer) -> some View {
        let on = kind == layer
        return HStack(spacing: 4) {
            if on { Image(systemName: "pencil").font(.caption2.weight(.heavy)) }
            Text(on ? "\(t) · 编辑中" : t).font(.caption.weight(on ? .heavy : .semibold))
        }
        .foregroundStyle(on ? AnyShapeStyle(Storm.lilac) : AnyShapeStyle(.secondary))
        .padding(.leading, 10)
    }

    // MARK: lanes

    private func lanes(_ d: DayDoc, plan: [String?], actual: [String?], ctx: TimeCtx) -> some View {
        GeometryReader { g in
            let L = LaneLayout(g.size.width, layer)
            ZStack(alignment: .topLeading) {
                Canvas { c, size in
                    for i in stride(from: 0, through: 48, by: 2) {
                        let y = CGFloat(i) * Self.rowH
                        c.fill(Path(CGRect(x: L.gutter, y: y - 0.25, width: size.width - L.gutter, height: 0.5)), with: .color(.white.opacity(i % 12 == 0 ? 0.14 : 0.06)))
                    }
                }
                .allowsHitTesting(false)
                HStack(alignment: .top, spacing: L.gap) {
                    timeColumn.frame(width: L.gutter)
                    lane(.plan, d, plan, plan: plan, ctx: ctx).frame(width: L.plan)
                    lane(.actual, d, actual, plan: plan, ctx: ctx).frame(width: L.actual)
                }
                if ctx.mode == .today { nowLine(ctx, width: g.size.width) }
            }
        }
        .frame(height: 48 * Self.rowH)
        .padding(.horizontal, 8)
    }

    private var timeColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<48, id: \.self) { i in
                Text(i % 2 == 0 ? Slot.time(i) : "")
                    .font(.system(size: 11, weight: i % 12 == 0 ? .heavy : .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(i % 12 == 0 ? AnyShapeStyle(Storm.lilac) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(y: i == 0 ? 0 : -7)
                    .frame(height: Self.rowH)
                    .id(i)
            }
        }
    }

    private func lane(_ kind: Layer, _ d: DayDoc, _ arr: [String?], plan: [String?], ctx: TimeCtx) -> some View {
        let editable = kind == layer
        let range = editable ? drag?.range : nil
        let compact = !editable
        return VStack(spacing: 0) {
            ForEach(0..<48, id: \.self) { i in
                let start = i == 0 || arr[i - 1] != arr[i], end = i == 47 || arr[i + 1] != arr[i]
                let info = d.info(arr[i])
                let missing = kind == .actual && arr[i] == nil && i < ctx.elapsed
                LaneCell(info: info, start: start, end: end,
                         label: start ? label(kind, d, arr, plan, i, compact: compact) : nil,
                         offPlan: kind == .actual && info != nil && plan[i] != nil && plan[i] != arr[i] ? d.info(plan[i])?.color : nil,
                         missing: missing, missingLabel: missing && (i == 0 || !(arr[i - 1] == nil && i - 1 < ctx.elapsed)))
                    .frame(height: Self.rowH)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : (kind == .plan ? -36 : 36))
                    .animation(.spring(duration: 0.5, bounce: 0.22).delay(min(0.42, Double(abs(i - target)) * 0.028)), value: appeared)
            }
        }
        .contentShape(.rect)
        .opacity(editable ? 1 : 0.6)
        .overlay(alignment: .topLeading) {
            if let range {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                        .shadow(color: Storm.lilac.opacity(0.9), radius: 8)
                        .frame(height: CGFloat(range.count) * Self.rowH - 4)
                        .offset(y: CGFloat(range.lowerBound) * Self.rowH + 2)
                    Text("\(Slot.time(range.lowerBound))–\(Self.end(range.upperBound)) · \(range.count) 格")
                        .font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Slant(k: 5).fill(Storm.crimson).shadow(color: Storm.crimson.opacity(0.6), radius: 8))
                        .fixedSize()
                        .offset(x: -4, y: max(-30, CGFloat(range.lowerBound) * Self.rowH - 30))
                }
                .allowsHitTesting(false)
            }
        }
        .onTapGesture(coordinateSpace: .local) { p in
            if editable { tap(Self.row(p.y)) } else { withAnimation(.snappy) { layer = kind }; info = "切换到「\(kind.rawValue)」" }
        }
        .gesture(PressDrag(enabled: editable) { state, p in
            switch state {
            case .began: drag = Drag(anchor: Self.row(p.y), current: Self.row(p.y))
            case .changed: if drag != nil, drag?.current != Self.row(p.y) { drag?.current = Self.row(p.y) }
            case .ended: if let g = drag { drag = nil; commitRange(g) }
            default: drag = nil
            }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .plan ? "计划列" : "实际列")
        .accessibilityHint(editable ? "点按涂一格，长按拖动涂一段" : "点按切换到这一列")
    }

    private static func row(_ y: CGFloat) -> Int { max(0, min(47, Int(y / rowH))) }

    private func label(_ kind: Layer, _ d: DayDoc, _ arr: [String?], _ plan: [String?], _ i: Int, compact: Bool) -> LaneCell.Label? {
        guard let info = d.info(arr[i]) else { return nil }
        var j = i
        while j < 47, arr[j + 1] == arr[i] { j += 1 }
        let n = j - i + 1
        let time = compact ? Dates.hours(n) : "\(Slot.time(i))–\(Self.end(j)) · \(Dates.hours(n))"
        var sub = time
        if kind == .actual, let p = plan[i], p != arr[i], let pi = d.info(p) { sub = compact ? "≠ \(pi.short)" : "原计划 \(pi.title)" }
        return LaneCell.Label(title: compact ? info.short : info.title, sub: sub, rows: n,
                              matched: kind == .actual && plan[i] == arr[i])
    }

    private func nowLine(_ ctx: TimeCtx, width: CGFloat) -> some View {
        let y = CGFloat(ctx.minutes) / 30 * Self.rowH
        return ZStack(alignment: .leading) {
            Rectangle().fill(Storm.crimson).frame(height: 2)
                .shadow(color: Storm.crimson, radius: 6)
                .padding(.leading, 36)
            Text(String(format: "%02d:%02d", ctx.minutes / 60, ctx.minutes % 60))
                .font(.system(size: 10.5, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Slant(k: 4).fill(Storm.crimson))
        }
        .frame(width: width, height: 16)
        .offset(y: y - 8)
        .allowsHitTesting(false)
    }

    // MARK: brush dock

    private func dock(_ d: DayDoc) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(info ?? (layer == .actual ? "选画笔 · 点按记一格 · 长按再拖动记一段" : "选任务 · 点按排一格 · 长按再拖动排一段"))
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(info == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Storm.lilac))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .contentTransition(.opacity)
                .animation(.snappy, value: info)
            ScrollViewReader { sp in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(brushes(d)) { b in chip(b).id(b.id) } }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: brush) { withAnimation(.snappy) { sp.scrollTo(brush, anchor: .center) } }
            }
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .offset(y: appeared ? 0 : 160)
        .animation(.spring(duration: 0.55, bounce: 0.22).delay(0.12), value: appeared)
    }

    private func chip(_ b: Brush) -> some View {
        let on = b.id == brush, c = b.color ?? Storm.lilac
        return Button {
            withAnimation(.snappy) { brush = b.id }
            info = nil
        } label: {
            HStack(spacing: 6) {
                if let s = b.symbol { Image(systemName: s).font(.caption.weight(.bold)) }
                else { Slant(k: 3).fill(c).frame(width: 13, height: 12) }
                Text(on ? b.title : b.short).font(.footnote.weight(on ? .bold : .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(on ? c.opacity(0.32) : Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(on ? c : .clear, lineWidth: 1.5))
            .shadow(color: on ? c.opacity(0.55) : .clear, radius: 8)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: toolbar

    @ToolbarContentBuilder private func toolbar(_ d: DayDoc, _ ctx: TimeCtx) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("关闭时间轴")
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 4) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.footnote.weight(.bold)) }
                    .accessibilityLabel("前一天")
                VStack(spacing: 0) {
                    Text(Dates.label(date)).font(.subheadline.weight(.bold))
                    Text(Dates.relative(date) ?? TimeAxisScreen.stamp(date)).font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(Storm.lilac)
                }
                .frame(minWidth: 104)
                Button { shift(1) } label: { Image(systemName: "chevron.right").font(.footnote.weight(.bold)) }
                    .accessibilityLabel("后一天")
            }
            .buttonStyle(.plain)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: undoLast) { Image(systemName: "arrow.uturn.backward") }
                .disabled(undo.isEmpty)
                .accessibilityLabel("撤销")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("当前格按计划", systemImage: "checkmark.circle") {
                    var a = d.actual; a[ctx.now] = d.plan[ctx.now]
                    commit(.actual, a, note: "\(Slot.range(ctx.now)) → 按计划")
                }
                .disabled(ctx.mode != .today || d.plan[ctx.now] == nil)
                Button("按计划补齐到现在", systemImage: "text.append") {
                    var a = d.actual, n = 0
                    for i in 0..<ctx.elapsed where a[i] == nil && d.plan[i] != nil { a[i] = d.plan[i]; n += 1 }
                    if n > 0 { commit(.actual, a, note: "按计划补齐了 \(n) 格") } else { info = "没有需要补齐的格子" }
                }
                .disabled(ctx.elapsed == 0)
                Divider()
                Button("清空实际记录", systemImage: "trash", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("更多")
        }
    }
}

/// One half hour of a lane. Neighbouring cells with the same token join into one block.
struct LaneCell: View {
    struct Label { let title: String, sub: String, rows: Int, matched: Bool }
    let info: TokenInfo?
    let start: Bool, end: Bool
    let label: Label?
    let offPlan: Color?
    let missing: Bool, missingLabel: Bool

    var body: some View {
        let r: CGFloat = 12
        let shape = UnevenRoundedRectangle(topLeadingRadius: start ? r : 0, bottomLeadingRadius: end ? r : 0,
                                           bottomTrailingRadius: end ? r : 0, topTrailingRadius: start ? r : 0, style: .continuous)
        ZStack(alignment: .topLeading) {
            if let info {
                shape.fill(LinearGradient(colors: [info.color, info.color.mix(with: .black, by: 0.2)], startPoint: .top, endPoint: .bottom))
                if start { shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)) }
                else { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
                if let offPlan { Rectangle().fill(offPlan).frame(width: 4).frame(maxHeight: .infinity) }
                if let label {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(label.title).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                            if label.matched { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                        }
                        Text(label.sub).font(.system(size: 10.5, weight: .semibold)).monospacedDigit().opacity(0.82).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(.leading, offPlan == nil ? 10 : 12).padding(.trailing, 6)
                    .padding(.top, label.rows == 1 ? 4 : 8)
                }
            } else if missing {
                shape.fill(.white.opacity(0.035))
                Hatch().stroke(.white.opacity(0.09), lineWidth: 1).clipShape(shape)
                if missingLabel { Text("未记录").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 6) }
            } else {
                shape.fill(.white.opacity(0.035))
            }
        }
        .clipShape(shape)
        .padding(.top, start ? 2 : 0)
        .padding(.bottom, end ? 2 : 0)
    }
}

/// The whole day in one strip: plan on top, actual below. Dragging along it scrubs the timeline.
struct Minimap: View {
    let day: DayDoc, plan: [String?], actual: [String?], ctx: TimeCtx
    var jump: ((Int) -> Void)? = nil
    @State private var last = -1

    var body: some View {
        GeometryReader { g in
            Canvas { c, size in
                let w = size.width / 48, ph = size.height * 0.55, ah = size.height * 0.32
                for i in 0..<48 {
                    let x = CGFloat(i) * w
                    let p = day.info(plan[i]), a = day.info(actual[i])
                    c.fill(Path(roundedRect: CGRect(x: x + 0.5, y: 0, width: w - 1, height: ph), cornerRadius: 1.5),
                           with: .color(p?.color ?? .white.opacity(0.08)))
                    c.fill(Path(roundedRect: CGRect(x: x + 0.5, y: size.height - ah, width: w - 1, height: ah), cornerRadius: 1.5),
                           with: .color(a?.color ?? .white.opacity(i < ctx.elapsed ? 0.2 : 0.06)))
                }
                for h in [12, 24, 36] {
                    c.fill(Path(CGRect(x: CGFloat(h) * w - 0.5, y: ph + 1, width: 1, height: size.height - ph - ah - 2)), with: .color(.white.opacity(0.35)))
                }
                if ctx.mode == .today {
                    let x = CGFloat(ctx.minutes) / 1440 * size.width
                    c.fill(Path(CGRect(x: x - 1, y: -2, width: 2, height: size.height + 4)), with: .color(Storm.crimson))
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard let jump else { return }
                        let i = max(0, min(47, Int(v.location.x / max(1, g.size.width) * 48)))
                        if i != last { last = i; jump(i) }
                    }
                    .onEnded { _ in last = -1 },
                including: jump == nil ? .none : .all)
        }
        .sensoryFeedback(.selection, trigger: last) { _, new in new >= 0 }
        .accessibilityElement()
        .accessibilityLabel("全天缩略条：上为计划，下为实际")
    }
}

struct StatPlate: View {
    let label: String, value: String, unit: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).italic().monospacedDigit()
                Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                Slant(k: 10).fill(.white.opacity(0.07))
                Slant(k: 10).fill(color).frame(width: 15)
            }
        }
        .overlay(Slant(k: 10).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Today's entry point: the day as one strip plus what is happening now. Tap to enter the time axis.
struct AxisEntryCard: View {
    let day: DayDoc
    let ctx: TimeCtx
    let m: Metrics
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("时间轴").sectionTitle()
                    Text("48 TOKENS").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 3) { Text("进入"); Image(systemName: "chevron.right") }
                        .font(.footnote.weight(.heavy)).foregroundStyle(.white)
                        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 6)
                        .background(Slant(k: 7).fill(LinearGradient(colors: [Storm.crimson, Storm.violet], startPoint: .leading, endPoint: .trailing)))
                }
                Minimap(day: day, plan: day.plan, actual: day.actual, ctx: ctx).frame(height: 30)
                HStack {
                    ForEach(["0", "6", "12", "18", "24"], id: \.self) { h in
                        Text(h).frame(maxWidth: .infinity, alignment: h == "0" ? .leading : h == "24" ? .trailing : .center)
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.tertiary)
                .padding(.top, -8)
                HStack(alignment: .firstTextBaseline) {
                    Text(status).font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("已记录 \(m.recorded)/48").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .accessibilityHint("打开 48 格时间轴，可以编辑计划和实际")
    }

    private var status: String {
        switch ctx.mode {
        case .today:
            let cur = day.info(day.plan[ctx.now])
            var j = ctx.now + 1
            while j < 48, day.plan[j] == day.plan[ctx.now] { j += 1 }
            let next = j < 48 ? day.info(day.plan[j]) : nil
            return "现在 \(cur?.short ?? "空闲")" + (next.map { " → \(Slot.time(j)) \($0.short)" } ?? "")
        case .future:
            return day.hasPlan ? "已排 \(day.plan.compactMap { $0 }.count) 格 · 工作 \(Dates.hours(m.planWork))" : "还没有计划，进去排一排"
        case .past:
            return "吻合度 \(m.match.map { "\(Int(($0 * 100).rounded()))%" } ?? "—") · 工作 \(Dates.hours(m.actWork))"
        }
    }
}
