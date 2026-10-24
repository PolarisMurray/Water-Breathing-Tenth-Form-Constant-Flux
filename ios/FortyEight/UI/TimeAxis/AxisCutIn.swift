import SwiftUI

/// Honkai-style cut-in, drawn per frame from the elapsed time.
/// Enter: slanted bars slam across, thunder strikes, a title band opens and syncs, then the bars fly off.
/// Exit: the bars sweep through the screen once, so the page underneath can be swapped while covered.
struct AxisCutIn: View {
    enum Kind { case enter, exit }

    let kind: Kind
    let start: Date
    let title: String      // "TIME AXIS"
    let dateLine: String   // "10.24 SAT"
    let subtitle: String   // the day's title
    let stats: String      // "PLAN 37 · LOGGED 0"

    static func duration(_ k: Kind) -> Double { k == .enter ? 1.15 : 0.6 }
    /// When the screen is fully covered, so the page can be shown or removed unseen.
    static func covered(_ k: Kind) -> Double { k == .enter ? 0.8 : 0.26 }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { c, size in
                switch kind {
                case .enter: drawEnter(&c, size, t)
                case .exit: drawExit(&c, size, t)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: timing helpers

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func easeOut(_ x: Double) -> Double { let p = clamp(x); return 1 - pow(1 - p, 3) }
    private func easeIn(_ x: Double) -> Double { let p = clamp(x); return p * p * p }

    // MARK: bars

    /// Four slanted bars, one per horizontal band. `dx(k)` is how far bar k is pushed sideways.
    private func bars(_ c: inout GraphicsContext, _ size: CGSize, _ dx: (Int) -> Double) {
        let W = size.width, H = size.height, n = 4
        let bh = H / Double(n), slant = bh * 0.42
        let accents = [Storm.crimson, Storm.violet, Storm.lilac, Storm.crimson]
        for k in 0..<n {
            let off = dx(k)
            guard abs(off) < W + slant * 2 + 40 else { continue }
            let y0 = Double(k) * bh - 1, y1 = y0 + bh + 2
            let L = -slant - 6 + off, R = W + 6 + off
            var bar = Path()
            bar.move(to: CGPoint(x: L + slant, y: y0)); bar.addLine(to: CGPoint(x: R + slant, y: y0))
            bar.addLine(to: CGPoint(x: R, y: y1)); bar.addLine(to: CGPoint(x: L, y: y1)); bar.closeSubpath()
            c.fill(bar, with: .linearGradient(Gradient(colors: [Color(hex: 0x14142a), Storm.ink]),
                                              startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)))
            // faint hatching inside the bar
            var hatch = Path(), hx = L
            while hx < R { hatch.move(to: CGPoint(x: hx + slant, y: y0)); hatch.addLine(to: CGPoint(x: hx, y: y1)); hx += 26 }
            var inner = c
            inner.clip(to: bar)
            inner.stroke(hatch, with: .color(.white.opacity(0.035)), lineWidth: 1)
            // bright leading edges on both slanted sides
            for (edge, w) in [(L, 7.0), (R, -7.0)] {
                var e = Path()
                e.move(to: CGPoint(x: edge + slant, y: y0)); e.addLine(to: CGPoint(x: edge + slant + w, y: y0))
                e.addLine(to: CGPoint(x: edge + w, y: y1)); e.addLine(to: CGPoint(x: edge, y: y1)); e.closeSubpath()
                c.fill(e, with: .color(accents[k]))
            }
        }
    }

    private func bolt(_ c: inout GraphicsContext, _ size: CGSize, alpha: Double) {
        guard alpha > 0 else { return }
        var g = Seeded(0x48)
        let s = CGPoint(x: size.width * 0.9, y: -20), e = CGPoint(x: size.width * 0.08, y: size.height + 20)
        let dx = e.x - s.x, dy = e.y - s.y, len = hypot(dx, dy), nx = -dy / len, ny = dx / len
        var p = Path(); p.move(to: s)
        var fork: CGPoint?
        for k in 1..<18 {
            let f = Double(k) / 18, j = (g.next() - 0.5) * 2 * (k % 2 == 0 ? 30 : 14)
            let pt = CGPoint(x: s.x + dx * f + nx * j, y: s.y + dy * f + ny * j)
            p.addLine(to: pt)
            if k == 7 { fork = pt }
        }
        p.addLine(to: e)
        if var q = fork {
            p.move(to: q)
            for _ in 0..<5 { q = CGPoint(x: q.x - 24 - g.next() * 30, y: q.y + 6 + g.next() * 26); p.addLine(to: q) }
        }
        let st = { (w: Double) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        c.stroke(p, with: .color(Storm.violet.opacity(0.3 * alpha)), style: st(34))
        c.stroke(p, with: .color(Storm.lilac.opacity(0.75 * alpha)), style: st(11))
        c.stroke(p, with: .color(.white.opacity(alpha)), style: st(3.5))
    }

    // MARK: enter

    private func drawEnter(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let W = size.width, H = size.height
        let travel = W + H / 4 * 0.42 * 2 + 20
        bars(&c, size) { k in
            let dir: Double = k % 2 == 0 ? 1 : -1
            let inP = easeOut((t - 0.03 * Double(k)) / 0.2)
            let outP = easeIn((t - 0.84 - 0.035 * Double(k)) / 0.24)
            return dir * travel * (1 - inP) - dir * travel * outP
        }

        // thunder strike with a double flicker
        let boltA: Double = {
            if t < 0.15 || t > 0.47 { return 0 }
            if t < 0.21 { return 1 }
            if t < 0.25 { return 0.25 }
            if t < 0.33 { return 1 }
            return 1 - (t - 0.33) / 0.14
        }()
        bolt(&c, size, alpha: boltA)

        // title band
        let open = easeOut((t - 0.24) / 0.12) * (1 - easeIn((t - 0.78) / 0.09))
        if open > 0.01 { band(&c, size, t, open: open) }

        // white flash on impact
        let flash = (t > 0.15 ? 0.55 * exp(-(t - 0.15) * 16) : 0) + (t > 0.26 ? 0.25 * exp(-(t - 0.26) * 18) : 0)
        if flash > 0.01 { c.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.white.opacity(flash))) }
    }

