import XCTest
@testable import Textractor

final class ReleaseSafetyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TextractorRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func capture(_ name: String, bytes: Data, at date: Date) throws -> CapturedImage {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return CapturedImage(mode: .crosshair, origin: .file, rect: .zero, fileURL: url, capturedAt: date)
    }

    func testSameSecondRecoveryCapturesKeepBothOriginals() throws {
        let service = CacheService(recoveryFolder: directory.appendingPathComponent("Recovery"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let firstBytes = Data("first original image".utf8)
        let secondBytes = Data("second original image".utf8)
        let first = try capture("first.png", bytes: firstBytes, at: date)
        let second = try capture("second.png", bytes: secondBytes, at: date)
        let firstURL = try service.saveRecoveryImage(first)
        let secondURL = try service.saveRecoveryImage(second)
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.fileURL.path))
    }

    func testRepeatedFailedRetryDoesNotDeleteRecoveryOriginal() throws {
        let service = CacheService(recoveryFolder: directory.appendingPathComponent("Recovery"))
        let bytes = Data("original must survive every failed OCR retry".utf8)
        let original = try capture("source.png", bytes: bytes, at: Date())
        let recovered = try service.saveRecoveryImage(original)
        let retry = CapturedImage(id: original.id, mode: original.mode, origin: original.origin,
                                  rect: original.rect, fileURL: recovered, capturedAt: original.capturedAt)
        for _ in 0..<3 {
            XCTAssertEqual(try service.saveRecoveryImage(retry), recovered)
            XCTAssertEqual(try Data(contentsOf: recovered), bytes)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.recoveryFolder.path).count, 1)
    }

    func testMissingRecoveryInputDoesNotDamageExistingOriginal() throws {
        let service = CacheService(recoveryFolder: directory.appendingPathComponent("Recovery"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let bytes = Data("retained".utf8)
        let original = try capture("source.png", bytes: bytes, at: date)
        let recovered = try service.saveRecoveryImage(original)
        XCTAssertThrowsError(try service.saveRecoveryImage(original))
        XCTAssertEqual(try Data(contentsOf: recovered), bytes)
    }

    func testUnavailableLanguageModelDoesNotInventAnAnswer() async throws {
        let service = LocalLLMService.shared
        XCTAssertFalse(LocalLLMService.isAvailable)
        do {
            _ = try await service.generate(prompt: "Summarize this supplied text.")
            XCTFail("An unimplemented model must not return fabricated text")
        } catch LocalLLMError.unavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
        do {
            try await service.loadModel(.tinyLlama)
            XCTFail("An unimplemented model must not become loaded")
        } catch LocalLLMError.unavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(service.isModelLoaded)
    }

    func testCaptureModeCycleMatchesDistributionCapabilities() {
        XCTAssertEqual(CaptureMode.crosshair.nextAvailableMode, .window)
        XCTAssertEqual(CaptureMode.autoScroll.nextAvailableMode, .crosshair)
        XCTAssertEqual(CaptureMode.window.nextAvailableMode,
                       DistributionPolicy.supportsAutomaticScrolling ? .autoScroll : .crosshair)
    }

    @MainActor
    func testUnreadableHistorySurvivesCapturesUntilExplicitClear() throws {
        let historyDirectory = directory.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let metadata = historyDirectory.appendingPathComponent("history.json")
        let damaged = Data("{partial archive; do not overwrite}".utf8)
        try damaged.write(to: metadata)
        let store = HistoryStore(directory: historyDirectory)
        XCTAssertNotNil(store.storageError)
        let image = try capture("capture.png", bytes: Data("image".utf8), at: Date())
        store.record(capture: image, text: "New capture", mode: .crosshair, limit: 10)
        store.enforceLimit(1)
        XCTAssertEqual(try Data(contentsOf: metadata), damaged)
        XCTAssertTrue(store.records.isEmpty)

        store.clearAll()
        XCTAssertNil(store.storageError)
        store.record(capture: image, text: "New capture", mode: .crosshair, limit: 10)
        XCTAssertEqual(HistoryStore(directory: historyDirectory).records.first?.textPreview, "New capture")
    }

    func testDiagnosticsRequireCurrentOptInAndRetainUntilErased() {
        let file = directory.appendingPathComponent("diagnostics/events.jsonl")
        let service = TelemetryService(fileURL: file)
        let event = TelemetryEvent(kind: .sessionStart)
        XCTAssertFalse(service.isEnabled)
        service.record(event, telemetryEnabled: true)
        XCTAssertTrue(service.recent().isEmpty)
        service.isEnabled = true
        service.record(event, telemetryEnabled: true)
        XCTAssertEqual(service.recent().count, 1)
        service.isEnabled = false
        service.record(TelemetryEvent(kind: .sessionEnd), telemetryEnabled: true)
        XCTAssertEqual(service.recent().count, 1)
        XCTAssertTrue(service.recent(limit: -1).isEmpty)
        service.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFreshDiagnosticsDefaultDoesNotOverrideAnExistingChoice() throws {
        XCTAssertFalse(AppSettings.default.localTelemetryEnabled)
        var optedIn = AppSettings.default
        optedIn.localTelemetryEnabled = true
        let data = try JSONEncoder().encode(optedIn)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).localTelemetryEnabled)
    }

    func testAggregateAnalyticsUseTheSameDiagnosticsOptIn() {
        let optIn = TelemetryService(fileURL: directory.appendingPathComponent("events.jsonl"))
        let file = directory.appendingPathComponent("analytics.json")
        let analytics = AnalyticsService(fileURL: file, telemetry: optIn)
        let recordAll: () -> Void = {
            analytics.recordError(.ocrFailed)
            analytics.recordCapture(mode: .crosshair)
            analytics.recordOCRLanguage("en-US")
        }
        recordAll()
        XCTAssertTrue(analytics.getErrorCounts().isEmpty)
        XCTAssertTrue(analytics.getCaptureCounts().isEmpty)
        XCTAssertTrue(analytics.getOCRLanguageCounts().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        optIn.isEnabled = true
        recordAll()
        XCTAssertEqual(analytics.getErrorCounts()[.ocrFailed], 1)
        XCTAssertEqual(analytics.getCaptureCounts()[.crosshair], 1)
        XCTAssertEqual(analytics.getOCRLanguageCounts()["en-US"], 1)

        optIn.isEnabled = false
        recordAll()
        XCTAssertEqual(analytics.getErrorCounts()[.ocrFailed], 1)
        XCTAssertEqual(analytics.getCaptureCounts()[.crosshair], 1)
        XCTAssertEqual(analytics.getOCRLanguageCounts()["en-US"], 1)
        analytics.wipe()
        XCTAssertTrue(analytics.getErrorCounts().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
