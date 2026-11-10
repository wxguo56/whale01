import Combine
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @StateObject private var keyboard = KeyboardObserver()
    @State private var page: AppTab? = .conversation
    @State private var showMusic = false
    @State private var showTodo = false
    @State private var settingsDetailOpen = false
    @State private var contentBottom: CGFloat = 0
    @AppStorage("whale.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ConversationTabView(
                            model: model,
                            bottomInset: ConversationComposerBar.reservedHeight + WhaleTabBar.height + keyboardOverlap,
                            onOpenRecords: { go(.records) },
                            onOpenSettings: { go(.settings) },
                            onOpenMusic: { showMusic = true },
                            onOpenTodo: { showTodo = true }
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
                    settingsDetailOpen || showMusic || showTodo || model.presentedConfirmation != nil || keyboard.isVisible
                )
                .background(WhaleBackdrop())

                VStack(spacing: 0) {
                    if page == .conversation {
                        ConversationComposerBar(model: model)
                    }
                    if !keyboard.isVisible && !settingsDetailOpen {
                        WhaleTabBar(selection: $page)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, keyboardOverlap)
                .animation(.easeInOut(duration: 0.18), value: keyboard.isVisible)
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ContentBottomKey.self,
                        value: geo.frame(in: .global).maxY
                    )
                }
            }
            .onPreferenceChange(ContentBottomKey.self) { contentBottom = $0 }
        }
        .background(WhaleBackdrop())
        .tint(WhaleTheme.accent)
        .ignoresSafeArea(.keyboard, edges: page == .conversation ? .bottom : [])
        .sheet(item: $model.presentedConfirmation) { item in
            ConfirmationSheet(model: model, item: item)
        }
        .sheet(isPresented: $showMusic) {
            MusicView(model: model, showsClose: true)
        }
        .sheet(isPresented: $showTodo) {
            TodoView(model: model)
        }
        .animation(.easeInOut(duration: 0.2), value: model.playback.track?.trackId)
        .preferredColorScheme(colorScheme)
        .task {
            await model.health()
            await model.reconcileUnknownWrites()
            await model.flushResultOutbox()
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
            Task {
                await model.flushResultOutbox()
                await model.drainSharedInbox()
            }
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

    private var keyboardOverlap: CGFloat {
        guard let top = keyboard.top, contentBottom > 0 else { return 0 }
        return max(0, contentBottom - top)
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
            .background(WhaleBackdrop())
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

private struct ContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
