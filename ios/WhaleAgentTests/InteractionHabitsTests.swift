import XCTest
@testable import WhaleAgent

final class InteractionHabitsTests: XCTestCase {
    @MainActor
    func testSendPreflightRejectsDuplicateClicksAndDoesNotAcceptBlockedDrafts() async throws {
        let originalHistory = ChatHistoryStore.load()
        defer { ChatHistoryStore.save(originalHistory) }
        let transport = PausedDemoTransport()
        let model = AppModel(transport: transport)
        model.agentMode = "cloud"
        var accepted = false
        let first = Task { await model.send(text: "keep this draft", onAccepted: { accepted = true }) }
        for _ in 0..<100 {
            if await transport.healthCalls == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(model.isBusy)
        await model.send(text: "duplicate click", onAccepted: { accepted = true })
        let calls = await transport.healthCalls
        XCTAssertEqual(calls, 1)
        await transport.releaseHealth()
        await first.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.messages.filter { $0.role == .user }.count, originalHistory.filter { $0.role == .user }.count)
    }
    private func defaults() -> (String, UserDefaults) {
        let suite = "whale.habits.\(UUID().uuidString)"
        return (suite, UserDefaults(suiteName: suite)!)
    }
    func testDraftsSurviveRecreationWithoutCrossingConversations() {
        let (suite, storage) = defaults()
        defer { storage.removePersistentDomain(forName: suite) }
        ComposerDraftStore(defaults: storage).save("明天的安排\n第二行", context: "conversation-a")
        ComposerDraftStore(defaults: storage).save("另一个草稿", context: "conversation-b")
        let restored = ComposerDraftStore(defaults: storage)
        XCTAssertEqual(restored.load(context: "conversation-a"), "明天的安排\n第二行")
        restored.save("", context: "conversation-a")
        XCTAssertEqual(restored.load(context: "conversation-a"), "")
        XCTAssertEqual(restored.load(context: "conversation-b"), "另一个草稿")
    }
    func testReadingOlderMessagesDoesNotFollowNewReplies() {
        var state = ConversationFollowState()
        XCTAssertTrue(state.receive())
        state.updatePosition(nearBottom: false)
        XCTAssertFalse(state.receive(2))
        XCTAssertEqual(state.unread, 2)
        state.follow()
        XCTAssertEqual(state.unread, 0)
        XCTAssertTrue(state.receive())
    }
    func testLegacySettingsTabRestoresToAssistantAndDiscoverRemainsSelectable() {
        XCTAssertEqual(NavigationHabits.restoredTab("settings"), .conversation)
        XCTAssertEqual(NavigationHabits.restoredTab("records"), .records)
        XCTAssertEqual(NavigationHabits.restoredTab("discover"), .discover)
        XCTAssertEqual(NavigationHabits.restoredTab("unknown"), .conversation)
    }
    func testQuickActionsPreserveOrderAndStayWithinThreeSlots() {
        let (suite, storage) = defaults()
        defer { storage.removePersistentDomain(forName: suite) }
        InteractionPreferences.setQuickActions([.music, .music, .nearby, .schedule, .reminder], defaults: storage)
        XCTAssertEqual(InteractionPreferences.quickActions(defaults: storage), [.music, .nearby, .schedule])
        storage.set(["invalid", "music"], forKey: InteractionPreferences.quickActionsKey)
        XCTAssertEqual(InteractionPreferences.quickActions(defaults: storage), [.music, .schedule])
    }
    func testUndoNeverDeletesADeduplicatedOrExternallyEditedReminder() throws {
        func item(title: String = "买菜", completed: Bool = false, deduplicated: Bool = false) throws -> TodoReminder {
            try XCTUnwrap(TodoReminder(json: .object(["recordId": .string("r-1"), "title": .string(title), "completed": .bool(completed), "deduplicated": .bool(deduplicated)])))
        }
        let now = Date()
        let original = try item()
        XCTAssertTrue(TodoUndo.added(original).canUndo(current: original, now: now, expiresAt: now.addingTimeInterval(8)))
        XCTAssertFalse(TodoUndo.added(original).canUndo(current: try item(title: "买水果"), now: now, expiresAt: now.addingTimeInterval(8)))
        let existing = try item(deduplicated: true)
        XCTAssertFalse(TodoUndo.added(existing).canUndo(current: existing, now: now, expiresAt: now.addingTimeInterval(8)))
        XCTAssertFalse(TodoUndo.added(original).canUndo(current: original, now: now.addingTimeInterval(9), expiresAt: now.addingTimeInterval(8)))
    }
    func testConfirmationNamesTheActualActionAndConflictChoice() {
        XCTAssertEqual(ToolPresentation.confirmationAction("create_reminder"), "添加提醒")
        XCTAssertEqual(ToolPresentation.confirmationAction("delete_reminder"), "删除这条待办")
        XCTAssertEqual(ToolPresentation.confirmationAction("create_calendar_event", conflictCount: 2), "仍安排这个时间")
        XCTAssertFalse(ToolPresentation.resultTitle(tool: "create_reminder", status: "execution_unknown").contains("已完成"))
    }
}

private actor PausedDemoTransport: AgentTransport {
    private(set) var healthCalls = 0
    private var continuation: CheckedContinuation<HealthResponse, Never>?
    func health() async throws -> HealthResponse {
        healthCalls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func releaseHealth() {
        continuation?.resume(returning: HealthResponse(status: "ok", modelMode: "mock", executionMode: "mock", adapterConfigured: true, tools: 0, requiresDeferExecution: false, authRequired: false))
        continuation = nil
    }
    func turnSnapshot(turnId: String) async throws -> AgentTurnResponse { throw URLError(.unsupportedURL) }
    func startTurn(text: String, conversationId: String?, permissions: [String: String], deferExecution: Bool) async throws -> AgentTurnResponse { throw URLError(.unsupportedURL) }
    func submitToolResults(turnId: String, results: [ToolResultPayload]) async throws -> AgentTurnResponse { throw URLError(.unsupportedURL) }
}
