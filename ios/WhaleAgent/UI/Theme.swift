import SwiftUI

enum WhaleTheme {
    static let accent = Color(red: 0.03, green: 0.53, blue: 0.56)
    static let accentDeep = Color(red: 0.02, green: 0.25, blue: 0.31)
    static let warm = Color(red: 0.96, green: 0.55, blue: 0.28)
    static let ink = Color(red: 0.07, green: 0.10, blue: 0.12)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let muted = Color(uiColor: .secondaryLabel)
    static let heroGradient = LinearGradient(
        colors: [accentDeep, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func whaleCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
            }
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
        .background(color.opacity(0.13), in: Capsule())
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
                .font(.headline)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}
