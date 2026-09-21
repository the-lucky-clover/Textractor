// TextractorUITests/ScreenshotTests.swift
// Automated App Store screenshot generation
// Run with: xcodebuild test -scheme Textractor -destination 'platform=macOS' -only-testing:TextractorUITests/ScreenshotTests

import XCTest

final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()
    let screenshotDir = URL(fileURLWithPath: "dist/screenshots")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-UITest_Screenshots", "YES"]
        app.launch()
        
        // Create screenshot directory
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        
        // Wait for app to be ready
        sleep(1)
    }

    override func tearDown() {
        app.terminate()
    }

    // MARK: - Helper to save screenshot
    func saveScreenshot(named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Also save to dist/screenshots for easy access
        let pngData = screenshot.pngRepresentation
        let url = screenshotDir.appendingPathComponent("\(name).png")
        try? pngData.write(to: url)
        print("📸 Saved screenshot: \(url.path)")
    }

    // MARK: - Test Scenes

    /// 1. Capture overlay with live OCR preview grid
    func testCaptureOverlay() {
        // Trigger region capture via menu (more reliable than hotkey in tests)
        let captureMenu = app.menuBars["Textractor"].menuBarItems["Capture"]
        captureMenu.click()
        app.menuItems["Capture Region"].click()
        
        // Wait for overlay to appear
        let overlay = app.windows["Capture Overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        
        // The overlay should show grid and live OCR text
        // Position mouse to show interesting content
        let center = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.hover()
        
        sleep(1)
        saveScreenshot(named: "01-capture-overlay")
    }

    /// 2. Window capture mode
    func testWindowCapture() {
        // Trigger window capture
        let captureMenu = app.menuBars["Textractor"].menuBarItems["Capture"]
        captureMenu.click()
        app.menuItems["Capture Window"].click()
        
        // Window picker should appear - click on a known window (Finder)
        let windowPicker = app.windows["Window Picker"]
        XCTAssertTrue(windowPicker.waitForExistence(timeout: 3))
        
        // Click on Finder window if visible, otherwise first available
        let finderWindow = windowPicker.staticTexts["Finder"]
        if finderWindow.exists {
            finderWindow.click()
        } else {
            windowPicker.buttons.firstMatch.click()
        }
        
        sleep(1)
        saveScreenshot(named: "02-window-capture")
    }

    /// 3. History grid with thumbnails
    func testHistoryGrid() {
        // Open history window
        app.menuBars["Textractor"].menuBarItems["Window"].click()
        app.menuItems["History"].click()
        
        let historyWindow = app.windows["History"]
        XCTAssertTrue(historyWindow.waitForExistence(timeout: 3))
        
        // Resize to App Store dimensions
        historyWindow.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800))
        
        sleep(1)
        saveScreenshot(named: "03-history-grid")
    }

    /// 4. Source Code Mode settings
    func testSourceCodeMode() {
        // Open settings
        app.menuBars["Textractor"].menuBarItems["Textractor"].click()
        app.menuItems["Settings..."].click()
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3))
        
        // Navigate to Formatting section
        let formattingSection = settingsWindow.staticTexts["Formatting"]
        if formattingSection.exists {
            formattingSection.click()
        }
        
        // Find and enable Source Code Mode toggle
        let sourceCodeToggle = settingsWindow.switches["Source Code Mode"]
        if sourceCodeToggle.exists {
            if sourceCodeToggle.value as? String == "0" {
                sourceCodeToggle.click()
            }
        }
        
        sleep(1)
        saveScreenshot(named: "04-source-code-mode")
    }

    /// 5. Translation settings
    func testTranslationSettings() {
        app.menuBars["Textractor"].menuBarItems["Textractor"].click()
        app.menuItems["Settings..."].click()
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3))
        
        // Navigate to Translation section (may be in Language section)
        let translationPicker = settingsWindow.popUpButtons["Target Language"]
        if translationPicker.exists {
            translationPicker.click()
            // Select Spanish
            app.menuItems["Spanish"].click()
        }
        
        sleep(1)
        saveScreenshot(named: "05-translation-settings")
    }

    /// 6. Toast with quick actions
    func testToastActions() {
        // Trigger a capture to show toast
        let captureMenu = app.menuBars["Textractor"].menuBarItems["Capture"]
        captureMenu.click()
        app.menuItems["Capture Region"].click()
        
        let overlay = app.windows["Capture Overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        
        // Capture a small region (top-left)
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let end = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
        start.press(forDuration: 0, thenDragTo: end)
        
        // Wait for toast to appear
        let toast = app.windows["Toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        
        sleep(1)
        saveScreenshot(named: "06-toast-actions")
    }

    /// 7. PII Redaction settings
    func testPIIRedaction() {
        app.menuBars["Textractor"].menuBarItems["Textractor"].click()
        app.menuItems["Settings..."].click()
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3))
        
        // Navigate to Privacy section
        let privacySection = settingsWindow.staticTexts["Privacy"]
        if privacySection.exists {
            privacySection.click()
        }
        
        // Enable PII Redaction
        let piiToggle = settingsWindow.switches["PII Redaction"]
        if piiToggle.exists {
            if piiToggle.value as? String == "0" {
                piiToggle.click()
            }
        }
        
        sleep(1)
        saveScreenshot(named: "07-pii-redaction")
    }
}