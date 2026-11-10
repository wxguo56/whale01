import SwiftUI

struct WhaleTabBar: View {
    static let height: CGFloat = 62

    @Binding var selection: AppTab?

    var body: some View {
        HStack(spacing: 4) {
            item(.conversation, title: "对话", icon: "bubble.left.and.bubble.right.fill")
            item(.records, title: "记录", icon: "list.bullet.rectangle")
            item(.settings, title: "设置", icon: "slider.horizontal.3")
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .frame(height: Self.height)
        .background {
            WhaleChromeBackground()
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhaleTheme.glassStroke)
                .frame(height: 0.5)
        }
    }

    private func item(_ tab: AppTab, title: String, icon: String) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.28)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(selected ? .fill : .none)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? WhaleTheme.accent : WhaleTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(WhaleTheme.accent.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(WhaleTheme.accent.opacity(0.2), lineWidth: 0.8)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
