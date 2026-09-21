import AppKit
import SwiftUI
import Combine
import ImageIO
import CoreGraphics
import SwiftData

/// Top-level coordinator that owns the application lifecycle:
///   • registers the global hotkey
///   • presents capture overlays (crosshair / window)
///   • runs the capture → OCR → AI → clipboard pipeline
///   • pops the menubar `MenuContentView` panels
@MainActor
public final class AppCoordinator: ObservableObject {

    public static let shared = AppCoordinator()

    // MARK: - State

    public let settingsStore = SettingsStore.shared
    public let captureStore = CaptureStore.shared
    public let appState: AppState

  /// Currently presented capture overlay (the fullscreen NSWindow).
  private var captureWindow: NSWindow?

  /// When `true`, the next window selected by the overlay runs through
  /// `ScreenshotService.captureWindowWithAutoScroll` instead of plain window
  /// capture. Toggled by `startAutoScrollCapture()` and consumed by
  /// `runCaptureWindow(_:)`.
  private var pendingAutoScrollCapture: Bool = false

    /// The menu-bar status item controller (replaces SwiftUI's `MenuBarExtra`).
    public var statusBarController: StatusBarController?

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        self.appState = AppState(settingsStore: settingsStore)
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        // Listen for dock presence changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DockPresenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let presence = notification.object as? AppSettings.DockPresence else { return }
            Task { @MainActor in
                self.handleDockPresenceChange(presence)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func handleDockPresenceChange(_ presence: AppSettings.DockPresence) {
        switch presence {
        case .menuBarOnly, .both:
            if statusBarController == nil {
                statusBarController = StatusBarController(coordinator: self)
            }
        case .dockOnly:
            statusBarController = nil
        }
    }

    // MARK: - Lifecycle

    public func bootstrap() {
        // Hotkey — use whatever has been configured in settings, falling back
        // to the default ⌘⇧2.
        HotkeyManager.shared.onHotkey = { [weak self] in
            SoundManager.playCaptureStartIfEnabled()
            // Check if Option key is held for per-capture language override
            let optionHeld = NSEvent.modifierFlags.contains(.option)
            self?.startCaptureRegion(perCaptureLanguageOverride: optionHeld)
        }
        let s = appState.settings
        let result = HotkeyManager.shared.register(
            keyCode: s.resolvedHotkeyKeyCode,
            modifiers: s.resolvedHotkeyModifiers,
            label: s.resolvedHotkeyLabel
        )
        if !result.ok {
            LoggerService.shared.warning("Hotkey registration reported issue: \(result.description)")
        }

        // Menu-bar status item — only if not dockOnly.
        // For .menuBarOnly and .both modes, we show the menu bar icon.
        if s.dockPresence != .dockOnly {
            statusBarController = StatusBarController(coordinator: self)
        }

        // Toast window (non-activating panel, top-right of main display).
        ToastWindowController.shared.configure(appState: appState)

        // Phase 1: Clipboard Image OCR monitor
        ClipboardImageOCRService.shared.configure(coordinator: self)

        // Phase 1: Shortcuts Actions
        ShortcutsActionService.shared.configure(coordinator: self)

        // Phase 1: Structured Export
        StructuredExportService.shared.configure(coordinator: self)

        // Telemetry
        TelemetryService.shared.record(
            TelemetryEvent(kind: .sessionStart),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )


        LoggerService.shared.info("Textractor bootstrap complete")
    }

    // MARK: - Capture flows

    public func startCaptureRegion(perCaptureLanguageOverride: Bool = false) {
        guard !appState.isCapturing else { return }
        if perCaptureLanguageOverride {
            // Show language picker for per-capture override
            showPerCaptureLanguagePicker { [weak self] selectedLanguage in
                self?.presentCaptureOverlay(initialMode: .crosshair, perCaptureLanguage: selectedLanguage)
            }
        } else {
            presentCaptureOverlay(initialMode: .crosshair, perCaptureLanguage: nil)
        }
        TelemetryService.shared.record(
            TelemetryEvent(kind: .hotkeyPressed),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )
    }

public func startCaptureWindow(perCaptureLanguageOverride: Bool = false) {
        guard !appState.isCapturing else { return }
        if perCaptureLanguageOverride {
            showPerCaptureLanguagePicker { [weak self] selectedLanguage in
                self?.presentCaptureOverlay(initialMode: .window, perCaptureLanguage: selectedLanguage)
            }
        } else {
            presentCaptureOverlay(initialMode: .window, perCaptureLanguage: nil)
        }
    }

  public func startAutoScrollCapture() {
    guard !appState.isCapturing else { return }
    pendingAutoScrollCapture = true
    presentCaptureOverlay(initialMode: .autoScroll, perCaptureLanguage: nil)
  }

    public func startCaptureFullScreen() {
        guard !appState.isCapturing else { return }
        Task {
            appState.pipelinePhase = .capturing
            await runFullScreenPipeline()
        }
    }

    public func startCapture(_ file: URL) {
        guard !appState.isCapturing else { return }
        Task { await ingestFile(at: file) }
    }

    // MARK: - Pipeline (file ingestion, fullscreen, region/window via overlay)

    public func ingestFile(at url: URL) async {
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureFromFile(at: url)
            await runPipeline(for: capture, perCaptureLanguage: nil)
        } catch {
            handleFailure(error: error, context: "ingestFile")
        }
        appState.isCapturing = false
    }

