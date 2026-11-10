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

    func testRealDataIntentKeepsHomeNavigationSeparate() {
        XCTAssertEqual(RealDataGuard.intent(for: "导航回家"), RealDataIntent.homeNavigation)
        XCTAssertEqual(RealDataGuard.intent(for: "我在哪"), RealDataIntent.currentLocation)
        XCTAssertEqual(RealDataGuard.intent(for: "附近有咖啡店吗"), RealDataIntent.nearbyPlaces)
        XCTAssertEqual(RealDataGuard.intent(for: "明天会下雨吗"), RealDataIntent.weather)
        XCTAssertNil(RealDataGuard.intent(for: "我回家了"))
        XCTAssertNil(RealDataGuard.intent(for: "把照片发过去"))
    }

    func testHomeAddressRequiresARealAddress() {
        let vague = MemoryPreference(id: "home", key: "家庭地址", value: "杭州", updatedAt: Date())
        XCTAssertNil(RealDataGuard.homeAddress(in: [vague]))

        let detailed = MemoryPreference(
            id: "home-full",
            key: "家庭地址",
            value: "浙江省杭州市西湖区文三路 100 号",
            updatedAt: Date()
        )
        XCTAssertEqual(RealDataGuard.homeAddress(in: [detailed]), detailed.value)
    }

    func testHomeNavigationCannotClaimRouteWithoutToolResult() {
        let missingAddress = RealDataGuard.finalReply(
            for: .homeNavigation,
            usedTools: [],
            proposed: "已经带你回家了"
        )
        XCTAssertTrue(missingAddress.contains("不能规划回家路线"))

        let searchOnly = RealDataGuard.finalReply(
            for: .homeNavigation,
            usedTools: ["search_places"],
            proposed: "路线已经规划好"
        )
        XCTAssertTrue(searchOnly.contains("还没有把目的地交给地图"))
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

    @MainActor
    func testCurrentLocationAddressKeepsRegionTogetherAndDeduplicates() {
        let address = LocationExecutor.displayAddress(
            region: [" 浙江省 ", "杭州市", "西湖区", "杭州市"],
            detail: ["文三路", "文三路 90号"]
        )
        XCTAssertEqual(address, "浙江省杭州市西湖区 文三路 文三路 90号")
    }
    @MainActor
    func testWeatherCodeMappingUsesWMOValues() {
        XCTAssertEqual(WeatherExecutor.summary(for: 0), "晴")
        XCTAssertEqual(WeatherExecutor.summary(for: 61), "小雨")
        XCTAssertEqual(WeatherExecutor.summary(for: 75), "大雪")
        XCTAssertEqual(WeatherExecutor.summary(for: 95), "雷雨")
        XCTAssertEqual(WeatherExecutor.conditionKey(for: 3), "cloudy")
        XCTAssertEqual(WeatherExecutor.conditionKey(for: 82), "showers")
        XCTAssertEqual(WeatherExecutor.conditionKey(for: 96), "thunderstorm")
    }

    @MainActor
    func testWeatherForecastParsesProviderPayloadWithoutFabricating() throws {
        let json = """
        {"timezone":"Asia/Shanghai","daily":{"time":["2026-11-10","2026-11-11"],"weather_code":[61,0],"temperature_2m_max":[18.4,21.6],"temperature_2m_min":[11.2,12.8],"precipitation_probability_max":[70,10]}}
        """
        let payload = try WeatherExecutor.parseForecast(data: Data(json.utf8))
        XCTAssertEqual(payload["dayCount"]?.doubleValue, 2)
        XCTAssertEqual(payload["summary"]?.stringValue, "小雨")
        XCTAssertEqual(payload["precipitationChance"]?.doubleValue, 70)
        XCTAssertEqual(payload["timezone"]?.stringValue, "Asia/Shanghai")

        let days = payload["days"]?.arrayValue ?? []
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[1].objectValue?["summary"]?.stringValue, "晴")
        let temperatures = days[0].objectValue?["temperatureC"]?.objectValue
        XCTAssertEqual(temperatures?["min"]?.doubleValue, 11.2)
        XCTAssertEqual(temperatures?["max"]?.doubleValue, 18.4)
    }

    @MainActor
    func testWeatherForecastRejectsEmptyProviderPayload() {
        XCTAssertThrowsError(try WeatherExecutor.parseForecast(data: Data("{\"daily\":{\"time\":[]}}".utf8)))
        XCTAssertThrowsError(try WeatherExecutor.parseForecast(data: Data("{}".utf8)))
    }

    @MainActor
    func testWeatherAdviceMentionsUmbrellaAndHeat() {
        let advice = WeatherExecutor.advice(high: 34, low: 26, chance: 80, code: 61)
        XCTAssertTrue(advice.contains("带伞"))
        XCTAssertTrue(advice.contains("防晒"))
        XCTAssertEqual(WeatherExecutor.advice(high: 22, low: 15, chance: 5, code: 0), "暂无明显降水或极端气温信号")
    }

    @MainActor
    func testWeatherDaySpanCountsInclusiveDays() {
        XCTAssertEqual(WeatherExecutor.daySpan(from: "2026-11-10", to: "2026-11-10"), 1)
        XCTAssertEqual(WeatherExecutor.daySpan(from: "2026-11-10", to: "2026-11-12"), 3)
        XCTAssertEqual(WeatherExecutor.daySpan(from: "bad", to: "2026-11-12"), Int.max)
    }

    @MainActor
    func testFreeBuildBlocksHealthButNotWeather() {
        XCTAssertFalse(NativeToolRouter.freeBuildUnavailableTools.contains("get_weather"))
        XCTAssertTrue(NativeToolRouter.freeBuildUnavailableTools.contains("get_activity_summary"))
    }
}

