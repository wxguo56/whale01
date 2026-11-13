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
    // Abyss Aurora: deep-sea surfaces, mint aurora, moonlit blue and only a
    // little coral for time/weather/attention states.
    static let accent = Color(light: 0x087C75, dark: 0x62EAD6)
    static let accentDeep = Color(light: 0x0B756F, dark: 0x3CCFC4)
    static let accentSoft = Color(light: 0xDFF6F2, dark: 0x123B3D)
    static let moon = Color(light: 0x2E73C8, dark: 0x78B9FF)
    static let coral = Color(light: 0xD77B3D, dark: 0xFFB27A)
    static let ink = Color(light: 0x102522, dark: 0xF2F8F7)
    static let muted = Color(light: 0x53645F, dark: 0xA6B9B6)
    static let background = Color(light: 0xF2F8F7, dark: 0x071311)
    static let card = Color(light: 0xFFFFFF, dark: 0x0D201E)
    static let cardSolid = Color(light: 0xE7F1EE, dark: 0x142C29)
    static let soft = Color(light: 0xE7F2EF, dark: 0x132724)
    static let line = Color(light: 0xD8E6E2, dark: 0x25403C)
    static let field = Color(light: 0xEAF3F0, dark: 0x0C1D1B)
    static let chrome = Color(light: 0xF7FBFA, dark: 0x091714)
    static let onAccent = Color(light: 0x062521, dark: 0x04211E)
    static let buttonInk = Color(light: 0x062521, dark: 0x04211E)
    static let glassStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.16)
            : UIColor.white.withAlphaComponent(0.72)
    })
    static let warm = Color(light: 0xC68136, dark: 0xF3BC77)
    static let success = Color(light: 0x168F68, dark: 0x54DFAF)
    static let danger = Color(light: 0xD34747, dark: 0xF07A7A)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let pagePadding: CGFloat = 20

    static let pageGradient = LinearGradient(
        colors: [
            Color(light: 0xE8F5F2, dark: 0x06110F),
            Color(light: 0xEDF7F7, dark: 0x0A1A19),
            Color(light: 0xF8FBF7, dark: 0x0B1714)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(light: 0x139C91, dark: 0x0B4647),
            Color(light: 0x1D777C, dark: 0x103338),
            Color(light: 0x315D74, dark: 0x0B2028)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auroraGradient = LinearGradient(
        colors: [accent, moon],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let gameGradient = LinearGradient(
        colors: [
            Color(light: 0xB85C2E, dark: 0x6B2C12),
            Color(light: 0xD79A3F, dark: 0x4A3510)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let musicGradient = LinearGradient(
        colors: [
            Color(light: 0x8A4B8F, dark: 0x3A1E45),
            Color(light: 0xC0566F, dark: 0x5A2436)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headlineGradient = LinearGradient(
        colors: [
            Color(light: 0x1E8A7A, dark: 0x0C4A42),
            Color(light: 0x2E73C8, dark: 0x143352)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let weiboGradient = LinearGradient(
        colors: [
            Color(light: 0xD34747, dark: 0x5A1A1A),
            Color(light: 0xD77B3D, dark: 0x5B3216)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Composer send button. Matches the v9 reference: mint-to-sky paper plane
    /// tile that stays legible on both the abyss and the morning-mist surface.
    static let composerSendGradient = LinearGradient(
        colors: [
            Color(light: 0x3FCDBE, dark: 0x2FBFB2),
            Color(light: 0x4E9BE8, dark: 0x3E86C9)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rose = Color(light: 0xC0566F, dark: 0xF292A6)
    static let blueSoft = Color(light: 0xE6EFFC, dark: 0x14283F)
    static let amberSoft = Color(light: 0xFBF0DC, dark: 0x33260E)
    static let roseSoft = Color(light: 0xFBE8EC, dark: 0x341A20)
    static let bubble = Color(light: 0xFFFFFF, dark: 0x102622)
}

extension View {
    func whaleCard(padding: CGFloat = 16) -> some View {
        self
            .modifier(GlassCardStyle(padding: padding))
    }

    func whalePrimaryButton() -> some View {
        self
            .font(.headline)
            .foregroundStyle(WhaleTheme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                WhaleTheme.composerSendGradient,
                in: RoundedRectangle(cornerRadius: WhaleTheme.controlRadius, style: .continuous)
            )
            .whaleSoftElevation()
    }

    func whaleSoftElevation(selected: Bool = false) -> some View {
        modifier(SoftElevation(selected: selected))
    }

    func whaleRaisedPill(selected: Bool) -> some View {
        modifier(RaisedPillStyle(selected: selected))
    }
}

private struct SoftElevation: ViewModifier {
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(scheme == .dark ? 0.24 : 0.075), radius: selected ? 10 : 8, x: 0, y: 4)
            .shadow(color: WhaleTheme.accent.opacity(selected ? 0.14 : 0.045), radius: selected ? 16 : 12, x: 0, y: 7)
    }
}

private struct RaisedPillStyle: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.foregroundStyle(selected ? WhaleTheme.onAccent : WhaleTheme.ink)
            .padding(.horizontal, 10).frame(minHeight: 44).fixedSize(horizontal: true, vertical: false)
            .background {
                if selected { Capsule().fill(WhaleTheme.composerSendGradient) }
                else if reduceTransparency { Capsule().fill(WhaleTheme.cardSolid) }
                else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(WhaleTheme.card.opacity(0.6)))
                }
            }
            .overlay(Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8))
            .whaleSoftElevation(selected: selected)
            .contentShape(Capsule())
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
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(WhaleTheme.cardSolid)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(WhaleTheme.card.opacity(0.62)))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
            .whaleSoftElevation()
    }
}

/// Full-page atmosphere. The aurora stays behind content, so every card keeps
/// a dark-to-mint edge and the header/footer can use opaque chrome.
struct WhaleBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            WhaleTheme.pageGradient
            Circle().fill(WhaleTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.20))
                .frame(width: 360, height: 360).blur(radius: 82).offset(x: -150, y: -300)
            Circle().fill(WhaleTheme.moon.opacity(colorScheme == .dark ? 0.13 : 0.12))
                .frame(width: 320, height: 320).blur(radius: 92).offset(x: 168, y: -150)
            Ellipse().fill(WhaleTheme.accentDeep.opacity(colorScheme == .dark ? 0.13 : 0.08))
                .frame(width: 420, height: 240).blur(radius: 110).offset(x: 80, y: 360)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WhaleMarkView: View {
    var size: CGFloat = 38

    private static let logoImage: UIImage? = {
        if let image = UIImage(named: "WhaleLogo") { return image }
        if let url = Bundle.main.url(forResource: "WhaleLogo", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return nil
    }()

    var body: some View {
        Group {
            if let logo = Self.logoImage {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(WhaleTheme.auroraGradient)
                    Image(systemName: "fish.fill")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8)
        }
        .shadow(color: WhaleTheme.accent.opacity(0.22), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

struct WhaleChromeBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
            Rectangle().fill(WhaleTheme.chrome.opacity(reduceTransparency ? 1 : 0.82))
        }
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
                .whaleFont(size: 17, weight: .semibold)
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
            .whaleSoftElevation()
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
            .whaleSoftElevation()
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
