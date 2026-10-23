import SwiftUI

/// Anime twilight sky (dark) / daytime sky with drifting sakura (light).
/// Everything is a pure function of time, so it renders at the display's full refresh rate.
struct SkyBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: scheme == .dark ? Self.night : Self.day)
                Canvas(rendersAsynchronously: true) { ctx, size in
                    if scheme == .dark { Self.drawNight(&ctx, size, t) } else { Self.drawDay(&ctx, size, t) }
                }
            }
        }
        .overlay(alignment: .bottom) { Skyline(dark: scheme == .dark).frame(height: 230) }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    static let night: [Color] = [
        Color(hex: 0x04061a), Color(hex: 0x0a0f38), Color(hex: 0x070b26),
        Color(hex: 0x1d1754), Color(hex: 0x2c1a5e), Color(hex: 0x141a4a),
        Color(hex: 0x8a3a6b), Color(hex: 0xb44f6e), Color(hex: 0x5e2862),
    ]
    static let day: [Color] = [
        Color(hex: 0x7fbfff), Color(hex: 0x9fd0ff), Color(hex: 0x8cc6ff),
        Color(hex: 0xd6ebff), Color(hex: 0xeaf4ff), Color(hex: 0xc9e4ff),
        Color(hex: 0xffd9e6), Color(hex: 0xffcdbd), Color(hex: 0xffe4ee),
    ]

    static func points(_ t: Double) -> [SIMD2<Float>] {
        let s = { (p: Double, a: Double) in Float(sin(t * p) * a) }
        return [
            [0, 0], [0.5 + s(0.11, 0.08), 0], [1, 0],
            [0, 0.45 + s(0.09, 0.06)], [0.5 + s(0.07, 0.12), 0.55 + s(0.13, 0.08)], [1, 0.5 + s(0.08, 0.07)],
            [0, 1], [0.5 + s(0.1, 0.1), 1], [1, 1],
        ]
    }

    // Seeded so the sky looks the same on every launch.
    struct Star { let x, y, r, ph, sp, a: Double }
    struct Mote { let x, y, r, vy, sw: Double; let cyan: Bool }
    struct Petal { let x, y, s, vx, vy, rot, vr, sw: Double }
    static let stars: [Star] = { var g = Seeded(48); return (0..<150).map { _ in Star(x: g.next(), y: pow(g.next(), 1.4) * 0.78, r: 0.6 + g.next() * 1.4, ph: g.next() * 6.28, sp: 0.6 + g.next() * 2.2, a: 0.35 + g.next() * 0.65) } }()
    static let motes: [Mote] = { var g = Seeded(7); return (0..<14).map { _ in Mote(x: g.next(), y: g.next(), r: 14 + g.next() * 34, vy: 0.006 + g.next() * 0.012, sw: g.next() * 6.28, cyan: g.next() < 0.45) } }()
    static let petals: [Petal] = { var g = Seeded(21); return (0..<26).map { _ in Petal(x: g.next(), y: g.next(), s: 9 + g.next() * 11, vx: 0.01 + g.next() * 0.02, vy: 0.025 + g.next() * 0.035, rot: g.next() * 6.28, vr: (g.next() - 0.5) * 2.4, sw: g.next() * 6.28) } }()

    static func wrap(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        let span = hi - lo
        var r = (v - lo).truncatingRemainder(dividingBy: span)
        if r < 0 { r += span }
        return lo + r
    }

    static func drawNight(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for s in stars {
            let tw = 0.45 + 0.55 * pow(sin(t * s.sp + s.ph), 2)
            let rect = CGRect(x: s.x * size.width - s.r, y: s.y * size.height - s.r, width: s.r * 2, height: s.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(s.a * tw)))
        }
        ctx.blendMode = .plusLighter
        for m in motes {
            let y = wrap(m.y - m.vy * t, -0.1, 1.1) * size.height
            let x = (m.x + sin(t * 0.3 + m.sw) * 0.015) * size.width
            let c = m.cyan ? Color(hex: 0x78dcff) : Color(hex: 0xff96c8)
            ctx.fill(Path(ellipseIn: CGRect(x: x - m.r, y: y - m.r, width: m.r * 2, height: m.r * 2)),
                     with: .radialGradient(Gradient(colors: [c.opacity(0.28), c.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: m.r))
        }
        ctx.blendMode = .normal
        // A meteor every 9 s, position seeded by its cycle number.
        let cycle = floor(t / 9), k = (t - cycle * 9) / 1.1
        if k < 1 {
            var g = Seeded(UInt64(abs(cycle).truncatingRemainder(dividingBy: 100000)) + 3)
            let sx = (0.35 + g.next() * 0.6) * size.width, sy = g.next() * 0.3 * size.height, len = 120 + g.next() * 140
            let ang = 2.6, dist = k * len * 2.2
            let head = CGPoint(x: sx + cos(ang) * dist, y: sy + sin(ang) * dist)
            let tail = CGPoint(x: head.x - cos(ang) * len, y: head.y - sin(ang) * len)
            var p = Path(); p.move(to: head); p.addLine(to: tail)
            ctx.opacity = sin(k * .pi)
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [.white, Color(hex: 0xffc8e6).opacity(0)]), startPoint: head, endPoint: tail), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.opacity = 1
        }
    }

    static func drawDay(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for p in petals {
            let y = wrap(p.y + p.vy * t, -0.08, 1.08) * size.height
            let x = wrap(p.x + p.vx * t + sin(t * 0.8 + p.sw) * 0.012, -0.1, 1.1) * size.width
            var c = ctx
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(p.rot + p.vr * t))
            c.scaleBy(x: 1, y: 0.6 + 0.4 * abs(sin(t * 1.4 + p.sw)))
            let s = p.s
            var petal = Path()
            petal.move(to: CGPoint(x: 0, y: s * 0.42))
            petal.addCurve(to: CGPoint(x: s * 0.06, y: -s * 0.4), control1: CGPoint(x: s * 0.42, y: s * 0.1), control2: CGPoint(x: s * 0.3, y: -s * 0.38))
            petal.addLine(to: CGPoint(x: 0, y: -s * 0.3))
            petal.addLine(to: CGPoint(x: -s * 0.06, y: -s * 0.4))
            petal.addCurve(to: CGPoint(x: 0, y: s * 0.42), control1: CGPoint(x: -s * 0.3, y: -s * 0.38), control2: CGPoint(x: -s * 0.42, y: s * 0.1))
            c.fill(petal, with: .linearGradient(Gradient(colors: [Color(hex: 0xffe3ee), Color(hex: 0xff9cc2)]), startPoint: CGPoint(x: 0, y: -s / 2), endPoint: CGPoint(x: 0, y: s / 2)))
        }
        ctx.blendMode = .plusLighter
        for m in motes.prefix(8) {
            let y = wrap(m.y - m.vy * 0.6 * t, -0.1, 1.1) * size.height, x = m.x * size.width, r = m.r * 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }
}

