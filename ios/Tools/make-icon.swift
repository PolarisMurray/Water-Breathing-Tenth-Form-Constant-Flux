// App icon: a 48-segment day ring cut in two by a violet lightning bolt over a storm sky.
// Art direction from 崩坏3「罪人挽歌」: overcast storm, violet thunder, crimson trail, drifting light orbs.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)   // top-left origin

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 0xff) / 255, CGFloat((h >> 8) & 0xff) / 255, CGFloat(h & 0xff) / 255, a])!
}
func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    func c(_ h: UInt32, _ s: UInt32) -> CGFloat { CGFloat((h >> s) & 0xff) / 255 }
    return CGColor(colorSpace: cs, components: [c(a, 16) + (c(b, 16) - c(a, 16)) * t, c(a, 8) + (c(b, 8) - c(a, 8)) * t, c(a, 0) + (c(b, 0) - c(a, 0)) * t, 1])!
}
var seed: UInt64 = 0x48_2026
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
func radial(_ c: CGPoint, _ r: CGFloat, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

// Sky
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x34365a), rgb(0x1d1e34), rgb(0x0c0c18)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: S), options: [])
radial(CGPoint(x: 760, y: 230), 560, rgb(0x7a5cff, 0.55), rgb(0x7a5cff, 0))     // cloud lit from inside by thunder
radial(CGPoint(x: 180, y: 820), 420, rgb(0xe11d48, 0.22), rgb(0xe11d48, 0))     // ember glow low-left

// Clouds: soft overlapping puffs, brighter where the lightning is
for _ in 0..<220 {
    let x = rnd() * S, y = rnd() * 640 - 60, r = 60 + rnd() * 190
    let lit = max(0, 1 - hypot(x - 760, y - 230) / 620)
    // dark underside, lit crown
    radial(CGPoint(x: x, y: y + r * 0.35), r * 1.05, rgb(0x0b0b16, 0.10), rgb(0x0b0b16, 0))
    radial(CGPoint(x: x, y: y - r * 0.15), r * 0.8, mix(0x7b78a6, 0xe2d6ff, lit).copy(alpha: 0.06 + 0.16 * lit)!, rgb(0x7b78a6, 0))
}
// vignette
let vg = CGGradient(colorsSpace: cs, colors: [rgb(0x05050c, 0), rgb(0x05050c, 0.65)] as CFArray, locations: [0.55, 1])!
ctx.drawRadialGradient(vg, startCenter: CGPoint(x: 512, y: 470), startRadius: 0, endCenter: CGPoint(x: 512, y: 470), endRadius: 760, options: [.drawsAfterEndLocation])

// Ruined skyline
ctx.setFillColor(rgb(0x07070f))
var x: CGFloat = -10
while x < S {
    let w = 26 + rnd() * 60, h = 40 + rnd() * 110
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: S)); p.addLine(to: CGPoint(x: x, y: S - h))
    if rnd() > 0.5 { p.addLine(to: CGPoint(x: x + w * 0.4, y: S - h + 10 + rnd() * 18)); p.addLine(to: CGPoint(x: x + w * 0.7, y: S - h - 6)) }
    p.addLine(to: CGPoint(x: x + w, y: S - h + rnd() * 12)); p.addLine(to: CGPoint(x: x + w, y: S)); p.closeSubpath()
    ctx.addPath(p); ctx.fillPath()
    if rnd() > 0.7 { ctx.fill(CGRect(x: x + w * 0.5, y: S - h - 34, width: 4, height: 34)) }
    x += w - 4
}

// Ring, sliced along the bolt
let C = CGPoint(x: 512, y: 512), r0: CGFloat = 236, r1: CGFloat = 334
let cut = CGFloat(-56) * .pi / 180                        // cut direction (screen coords, y down)
let dir = CGPoint(x: cos(cut), y: sin(cut)), nrm = CGPoint(x: -dir.y, y: dir.x)

