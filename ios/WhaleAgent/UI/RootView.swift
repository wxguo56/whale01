import Combine
import SwiftUI

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var selectedTab: AppTab = .home
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(model: model, selectedTab: $selectedTab)
                .tag(AppTab.home)
                .tabItem { Label("首页", systemImage: "square.grid.2x2.fill") }

            ChatView(model: model)
                .tag(AppTab.chat)
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }

            MusicView(model: model)
                .tag(AppTab.music)
                .tabItem { Label("音乐", systemImage: "music.note") }

            SettingsView(model: model)
                .tag(AppTab.settings)
                .tabItem { Label("设置", systemImage: "person.crop.circle.fill") }
        }
        .tint(WhaleTheme.accent)
        .sheet(item: $model.presentedConfirmation) { item in
            ConfirmationSheet(model: model, item: item)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .whaleOpenChat)) { _ in
            selectedTab = .chat
        }
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
                        Image(systemName: ToolPresentation.icon(item.tool))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(WhaleTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(WhaleTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ToolPresentation.title(item.tool))
                                .font(.title3.weight(.semibold))
                            Text("执行前确认")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(ToolPresentation.detail(for: item))
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .whaleCard()

                    Label(ToolPresentation.confirmationNote(item.tool), systemImage: "checkmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let error = model.errorText, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 12)

                    Button {
                        Task { await model.confirm(item) }
                    } label: {
                        Text("确认执行")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WhaleTheme.accent)
                    .disabled(model.isBusy)

                    Button(role: .destructive) {
                        Task { await model.skip(item) }
                    } label: {
                        Text("跳过本次操作")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .disabled(model.isBusy)
                }
                .padding(20)
            }
            .background(WhaleTheme.background)
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
