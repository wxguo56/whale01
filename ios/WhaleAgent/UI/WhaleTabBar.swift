import SwiftUI

struct WhaleTabBar: View {
    static let height: CGFloat = 66

    @Binding var selection: AppTab?

    var body: some View {
        HStack(spacing: 4) {
            item(.conversation, title: "对话", icon: "bubble.left.and.bubble.right")
            item(.records, title: "记录", icon: "list.bullet")
            item(.settings, title: "设置", icon: "slider.horizontal.3")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(height: 60)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(WhaleTheme.chrome.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.16), radius: 22, y: 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppTab, title: String, icon: String) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.26)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(selected ? .fill : .none)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                Circle()
                    .fill(selected ? WhaleTheme.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? WhaleTheme.accent : WhaleTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(WhaleTheme.accentSoft.opacity(0.9))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}