    /// Re-run OCR on a previously-captured image file (e.g. from history).
    /// Loads the image, runs the full pipeline, and replaces the captured text
    /// in the clipboard. The new result is appended to history.
    public func reOCR(imagePath: String) async {
        guard FileManager.default.fileExists(atPath: imagePath) else {
            handleFailure(
                error: ScreenshotError.fileLoadFailed(URL(fileURLWithPath: imagePath)),
                context: "reOCR"
            )
            return
        }
        await ingestFile(at: URL(fileURLWithPath: imagePath))
    }

    private func runFullScreenPipeline() async {
        appState.isCapturing = true
        do {
            let captures = try await ScreenshotService.shared.captureFullScreen()
            for capture in captures {
                await runPipeline(for: capture, perCaptureLanguage: nil)
            }
            appState.pipelinePhase = .completed
        } catch {
            handleFailure(error: error, context: "fullScreen")
        }
        appState.isCapturing = false
    }

    /// Captures a region via a CG rect (returned by overlay).
    public func runCaptureRegion(_ rect: CGRect, perCaptureLanguage: String? = nil) async {
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureRegion(rect)
            await runPipeline(for: capture, perCaptureLanguage: perCaptureLanguage)
        } catch {
            handleFailure(error: error, context: "region")
        }
        appState.isCapturing = false
    }

  public func runCaptureWindow(_ windowID: CGWindowID, perCaptureLanguage: String? = nil) async {
    appState.isCapturing = true
    appState.pipelinePhase = .capturing
    let useAutoScroll = pendingAutoScrollCapture
    pendingAutoScrollCapture = false
    do {
      let capture: CapturedImage
      if useAutoScroll {
        capture = try await ScreenshotService.shared.captureWindowWithAutoScroll(
          windowID,
          scrollInterval: 0.5,
          maxScrolls: 50,
          overlap: 120
        )
      } else {
        let windowCapture = try await ScreenshotService.shared.captureWindow(windowID)
        capture = windowCapture.0
      }
      await runPipeline(for: capture, perCaptureLanguage: perCaptureLanguage)
    } catch {
      handleFailure(error: error, context: "window")
    }
    appState.isCapturing = false
  }

    /// Continuity Camera (iPhone / iPad) capture -> OCR pipeline. macOS presents
    /// a native system sheet so the user can Take Photo / Scan Documents; the
    /// returned image is ingested and run through the same OCR path.
    @MainActor
    public func runContinuityCameraCapture() async {
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            if #available(macOS 13.0, *) {
                let capture = try await ScreenshotService.shared.captureFromContinuityCamera()
                await runPipeline(for: capture, perCaptureLanguage: nil)
            } else {
                throw ScreenshotError.continuityCameraNotAvailable
            }
        } catch {
            handleFailure(error: error, context: "continuityCamera")
        }
        appState.isCapturing = false
    }

    // MARK: - Core pipeline helpers

    /// Load the CGImage from the capture file, or fail fast.
    @MainActor
    private func pipelineLoadImage(from capture: CapturedImage) throws -> CGImage {
        try loadCGImage(from: capture.fileURL)
    }

    /// Run OCR on the image and return the result.
    @MainActor
    private func pipelineOCR(
        cgImage: CGImage,
        weirdness: Double,
        vocab: [String],
        uiLanguage: String
    ) async -> OCRResult {
        let langs = uiLanguage.isEmpty ? OCRService.automaticLanguages() : [uiLanguage]
return await OCRService.shared.recognizeText(
            in: cgImage,
            weirdness: weirdness,
            customVocabulary: vocab,
            autoWeirdness: true
        )
    }

    /// Extract metadata and scan PII.
    @MainActor
    private func pipelineMetadataAndPII(
        ocrText: String,
        piiEnabled: Bool
    ) -> (metadata: ExtractedMetadata, piiReport: SensitiveDataDetector.Report, piiRedacted: Bool, piiCount: Int, scrubbedText: String) {
        let metadata = MetadataExtractor.shared.extract(from: ocrText)
        let report = SensitiveDataDetector.scan(ocrText)
        let redacted = piiEnabled && !report.isClean
        let count = report.byKind.count
        let scrubbed = SensitiveDataDetector.scrub(ocrText, report: report)
        return (metadata, report, redacted, count, scrubbed)
    }

    /// Analyze, format, and persist the successful capture. Returns the
    /// output text and the analysis for the toast.
    @MainActor
    private func pipelineSuccessPath(
        capture: CapturedImage,
        cgImage: CGImage,
        ocrResult: OCRResult,
        metadata: ExtractedMetadata,
        piiRedacted: Bool,
        piiCount: Int,
        scrubbedText: String,
        weirdness: Double,
        vocab: [String],
        pasteAsPlainText: Bool,
        wordWrapCaptured: Bool,
        flattenText: Bool
    ) async -> (outputText: String, analysis: AIInferenceService.Analysis?) {
        let rawText = ocrResult.joinedText
        let finalText = piiRedacted ? (scrubbedText.isEmpty ? "[REDACTED:ALL]" : scrubbedText) : rawText

        let analysis = await AIInferenceService.shared.analyze(finalText, weirdness: weirdness)

        let isWindow = capture.mode == .window
        let tableMarkdown = (isWindow && appState.settings.windowCaptureAsTable)
            ? TableFormatter.toMarkdownTable(observations: ocrResult.rawObservations)
            : nil

        var outputText: String = wordWrapCaptured
            ? Self.flattenWordWrap(tableMarkdown ?? analysis.cleanedText, columns: 80)
            : tableMarkdown ?? analysis.cleanedText
        if flattenText {
            outputText = outputText
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            outputText = outputText.split(separator: " ").filter { !$0.isEmpty }.joined(separator: " ")
        }

        // Build attributed string for rich paste
        let attributed: NSAttributedString? = {
            if pasteAsPlainText { return nil }
            if let tableMarkdown {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 2.5
                return NSAttributedString(
                    string: tableMarkdown,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                        .paragraphStyle: p,
                        .foregroundColor: NSColor.labelColor
                    ]
                )
            }
            return TextFormatter.attributed(from: outputText, analysis: analysis, weirdness: weirdness)
        }()

        // Clipboard write
        appState.pipelinePhase = .clipboard
        _ = ClipboardService.shared.copy(outputText, attributed: attributed, plainTextOnly: pasteAsPlainText)
        SoundManager.playCaptureComplete()

        // Save to CaptureStore (new visual knowledge library)
        if appState.settings.knowledgeModeEnabled {
            let aiEntities: [String] = analysis.entities.compactMap { entity in
                switch entity {
                case .url(let s): return s
                case .email(let s): return s
                case .phone(let s): return s
                case .hashtag(let s): return s
                case .mention(let s): return s
                }
            }
            let metaEntities: [String] = metadata.values(for: .url)
                + metadata.values(for: .email) + metadata.values(for: .phone)
                + metadata.values(for: .cryptoAddress) + metadata.values(for: .trackingNumber)
                + metadata.values(for: .apiKey) + metadata.values(for: .creditCard)
                + metadata.values(for: .ipAddress) + metadata.values(for: .macAddress)
                + metadata.values(for: .uuid) + metadata.values(for: .filePath)
                + metadata.values(for: .sshKey) + metadata.values(for: .dockerId)
            let allEntities = Array(Set(aiEntities + metaEntities))

            let record = CaptureRecord(
                mode: capture.mode.rawValue,
                origin: capture.origin.rawValue,
                rect: capture.rect,
                filePath: capture.fileURL.path,
                ocrText: ocrResult.joinedText,
                language: appState.settings.uiLanguage.isEmpty ? "auto" : appState.settings.uiLanguage,
                confidence: Double(ocrResult.averageConfidence),
                tags: analysis.keywords,
                notes: "",
                summary: analysis.keywords.prefix(5).joined(separator: ", "),
                entities: allEntities,
                fileSize: (try? FileManager.default.attributesOfItem(atPath: capture.fileURL.path)[.size] as? Int64) ?? 0,
                imageWidth: cgImage.width,
                imageHeight: cgImage.height,
                isFavorite: false,
                applicationName: capture.mode == .window ? "Window" : nil,
                windowTitle: nil
            )
            try? CaptureStore.shared.save(record)
        }

