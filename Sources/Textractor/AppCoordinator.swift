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
            self?.startCaptureRegion()
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

        // Telemetry
        TelemetryService.shared.record(
            TelemetryEvent(kind: .sessionStart),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )


        LoggerService.shared.info("Textractor bootstrap complete")
    }

    // MARK: - Capture flows

    public func startCaptureRegion() {
        guard !appState.isCapturing else { return }
        presentCaptureOverlay(initialMode: .crosshair)
        TelemetryService.shared.record(
            TelemetryEvent(kind: .hotkeyPressed),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )
    }

    public func startCaptureWindow() {
        guard !appState.isCapturing else { return }
        presentCaptureOverlay(initialMode: .window)
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
            await runPipeline(for: capture)
        } catch {
            handleFailure(error: error, context: "ingestFile")
        }
        appState.isCapturing = false
    }

    private func runFullScreenPipeline() async {
        appState.isCapturing = true
        do {
            let captures = try await ScreenshotService.shared.captureFullScreen()
            for capture in captures {
                await runPipeline(for: capture)
            }
            appState.pipelinePhase = .completed
        } catch {
            handleFailure(error: error, context: "fullScreen")
        }
        appState.isCapturing = false
    }

    /// Captures a region via a CG rect (returned by overlay).
    public func runCaptureRegion(_ rect: CGRect) async {
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureRegion(rect)
            await runPipeline(for: capture)
        } catch {
            handleFailure(error: error, context: "region")
        }
        appState.isCapturing = false
    }

    public func runCaptureWindow(_ windowID: CGWindowID) async {
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            let (capture, _) = try await ScreenshotService.shared.captureWindow(windowID)
            await runPipeline(for: capture)
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
                await runPipeline(for: capture)
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
            preferredLanguages: langs
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
            share: toastShare
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
    public func runPipeline(for capture: CapturedImage) async {

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
        let ocrResult = await OCRService.shared.recognizeText(
            in: cgImage,
            weirdness: weirdness,
            customVocabulary: vocab,
            preferredLanguages: appState.settings.uiLanguage.isEmpty
                ? OCRService.automaticLanguages()
                : [appState.settings.uiLanguage]
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
                    Task { await self.runPipeline(for: retryCapture) }
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

    public func quitApp() {
        TelemetryService.shared.record(
            TelemetryEvent(kind: .sessionEnd),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )
        NSApp.terminate(nil)
    }

    // MARK: - Capture overlay window

    private func presentCaptureOverlay(initialMode: CaptureMode) {
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
                Task { await self?.runCaptureRegion(rect) }
            },
            onWindowCaptured: { [weak self] windowID in
                self?.dismissCaptureOverlay()
                Task { await self?.runCaptureWindow(windowID) }
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