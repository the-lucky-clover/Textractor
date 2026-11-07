import XCTest

final class MobilePlaytests: XCTestCase {
    func testScreenshotReviewAndExportFlow() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let skip = app.buttons["mobile.onboarding.skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        app.buttons["mobile.fixture"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic conversation.png"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Review"].tap()
        XCTAssertTrue(app.staticTexts["Please bring the blue folder."].waitForExistence(timeout: 10))
        app.buttons["mobile.export"].tap()
        XCTAssertTrue(app.buttons["mobile.pdf.create"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Print packet options"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["English (US)"].exists)
        app.buttons["mobile.onboarding.replay"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
    }
}