// History record (text-only) — in-memory recents + persistent store.
            appState.record(capture: capture, ocr: ocrResult, analysis: analysis)
            HistoryStore.shared.record(
                capture: capture,
                text: outputText,
                mode: capture.mode,
                limit: appState.settings.historyEntryLimit
            )

            // Auto-save captures to ~/Pictures/Textractor Captures/
            if appState.settings.autoSaveCaptures {
                Task.detached(priority: .utility) { [capture, outputText, ocrResult] in
                    let saveDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("Textractor Captures", isDirectory: true)
                    try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                    
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    let timestamp = formatter.string(from: capture.capturedAt)
                    let baseName = "Textractor_\(timestamp)"
                    
                    // Save image
                    let imageURL = saveDir.appendingPathComponent("\(baseName).png")
                    try? FileManager.default.copyItem(at: capture.fileURL, to: imageURL)
                    
                    // Save text
                    let textURL = saveDir.appendingPathComponent("\(baseName).txt")
                    try? outputText.write(to: textURL, atomically: true, encoding: .utf8)
                    
                    // Save metadata JSON
                    let metadata = [
                        "id": capture.id.uuidString,
                        "timestamp": ISO8601DateFormatter().string(from: capture.capturedAt),
                        "mode": capture.mode.rawValue,
                        "origin": capture.origin.rawValue,
                        "confidence": ocrResult.averageConfidence,
                        "textLength": outputText.count
                    ]
                    let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                    let jsonURL = saveDir.appendingPathComponent("\(baseName).json")
                    try? jsonData?.write(to: jsonURL, options: .atomic)
                }
            }

        return (outputText, analysis)
    }

    /// Present the success toast and record clipboard telemetry.
    @MainActor
    private func pipelinePresentToast(
        capture: CapturedImage,
        ocrResult: OCRResult,
        analysis: AIInferenceService.Analysis,
        outputText: String,
        tableMarkdown: String?,
        pasteAsPlainText: Bool,
        piiRedacted: Bool,
        piiCount: Int,
        telemetryEnabled: Bool
    ) {
        appState.pipelinePhase = .completed
        let toastText = analysis.cleanedText
        let toastCopy: () -> Void = {
            _ = ClipboardService.shared.copy(toastText, plainTextOnly: pasteAsPlainText)
            SoundManager.playClick()
        }
        let toastShare: (ShareService.Provider) -> Void = { provider in
            AppCoordinator.shared.share(text: toastText, via: provider)
        }
        // Quick action: translate on demand (when not auto-translating)
        let onTranslate: (() -> Void)? = {
            guard !self.appState.settings.translationTargetLanguage.isEmpty else { return }
            let targetLang = self.appState.settings.translationTargetLanguage
            let plainText = self.appState.settings.pasteAsPlainText
            Task { [targetLang, plainText, toastText] in
                guard let translated = await TranslationService.shared.translate(
                    toastText,
                    to: targetLang
                ) else { return }
                _ = ClipboardService.shared.copy(translated, plainTextOnly: plainText)
                SoundManager.playClick()
            }
        }
        // Quick action: format as code block
        let onFormatCode: (() -> Void)? = {
            guard !toastText.isEmpty else { return }
            let result = SourceCodeDetector.analyze(toastText)
            let formatted = result.formatted
            _ = ClipboardService.shared.copy(formatted, plainTextOnly: pasteAsPlainText)
            SoundManager.playClick()
        }
        // Smart action: open first detected URL
        let onOpenURL: (() -> Void)? = {
            let urls = MetadataExtractor.shared.extract(from: toastText).values(for: .url)
            guard let firstURL = urls.first, let url = URL(string: firstURL) else { return }
            NSWorkspace.shared.open(url)
        }
        // Smart action: compose email to first detected email
        let onComposeEmail: (() -> Void)? = {
            let emails = MetadataExtractor.shared.extract(from: toastText).values(for: .email)
            guard let firstEmail = emails.first else { return }
            let mailtoURL = URL(string: "mailto:\(firstEmail)")!
            NSWorkspace.shared.open(mailtoURL)
        }
        // Smart action: format as code block (with language detection)
let onFormatCodeBlock: (() -> Void)? = {
            guard !toastText.isEmpty else { return }
            let result = SourceCodeDetector.analyze(toastText)
            let formatted = result.formatted
            _ = ClipboardService.shared.copy(formatted, plainTextOnly: pasteAsPlainText)
            SoundManager.playClick()
        }
        // Smart action: undo last capture
        let onUndo: (() -> Void)? = {
            // Remove last history entry
            HistoryStore.shared.undoLastCapture()
            // Show confirmation toast
            SoundManager.playClick()
            self.appState.toast = ToastState(
                id: UUID(),
                kind: .success,
                headline: T.s("toast.undone"),
                body: T.s("toast.undone.body"),
                copy: nil,
                share: nil
            )
            // Schedule dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.appState.toast?.id == self.appState.toast?.id {
                    self.appState.toast = nil
                }
            }
        }
        let copyOk = ClipboardService.shared.copy(outputText, attributed: nil, plainTextOnly: pasteAsPlainText)
        appState.toast = ToastState(
            id: UUID(),
            kind: .success,
            headline: T.s("toast.copied"),
            body: copyOk ? T.s("toast.ready") : T.s("toast.copy_failed"),
            capture: capture,
            ocr: ocrResult,
            analysis: analysis,
            piiWasRedacted: piiRedacted,
            piiRedactionsApplied: piiCount,
            copy: toastCopy,
            share: toastShare,
            onTranslate: onTranslate,
            onFormatCode: onFormatCode,
            onOpenURL: onOpenURL,
            onComposeEmail: onComposeEmail,
            onFormatCodeBlock: onFormatCodeBlock,
            onUndo: onUndo
        )
        TelemetryService.shared.record(
            TelemetryEvent(
                kind: .clipboardWrite,
                success: copyOk,
                meta: [
                    "bytes": "\(outputText.count)",
                    "table": (tableMarkdown != nil ? "1" : "0"),
                    "pii": piiRedacted ? "1" : "0"
                ]
            ),
            telemetryEnabled: telemetryEnabled
        )
        scheduleToastDismiss()
    }

    // MARK: - Core pipeline

    @MainActor
    public func runPipeline(for capture: CapturedImage, perCaptureLanguage: String? = nil) async {

        let weirdness = appState.settings.weirdness
        let vocab = appState.settings.customVocabulary
        let telemetryEnabled = appState.settings.localTelemetryEnabled
        let pasteAsPlainText = appState.settings.pasteAsPlainText
        let wordWrapCaptured = appState.settings.wordWrapCaptured
        let flattenText = appState.settings.flattenText

        // MARK: - OCR ---------------------------------------------------------
        appState.pipelinePhase = .ocr
        let cgImage: CGImage
        do {
            cgImage = try loadCGImage(from: capture.fileURL)
        } catch {
            handleFailure(error: error, context: "loadImage")
            return
        }

        // Honor the user's chosen language. Empty = Automatic (english-first
        // multi-language superset); non-empty = that exact language for both
        // UI and OCR.
        // Per-capture language override (⌥ + capture) takes precedence over settings.
        let ocrLanguages: [String] = if let override = perCaptureLanguage, !override.isEmpty {
            [override]
        } else if appState.settings.uiLanguage.isEmpty {
            OCRService.automaticLanguages()
        } else {
            [appState.settings.uiLanguage]
        }
        let ocrResult = await OCRService.shared.recognizeText(
            in: cgImage,
            weirdness: weirdness,
            customVocabulary: vocab,
            preferredLanguages: ocrLanguages,
            autoWeirdness: true
        )

        // MARK: - Metadata Extraction ---------------------------------------
        let metadata = MetadataExtractor.shared.extract(from: ocrResult.joinedText)

        // MARK: - PII Scrubbing ---------------------------------------------
        let detectorReport = SensitiveDataDetector.scan(ocrResult.joinedText)
        let piiWasRedacted = appState.settings.piiRedactionEnabled && !detectorReport.isClean
        let piiRedactionsApplied = detectorReport.byKind.count
        let scrubbedText = SensitiveDataDetector.scrub(ocrResult.joinedText, report: detectorReport)

        // MARK: - Success check (language-aware) ---------------------------------
        let englishVerdict = EnglishSuccessDetector.judge(
            ocrResult,
            preferredLanguage: appState.settings.uiLanguage
        )

        // MARK: - English success path --------------------------------------
        if englishVerdict.success {
            let rawText = ocrResult.joinedText
            let finalText = appState.settings.piiRedactionEnabled
                ? (scrubbedText.isEmpty ? "[REDACTED:ALL]" : scrubbedText)
                : rawText

            // AI analysis
            appState.pipelinePhase = .ai
            let analysis = await AIInferenceService.shared.analyze(
                finalText,
                weirdness: weirdness
            )

            // Table formatting for window captures
            let isWindow = capture.mode == .window
            let tableMarkdown = (isWindow && appState.settings.windowCaptureAsTable)
                ? TableFormatter.toMarkdownTable(observations: ocrResult.rawObservations)
                : nil

            // Apply word-wrap and flatten transforms
            var outputText: String = wordWrapCaptured
                ? Self.flattenWordWrap(tableMarkdown ?? analysis.cleanedText, columns: 80)
                : tableMarkdown ?? analysis.cleanedText
            if flattenText {
                outputText = outputText
                    .replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                outputText = outputText.split(separator: " ").filter { !$0.isEmpty }.joined(separator: " ")
            }

            // Build attributed string for rich paste
            let attributed: NSAttributedString? = {
                if pasteAsPlainText { return nil }
                if let tableMarkdown {
                    let p = NSMutableParagraphStyle()
                    p.lineSpacing = 2.5
                    return NSAttributedString(
                        string: tableMarkdown,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                            .paragraphStyle: p,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                }
                return TextFormatter.attributed(
                    from: outputText,
                    analysis: analysis,
                    weirdness: weirdness
                )
            }()

            // Clipboard write
            appState.pipelinePhase = .clipboard
            let copyOk = ClipboardService.shared.copy(
                outputText,
                attributed: attributed,
                plainTextOnly: pasteAsPlainText
            )
            SoundManager.playCaptureComplete()

            // Post-capture translation (Snip-to-translate)
            var deliverableText = outputText
            if appState.settings.translateAfterCapture,
               !appState.settings.translationTargetLanguage.isEmpty,
               let translated = await TranslationService.shared.translate(
                outputText,
                to: appState.settings.translationTargetLanguage
               ) {
                deliverableText = translated
            }

            // Save to CaptureStore (new visual knowledge library)
            if appState.settings.knowledgeModeEnabled {
                let entities: [String] = analysis.entities.compactMap { entity in
                    switch entity {
                    case .url(let s): return s
                    case .email(let s): return s
                    case .phone(let s): return s
                    case .hashtag(let s): return s
                    case .mention(let s): return s
                    }
                }
                // Combine AI entities with extracted metadata
                let metadataEntities = metadata.values(for: .url) + metadata.values(for: .email) + metadata.values(for: .phone) + 
                    metadata.values(for: .cryptoAddress) + metadata.values(for: .trackingNumber) + metadata.values(for: .apiKey) +
                    metadata.values(for: .creditCard) + metadata.values(for: .ipAddress) + metadata.values(for: .macAddress) +
                    metadata.values(for: .uuid) + metadata.values(for: .filePath) + metadata.values(for: .sshKey) + metadata.values(for: .dockerId)
                let allEntities = Array(Set(entities + metadataEntities))
                
                let record = CaptureRecord(
                    mode: capture.mode.rawValue,
                    origin: capture.origin.rawValue,
                    rect: capture.rect,
                    filePath: capture.fileURL.path,
                    ocrText: ocrResult.joinedText,
                    language: appState.settings.uiLanguage.isEmpty ? "auto" : appState.settings.uiLanguage,
                    confidence: Double(ocrResult.averageConfidence),
                    tags: analysis.keywords,
                    notes: "",
                    summary: analysis.keywords.prefix(5).joined(separator: ", "),
                    entities: allEntities,
                    fileSize: (try? FileManager.default.attributesOfItem(atPath: capture.fileURL.path)[.size] as? Int64) ?? 0,
                    imageWidth: cgImage.width,
                    imageHeight: cgImage.height,
                    isFavorite: false,
                    applicationName: capture.mode == .window ? "Window" : nil,
                    windowTitle: nil
                )
                try? CaptureStore.shared.save(record)
            }

            // History record (text-only) — in-memory recents + persistent store.
            appState.record(capture: capture, ocr: ocrResult, analysis: analysis)
            HistoryStore.shared.record(
                capture: capture,
                text: outputText,
                mode: capture.mode,
                limit: appState.settings.historyEntryLimit
            )

            // Success toast
            appState.pipelinePhase = .completed
            // Capture text at creation time so the closures never read stale state.
let toastText = analysis.cleanedText
        let toastPlainText = pasteAsPlainText
        let toastCopy: () -> Void = {
            _ = ClipboardService.shared.copy(
                toastText,
                plainTextOnly: toastPlainText
            )
            SoundManager.playClick()
        }
        let toastShare: (ShareService.Provider) -> Void = { provider in
            AppCoordinator.shared.share(text: toastText, via: provider)
        }
            appState.toast = ToastState(
                id: UUID(),
                kind: .success,
                headline: T.s("toast.copied"),
                body: copyOk ? T.s("toast.ready") : T.s("toast.copy_failed"),
                capture: capture,
                ocr: ocrResult,
                analysis: analysis,
                piiWasRedacted: piiWasRedacted,
                piiRedactionsApplied: piiRedactionsApplied,
                copy: toastCopy,
                share: toastShare
            )

            // Telemetry
            TelemetryService.shared.record(
                TelemetryEvent(
                    kind: .clipboardWrite,
                    success: copyOk,
                    meta: [
                        "bytes": "\(outputText.count)",
                        "table": (tableMarkdown != nil ? "1" : "0"),
                        "pii": piiWasRedacted ? "1" : "0"
                    ]
                ),
                telemetryEnabled: telemetryEnabled
            )

            scheduleToastDismiss()
            return
        }

        // MARK: - English failure path – recovery toast ----------------------
        do {
            let recoveredURL = try CacheService.shared.saveRecoveryImage(capture)
            let recoveredPath = recoveredURL.path

            appState.pipelinePhase = .failed("OCR extraction failed")
            appState.toast = ToastState(
                id: UUID(),
                kind: .failure,
                headline: T.s("toast.ocr_failed"),
                body: T.s("toast.retry_hint"),
                capture: capture,
                ocr: ocrResult,
                analysis: nil,
                recoveryImagePath: recoveredPath,
                failureReason: englishVerdict.reason ?? "No English text detected",
                piiWasRedacted: piiWasRedacted,
                piiRedactionsApplied: piiRedactionsApplied,
                tryAgain: { [weak self] in
                    guard let self else { return }
                    let retryCapture = CapturedImage(
                        id: capture.id,
                        mode: capture.mode,
                        origin: capture.origin,
                        rect: capture.rect,
                        fileURL: recoveredURL,
                        capturedAt: capture.capturedAt,
                        screenIndex: capture.screenIndex
                    )
                    Task { await self.runPipeline(for: retryCapture, perCaptureLanguage: nil) }
                },
                cancel: { [weak self] in
                    guard let self else { return }
                    _ = CacheService.shared.trash(at: recoveredPath)
                    SoundManager.playCancel()
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.appState.toast = nil
                    }
                },
                revealRecovery: {
                    CacheService.shared.revealInFinder(recoveredPath)
                }
            )

            scheduleToastDismiss()

            TelemetryService.shared.record(
                TelemetryEvent(
                    kind: .ocrFailure,
                    success: false,
                    meta: ["reason": englishVerdict.reason ?? "unknown"]
                ),
                telemetryEnabled: telemetryEnabled
            )
        } catch {
            LoggerService.shared.error("Failed to store recovery screenshot", error: error)
            appState.toast = ToastState(
                id: UUID(),
                kind: .failure,
                headline: T.s("toast.capture_failed"),
                body: T.s("toast.cache_failed")
            )
        }
    }

    // MARK: - Sharing

    public func share(text: String, via provider: ShareService.Provider) {
        ShareService.shared.share(text: text, caption: "Text from Textractor", via: provider)
    }

    // MARK: - UI

    public func openSettings() {
        let anchor = statusBarController?.statusItemScreenRect
        SettingsWindowController.shared.show(appState: appState, anchor: anchor)
    }

    public func showCredits() {
        LoggerService.shared.info("Showing credits modal")
    }

    public func showHistoryWindow() {
        HistoryWindowController.shared.show()
    }

    /// Shows a quick language picker for per-capture OCR language override (⌥ + capture).
    private func showPerCaptureLanguagePicker(completion: @escaping (String?) -> Void) {
        let picker = NSPopUpButton()
        picker.addItems(withTitles: ["Auto"] + AppSettings.ocrLanguageCatalog.map { "\($0.flag) \($0.name)" })
        picker.selectItem(at: 0)
        
        let alert = NSAlert()
        alert.messageText = "Per-Capture Language Override"
        alert.informativeText = "Select OCR language for this capture only (hold ⌥ while capturing)"
        alert.accessoryView = picker
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let index = picker.indexOfSelectedItem
            if index == 0 {
                completion(nil) // Auto
            } else {
                let code = AppSettings.ocrLanguageCatalog[index - 1].code
                completion(code)
            }
        } else {
            completion(nil)
        }
    }

    public func quitApp() {
        TelemetryService.shared.record(
            TelemetryEvent(kind: .sessionEnd),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )
        NSApp.terminate(nil)
    }

    // MARK: - Capture overlay window

    private func presentCaptureOverlay(initialMode: CaptureMode, perCaptureLanguage: String?) {
        // Determine which display the cursor is currently on.
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }

        let view = CaptureOverlayView(
            frame: screen.frame,
            initialMode: initialMode,
            initialCursorPoint: mouseLocation,
            onRegionCaptured: { [weak self] rect in
                self?.dismissCaptureOverlay()
                Task { await self?.runCaptureRegion(rect, perCaptureLanguage: perCaptureLanguage) }
            },
            onWindowCaptured: { [weak self] windowID in
                self?.dismissCaptureOverlay()
                Task { await self?.runCaptureWindow(windowID, perCaptureLanguage: perCaptureLanguage) }
            },
            onCancel: { [weak self] in
                self?.dismissCaptureOverlay()
            },
            onContinuityCapture: { [weak self] in
                self?.dismissCaptureOverlay()
                Task { await self?.runContinuityCameraCapture() }
            },
            onDisplayChanged: { [weak self] newScreen in
                self?.moveCaptureWindow(to: newScreen)
            },
            captureFrameProvider: { [weak self] in
                self?.captureWindow?.frame ?? screen.frame
            },
            reduceMotion: appState.settings.reduceMotion,
            showLivePreview: true,
            onLiveOCRRequest: { [weak self] screenRect, completion in
                self?.handleLiveOCRRequest(screenRect: screenRect, completion: completion)
            }
        )

        let hosting = NSHostingView(rootView: view)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.contentView = hosting

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)

        LoggerService.shared.info("[capture.window] post-show isKeyWindow=\(window.isKeyWindow) isMainWindow=\(window.isMainWindow) firstResponder==hosting=\(window.firstResponder === hosting) screen=\(screen.frame)")

        captureWindow = window
    }

    private func dismissCaptureOverlay() {
        captureWindow?.orderOut(nil)
        captureWindow = nil
    }

    /// Moves the capture overlay window to a different display.
    private func moveCaptureWindow(to screen: NSScreen) {
        guard let window = captureWindow else { return }
        window.setFrame(screen.frame, display: true, animate: true)
        LoggerService.shared.info("[capture.window] moved to screen=\(screen.frame)")
    }

    /// Handles live OCR requests from the capture overlay.
    /// Runs OCR on the given screen rect with fast settings and returns the text.
    /// This is called ~4×/sec during region drag to update the preview text.
    @MainActor
    private func handleLiveOCRRequest(screenRect: CGRect, completion: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                let cgImage = try await ScreenshotService.shared.captureCGImageForRect(screenRect)
                let langs = OCRService.automaticLanguages()
                let result = try await OCRService.shared.recognizeText(
                    in: cgImage,
                    weirdness: appState.settings.weirdness,
                    customVocabulary: appState.settings.customVocabulary,
                    preferredLanguages: langs,
                    autoWeirdness: true
                )
                completion(result.isEmpty ? nil : result.joinedText)
            } catch {
                // Silently ignore — live OCR failures don't warrant on-screen noise
                completion(nil)
            }
        }
    }

    // MARK: - Toast auto-dismiss

    /// Auto-dismisses the current toast after a delay so it never lingers.
    /// Success/failure toasts both dismiss; failures get a slightly longer
    /// window so the user can still hit Retry / Reveal. The id check ensures a
    /// newer toast (e.g. a second capture) is never dismissed early.
    private func scheduleToastDismiss() {
        let messenger = appState
        let currentToastId = messenger.toast?.id
        let isFailure = messenger.toast?.kind == .failure
        let delayNs: UInt64 = isFailure ? 9_000_000_000 : 6_500_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            if let toast = messenger.toast,
               toast.id == currentToastId {
                withAnimation(.easeOut(duration: 0.4)) {
                    messenger.toast = nil
                }
            }
        }
    }

