import XCTest
@testable import WhaleAgent

final class CoreTests: XCTestCase {
    func testToolDateParsesCommonISOStyles() {
        XCTAssertNotNil(ToolDate.parse("2026-11-10T15:00:00+08:00"))
        XCTAssertNotNil(ToolDate.parse("2026-11-10T07:00:00.123Z"))
        XCTAssertNil(ToolDate.parse("明天下午三点"))
    }

    func testJSONValueRequiredString() throws {
        let value = JSONValue.object(["title": .string("取快递")])
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
}
