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
        let review = XCTAttachment(screenshot: app.screenshot()); review.name = "Reconstructed conversation review"; review.lifetime = .keepAlways; add(review)
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("libary")
        XCTAssertTrue(app.staticTexts["I will arrive at the library at noon."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Review"].tap()
        app.buttons["mobile.export"].tap()
        XCTAssertTrue(app.buttons["mobile.pdf.create"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Print packet options"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Settings"].tap()
        let language = app.descendants(matching: .any)["mobile.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertEqual(language.value as? String, "English (US)")
        app.buttons["mobile.onboarding.replay"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
    }
}