func ring() {
    ctx.setFillColor(rgb(0x0d0e1a, 0.72))
    ctx.fillEllipse(in: CGRect(x: C.x - r0 + 6, y: C.y - r0 + 6, width: (r0 - 6) * 2, height: (r0 - 6) * 2))
    for i in 0..<48 {
        let gap: CGFloat = 0.014
        let a0 = CGFloat(i) / 48 * 2 * .pi - .pi / 2 + gap, a1 = CGFloat(i + 1) / 48 * 2 * .pi - .pi / 2 - gap
        let p = CGMutablePath()
        p.addArc(center: C, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: C, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        let col: CGColor
        if i < 31 {
            let t = CGFloat(i) / 30
            col = t < 0.5 ? mix(0xe11d48, 0xd946ef, t * 2) : mix(0xd946ef, 0x8b5cf6, (t - 0.5) * 2)
        } else if i == 31 {
            col = rgb(0xffffff)
        } else {
            col = rgb(0x3a3c5c, 0.95)
        }
        ctx.saveGState()
        if i <= 31 { ctx.setShadow(offset: .zero, blur: i == 31 ? 40 : 18, color: i == 31 ? rgb(0xffffff, 0.9) : col.copy(alpha: 0.6)) }
        ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath()
        ctx.restoreGState()
    }
    // hour ticks inside
    for h in stride(from: 0, to: 24, by: 3) {
        let a = CGFloat(h) / 24 * 2 * .pi - .pi / 2
        ctx.setStrokeColor(rgb(0xc9c3ff, h % 6 == 0 ? 0.55 : 0.28)); ctx.setLineWidth(h % 6 == 0 ? 6 : 4); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: C.x + cos(a) * (r0 - 26), y: C.y + sin(a) * (r0 - 26)))
        ctx.addLine(to: CGPoint(x: C.x + cos(a) * (r0 - (h % 6 == 0 ? 58 : 44)), y: C.y + sin(a) * (r0 - (h % 6 == 0 ? 58 : 44))))
        ctx.strokePath()
    }
}
for side in [1.0, -1.0] as [CGFloat] {
    ctx.saveGState()
    // half-plane on one side of the cut line
    let far: CGFloat = 2000
    let a = CGPoint(x: C.x - dir.x * far, y: C.y - dir.y * far), b = CGPoint(x: C.x + dir.x * far, y: C.y + dir.y * far)
    let clip = CGMutablePath()
    clip.move(to: a); clip.addLine(to: b)
    clip.addLine(to: CGPoint(x: b.x + nrm.x * far * side, y: b.y + nrm.y * far * side))
    clip.addLine(to: CGPoint(x: a.x + nrm.x * far * side, y: a.y + nrm.y * far * side))
    clip.closeSubpath()
    ctx.addPath(clip); ctx.clip()
    ctx.translateBy(x: dir.x * 24 * side + nrm.x * 11 * side, y: dir.y * 24 * side + nrm.y * 11 * side)
    ring()
    ctx.restoreGState()
}

// Crimson blade trail parallel to the bolt
func band(_ off: CGFloat, _ w: CGFloat, _ len: CGFloat, _ col: CGColor) {
    let p = CGMutablePath()
    let c = CGPoint(x: C.x + nrm.x * off, y: C.y + nrm.y * off)
    p.move(to: CGPoint(x: c.x - dir.x * len, y: c.y - dir.y * len))
    p.addLine(to: CGPoint(x: c.x + dir.x * len + nrm.x * w, y: c.y + dir.y * len + nrm.y * w))
    p.addLine(to: CGPoint(x: c.x + dir.x * len - nrm.x * w * 0.2, y: c.y + dir.y * len - nrm.y * w * 0.2))
    p.closeSubpath()
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 24, color: col); ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath(); ctx.restoreGState()
}
band(-66, 22, 460, rgb(0xff2d55, 0.95))
band(70, 9, 360, rgb(0xd946ef, 0.75))