/// City silhouette along the horizon; windows light up at night.
struct Skyline: View {
    let dark: Bool
    var body: some View {
        Canvas { ctx, size in
            var g = Seeded(7)
            let base = size.height, maxH = min(220, size.height)
            let col = dark ? Color(hex: 0x05071a) : Color(hex: 0x5476bc).opacity(0.26)
            var x = -10.0
            while x < size.width + 10 {
                let bw = 18 + g.next() * 46, bh = maxH * (0.25 + g.next() * 0.5)
                ctx.fill(Path(CGRect(x: x, y: base - bh, width: bw, height: bh)), with: .color(col.opacity(dark ? 0.55 : 0.6)))
                x += bw - 2
            }
            x = -10
            while x < size.width + 10 {
                let bw = 26 + g.next() * 60, bh = maxH * (0.15 + g.next() * 0.62)
                ctx.fill(Path(CGRect(x: x, y: base - bh, width: bw, height: bh)), with: .color(col))
                if g.next() < 0.18 { ctx.fill(Path(CGRect(x: x + bw * 0.45, y: base - bh - 18, width: 2, height: 18)), with: .color(col)) }
                if dark {
                    var wy = base - bh + 8
                    while wy < base - 8 {
                        var wx = x + 5
                        while wx < x + bw - 6 {
                            if g.next() < 0.09 { ctx.fill(Path(CGRect(x: wx, y: wy, width: 3, height: 4)), with: .color(Color(hex: 0xffd48c).opacity(0.85))) }
                            wx += 8
                        }
                        wy += 9
                    }
                }
                x += bw - 1
            }
        }
    }
}

/// Small deterministic PRNG (SplitMix64) for stable layouts.
struct Seeded {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
