import XCTest
@testable import WhaleAgent

final class ReliabilityTests: XCTestCase {
    func testDiscussionDoesNotBecomeWeatherExecution() {
        for text in ["不要查天气", "天气这个词怎么解释", "假如我要导航回家", "你能不能查天气", "不用导航回家", "“查天气”", "查天气这句话怎么翻译"] {
            XCTAssertNil(RealDataGuard.intent(for: text), text)
        }
        XCTAssertEqual(RealDataGuard.intent(for: "不要查天气，查今天的股价"), .stock)
        XCTAssertEqual(RealDataGuard.intent(for: "我不查天气，查今天600519的行情"), .stock)
    }

    func testQuestionCannotLaunderUnsupportedFacts() {
        for text in ["现在25度，要帮你安排出行吗？", "今天晴，气温25度。你在哪个城市？"] {
            let reply = RealDataGuard.finalReply(for: .weather, usedTools: [], proposed: text)
            XCTAssertTrue(reply.contains("没有拿到真实天气"))
        }
        XCTAssertTrue(RealDataGuard.isClarifying("你想查哪个城市的天气？", for: .weather))
        XCTAssertFalse(RealDataGuard.isClarifying("今天股价上涨，要继续看吗？", for: .stock))
        XCTAssertFalse(RealDataGuard.finalReply(for: .weather, usedTools: [], proposed: "北京晴天，要查哪个城市？").contains("北京晴天"))
        XCTAssertTrue(RealDataGuard.finalReply(for: .stock, usedTools: ["search_stock"], proposed: "股价20元").contains("没有取得真实行情"))
    }

