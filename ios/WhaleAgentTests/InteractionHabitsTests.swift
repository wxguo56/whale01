import XCTest
@testable import WhaleAgent

final class InteractionHabitsTests: XCTestCase {
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
