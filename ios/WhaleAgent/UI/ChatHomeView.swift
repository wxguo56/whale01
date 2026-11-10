import SwiftUI

/// Root conversation page. Everything happens here: the composer, the message
/// list and voice input never push a detail screen or present a sheet.
struct ConversationTabView: View {
    @ObservedObject var model: AppModel
    let keyboardTop: CGFloat?
    let onOpenRecords: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ConversationSurface(
                model: model,
                keyboardTop: keyboardTop,
                onOpenRecords: onOpenRecords
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 29)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("鲸鱼")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                model.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开启新会话")

            Button(action: onOpenRecords) {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("任务与记录")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var statusText: String {
        if model.isExecutingTool { return "正在执行设备操作…" }
        if model.isBusy { return "正在处理…" }
        if !model.backendOnline { return "当前离线" }
        return "随时和我说"
    }
}
