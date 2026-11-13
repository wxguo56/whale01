import XCTest

final class InteractionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WHALE_DEMO_HOME"] = "1"
        app.launch()
        return app
    }
    func testThreeTabsKeepDiscoverySeparateFromTheAssistant() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["助手"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["待办"].exists)
        XCTAssertTrue(app.tabBars.buttons["发现"].exists)
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["游戏动态"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["热榜"].exists)
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue(app.staticTexts["常用操作"].waitForExistence(timeout: 5))
    }
    func testDraftSurvivesTabSwitchAndAppRelaunchWithoutSending() {
        let app = launch()
        let composer = app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("draft preserved without sending")
        app.buttons["收起键盘"].tap()
        app.tabBars.buttons["发现"].tap()
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch.value as? String ?? "").contains("draft preserved"))
        app.terminate()
        app.launch()
        let restored = app.descendants(matching: .any).matching(identifier: "assistant-composer").firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue((restored.value as? String ?? "").contains("draft preserved"))
    }
}
