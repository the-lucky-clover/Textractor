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
        let scroll = app.windows["Settings"].scrollViews.firstMatch
        for _ in 0..<20 {
            if element.isHittable { return }
            scroll.scroll(byDeltaX: 0, deltaY: element.frame.midY > scroll.frame.midY ? -15 : 15)
        }
        XCTFail("Element is not reachable: \(element.identifier)")
    }
    private func textValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
    func testUSEnglishPersistsAfterRelaunch() {
        let picker = app.popUpButtons["settings.language"]
        reveal(picker)
        XCTAssertTrue(textValue(app.staticTexts["settings.language.status"]).contains("en-US"))
        picker.click()
        app.menuItems["French"].click()
        picker.click()
        app.menuItems["English (US)"].click()
        let status = app.staticTexts["settings.language.status"]
        XCTAssertTrue(textValue(status).contains("en-US"))
        // A second launch must restore the choice from the isolated settings suite.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 10))
        reveal(app.popUpButtons["settings.language"])
        XCTAssertTrue(textValue(app.staticTexts["settings.language.status"]).contains("en-US"))
        let attachment = XCTAttachment(screenshot: app.windows["Settings"].screenshot())
        attachment.name = "US English at 252pt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testTourSkipAndReplay() {
        let picker = app.popUpButtons["settings.language"]
        reveal(picker)
        picker.click()
        app.menuItems["French"].click()
        let replay = app.buttons["settings.onboarding.replay"]
        reveal(replay)
        replay.click()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].click()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        replay.click()
        XCTAssertTrue(app.staticTexts["onboarding.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(textValue(app.staticTexts["onboarding.progress"]), "1 of 4")
        for expected in 2...4 {
            app.buttons["onboarding.next"].click()
            XCTAssertEqual(textValue(app.staticTexts["onboarding.progress"]), "\(expected) of 4")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Welcome step \(expected)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["onboarding.next"].click()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        reveal(app.popUpButtons["settings.language"])
        XCTAssertTrue(textValue(app.staticTexts["settings.language.status"]).contains("fr-FR"))
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