    private func band(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double, open: Double) {
        let W = size.width, H = size.height
        let cy = H * 0.47, h = 182 * open, sl = 26 * open
        var shape = Path()
        shape.move(to: CGPoint(x: -40 + sl, y: cy - h / 2)); shape.addLine(to: CGPoint(x: W + 40 + sl, y: cy - h / 2))
        shape.addLine(to: CGPoint(x: W + 40, y: cy + h / 2)); shape.addLine(to: CGPoint(x: -40, y: cy + h / 2)); shape.closeSubpath()
        c.fill(shape, with: .linearGradient(Gradient(colors: [Storm.crimson, Storm.magenta, Storm.violet]),
                                            startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: W, y: cy)))
        // rims
        c.fill(Path(CGRect(x: -40, y: cy - h / 2 - 3, width: W + 80, height: 3)), with: .color(.white.opacity(0.9)))
        c.fill(Path(CGRect(x: -40, y: cy + h / 2, width: W + 80, height: 3)), with: .color(Storm.ink))

        var inside = c
        inside.clip(to: shape)
        // moving ink stripes and speed lines
        var stripes = Path(), sx = -h + (t * 140).truncatingRemainder(dividingBy: 22)
        while sx < W + h { stripes.move(to: CGPoint(x: sx + h * 0.5, y: cy - h / 2)); stripes.addLine(to: CGPoint(x: sx, y: cy + h / 2)); sx += 22 }
        inside.stroke(stripes, with: .color(Storm.ink.opacity(0.13)), lineWidth: 6)
        var g = Seeded(9)
        for _ in 0..<16 {
            let y = cy - h / 2 + g.next() * h, len = 50 + g.next() * 150, v = 900 + g.next() * 900
            let x = W + 120 - ((g.next() * (W + 240) + t * v).truncatingRemainder(dividingBy: W + 240))
            inside.fill(Path(CGRect(x: x, y: y, width: len, height: 1.5)), with: .color(.white.opacity(0.35)))
        }

