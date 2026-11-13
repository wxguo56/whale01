import Combine
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var page = NavigationHabits.restoredTab(UserDefaults.standard.string(forKey: "whale.root.tab"))
    @State private var showRecords = false
    @State private var showSettings = false
    @State private var settingsDetailOpen = false
    @State private var showDiscover = false
    @State private var discoverChannel: DiscoverChannel = .ai
    @State private var discoverReturnTitle = "助手"
    @AppStorage("whale.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTextSize

    var body: some View {
        TabView(selection: $page) {
            ConversationTabView(model: model, bottomInset: 0,
                onOpenRecords: { showRecords = true }, onOpenSettings: { showSettings = true },
                onOpenMusic: { openDiscover(.music) }, onOpenTodo: { page = .records }, onOpenDiscover: openDiscover)
                .safeAreaInset(edge: .bottom, spacing: 0) { ConversationComposerBar(model: model) }
                .tabItem { Label("助手", systemImage: "bubble.left.and.bubble.right") }.tag(AppTab.conversation)
            TodoView(model: model, embedded: true, onBackToChat: { page = .conversation }, bottomBarInset: 0)
                .tabItem { Label("待办", systemImage: "checklist") }.tag(AppTab.records)
            DiscoverHubView(model: model, onOpen: openDiscover, onSettings: { showSettings = true })
                .tabItem { Label("发现", systemImage: "square.grid.2x2") }.tag(AppTab.discover)
        }
        .tint(WhaleTheme.accent)
        .toolbarBackground(WhaleTheme.chrome, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(colorScheme)
        .dynamicTypeSize(preferredTextSize)
        .sheet(item: $model.presentedConfirmation) { item in ConfirmationSheet(model: model, item: item) }
        .sheet(isPresented: $showRecords) { RecordsView(model: model, showsClose: true, onClose: { showRecords = false }) }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, isDetailOpen: $settingsDetailOpen, onBackToChat: { showSettings = false })
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showDiscover) {
            DiscoverView(initialChannel: discoverChannel, appModel: model, returnTitle: discoverReturnTitle)
                .id(discoverChannel)
        }
        .task {
#if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["WHALE_DEMO_HOME"] == "1" || environment["WHALE_DEMO_WEATHER"] == "1" { page = .conversation }
            if environment["WHALE_DEMO_TODO"] == "1" { page = .records }
            if environment["WHALE_DEMO_HUB"] == "1" { page = .discover }
            if environment["WHALE_DEMO_SETTINGS"] == "1" { showSettings = true }
            if environment["WHALE_DEMO_DISCOVER"] == "1" { openDiscover(.market) }
            if environment["WHALE_DEMO_GAME"] == "1" { openDiscover(.game) }
            if let raw = environment["WHALE_DEMO_CHANNEL"], let channel = DiscoverChannel(rawValue: raw) { openDiscover(channel) }
#endif
            await model.health()
            await model.reconcileUnknownWrites()
            await model.flushResultOutbox()
            await model.resumeActiveTurnIfNeeded()
            model.refreshPermissions()
            await model.refreshDashboard(force: true)
            await model.drainSharedInbox()
        }
        .onOpenURL { url in Task { await model.handleSharedURL(url) } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.flushResultOutbox(); await model.drainSharedInbox() }
        }
        .onChange(of: page) { _, tab in
            UserDefaults.standard.set(tab.rawValue, forKey: "whale.root.tab")
            UISelectionFeedbackGenerator().selectionChanged()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .whaleOpenChat)) { _ in
            showDiscover = false; showRecords = false; showSettings = false; page = .conversation
        }
    }
    private func openDiscover(_ channel: DiscoverChannel) {
        discoverReturnTitle = page == .discover ? "发现" : "助手"
        discoverChannel = channel; showDiscover = true
    }
    private var colorScheme: ColorScheme? {
        appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }
    private var preferredTextSize: DynamicTypeSize {
#if DEBUG
        if ProcessInfo.processInfo.environment["WHALE_DEMO_LARGE_TEXT"] == "1" { return .accessibility3 }
#endif
        return systemTextSize
    }
}

private struct ConfirmationSheet: View {
    @ObservedObject var model: AppModel
    let item: PendingTool
    @State private var calendarPreview: CalendarWritePreview?
    @State private var previewError: String?
    @State private var checkingPreview = true

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
                        .whaleFont(size: 17, weight: .medium)
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .whaleCard()

                    if checkingPreview {
                        ProgressView("正在核对操作信息…")
                    }
                    if let preview = calendarPreview {
                        Label(preview.detail, systemImage: preview.conflictCount > 0 ? "exclamationmark.calendar" : "calendar.badge.checkmark")
                            .font(.subheadline).foregroundStyle(WhaleTheme.muted)
                    }
                    if let previewError {
                        Text(previewError).font(.footnote).foregroundStyle(WhaleTheme.danger)
                        Button("重新核对") { Task { await loadPreview() } }
                    }

                    Label(ToolPresentation.confirmationNote(item.tool), systemImage: "checkmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(WhaleTheme.muted)

                    if let error = model.errorText, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(WhaleTheme.danger)
                    }

                    Button {
                        Task { await model.confirm(item, calendarFingerprint: calendarPreview?.fingerprint) }
                    } label: {
                        Text(ToolPresentation.confirmationAction(item.tool, conflictCount: calendarPreview?.conflictCount ?? 0)).whalePrimaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy || checkingPreview || previewError != nil)
                    .padding(.top, 8)

                    Button(role: .destructive) {
                        Task { await model.skip(item) }
                    } label: {
                        Text("跳过本次，不执行")
                            .whaleFont(size: 15)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .disabled(model.isBusy)
                }
                .padding(20)
            }
            .background(WhaleBackdrop())
            .navigationTitle("确认操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后处理") { model.dismissConfirmation() }
                }
            }
        }
        .task(id: item.id) { await loadPreview() }
        .onChange(of: model.errorText) { _, value in
            if value?.contains("日历内容已变化") == true { Task { await loadPreview() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    private func loadPreview() async {
        checkingPreview = true
        previewError = nil
        defer { checkingPreview = false }
        do { calendarPreview = try await model.calendarPreview(item) }
        catch { previewError = error.localizedDescription }
    }

}
