import XCTest
@testable import WhaleAgent

final class CoreTests: XCTestCase {
    func testToolDateParsesCommonISOStyles() {
        XCTAssertNotNil(ToolDate.parse("2026-11-10T15:00:00+08:00"))
        XCTAssertNotNil(ToolDate.parse("2026-11-10T07:00:00.123Z"))
        XCTAssertNil(ToolDate.parse("明天下午三点"))
    }

    func testJSONValueRequiredString() throws {
        let value: [String: JSONValue] = ["title": .string("取快递")]
        XCTAssertEqual(try value.requiredString("title"), "取快递")
        XCTAssertThrowsError(try value.requiredString("missing"))
    }

    func testOperationLedgerCachesOutcome() async {
        let ledger = OperationLedger()
        let operationId = "test-\(UUID().uuidString)"
        let outcome = CachedToolOutcome(
            status: "success",
            data: .object(["ok": .bool(true)]),
            error: nil
        )
        await ledger.record(operationId: operationId, outcome: outcome)
        let cached = await ledger.outcome(for: operationId)
        XCTAssertEqual(cached?.status, "success")
    }

    func testSharedInboxRoundTrip() {
        let suite = "whale.tests.\(UUID().uuidString)"
        SharedInbox.testDefaults = UserDefaults(suiteName: suite)
        defer {
            SharedInbox.clear()
            SharedInbox.testDefaults = nil
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let item = SharedItem(
            id: "share-\(UUID().uuidString)",
            text: "这是一段用于测试的分享正文，长度足够。",
            url: "https://example.com",
            title: nil,
            createdAt: Date()
        )
        SharedInbox.save(item)
        XCTAssertEqual(SharedInbox.pending()?.id, item.id)
        SharedInbox.clear(id: item.id)
        XCTAssertNil(SharedInbox.pending())
    }

    func testXfyunStatusIsHonestWhenUnconfigured() {
        XCTAssertEqual(XfyunConfig.isConfigured, false)
        XCTAssertTrue(XfyunConfig.statusText.contains("未配置"))
    }

    func testResultDetailSeparatesReadsFromWrites() {
        let emptyRange = JSONValue.object([
            "count": .number(0),
            "source": .string("eventkit")
        ])
        XCTAssertEqual(
            ToolPresentation.resultDetail(tool: "list_calendar_events", status: "success", data: emptyRange, error: nil),
            "已读取系统日历 · 这段时间没有安排"
        )

        let places = JSONValue.object([
            "count": .number(5),
            "source": .string("mapkit")
        ])
        XCTAssertEqual(
            ToolPresentation.resultDetail(tool: "search_places", status: "success", data: places, error: nil),
            "找到 5 个候选地点 · 未打开地图"
        )
    }

    func testDuplicateReminderDetailDoesNotClaimNewWrite() {
        let payload = JSONValue.object([
            "dueAt": .string("2026-11-10T15:00:00+08:00"),
            "deduplicated": .bool(true),
            "source": .string("eventkit")
        ])
        let detail = ToolPresentation.resultDetail(tool: "create_reminder", status: "success", data: payload, error: nil)
        XCTAssertTrue(detail.hasPrefix("已存在相同提醒，未重复创建"))
    }

    func testExecutionUnknownKeepsItsStatus() {
        let error = ToolExecutionError(code: "execution_unknown", message: "需要核对")
        XCTAssertEqual(error.status, "execution_unknown")
    }

    func testHistoryTrimDropsOrphanToolMessages() {
        let call = DSToolCall(
            id: "call_1",
            type: "function",
            function: DSFunctionCall(name: "list_reminders", arguments: "{}")
        )
        let history = [
            DSMessage(role: "assistant", content: nil, tool_calls: [call], tool_call_id: nil, name: nil),
            DSMessage(role: "tool", content: "{\"status\":\"success\"}", tool_calls: nil, tool_call_id: "call_1", name: nil)
        ]
        XCTAssertEqual(LocalAgentEngine.trimmedHistory(history, limit: 1).count, 0)
        XCTAssertEqual(LocalAgentEngine.trimmedHistory(history, limit: 2).count, 2)
    }

    func testHistoryTrimDropsIncompleteToolCallBlock() {
        let calls = [
            DSToolCall(
                id: "call_a",
                type: "function",
                function: DSFunctionCall(name: "list_reminders", arguments: "{}")
            ),
            DSToolCall(
                id: "call_b",
                type: "function",
                function: DSFunctionCall(name: "list_calendar_events", arguments: "{}")
            )
        ]
        let history = [
            DSMessage(role: "assistant", content: nil, tool_calls: calls, tool_call_id: nil, name: nil),
            DSMessage(role: "tool", content: "{}", tool_calls: nil, tool_call_id: "call_a", name: nil)
        ]
        XCTAssertEqual(LocalAgentEngine.trimmedHistory(history, limit: 10).count, 0)
    }

    func testMerchantPriceExtractionSeparatesKindsAndMatchesBranch() {
        let text = "海底捞西湖店 人均消费约 120 元，双人套餐 198 元，菜单价 68 元。"
        let rows = MerchantPriceExtractor.extract(
            text: text,
            merchant: "海底捞",
            branch: "西湖店",
            city: "杭州",
            sourceURL: "https://example.com/shop",
            sourceTitle: "海底捞西湖店",
            fetchedAt: "2026-11-10T12:00:00+08:00"
        )
        XCTAssertTrue(rows.contains { $0.kind == "per_person" && $0.amount == 120 })
        XCTAssertTrue(rows.contains { $0.kind == "package" && $0.amount == 198 })
        XCTAssertTrue(rows.allSatisfy { $0.branchMatch == "matched" })
    }

    func testMerchantPriceExtractionMarksUnverifiedBranchAndRejectsUnrelatedPage() {
        let rows = MerchantPriceExtractor.extract(
            text: "海底捞（滨江店）人均 110 元。",
            merchant: "海底捞",
            branch: "西湖店",
            city: "杭州",
            sourceURL: "https://example.com/other",
            sourceTitle: "海底捞滨江店",
            fetchedAt: "2026-11-10T12:00:00+08:00"
        )
        XCTAssertEqual(rows.first?.branchMatch, "unverified")

        let unrelated = MerchantPriceExtractor.extract(
            text: "另一家餐厅人均 80 元。",
            merchant: "海底捞",
            branch: "西湖店",
            city: "杭州",
            sourceURL: "https://example.com/unrelated",
            sourceTitle: "另一家餐厅",
            fetchedAt: "2026-11-10T12:00:00+08:00"
        )
        XCTAssertTrue(unrelated.isEmpty)
    }
}
