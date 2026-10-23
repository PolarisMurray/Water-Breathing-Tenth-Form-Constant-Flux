import SwiftUI

enum Theme {
    static let accent = Color.accentColor                       // sakura pink (asset catalog)
    static let accent2 = Color(dark: 0x7fe6ff, light: 0x0a8fc4)  // sky cyan
    static let good = Color(dark: 0x4fe0a6, light: 0x13996a)
    static let warn = Color(dark: 0xffc35a, light: 0xb97800)
    static let bad = Color(dark: 0xff6b7d, light: 0xd83a52)

    static func level(_ rank: Int) -> Color { [good, accent2, warn, bad][max(0, min(3, rank))] }
    static func strategy(_ lv: Strategy.Lv) -> Color {
        switch lv {
        case .bad: return bad
        case .warn: return warn
        case .tip: return accent2
        case .good: return good
        }
    }
}

extension View {
    /// A content panel floating over the sky: Liquid Glass, rounded, padded.
    func glassCard(_ radius: CGFloat = 26, padding: CGFloat = 18, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: radius))
    }

    func sectionTitle() -> some View {
        self.font(.system(.headline, design: .rounded).weight(.bold))
    }
}

struct Pill: View {
    let text: String
    var symbol: String? = nil
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(color)
        .overlay(Capsule().strokeBorder(color, lineWidth: 1))
    }
}
