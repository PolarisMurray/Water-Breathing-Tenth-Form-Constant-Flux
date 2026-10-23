import SwiftUI

/// 24-hour dial: outer ring = plan, inner ring = actual, needle = now.
struct DialView: View {
    let day: DayDoc
    let plan: [String?]
    let actual: [String?]
    let ctx: TimeCtx
    let m: Metrics
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: ctx.mode != .today)) { tl in
                let pulse = 0.55 + 0.45 * sin(tl.date.timeIntervalSinceReferenceDate * 3.9)
                Canvas { c, size in draw(&c, size, pulse: pulse) }
            }
            .overlay { center }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .onTapGesture(coordinateSpace: .local) { loc in
                let dx = loc.x - side / 2, dy = loc.y - side / 2
                let r = hypot(dx, dy) / (side / 2)
                guard r > 0.55, r < 1 else { return }
                var a = atan2(dx, -dy); if a < 0 { a += 2 * .pi }
                onSelect(min(47, Int(a / (2 * .pi) * 48)))
            }
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("48 格表盘，计划工作 \(Dates.hours(m.planWork))，已记录 \(m.recorded) 格")
    }

    private func seg(_ i: Int, r0: Double, r1: Double, c: CGPoint, gap: Double = 0.011) -> Path {
        let a0 = Double(i) / 48 * 2 * .pi - .pi / 2 + gap, a1 = Double(i + 1) / 48 * 2 * .pi - .pi / 2 - gap
        var p = Path()
        p.addRelativeArc(center: c, radius: r1, startAngle: .radians(a0), delta: .radians(a1 - a0))
        p.addRelativeArc(center: c, radius: r0, startAngle: .radians(a1), delta: .radians(a0 - a1))
        p.closeSubpath()
        return p
    }

    private func draw(_ c: inout GraphicsContext, _ size: CGSize, pulse: Double) {
        let R = min(size.width, size.height) / 2, ctr = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = (R * 0.74, R * 0.92), inner = (R * 0.57, R * 0.71)
        c.stroke(Path(ellipseIn: CGRect(x: ctr.x - R * 0.96, y: ctr.y - R * 0.96, width: R * 1.92, height: R * 1.92)), with: .color(.primary.opacity(0.08)), lineWidth: 1)
        for i in 0..<48 {
            let p = day.info(plan[i]), a = day.info(actual[i])
            c.fill(seg(i, r0: outer.0, r1: outer.1, c: ctr), with: .color(p?.color ?? .primary.opacity(0.06)))
            let ap = seg(i, r0: inner.0, r1: inner.1, c: ctr)
            if let a { c.fill(ap, with: .color(a.color)) }
            else if i < ctx.elapsed { c.stroke(ap, with: .color(.secondary), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])) }
            else { c.fill(ap, with: .color(.primary.opacity(0.06))) }
        }
        for h in stride(from: 0, to: 24, by: 3) {
            let a = Double(h) / 24 * 2 * .pi - .pi / 2
            c.draw(Text("\(h)").font(.system(size: R * 0.055, weight: .semibold, design: .rounded)).foregroundStyle(.secondary),
                   at: CGPoint(x: ctr.x + cos(a) * R * 0.5, y: ctr.y + sin(a) * R * 0.5))
        }
        guard ctx.mode == .today else { return }
        var glow = seg(ctx.now, r0: R * 0.55, r1: R * 0.935, c: ctr, gap: 0)
        glow = glow.strokedPath(StrokeStyle(lineWidth: 2.4, lineJoin: .round))
        c.fill(glow, with: .color(Theme.accent.opacity(pulse)))
        let ang = Double(ctx.minutes) / 1440 * 2 * .pi - .pi / 2
        var needle = Path()
        needle.move(to: CGPoint(x: ctr.x + cos(ang) * R * 0.54, y: ctr.y + sin(ang) * R * 0.54))
        let tip = CGPoint(x: ctr.x + cos(ang) * R * 0.95, y: ctr.y + sin(ang) * R * 0.95)
        needle.addLine(to: tip)
        c.stroke(needle, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        c.fill(Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)), with: .color(Theme.accent))
    }

    @ViewBuilder private var center: some View {
        VStack(spacing: 4) {
            switch ctx.mode {
            case .today:
                let p = day.info(plan[ctx.now])
                Text("第 \(ctx.now + 1) / 48 格").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(String(format: "%02d:%02d", ctx.minutes / 60, ctx.minutes % 60))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("\(p?.title ?? "空闲") · 余 \(30 - ctx.minutes % 30) 分").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            default:
                let d = Dates.date(day.date)
                Text(ctx.mode == .future ? "计划" : "回看").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(String(format: "%02d·%02d", Dates.cal.component(.month, from: d), Dates.cal.component(.day, from: d)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(m.planWork > 0 ? "工作 \(Dates.hours(m.planWork)) · 睡眠 \(Dates.hours(m.planSleep))" : "还没有计划").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 170)
        .allowsHitTesting(false)
    }
}
