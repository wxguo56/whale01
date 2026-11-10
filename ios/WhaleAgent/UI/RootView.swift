import Combine
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var page: AppTab? = .conversation
    @State private var showMusic = false
    @State private var conversationDetailOpen = false
    @State private var settingsDetailOpen = false
    @AppStorage("whale.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ConversationTabView(
                        model: model,
                        isDetailOpen: $conversationDetailOpen,
                        onOpenRecords: { go(.records) },
                        onOpenSettings: { go(.settings) }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id(AppTab.conversation)

                    RecordsView(model: model, onBackToChat: { go(.conversation) })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(AppTab.records)

                    SettingsView(
                        model: model,
                        isDetailOpen: $settingsDetailOpen,
                        onBackToChat: { go(.conversation) }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id(AppTab.settings)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            .scrollDisabled(
                conversationDetailOpen || settingsDetailOpen || showMusic || model.presentedConfirmation != nil
            )
            .background(WhaleTheme.pageGradient)
        }
        .background(WhaleTheme.pageGradient.ignoresSafeArea())
        .tint(WhaleTheme.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let track = model.playback.track {
                miniPlayer(track)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $model.presentedConfirmation) { item in
            ConfirmationSheet(model: model, item: item)
        }
        .sheet(isPresented: $showMusic) {
            MusicView(model: model, showsClose: true)
        }
        .animation(.easeInOut(duration: 0.2), value: model.playback.track?.trackId)
        .preferredColorScheme(colorScheme)
        .task {
            await model.health()
            await model.reconcileUnknownWrites()
            await model.resumeActiveTurnIfNeeded()
            model.refreshPermissions()
            await model.refreshDashboard(force: true)
            await model.drainSharedInbox()
        }
        .onOpenURL { url in
            Task { await model.handleSharedURL(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.drainSharedInbox() }
        }
        .onChange(of: page) { oldPage, newPage in
            guard oldPage != newPage else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .whaleOpenChat)) { _ in
            go(.conversation)
        }
    }

    private func go(_ tab: AppTab) {
        guard page != tab else { return }
        if reduceMotion {
            page = tab
        } else {
            withAnimation(.snappy(duration: 0.34)) {
                page = tab
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func miniPlayer(_ track: MusicTrackItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [WhaleTheme.accent.opacity(0.8), WhaleTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            Button {
                showMusic = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(1)
                    Text(model.playback.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .frame(width: 34, height: 34)
            }
            Button {
                Task { await model.playNext() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 30, height: 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
    }
}

private struct ConfirmationSheet: View {
    @ObservedObject var model: AppModel
    let item: PendingTool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        WhaleIconTile(systemName: ToolPresentation.icon(item.tool), size: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ToolPresentation.title(item.tool))
                                .font(.headline)
                                .foregroundStyle(WhaleTheme.ink)
                            Text("执行前确认")
                                .font(.caption)
                                .foregroundStyle(WhaleTheme.muted)
                        }
                    }

                    Text(ToolPresentation.detail(for: item))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .whaleCard()

                    Label(ToolPresentation.confirmationNote(item.tool), systemImage: "checkmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(WhaleTheme.muted)

                    if let error = model.errorText, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(WhaleTheme.danger)
                    }

                    Button {
                        Task { await model.confirm(item) }
                    } label: {
                        Text("确认执行").whalePrimaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .padding(.top, 8)

                    Button(role: .destructive) {
                        Task { await model.skip(item) }
                    } label: {
                        Text("取消这次操作")
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .disabled(model.isBusy)
                }
                .padding(20)
            }
            .background(WhaleTheme.pageGradient)
            .navigationTitle("确认操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { model.dismissConfirmation() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
