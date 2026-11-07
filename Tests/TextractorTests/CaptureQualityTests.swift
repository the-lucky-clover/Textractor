import XCTest
import AppKit
import CoreImage
@testable import Textractor

@MainActor
final class CaptureQualityTests: XCTestCase {
    private func result(_ text: String, confidence: Float = 0.95) -> OCRResult {
        OCRResult(rawObservations: [TextObservation(text: text, confidence: confidence, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))],
                  recognizedAtSeconds: 0, languageCandidates: [], revisionsUsed: [])
    }
    func testShortTextAndNumbersRemainUseful() {
        for text in ["OK", "123456", "Hello", "你好世界", "مرحبا بالعالم"] {
            XCTAssertTrue(EnglishSuccessDetector.judge(result(text)).success, text)
        }
        XCTAssertFalse(EnglishSuccessDetector.judge(result("OK", confidence: 0.1)).success)
        XCTAssertFalse(EnglishSuccessDetector.judge(result("... ")).success)
        XCTAssertFalse(EnglishSuccessDetector.judge(result("你好世界"), preferredLanguage: "en-US").success)
    }
    func testQRPayloadIsExact() throws {
        let payload = "https://example.com/path?value=1&lang=en-US"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let image = try XCTUnwrap(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let raster = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        XCTAssertEqual(try BarcodeRecognition.recognize(raster), [payload])
    }
    func testCameraRejectsUnsupportedPasteboardWithoutOutput() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("not an image", forType: .string)
        XCTAssertThrowsError(try CameraImportDecoder.decode(board))
    }
    func testFormattingPreservesTableAndCodeNewlines() {
        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        XCTAssertEqual(PasteFormatter.format("ignored", tableMarkdown: table, layout: .reconstruct,
                                            deHyphenate: true, collapseBlankLines: true, trimTrailingWhitespace: true), table)
        XCTAssertEqual(PasteFormatter.deHyphenate("inter-\nnational"), "international")
        XCTAssertEqual(PasteFormatter.flattenToParagraphs("first\nsecond\n\nthird"), "first second\n\nthird")
    }
    func testMeasuredOCRFixtures() async throws {
        let fixtures = [
            ("prose", "The quick brown fox jumps over the lazy dog."),
            ("numbers", "Order 123456 total 42.95 reference 2026"),
            ("code", "let count = 42; print(count + 1)")
        ]
        var samples: [[String: Any]] = []
        for (id, text) in fixtures {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 240,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 240).fill()
            (text as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .regular), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            let image = try XCTUnwrap(bitmap.cgImage)
            for iteration in 0..<6 {
                let start = ProcessInfo.processInfo.systemUptime
                let output = await OCRService.shared.recognizeText(in: image, preferredLanguages: ["en-US"])
                let latency = (ProcessInfo.processInfo.systemUptime - start) * 1000
                XCTAssertFalse(output.joinedText.isEmpty, id)
                if iteration > 0 { // warm-up is excluded, never hidden within measured latency
                    samples.append(["case_id": id, "iteration": iteration, "expected": text,
                                    "actual": output.joinedText, "latency_ms": latency])
                }
            }
        }
        let environment = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                           "hardware": ProcessInfo.processInfo.hostName, "corpus": "rendered-v1-1200x240-30pt"]
        let data = try JSONSerialization.data(withJSONObject: ["environment": environment, "samples": samples], options: [.prettyPrinted, .sortedKeys])
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEXTRACTOR_QA_OUTPUT"] ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("ocr-measurements.json"), options: .atomic)
    }
}
