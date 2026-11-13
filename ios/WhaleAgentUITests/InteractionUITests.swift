import XCTest

final class InteractionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["WHALE_DEMO_HOME"] = "1"
        app.launchEnvironment["WHALE_DEMO_INITIAL_CHANNEL"] = "ai"
        app.launch()
        return app
    }
    func testThreeTabsKeepDiscoverySeparateFromTheAssistant() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["助手"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["待办"].exists)
        XCTAssertTrue(app.tabBars.buttons["发现"].exists)
        app.tabBars.buttons["待办"].tap()
        XCTAssertTrue(app.buttons["回到对话"].waitForExistence(timeout: 5))
        app.tabBars.buttons["发现"].tap()
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "discovery-after-tab-tap"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertTrue(app.buttons["discover-channel-game"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["discover-channel-weibo"].exists)
        app.buttons["discover-channel-game"].tap()
        XCTAssertTrue(app.otherElements["discover-content-game"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["发现"].isHittable)
        XCTAssertFalse(app.buttons["返回发现"].exists)
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue(app.staticTexts["常用操作"].waitForExistence(timeout: 5))
    }
    func testChannelSwitchesKeepNavigationAndSelectorFramesFixed() {
        let app = launch()
        app.tabBars.buttons["发现"].tap()
        let navigation = app.otherElements["discover-fixed-header"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let navFrame = navigation.frame
        let tabsFrame = app.tabBars.firstMatch.frame
        let selectorY = app.buttons["discover-channel-ai"].frame.minY
        for channel in ["game", "headline", "market", "ai"] {
            app.buttons["discover-channel-" + channel].tap()
            XCTAssertTrue(app.otherElements["discover-content-" + channel].waitForExistence(timeout: 10))
            XCTAssertEqual(navigation.frame.minY, navFrame.minY, accuracy: 1)
            XCTAssertEqual(navigation.frame.height, navFrame.height, accuracy: 1)
            XCTAssertEqual(app.tabBars.firstMatch.frame.minY, tabsFrame.minY, accuracy: 1)
            XCTAssertEqual(app.buttons["discover-channel-ai"].frame.minY, selectorY, accuracy: 1)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch.exists)
            attach("fixed-shell-" + channel)
        }
    }
    func testNewsSectionSelectorStaysPinnedWhileContentScrollsAndChanges() {
        let app = launch()
        app.tabBars.buttons["发现"].tap()
        let all = app.buttons["discover-section-ai-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        let baseline = all.frame.minY
        app.otherElements["discover-content-ai"].swipeUp()
        XCTAssertEqual(all.frame.minY, baseline, accuracy: 1)
        app.buttons["discover-section-ai-coding"].tap()
        XCTAssertEqual(all.frame.minY, baseline, accuracy: 1)
        XCTAssertTrue(app.tabBars.buttons["助手"].isHittable)
        attach("pinned-ai-coding")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDraftSurvivesTabSwitchAndAppRelaunchWithoutSending() {
        let app = launch()
        let composer = app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("draft preserved without sending")
        app.buttons["收起键盘"].tap()
        app.tabBars.buttons["发现"].tap()
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "draft-after-discovery-tab"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertTrue(app.buttons["discover-channel-music"].waitForExistence(timeout: 10))
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch.value as? String ?? "").contains("draft preserved"))
        app.terminate()
        app.launch()
        let restored = app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue((restored.value as? String ?? "").contains("draft preserved"))
    }
}
