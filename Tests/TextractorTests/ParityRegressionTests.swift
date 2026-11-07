import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Textractor

final class ParityRegressionTests: XCTestCase {
    func testFunctionKeyLabelsUseActualNoncontiguousMacKeyCodes() {
        let keys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                    kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                    kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(HotkeyManager.labelFor(keyCode: UInt32(key), modifiers: UInt32(cmdKey)), "⌘F\(index + 1)")
        }
    }
    func testScrollAssemblyKeepsPageOrderAndRemovesOnlySpecifiedOverlap() throws {
        func raster(_ values: [UInt8], width: Int = 1) throws -> CGImage {
            let data = Data(values.flatMap { [ $0, $0, $0, UInt8(255) ] })
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            return try XCTUnwrap(CGImage(width: width, height: values.count / width,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        let top = try raster([20, 40, 60]), bottom = try raster([60, 80, 100])
        let result = try ScrollImageComposer.append(top: top, bottom: bottom, overlap: 1)
        XCTAssertEqual(result.height, 5)
        let bytes = try XCTUnwrap(result.dataProvider?.data) as Data
        XCTAssertEqual((0..<result.height).map { bytes[$0 * result.bytesPerRow] }, [20, 40, 60, 80, 100])
        XCTAssertThrowsError(try ScrollImageComposer.append(top: top, bottom: bottom, overlap: 3))
        XCTAssertThrowsError(try ScrollImageComposer.append(top: top, bottom: bottom, overlap: -1))
        XCTAssertThrowsError(try ScrollImageComposer.append(top: top, bottom: raster([1, 2, 3, 4], width: 2), overlap: 0))
        let huge = try raster(Array(repeating: 1, count: 32_000))
        XCTAssertThrowsError(try ScrollImageComposer.append(top: huge, bottom: bottom, overlap: 0))
    }
    func testPointerSelectionAndCropRoundTripsAcrossDisplayArrangements() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let others = [CGRect(x: -1920, y: -180, width: 1920, height: 1080),
                      CGRect(x: 1440, y: 200, width: 2560, height: 1440),
                      CGRect(x: -400, y: 900, width: 1920, height: 1080),
                      CGRect(x: 100, y: -1080, width: 1920, height: 1080)]
        for frame in others {
            let pointer = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertEqual(CaptureDisplayGeometry.displayIndex(at: pointer, frames: [main, frame]), 1)
            let local = CaptureDisplayGeometry.overlayPoint(fromGlobal: pointer, frame: frame)
            XCTAssertEqual(local, CGPoint(x: frame.width / 2, y: frame.height / 2))
            let region = CGRect(x: 80, y: 120, width: 200, height: 70)
            let global = CaptureDisplayGeometry.globalRect(fromOverlay: region, frame: frame)
            let quartz = CGRect(x: global.minX, y: main.height - global.maxY, width: global.width, height: global.height)
            XCTAssertEqual(CaptureDisplayGeometry.overlayRect(fromQuartz: quartz, frame: frame, primaryHeight: main.height), region)
            for scale in [CGFloat(1), CGFloat(2)] {
                let crop = CaptureDisplayGeometry.pixelCrop(globalRect: global, displayFrame: frame,
                    imageSize: CGSize(width: frame.width * scale, height: frame.height * scale))
                XCTAssertEqual(crop, CGRect(x: 80 * scale, y: 120 * scale, width: 200 * scale, height: 70 * scale))
            }
        }
        XCTAssertNil(CaptureDisplayGeometry.displayIndex(at: CGPoint(x: 99999, y: 0), frames: [main]))
    }
    func testInvalidCropDoesNotFallBackToWholeScreen() {
        let frame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertNil(CaptureDisplayGeometry.pixelCrop(globalRect: CGRect(x: 5000, y: 0, width: 20, height: 20), displayFrame: frame, imageSize: frame.size))
        XCTAssertNil(CaptureDisplayGeometry.pixelCrop(globalRect: .zero, displayFrame: frame, imageSize: frame.size))
        XCTAssertNil(CaptureDisplayGeometry.pixelCrop(globalRect: frame, displayFrame: .zero, imageSize: frame.size))
    }
    @MainActor func testBorderlessOverlayAcceptsSecondaryFrameAndKeyboard() {
        _ = NSApplication.shared
        let frame = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        let window = CaptureOverlayWindow(frame: frame)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(window.constrainFrameRect(frame, to: nil), frame)
        window.isReleasedWhenClosed = false; window.close()
    }
    func testCaptureIntentsDoNotMutateSavedPreferences() {
        var original = AppSettings.default; original.flattenText = true; original.recognizeBarcodes = true
        let result = CaptureIntent(flatten: false, speech: true, barcode: false).applying(to: original)
        XCTAssertFalse(result.flattenText); XCTAssertTrue(result.readAloud); XCTAssertFalse(result.recognizeBarcodes)
        XCTAssertTrue(original.flattenText); XCTAssertFalse(original.readAloud); XCTAssertTrue(original.recognizeBarcodes)
        XCTAssertEqual(CaptureIntent().applying(to: original).flattenText, original.flattenText)
    }
    func testShortcutConflictIncludesOverlayAndGlobalBindings() throws {
        var settings = AppSettings.default
        settings.actionShortcuts[CaptureAction.previous.rawValue] = settings.shortcut(for: .capture)
        XCTAssertNotNil(settings.shortcutConflict())
        settings.actionShortcuts = [:]
        settings.actionShortcuts[CaptureAction.barcode.rawValue] = CaptureAction.overlayLines.defaultBinding
        XCTAssertNotNil(settings.shortcutConflict())
        settings.disabledShortcuts = [CaptureAction.overlayLines.rawValue]
        XCTAssertNil(settings.shortcutConflict())
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.shortcut(for: .barcode), settings.shortcut(for: .barcode))
        XCTAssertNil(restored.shortcut(for: .overlayLines))
    }
    func testAllPublishedActionsHaveDistinctIdentity() {
        XCTAssertEqual(Set(CaptureAction.allCases.map(\.rawValue)).count, 12)
        XCTAssertEqual(CaptureAction.allCases.filter(\.overlayOnly).count, 3)
        XCTAssertNil(AppSettings.default.shortcutConflict())
    }
    func testPersistentAdditiveRoundTripPreservesRepeatedMessagesAndClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AdditiveClipboardPersistence(url: directory.appendingPathComponent("batch.json"))
        var batch = CaptureAccumulator(); batch.append("Yes"); batch.append("Yes"); batch.append("Line 1\nLine 2 👨‍👩‍👧‍👦")
        try store.save(batch)
        XCTAssertEqual(try store.load().entries, batch.entries)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try store.save(CaptureAccumulator()); XCTAssertTrue(try store.load().entries.isEmpty)
        try store.remove(); XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
    func testCorruptAdditiveFileIsRetained() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not JSON".utf8); try original.write(to: url)
        XCTAssertThrowsError(try AdditiveClipboardPersistence(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    @MainActor func testPasteClearsOnlyOwnedTextAndOnlyPasteCombination() {
        let key = UInt16(kVK_ANSI_V)
        XCTAssertTrue(CaptureExtras.isOwnedPaste(keyCode: key, modifiers: .command, clipboardChange: 5, ownedChange: 5, clipboardText: "abc", batchText: "abc"))
        XCTAssertFalse(CaptureExtras.isOwnedPaste(keyCode: key, modifiers: .command, clipboardChange: 6, ownedChange: 5, clipboardText: "abc", batchText: "abc"))
        XCTAssertFalse(CaptureExtras.isOwnedPaste(keyCode: key, modifiers: .command, clipboardChange: 5, ownedChange: 5, clipboardText: "other", batchText: "abc"))
        XCTAssertFalse(CaptureExtras.isOwnedPaste(keyCode: key, modifiers: [], clipboardChange: 5, ownedChange: 5, clipboardText: "abc", batchText: "abc"))
        XCTAssertFalse(CaptureExtras.isOwnedPaste(keyCode: 0, modifiers: .command, clipboardChange: 5, ownedChange: 5, clipboardText: "abc", batchText: "abc"))
    }
    func testCapturedLinksAreExplicitWebOnlyDeduplicatedAndBounded() {
        let text = "https://example.org/a https://example.org/a http://example.com/b https://example.net/c https://example.edu/d"
        XCTAssertEqual(CapturedLinkPolicy.links(in: text).count, 3)
        XCTAssertTrue(CapturedLinkPolicy.links(in: "javascript:alert(1) file:///etc/passwd mailto:me@example.com tel:123456").isEmpty)
        XCTAssertTrue(CapturedLinkPolicy.links(in: "https://user:secret@example.com").isEmpty)
        XCTAssertTrue(CapturedLinkPolicy.links(in: text, maximum: 0).isEmpty)
    }
    func testUpdateVersionComparisonIsNumericAndRejectsAmbiguousMetadata() throws {
        XCTAssertTrue(try XCTUnwrap(ReleaseVersion("v2.10.0")) > XCTUnwrap(ReleaseVersion("2.9.9")))
        XCTAssertEqual(ReleaseVersion("2.1"), ReleaseVersion("2.1.0"))
        XCTAssertNil(ReleaseVersion("2.1.0-beta")); XCTAssertNil(ReleaseVersion("2..1"))
        let body = Data(#"{"tag_name":"v2.10.0","draft":false,"prerelease":false}"#.utf8)
        XCTAssertEqual(try ReleaseCheck.parse(status: 200, data: body, installed: "2.9.9"), .available("v2.10.0"))
        XCTAssertEqual(try ReleaseCheck.parse(status: 404, data: Data(), installed: "2.9.9"), .noPublishedRelease)
        XCTAssertThrowsError(try ReleaseCheck.parse(status: 403, data: body, installed: "2.9.9"))
        XCTAssertThrowsError(try ReleaseCheck.parse(status: 200, data: Data(), installed: "2.9.9"))
    }
    func testVerticalCJKColumnsReadRightToLeft() {
        let result = OCRResult(rawObservations: [
            .init(text: "左", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.08, height: 0.7)),
            .init(text: "右", confidence: 1, boundingBox: CGRect(x: 0.7, y: 0.2, width: 0.08, height: 0.7))
        ], recognizedAtSeconds: 0, languageCandidates: ["ja-JP"], revisionsUsed: [])
        XCTAssertEqual(result.joinedText, "右\n左")
    }
    func testLanguagePickerReflectsRuntimeAndKeepsUSEnglishDefault() {
        XCTAssertEqual(Set(AppSettings.availableOCRLanguages.map(\.code)), Set(OCRService.automaticLanguages()))
        XCTAssertEqual(AppSettings.default.uiLanguage, "en-US")
        for value in ["uk-UA", "fi-FI", "mr-IN", "yue-Hant"] { XCTAssertEqual(AppSettings.normalizedLanguage(value), value) }
    }
    @MainActor func testClearUndoAndRestartPreserveHistoryWithoutClobberingForeignClipboard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AdditiveClipboardPersistence(url: directory.appendingPathComponent("batch.json"))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let extras = CaptureExtras(persistence: persistence, pasteboard: board, copyText: { text, _, _ in
            board.clearContents(); return board.setString(text, forType: .string)
        })
        var settings = AppSettings.default; settings.additiveClipboard = true; settings.persistAdditiveClipboard = true
        extras.configure(settings: settings)
        XCTAssertTrue(extras.deliver("first", settings: settings))
        XCTAssertTrue(extras.deliver("second", settings: settings))
        XCTAssertEqual(try persistence.load().text, "first\n\nsecond")
        extras.clearBatch()
        XCTAssertEqual(board.string(forType: .string), "first\n\nsecond")
        XCTAssertTrue(try persistence.load().entries.isEmpty)
        board.clearContents(); board.setString("unrelated clipboard", forType: .string)
        extras.undoBatch()
        XCTAssertEqual(extras.batch.entries, ["first", "second"])
        XCTAssertEqual(board.string(forType: .string), "unrelated clipboard")
        let restarted = CaptureExtras(persistence: persistence, pasteboard: board)
        restarted.configure(settings: settings)
        XCTAssertEqual(restarted.batch.entries, ["first", "second"])
        settings.persistAdditiveClipboard = false; restarted.configure(settings: settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistence.url.path))
        XCTAssertEqual(restarted.batch.entries.count, 2)
    }
    @MainActor func testFailedClipboardCopyDoesNotAppendOrPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let extras = CaptureExtras(persistence: .init(url: url), copyText: { _, _, _ in false })
        var settings = AppSettings.default; settings.additiveClipboard = true; settings.persistAdditiveClipboard = true
        extras.configure(settings: settings)
        XCTAssertFalse(extras.deliver("must not append", settings: settings))
        XCTAssertTrue(extras.batch.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(extras.lastDeliveredText)
    }

    @MainActor func testCarbonDispatchReachesBothRegisteredActions() async throws {
        _ = NSApplication.shared
        let first = HotkeyManager(id: 100), second = HotkeyManager(id: 101)
        defer { first.unregister(); second.unregister() }
        let firstFired = expectation(description: "First action routed")
        let secondFired = expectation(description: "Second action routed")
        first.onHotkey = { firstFired.fulfill() }; second.onHotkey = { secondFired.fulfill() }
        let modifiers = UInt32(cmdKey | controlKey | optionKey)
        XCTAssertTrue(first.register(keyCode: UInt32(kVK_ANSI_1), modifiers: modifiers, label: "test1").ok)
        XCTAssertTrue(second.register(keyCode: UInt32(kVK_ANSI_2), modifiers: modifiers, label: "test2").ok)
        for id in [UInt32(100), UInt32(101)] {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(0), &event), noErr)
            let value = try XCTUnwrap(event)
            var hotkey = EventHotKeyID(signature: 0x54524332, id: id)
            XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotkey), noErr)
            XCTAssertEqual(SendEventToEventTarget(value, GetApplicationEventTarget()), noErr)
            ReleaseEvent(value)
        }
        await fulfillment(of: [firstFired, secondFired], timeout: 3)
    }
    @MainActor func testCommandShortcutRecordingConsumesMenuEquivalentAndCancelRestores() {
        _ = NSApplication.shared
        let button = ShortcutRecorder.RecorderButton(title: "Original", target: nil, action: nil)
        var received: UInt32?
        button.onRecord = { code, _, _ in received = code; return nil }
        button.beginRecording()
        let commandW = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                       windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: UInt16(kVK_ANSI_W))!
        XCTAssertTrue(button.performKeyEquivalent(with: commandW))
        XCTAssertEqual(received, UInt32(kVK_ANSI_W))
        XCTAssertFalse(button.recording)
        button.title = "Saved"; button.beginRecording()
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: UInt16(kVK_Escape))!
        button.keyDown(with: escape)
        XCTAssertEqual(button.title, "Saved"); XCTAssertFalse(button.recording)
    }
    func testOverlaySessionSharesModeAcrossDisplayConsumers() {
        let session = CaptureOverlaySession(mode: .crosshair)
        let secondDisplay = session
        session.mode = .window
        XCTAssertEqual(secondDisplay.mode, .window)
        secondDisplay.status = "Line breaks: off"
        XCTAssertEqual(session.status, "Line breaks: off")
    }

}
