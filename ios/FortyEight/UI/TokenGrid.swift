import SwiftUI

enum Layer: String, CaseIterable { case actual = "记录实际", plan = "调整计划" }

/// The 48 cells. Tap paints one cell; press-and-hold then drag paints a run of cells,
/// so a normal swipe still scrolls the page.
struct TokenGrid: View {
    let day: DayDoc
    let plan: [String?]
    let actual: [String?]
    let ctx: TimeCtx
    let layer: Layer
    let cols: Int
    var paint: (Int) -> Void
    var commit: () -> Void

    private let labelW: CGFloat = 40, gap: CGFloat = 5, cellH: CGFloat = 46
    private var rows: Int { 48 / cols }
    @State private var lastPainted = -1
    @State private var ticks = 0

    var body: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - labelW - gap * CGFloat(cols)) / CGFloat(cols)
            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { r in
                    Text(Slot.time(r * cols))
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: labelW, height: cellH, alignment: .leading)
                        .offset(y: CGFloat(r) * (cellH + gap))
                }
                ForEach(0..<48, id: \.self) { i in
                    cell(i)
                        .frame(width: cellW, height: cellH)
                        .offset(x: labelW + gap + CGFloat(i % cols) * (cellW + gap), y: CGFloat(i / cols) * (cellH + gap))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                if let i = index(loc, cellW) { paint(i); ticks += 1; commit() }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.22)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { v in
                        guard case .second(true, let drag?) = v, let i = index(drag.location, cellW), i != lastPainted else { return }
                        lastPainted = i; ticks += 1; paint(i)
                    }
                    .onEnded { _ in lastPainted = -1; commit() }
            )
        }
        .frame(height: CGFloat(rows) * (cellH + gap) - gap)
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private func index(_ p: CGPoint, _ cellW: CGFloat) -> Int? {
        let x = p.x - labelW - gap
        guard x >= 0, p.y >= 0 else { return nil }
        let c = Int(x / (cellW + gap)), r = Int(p.y / (cellH + gap))
        guard c < cols, r < rows else { return nil }
        return r * cols + c
    }

    @ViewBuilder private func cell(_ i: Int) -> some View {
        let p = day.info(plan[i]), a = day.info(actual[i])
        let filled = layer == .plan ? p != nil : a != nil
        let fill = layer == .plan ? p?.color : (a?.color ?? p?.color)
        let bar: Color? = layer == .actual && p != nil && a?.id != p?.id ? p?.color : nil
        let label = layer == .plan ? (p?.short ?? "") : (a?.short ?? p?.short ?? "")
        TokenCell(fill: fill, filled: filled, bar: bar, label: label,
                  diff: layer == .actual && a != nil && p != nil && a?.id != p?.id,
                  missing: layer == .actual && a == nil && i < ctx.elapsed,
                  isNow: i == ctx.now)
            .accessibilityElement()
            .accessibilityLabel("\(Slot.range(i))，计划 \(p?.title ?? "空")，实际 \(a?.title ?? "未记录")")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { paint(i); commit() }
    }
}

struct TokenCell: View {
    let fill: Color?
    let filled: Bool
    let bar: Color?
    let label: String
    let diff: Bool
    let missing: Bool
    let isNow: Bool
    @State private var glow = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        ZStack {
            if filled, let fill {
                shape.fill(fill)
                shape.fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
            } else {
                shape.fill((fill ?? .primary).opacity(fill == nil ? 0.05 : 0.17))
            }
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
                .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .shadow(color: filled ? .black.opacity(0.25) : .clear, radius: 1, y: 1)
        }
        .overlay(alignment: .top) {
            if let bar { Capsule().fill(bar).frame(height: 3).padding(.horizontal, 6).padding(.top, 4) }
        }
        .overlay(alignment: .bottomTrailing) {
            if diff, let bar { Triangle().fill(bar).frame(width: 11, height: 11) }
        }
        .clipShape(shape)
        .overlay {
            if missing { shape.strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            else if !filled { shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
        }
        .overlay {
            if isNow {
                shape.strokeBorder(Theme.accent, lineWidth: 2)
                    .shadow(color: Theme.accent.opacity(glow ? 0.9 : 0.2), radius: glow ? 10 : 2)
                    .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true } }
            }
        }
        .animation(.spring(duration: 0.25), value: filled)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}