    func testTodoKeepsIncompleteTimesAsDraftsAndDoesNotAddEdits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10))!
        for text in ["今晚取快递", "明天取快递", "三点取快递", "明天25点取快递", "把买菜改到明天", "每周五买菜"] {
            let result = TodoQuickParser.parseAdd(text, now: now, calendar: calendar)
            XCTAssertNotNil(result.validationError, text)
            XCTAssertNil(result.dueAt, text)
        }
        let simple = TodoQuickParser.parseAdd("买菜", now: now, calendar: calendar)
        XCTAssertNil(simple.validationError)
        XCTAssertEqual(simple.title, "买菜")
        let scheduled = TodoQuickParser.parseAdd("明天下午三点取快递", now: now, calendar: calendar)
        XCTAssertNil(scheduled.validationError)
        XCTAssertEqual(calendar.component(.hour, from: scheduled.dueAt!), 15)
        XCTAssertEqual(calendar.component(.day, from: scheduled.dueAt!), 14)
        XCTAssertEqual(scheduled.title, "取快递")
        let relative = TodoQuickParser.parseAdd("10分钟后喝水", now: now, calendar: calendar)
        XCTAssertEqual(relative.dueAt?.timeIntervalSince(now), 600)
    }

    func testUnknownPublishedDateStaysUnknown() {
        XCTAssertNil(DirectContentClient.isoDate(""))
        XCTAssertNil(DirectContentClient.isoDate("not-a-date"))
        XCTAssertEqual(DiscoverFormat.relative(nil), "时间未知")
        XCTAssertNotNil(DirectContentClient.isoDate("Fri, 13 Nov 2026 08:00:00 +0800"))
    }

    func testNewsLimitAndTopicMembershipAreIndependentOfArrivalOrder() {
        let first = NewsItem(id: "a", title: "同一条新闻", summary: "摘要", source: "A", link: "https://example.com/a", publishedAt: nil, channel: "ai", rank: nil, section: "coding")
        let duplicate = NewsItem(id: "b", title: "同一条新闻", summary: "摘要", source: "B", link: first.link, publishedAt: nil, channel: "ai", rank: nil, section: "game-ai")
        let other = NewsItem(id: "c", title: "另一条新闻", summary: "摘要", source: "A", link: "https://example.com/c", publishedAt: "2026-11-13T10:00:00Z", channel: "ai", rank: nil, section: "vendor")
        let selected = NewsSelection.select([first, duplicate, other], limit: 2, topics: ["coding", "vendor"])
        XCTAssertEqual(selected, NewsSelection.select([other, duplicate, first], limit: 2, topics: ["coding", "vendor"]))
        XCTAssertEqual(selected.count, 2)
        let shared = selected.first { $0.link == first.link }!
        XCTAssertTrue(shared.topicIDs.contains("coding"))
        XCTAssertTrue(shared.topicIDs.contains("game-ai"))
        XCTAssertEqual(NewsSelection.select([first, duplicate, other], limit: 1).count, 1)
    }

    func testPublicWebPolicyRejectsPrivateAndAlternateURLs() {
        for raw in ["http://127.0.0.1/a", "http://10.0.0.1", "http://192.168.1.1", "http://[::1]", "http://[::ffff:127.0.0.1]", "http://2130706433", "http://localhost", "http://user:password@example.com", "file:///tmp/a", "http://example.com:8080"] {
            XCTAssertThrowsError(try PublicURLPolicy.validate(URL(string: raw)!))
        }
        XCTAssertNoThrow(try PublicURLPolicy.validate(URL(string: "https://example.com/article")!))
        XCTAssertNoThrow(try PublicURLPolicy.validate(URL(string: "https://8.8.8.8")!))
    }

    func testSensitiveCoordinatesNeverReachModelSummary() {
        let input = JSONValue.object(["placeId": .string("opaque-ref"), "latitude": .number(30.12), "longitude": .number(120.11), "nested": .object(["phoneNumber": .string("123"), "name": .string("联系人")])])
        let result = ToolModelSummary.project(input).objectValue!
        XCTAssertNil(result["latitude"])
        XCTAssertNil(result["longitude"])
        XCTAssertNil(result["nested"]?.objectValue?["phoneNumber"])
        XCTAssertEqual(result["placeId"], .string("opaque-ref"))
    }

    func testLiveEvidenceRequiresSourceTimeAndUsefulPayload() {
        let now = Date()
        let current: [String: Any] = ["source": "public-feed", "updatedAt": ToolDate.iso(now), "items": [["title": "真实新闻"]]]
        XCTAssertTrue(ToolEvidencePolicy.accepts(tool: "get_tech_news", data: current, now: now))
        XCTAssertFalse(ToolEvidencePolicy.accepts(tool: "get_tech_news", data: ["source": "feed", "items": []], now: now))
        XCTAssertFalse(ToolEvidencePolicy.accepts(tool: "get_tech_news", data: ["source": "feed", "updatedAt": ToolDate.iso(now.addingTimeInterval(-3600)), "items": ["旧新闻"]], now: now))
        XCTAssertFalse(ToolEvidencePolicy.accepts(tool: "get_stock_quote", data: ["source": "quotes", "updatedAt": ToolDate.iso(now), "quotes": []], now: now))
    }

    func testMemoryWriteFailureRollsBackAndReportsFailure() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("file-not-directory".utf8).write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = MemoryStore(fileURL: base.appendingPathComponent("preferences.json"))
        XCTAssertThrowsError(try store.set(key: "测试", value: "测试值"))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testMissingSystemRecordNeverProvesDeletion() {
        XCTAssertFalse(SystemRecordPresence.missing.provesDeletion)
        XCTAssertFalse(SystemRecordPresence.unobservable.provesDeletion)
    }

    func testTaskStatePreservesUnknownOutcomes() throws {
        var state = LocalTaskState(goal: "先创建提醒，再查看日历")
        state.observations["call-a"] = "execution_unknown"
        state.remaining = ["list_calendar_events"]
        let roundTrip = try JSONDecoder().decode(LocalTaskState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(roundTrip.hasUnresolvedResults)
        XCTAssertEqual(roundTrip.goal, state.goal)
        XCTAssertEqual(roundTrip.remaining, state.remaining)
    }
}
