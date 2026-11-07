import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Textractor

final class ParityRegressionTests: XCTestCase {
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
        let window = CaptureOverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        XCTAssertTrue(window.canBecomeKey)
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

}