// MARK: - Failure helper
    
    private func handleFailure(error: Error, context: String, failureReason: String? = nil) {
        LoggerService.shared.error("\(context) failure", error: error)
        appState.isCapturing = false

        // Screen Recording permission denial: show a calm, privacy-first
        // reassurance instead of a scary generic error. No data left the device.
        if let screenshotError = error as? ScreenshotError,
           case .permissionDenied = screenshotError {
            appState.toast = ToastState(
                id: UUID(),
                kind: .info,
                headline: T.s("toast.screen_permission_title"),
                body: T.s("toast.screen_permission_body"),
                capture: nil,
                ocr: nil,
                analysis: nil,
                piiWasRedacted: false,
                piiRedactionsApplied: 0,
                screenRecordingDenied: true,
                openSettings: { PermissionService.shared.openScreenRecordingSettings() }
            )
            appState.pipelinePhase = .failed(T.s("toast.screen_permission_title"))
            scheduleToastDismiss()
            return
        }

        let headline = failureReason ?? T.s("toast.capture_failed")
        appState.toast = ToastState(
            id: UUID(),
            kind: .failure,
            headline: headline,
            body: error.localizedDescription,
            // No additional toast-specific fields are required for generic failures
            capture: nil,
            ocr: nil,
            analysis: nil,
            piiWasRedacted: false,
            piiRedactionsApplied: 0
        )
        appState.pipelinePhase = .failed(error.localizedDescription)
        scheduleToastDismiss()
    }

    // MARK: - Utility

    private func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotError.fileLoadFailed(url)
        }
        return img
    }

    /// Flatten paragraphs so each fits within `columns` characters per line.
    static func flattenWordWrap(_ text: String, columns: Int = 80) -> String {
        guard columns > 0 else { return text }
        let maxChars = columns
        var out = ""
        out.reserveCapacity(text.count)
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, paragraph) in paragraphs.enumerated() {
            let para = String(paragraph)
            if para.isEmpty {
                out.append("\n")
                continue
            }
            var currentLine = ""
            let tokens = para.split(separator: " ", omittingEmptySubsequences: false)
            for token in tokens {
                let tokenStr = String(token)
                if currentLine.isEmpty {
                    currentLine = tokenStr
                } else if (currentLine.count + 1 + tokenStr.count) <= maxChars {
                    currentLine.append(" ")
                    currentLine.append(tokenStr)
                } else {
                    out.append(currentLine)
                    out.append("\n")
                    currentLine = tokenStr
                }
            }
            if !currentLine.isEmpty { out.append(currentLine) }
            if idx < paragraphs.count - 1 { out.append("\n") }
        }
        return out
    }
}

// MARK: - Window helpers

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsMouseMovedEvents: Bool {
        get { true }
        set { }
    }
}

/// Wraps a SwiftUI view in an NSView that becomes first responder on appear,
/// so the SwiftUI view reliably receives keyboard events (ESC, SPACE, RETURN,
/// G) even in a borderless .screenSaver-level window.
struct FirstResponderHostingView<Content: View>: NSViewRepresentable {
    let rootView: Content

    init(rootView: Content) {
        self.rootView = rootView
    }

    func makeNSView(context: Context) -> NSView {
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            hosting.window?.makeFirstResponder(hosting)
        }
        return hosting
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op — static content.
    }
}

extension AppCoordinator {
    public func wake() {
        HotkeyManager.shared.register()
    }
}