        guard open > 0.6 else { return }
        let a = (open - 0.6) / 0.4
        inside.opacity = a
        let drift = (t - 0.28) * 28
        // ghost numeral
        inside.draw(Text("48").font(.system(size: 168, weight: .black)).italic().foregroundStyle(.white.opacity(0.16)),
                    at: CGPoint(x: W - 10 - drift * 0.8, y: cy + 6), anchor: .trailing)
        inside.draw(Text("CHRONO SYNC  //  48 TOKENS").font(.system(size: 11, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.85)),
                    at: CGPoint(x: 26 + drift * 0.4, y: cy - 60), anchor: .leading)
        // title with a decaying chromatic split and a hard manga shadow
        let split = max(0, 1 - (t - 0.3) / 0.2) * 8
        let font = Font.system(size: 58, weight: .black).italic()
        let tp = CGPoint(x: 20 + drift, y: cy - 12)
        inside.draw(Text(title).font(font).foregroundStyle(Storm.ink), at: CGPoint(x: tp.x + 4, y: tp.y + 4), anchor: .leading)
        if split > 0.3 {
            var cc = inside
            cc.blendMode = .screen
            cc.draw(Text(title).font(font).foregroundStyle(Color(hex: 0xff2050)), at: CGPoint(x: tp.x - split, y: tp.y), anchor: .leading)
            cc.draw(Text(title).font(font).foregroundStyle(Color(hex: 0x40e0ff)), at: CGPoint(x: tp.x + split, y: tp.y), anchor: .leading)
        }
        inside.draw(Text(title).font(font).foregroundStyle(.white), at: tp, anchor: .leading)
        inside.draw(Text("\(dateLine)  ·  \(subtitle)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white),
                    at: CGPoint(x: 26 + drift * 0.6, y: cy + 34), anchor: .leading)
        // sync bar
        let p = easeOut((t - 0.32) / 0.42)
        let barY = cy + 62, barW = (W - 52) * p
        inside.fill(Path(CGRect(x: 26, y: barY, width: W - 52, height: 2)), with: .color(Storm.ink.opacity(0.35)))
        inside.fill(Path(CGRect(x: 26, y: barY - 0.5, width: barW, height: 3)), with: .color(.white))
        inside.draw(Text("\(stats)   SYNC \(Int(p * 100))%").font(.system(size: 10, weight: .heavy)).monospacedDigit().tracking(1).foregroundStyle(.white),
                    at: CGPoint(x: W - 26, y: barY - 10), anchor: .trailing)
    }

    // MARK: exit

    private func drawExit(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let W = size.width, H = size.height
        let travel = W + H / 4 * 0.42 * 2 + 20
        bars(&c, size) { k in
            let dir: Double = k % 2 == 0 ? -1 : 1
            let inP = easeOut((t - 0.025 * Double(k)) / 0.2)
            let outP = easeIn((t - 0.3 - 0.03 * Double(k)) / 0.22)
            return dir * travel * (1 - inP) - dir * travel * outP
        }
        // a single crimson slash while covered
        let s = easeOut((t - 0.12) / 0.14), fade = 1 - clamp((t - 0.3) / 0.1)
        if s > 0, fade > 0 {
            var p = Path()
            p.move(to: CGPoint(x: W * 1.05, y: H * 0.2))
            p.addLine(to: CGPoint(x: W * 1.05 - W * 1.15 * s, y: H * 0.2 + H * 0.6 * s))
            c.stroke(p, with: .color(Storm.crimson.opacity(fade)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            c.stroke(p, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}