// Lightning bolt along the cut: a tapered filled zig-zag with a layered violet glow
func boltPoints(from s: CGPoint, to e: CGPoint, jag: CGFloat, steps: Int) -> [CGPoint] {
    var pts = [s]
    for k in 1..<steps {
        let t = CGFloat(k) / CGFloat(steps)
        let j = (rnd() - 0.5) * 2 * jag * (k % 2 == 0 ? 1 : 0.5)
        pts.append(CGPoint(x: s.x + (e.x - s.x) * t + nrm.x * j, y: s.y + (e.y - s.y) * t + nrm.y * j))
    }
    pts.append(e); return pts
}
func drawBolt(_ pts: [CGPoint], width: CGFloat) {
    let spine = CGMutablePath(); spine.addLines(between: pts)
    ctx.setLineJoin(.miter); ctx.setLineCap(.round)
    for (w, a) in [(width * 7, 0.06), (width * 4.2, 0.10), (width * 2.4, 0.22)] as [(CGFloat, CGFloat)] {
        ctx.addPath(spine); ctx.setStrokeColor(rgb(0x8b5cf6, a)); ctx.setLineWidth(w); ctx.strokePath()
    }
    var left: [CGPoint] = [], right: [CGPoint] = []
    for (k, p) in pts.enumerated() {
        let t = CGFloat(k) / CGFloat(pts.count - 1)
        let w = width * (0.15 + 0.85 * pow(sin(.pi * t), 0.7)) / 2
        left.append(CGPoint(x: p.x + nrm.x * w, y: p.y + nrm.y * w)); right.append(CGPoint(x: p.x - nrm.x * w, y: p.y - nrm.y * w))
    }
    let body = CGMutablePath(); body.addLines(between: left + right.reversed()); body.closeSubpath()
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: width * 1.6, color: rgb(0xb59bff))
    ctx.addPath(body); ctx.setFillColor(rgb(0xf4efff)); ctx.fillPath(); ctx.restoreGState()
    let core = CGMutablePath(); core.addLines(between: pts)
    ctx.addPath(core); ctx.setStrokeColor(rgb(0xffffff)); ctx.setLineWidth(max(2, width * 0.28)); ctx.strokePath()
}
let s = CGPoint(x: C.x - dir.x * 640, y: C.y - dir.y * 640), e = CGPoint(x: C.x + dir.x * 640, y: C.y + dir.y * 640)
drawBolt(boltPoints(from: s, to: e, jag: 30, steps: 14), width: 30)
drawBolt(boltPoints(from: CGPoint(x: C.x - dir.x * 250 + nrm.x * 8, y: C.y - dir.y * 250 + nrm.y * 8), to: CGPoint(x: C.x - dir.x * 90 + nrm.x * 170, y: C.y - dir.y * 90 + nrm.y * 170), jag: 16, steps: 5), width: 11)
drawBolt(boltPoints(from: CGPoint(x: C.x + dir.x * 210, y: C.y + dir.y * 210), to: CGPoint(x: C.x + dir.x * 340 - nrm.x * 140, y: C.y + dir.y * 340 - nrm.y * 140), jag: 14, steps: 5), width: 10)

// Drifting light orbs
for _ in 0..<14 {
    let p = CGPoint(x: 80 + rnd() * 860, y: 120 + rnd() * 760), r = 3 + rnd() * 9
    if hypot(p.x - C.x, p.y - C.y) < r1 + 20 { continue }
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: r * 3, color: rgb(0xffe4f1, 0.9))
    ctx.setFillColor(rgb(0xfff4fb, 0.85)); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)); ctx.restoreGState()
}

// Center spark
let star = CGMutablePath()
for k in 0..<8 {
    let a = CGFloat(k) / 8 * 2 * .pi - .pi / 2, r: CGFloat = k % 2 == 0 ? 58 : 12
    let pt = CGPoint(x: C.x + cos(a) * r, y: C.y + sin(a) * r)
    k == 0 ? star.move(to: pt) : star.addLine(to: pt)
}
star.closeSubpath()
ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 36, color: rgb(0xc9b8ff)); ctx.addPath(star); ctx.setFillColor(rgb(0xffffff)); ctx.fillPath(); ctx.restoreGState()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
