import SwiftUI

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

enum WhaleTheme {
    static let accent = Color(light: 0x5856D6, dark: 0x8B8AF0)
    static let accentDeep = Color(light: 0x433FC0, dark: 0x7B79E8)
    static let accentSoft = Color(light: 0xECEBFB, dark: 0x2A2A4A)
    static let ink = Color(light: 0x1D1D1F, dark: 0xF5F6FA)
    static let muted = Color(light: 0x6B6B70, dark: 0xB9BDD0)
    static let background = Color(light: 0xF6F8FC, dark: 0x101725)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B2434)
    static let cardSolid = Color(light: 0xE3E9F5, dark: 0x232A42)
    static let soft = Color(light: 0xEEF0FA, dark: 0x232A42)
    static let line = Color(light: 0xE1E3F2, dark: 0x34405C)
    static let glassStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.white.withAlphaComponent(0.65)
    })
    static let warm = Color(light: 0xE9A23B, dark: 0xF0B45C)
    static let success = Color(light: 0x2E9E6B, dark: 0x4FC08D)
    static let danger = Color(light: 0xD34747, dark: 0xF07A7A)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let pagePadding: CGFloat = 20

    static let pageGradient = LinearGradient(
        colors: [
            Color(light: 0xDCE7F5, dark: 0x0E1220),
            Color(light: 0xEDE4F2, dark: 0x161B2E),
            Color(light: 0xF6E8E4, dark: 0x1E1A26)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func whaleCard(padding: CGFloat = 16) -> some View {
        self
            .modifier(GlassCardStyle(padding: padding))
    }

    func whalePrimaryButton() -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(WhaleTheme.accent, in: RoundedRectangle(cornerRadius: WhaleTheme.controlRadius, style: .continuous))
    }
}

struct GlassCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = WhaleTheme.cardRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(WhaleTheme.cardSolid)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
}

// GLASS 是设计方向（层次、半透明、hairline），不是 CSS blur 的像素级复刻。
// 原生统一走系统 Material；Liquid Glass 是 iOS 26 SDK 的新 API，本工程
// 以 iOS 17 为基线且 CI 使用旧 SDK，不能假装已接入。

struct WhaleStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}

struct WhaleSectionTitle: View {
    let title: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.subheadline.weight(.medium))
                    .tint(WhaleTheme.accent)
            }
        }
    }
}

struct WhaleIconTile: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = WhaleTheme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct GlassChipStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if reduceTransparency {
                    Capsule().fill(WhaleTheme.cardSolid)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
    }
}

extension View {
    func whaleChip() -> some View {
        modifier(GlassChipStyle())
    }

    func whaleGlassCircle(size: CGFloat = 44) -> some View {
        self
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
    }
}

/// Wraps chips onto as many lines as needed without a horizontal scroll view,
/// so the root pager keeps exclusive ownership of horizontal drags.
struct WhaleFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        widest = max(widest, max(0, x - spacing))
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
