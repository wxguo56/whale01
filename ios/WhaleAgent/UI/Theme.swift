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
    static let accent = Color(light: 0x2F67D8, dark: 0x346DDD)
    static let accentDeep = Color(light: 0x1E4BA8, dark: 0x2A5BC0)
    static let accentSoft = Color(light: 0xEAF1FE, dark: 0x1C2C4A)
    static let ink = Color(light: 0x1D2B42, dark: 0xEDF2FA)
    static let muted = Color(light: 0x64748B, dark: 0xADBACD)
    static let background = Color(light: 0xF6F8FC, dark: 0x101725)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B2434)
    static let soft = Color(light: 0xEEF2F8, dark: 0x232E40)
    static let line = Color(light: 0xE3E9F2, dark: 0x344055)
    static let warm = Color(light: 0xE9A23B, dark: 0xF0B45C)
    static let success = Color(light: 0x2E9E6B, dark: 0x4FC08D)
    static let danger = Color(light: 0xD34747, dark: 0xF07A7A)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let pagePadding: CGFloat = 20

    static let heroGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func whaleCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: WhaleTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WhaleTheme.cardRadius, style: .continuous)
                    .strokeBorder(WhaleTheme.line, lineWidth: 1)
            }
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
