import XCTest

final class SettingsPlaytests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TEXTRACTOR_UI_TEST_SUITE"] = "com.textractor.uitest.\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 10))
    }
    override func tearDown() { app.terminate() }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<35 {
            if element.isHittable { return }
            app.windows["Settings"].scrollViews.firstMatch.swipeUp()
        }
        XCTFail("Element is not reachable: \(element.identifier)")
    }
    func testUSEnglishPersistsAfterRelaunch() {
        let picker = app.popUpButtons["settings.language"]
        reveal(picker)
        picker.click()
        app.menuItems["French"].click()
        picker.click()
        app.menuItems["English (US)"].click()
        let status = app.staticTexts["settings.language.status"]
        XCTAssertTrue(status.label.contains("en-US"))
        // A second launch must restore the choice from the isolated settings suite.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 10))
        reveal(app.popUpButtons["settings.language"])
        XCTAssertTrue(app.staticTexts["settings.language.status"].label.contains("en-US"))
        let attachment = XCTAttachment(screenshot: app.windows["Settings"].screenshot())
        attachment.name = "US English at 252pt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testTourSkipAndReplay() {
        let replay = app.buttons["settings.onboarding.replay"]
        replay.click()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].click()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        replay.click()
        XCTAssertTrue(app.staticTexts["onboarding.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.progress"].label, "1 of 4")
        for expected in 2...4 {
            app.buttons["onboarding.next"].click()
            XCTAssertEqual(app.staticTexts["onboarding.progress"].label, "\(expected) of 4")
        }
        app.buttons["onboarding.next"].click()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
    }
    func testCameraCancellationReturnsToSettings() {
        reveal(app.buttons["settings.continuity"])
        app.buttons["settings.continuity"].click()
        let window = app.windows["Import from iPhone or iPad"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["continuity.chooseDevice"].exists)
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertFalse(window.exists)
        XCTAssertTrue(app.windows["Settings"].exists)
    }
}
