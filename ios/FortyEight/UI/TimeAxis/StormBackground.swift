import SwiftUI

/// Palette taken from 崩坏3「罪人挽歌」: storm slate, violet thunder, crimson blade, rose light.
enum Storm {
    static let ink = Color(hex: 0x0b0b16)
    static let slate = Color(hex: 0x1d1e34)
    static let cloud = Color(hex: 0x34365a)
    static let violet = Color(hex: 0x8b5cf6)
    static let lilac = Color(hex: 0xc9b8ff)
    static let magenta = Color(hex: 0xd946ef)
    static let crimson = Color(hex: 0xff2d55)
    static let rose = Color(hex: 0xffe4f1)
}

/// A parallelogram leaning right, the basic panel shape of the HUD.
struct Slant: Shape {
    var k: CGFloat = 8
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + k, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - k, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Diagonal hatching for half hours that passed without a record.
struct Hatch: Shape {
    var spacing: CGFloat = 7
    func path(in r: CGRect) -> Path {
        Path { p in
            var x = r.minX - r.height
            while x < r.maxX {
                p.move(to: CGPoint(x: x, y: r.maxY))
                p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
                x += spacing
            }
        }
    }
}

enum Haptics {
    static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat = 1) {
        UIImpactFeedbackGenerator(style: s).impactOccurred(intensity: intensity)
    }
}

/// Overcast storm sky: drifting cloud banks, a thunder strike every few seconds, rising light motes,
/// and a ruined skyline. Everything is procedural and drawn in one Canvas per frame.
struct StormBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Puff { let x: Double, y: Double, r: Double, speed: Double, lit: Double }
    private struct Mote { let x: Double, y: Double, r: Double, speed: Double, phase: Double }

    private static let puffs: [Puff] = {
        var g = Seeded(2026)
        return (0..<26).map { k in
            let layer = Double(k % 3)
            return Puff(x: g.next(), y: -0.05 + g.next() * 0.55, r: 0.28 + g.next() * 0.35 - layer * 0.05,
                        speed: 0.004 + layer * 0.004 + g.next() * 0.003, lit: g.next())
        }
    }()
    private static let motes: [Mote] = {
        var g = Seeded(48)
        return (0..<18).map { _ in Mote(x: g.next(), y: g.next(), r: 1.2 + g.next() * 2.6, speed: 0.008 + g.next() * 0.018, phase: g.next() * 6.28) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { c, size in Self.draw(&c, size, t) }
        }
        .background(LinearGradient(colors: [Color(hex: 0x2e3052), Storm.slate, Storm.ink], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { RuinLine().frame(height: 120).allowsHitTesting(false) }
        .accessibilityHidden(true)
    }

    private static func draw(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let W = size.width, H = size.height

        // Thunder: one strike per 6.5 s window, at a random moment and place inside it.
        let period = 6.5, n = floor(t / period)
        var g = Seeded(UInt64(max(0, n)) &+ 11)
        let at = 0.6 + g.next() * 3.4, bx = W * (0.15 + g.next() * 0.7)
        let local = t - n * period - at
        let flash: Double = {
            guard local > 0, local < 0.55 else { return 0 }
            if local < 0.07 { return 1 }
            if local < 0.12 { return 0.25 }
            if local < 0.2 { return 0.85 }
            return max(0, 0.85 * (1 - (local - 0.2) / 0.35))
        }()

        // Glow inside the clouds where the strike is.
        if flash > 0 {
            c.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .radialGradient(Gradient(colors: [Storm.lilac.opacity(0.35 * flash), Storm.violet.opacity(0.12 * flash), .clear]),
                                         center: CGPoint(x: bx, y: H * 0.12), startRadius: 0, endRadius: H * 0.7))
        }

        // Cloud banks, dark underside and a crown lit by the violet thunder.
        for p in puffs {
            let r = p.r * W, span = W + 2 * r
            var x = (p.x * span + t * p.speed * W).truncatingRemainder(dividingBy: span) - r
            if x < -r { x += span }
            let y = p.y * H
            let near = max(0, 1 - abs(x - bx) / (W * 0.6))
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.55 + r * 0.3, width: r * 2, height: r * 1.1)),
                   with: .radialGradient(Gradient(colors: [Storm.ink.opacity(0.32), .clear]), center: CGPoint(x: x, y: y + r * 0.3), startRadius: 0, endRadius: r))
            let lit = 0.10 + 0.10 * p.lit + 0.35 * flash * near
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2)),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0x8f8cc0).mix(with: Storm.lilac, by: flash * near).opacity(lit), .clear]),
                                         center: CGPoint(x: x, y: y - r * 0.1), startRadius: 0, endRadius: r))
        }

        // The bolt itself.
        if flash > 0.2 {
            var path = Path(), pt = CGPoint(x: bx, y: -10)
            path.move(to: pt)
            let endY = H * (0.32 + g.next() * 0.2)
            var branch: CGPoint?
            for k in 1...12 {
                pt = CGPoint(x: pt.x + (g.next() - 0.5) * 46, y: -10 + (endY + 10) * Double(k) / 12)
                path.addLine(to: pt)
                if k == 5 { branch = pt }
            }
            if let b = branch {
                var q = b
                path.move(to: q)
                for _ in 0..<4 { q = CGPoint(x: q.x + 10 + g.next() * 22, y: q.y + 14 + g.next() * 18); path.addLine(to: q) }
            }
            c.stroke(path, with: .color(Storm.violet.opacity(0.35 * flash)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            c.stroke(path, with: .color(Storm.lilac.opacity(0.8 * flash)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            c.stroke(path, with: .color(.white.opacity(flash)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }

        // Rising light motes (the drifting orbs of the short).
        for m in motes {
            let y = (1 - (m.y + t * m.speed).truncatingRemainder(dividingBy: 1)) * (H + 20) - 10
            let x = m.x * W + sin(t * 0.4 + m.phase) * 14
            let tw = 0.55 + 0.45 * sin(t * 1.7 + m.phase * 3)
            let r = m.r * 4
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [Storm.rose.opacity(0.55 * tw), Storm.rose.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
            c.fill(Path(ellipseIn: CGRect(x: x - m.r * 0.6, y: y - m.r * 0.6, width: m.r * 1.2, height: m.r * 1.2)), with: .color(.white.opacity(0.85 * tw)))
        }

        if flash > 0 { c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Storm.lilac.opacity(0.07 * flash))) }
    }
}

/// Broken rooftops along the bottom edge.
private struct RuinLine: View {
    var body: some View {
        Canvas { c, size in
            var g = Seeded(77)
            var p = Path(), x = -8.0
            p.move(to: CGPoint(x: x, y: size.height))
            while x < size.width + 8 {
                let w = 18 + g.next() * 44, h = size.height * (0.2 + g.next() * 0.55)
                p.addLine(to: CGPoint(x: x, y: size.height - h))
                if g.next() > 0.55 { p.addLine(to: CGPoint(x: x + w * 0.45, y: size.height - h + 6 + g.next() * 12)) }
                p.addLine(to: CGPoint(x: x + w, y: size.height - h - g.next() * 8))
                if g.next() > 0.75 {
                    c.fill(Path(CGRect(x: x + w * 0.5, y: size.height - h - 22, width: 2, height: 22)), with: .color(Storm.ink.opacity(0.9)))
                }
                x += w
            }
            p.addLine(to: CGPoint(x: size.width + 8, y: size.height))
            p.closeSubpath()
            c.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: 0x05050c).opacity(0.85), Color(hex: 0x05050c)]),
                                            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
