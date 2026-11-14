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

    func testDiscoverGameChannelAndRankBoards() {
        XCTAssertEqual(DiscoverChannel.game.title, "游戏动态")
        XCTAssertEqual(DiscoverChannel.game.icon, "gamecontroller.fill")
        XCTAssertEqual(DiscoverChannel.weibo.title, "热榜")
        XCTAssertEqual(DiscoverChannel.weibo.icon, "flame.fill")
        XCTAssertNil(GameSection.news.board)
        XCTAssertEqual(GameSection.free.board, .free)
        XCTAssertEqual(GameSection.grossing.board, .grossing)
    }

    func testDiscoverNewsSectionsCoverTopicsAndCategories() {
        XCTAssertEqual(
            DiscoverChannel.ai.newsSections.map(\.title),
            ["全部", "游戏应用", "程序开发", "游戏科技", "厂商动态"]
        )
        XCTAssertTrue(DiscoverChannel.headline.newsSections.contains { $0.id == "military" })
        XCTAssertTrue(DiscoverChannel.headline.newsSections.contains { $0.id == "auto" })
        XCTAssertEqual(GameSection.steamDeals.steamKind, .specials)
        XCTAssertEqual(GameSection.comingSoon.title, "新作预告")
    }

    func testSteamPriceFormattingUsesStoreCents() {
        let deal = SteamItem(
            id: 1,
            name: "影之刃零",
            discounted: true,
            discountPercent: 20,
            originalPrice: 26_800,
            finalPrice: 21_440,
            currency: "CNY",
            headerImage: ""
        )
        XCTAssertEqual(deal.discountText, "-20%")
        XCTAssertEqual(deal.originalPriceText, "¥268")
        XCTAssertEqual(deal.finalPriceText, "¥214.40")
    }

    func testWeatherSnapshotParsesCurrentHourlyAndAirQuality() throws {
        let payload = JSONValue.object([
            "locationName": .string("杭州市"),
            "current": .object([
                "temperatureC": .number(21.4),
                "apparentC": .number(20.1),
                "humidity": .number(63),
                "windKph": .number(8.2),
                "condition": .string("partlyCloudy"),
                "summary": .string("局部多云"),
                "isDay": .bool(true)
            ]),
            "hourly": .array([
                .object([
                    "time": .string("2026-11-12T14:00"),
                    "temperatureC": .number(21.4),
                    "condition": .string("clear"),
                    "summary": .string("晴"),
                    "isDay": .bool(true)
                ])
            ]),
            "sun": .object([
                "sunrise": .string("2026-11-12T06:32"),
                "sunset": .string("2026-11-12T17:05")
            ]),
            "airQuality": .object([
                "usAqi": .number(42),
                "pm25": .number(18.5)
            ]),
            "days": .array([
                .object([
                    "date": .string("2026-11-12"),
                    "condition": .string("partlyCloudy"),
                    "summary": .string("局部多云"),
                    "temperatureC": .object(["min": .number(16), "max": .number(23)]),
                    "precipitationChance": .number(20),
                    "advice": .string("暂无")
                ])
            ])
        ])
        let snapshot = try XCTUnwrap(WeatherSnapshot.from(payload))
        XCTAssertEqual(snapshot.locationName, "杭州市")
        XCTAssertEqual(snapshot.current?.temperatureC, 21.4)
        XCTAssertEqual(snapshot.hours.count, 1)
        XCTAssertEqual(snapshot.sun?.sunriseText, "06:32")
        XCTAssertEqual(snapshot.air?.levelText, "优")
        XCTAssertEqual(snapshot.days.count, 1)
    }

    func testDiscoverChannelsMatchHomeOrder() {
        XCTAssertEqual(
            DiscoverChannel.allCases.map(\.title),
            ["AI科技", "A股自选", "游戏动态", "我的音乐", "时事新闻", "热榜"]
        )
        XCTAssertEqual(AIPaperCategory.allCases.map(\.rawValue), ["cs.AI", "cs.LG", "cs.CL", "cs.CV"])
    }

    func testWeiboHotItemFormatsRealHeat() {
        let item = WeiboHotItem(
            rank: 1,
            id: "weibo-1",
            word: "测试热搜",
            note: "测试热搜",
            category: "社会",
            tag: "热",
            hotValue: 1_092_000,
            link: "https://s.weibo.com/weibo?q=%E6%B5%8B%E8%AF%95"
        )
        XCTAssertEqual(item.hotText, "109.2万")
        XCTAssertNotNil(item.url)
    }

    func testNewsTextRemovesNestedHTMLAndEntities() {
        XCTAssertEqual(NewsText.plain("&lt;p&gt;今天 &amp;quot;AI&amp;quot; 新闻&lt;/p&gt;"), "今天 \"AI\" 新闻")
        XCTAssertEqual(NewsText.plain("<![CDATA[<b>标题</b>]]>"), "标题")
        XCTAssertEqual(NewsText.plain("&lt;script&gt;alert(1)&lt;/script&gt;正文"), "正文")
        XCTAssertEqual(NewsText.plain("&amp;lt;div&amp;gt;双层转义&amp;lt;/div&amp;gt;"), "双层转义")
    }

    func testMusicAlbumAndTrackKeepRealLibraryIdentity() {
        let albumJSON = JSONValue.object([
            "albumId": .string("album:123"),
            "title": .string("真实专辑"),
            "artist": .string("真实艺人"),
            "trackCount": .number(9),
            "source": .string("system")
        ])
        let album = MusicAlbumItem(json: albumJSON)
        XCTAssertEqual(album?.albumId, "album:123")
        XCTAssertEqual(album?.trackCount, 9)

        let trackJSON = JSONValue.object([
            "trackId": .string("library:456"),
            "title": .string("第一首"),
            "artist": .string("真实艺人"),
            "album": .string("真实专辑"),
            "albumId": .string("album:123"),
            "durationSec": .number(201),
            "source": .string("system")
        ])
        let track = MusicTrackItem(json: trackJSON)
        XCTAssertEqual(track?.albumId, "album:123")
        XCTAssertEqual(track?.source, "system")
        XCTAssertEqual(track?.durationText, "3:21")
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
    func testWeatherFallbackMapsWWOToChinese() {
        XCTAssertEqual(WeatherExecutor.wmoEquivalent(forWWO: 113), 0)
        XCTAssertEqual(WeatherExecutor.wmoEquivalent(forWWO: 266), 61)
        XCTAssertEqual(WeatherExecutor.wmoEquivalent(forWWO: 389), 95)
        XCTAssertEqual(WeatherExecutor.summary(for: WeatherExecutor.wmoEquivalent(forWWO: 266)), "小雨")
    }

    @MainActor
    func testWeatherFallbackParsesWttrPayloadWithoutFabricating() throws {
        let json = """
        {"current_condition":[{"temp_C":"17","FeelsLikeC":"18","humidity":"94","precipMM":"0.2","windspeedKmph":"9","weatherCode":"266"}],"weather":[{"date":"2026-11-14","maxtempC":"20","mintempC":"16","astronomy":[{"sunrise":"06:20 AM","sunset":"05:05 PM"}],"hourly":[{"time":"1200","tempC":"18","FeelsLikeC":"18","weatherCode":"116","chanceofrain":"10"}]}]}
        """
        let payload = try WeatherExecutor.parseFallback(data: Data(json.utf8))
        XCTAssertEqual(payload["source"]?.stringValue, "wttr.in")
        XCTAssertEqual(payload["dayCount"]?.doubleValue, 1)
        XCTAssertEqual(payload["days"]?.arrayValue?.count, 1)
        XCTAssertEqual(payload["current"]?.objectValue?["summary"]?.stringValue, "小雨")
        XCTAssertEqual(payload["days"]?.arrayValue?.first?.objectValue?["temperatureC"]?.objectValue?["max"]?.doubleValue, 20)
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
    func testDirectContentCaptureUsesOneBasedGroups() {
        let groups = DirectContentClient.capture("^(sh|sz)([0-9]{6})$", in: "sh600519")
        XCTAssertEqual(groups?[1], "sh")
        XCTAssertEqual(groups?[2], "600519")
    }

    func testDirectContentTagReturnsTextWithoutCrashing() {
        let block = "<item><title>AI 芯片新进展</title><link>https://example.com/a</link></item>"
        XCTAssertEqual(DirectContentClient.tag("title", in: block), "AI 芯片新进展")
    }

    func testDirectContentNormalizesSymbols() {
        XCTAssertEqual(DirectContentClient.normalizeSymbol("sh600519")?.symbol, "sh600519")
        XCTAssertEqual(DirectContentClient.normalizeSymbol("600519.SH")?.symbol, "sh600519")
        XCTAssertEqual(DirectContentClient.normalizeSymbol("600519")?.symbol, "sh600519")
        XCTAssertEqual(DirectContentClient.normalizeSymbol("000001")?.symbol, "sz000001")
    }
    func testDirectContentParsesTencentQuote() {
        var fields = [String](repeating: "0", count: 50)
        fields[1] = "贵州茅台"
        fields[2] = "600519"
        fields[3] = "1402.30"
        fields[4] = "1439.00"
        fields[5] = "1435.00"
        fields[6] = "1000"
        fields[30] = "20261111161439"
        fields[31] = "-36.70"
        fields[32] = "-2.55"
        fields[33] = "1440.00"
        fields[34] = "1399.00"
        fields[37] = "12345"
        fields[38] = "0.5"
        fields[39] = "20.1"
        fields[44] = "17600"
        fields[45] = "20000"
        let quote = DirectContentClient.parseQuote(symbol: "sh600519", body: fields.joined(separator: "~"))
        XCTAssertEqual(quote?.name, "贵州茅台")
        XCTAssertEqual(quote?.price, 1402.30)
        XCTAssertEqual(quote?.changePercent, -2.55)
        XCTAssertEqual(quote?.marketCap, 2_000_000_000_000)
        XCTAssertNil(DirectContentClient.parseQuote(symbol: "sh600519", body: "1~2~3"))
    }

    func testDailyQuotePoolRepeatsOnlyAfterSixtyHours() {
        XCTAssertEqual(DailyQuote.pool.count, 120)
        XCTAssertEqual(Set(DailyQuote.pool).count, 120)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        var indexes = Set<Int>()
        for slot in 0..<120 {
            let date = calendar.date(byAdding: .minute, value: slot * 30, to: start)!
            XCTAssertTrue(indexes.insert(DailyQuote.slotIndex(at: date, calendar: calendar)).inserted)
        }
        XCTAssertEqual(indexes.count, 120)
    }

    func testDailyQuoteStaysStableInsideHalfHourSlot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let ten = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10, minute: 0))!
        let tenTwentyNine = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10, minute: 29))!
        let tenThirty = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10, minute: 30))!
        XCTAssertEqual(DailyQuote.slotIndex(at: ten, calendar: calendar), DailyQuote.slotIndex(at: tenTwentyNine, calendar: calendar))
        XCTAssertNotEqual(DailyQuote.slotIndex(at: tenTwentyNine, calendar: calendar), DailyQuote.slotIndex(at: tenThirty, calendar: calendar))
    }

    func testZhihuHeatAndLinksUseRealPublicValues() {
        XCTAssertEqual(DirectContentClient.zhihuHeatValue("432 万热度"), 4_320_000)
        XCTAssertEqual(DirectContentClient.zhihuHeatValue("1.2 亿热度"), 120_000_000)
        XCTAssertEqual(
            DirectContentClient.zhihuLink(type: "question", id: "2104125774148146904", raw: "https://api.zhihu.com/questions/2104125774148146904"),
            "https://www.zhihu.com/question/2104125774148146904"
        )
        XCTAssertEqual(
            DirectContentClient.zhihuLink(type: "article", id: "123456", raw: "https://api.zhihu.com/articles/123456"),
            "https://zhuanlan.zhihu.com/p/123456"
        )
    }

    func testHotBoardsExposeWeiboAndZhihu() {
        XCTAssertEqual(HotBoard.allCases.map(\.title), ["微博热搜", "知乎热榜"])
        XCTAssertEqual(HotBoard.zhihu.icon, "text.bubble.fill")
    }

    @MainActor
    func testHomeDigestUsesRealNewsTitlesAndSkipsBlank() {
        let items = [
            NewsItem(id: "a", title: "AI 芯片新进展", summary: "", source: "测试源", link: "https://example.com/a", publishedAt: nil, channel: "ai", rank: nil),
            NewsItem(id: "b", title: "   ", summary: "", source: "测试源", link: "", publishedAt: nil, channel: "ai", rank: nil),
            NewsItem(id: "c", title: "游戏科技大会新技术", summary: "", source: "测试源", link: "https://example.com/c", publishedAt: nil, channel: "ai", rank: nil)
        ]
        XCTAssertEqual(HomeDigestModel.newsLines(items), ["AI 芯片新进展", "游戏科技大会新技术"])
        XCTAssertEqual(HomeDigestModel.newsLines([]), [])
    }

    @MainActor
    func testHomeDigestHotLineKeepsRealHeat() {
        let items = [
            WeiboHotItem(rank: 1, id: "weibo-1", word: "测试热搜", note: "", category: "社会", tag: "", hotValue: 1_092_000, link: "")
        ]
        XCTAssertEqual(HomeDigestModel.hotLines(items), ["测试热搜 · 109.2万"])
        XCTAssertEqual(HomeDigestModel.hotLines([]), [])
    }
}
