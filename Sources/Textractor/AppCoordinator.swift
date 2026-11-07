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
    @Published public private(set) var previousRegion: CGRect?

  /// Currently presented capture overlay (the fullscreen NSWindow).
  private var captureWindows: [NSWindow] = []
  private var captureKeyboardMonitor: Any?
  private var captureIntent = CaptureIntent()
  private var captureSession: CaptureOverlaySession?

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
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismissCaptureOverlay() }
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
        ActionShortcuts.shared.onAction = { [weak self] action in self?.perform(action) }
        let s = appState.settings
        _ = ActionShortcuts.shared.configure(s)
        CaptureExtras.shared.configure(settings: s)

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


        if !settingsStore.hasCompletedOnboarding { replayOnboarding() }
        LoggerService.shared.info("Textractor Pro bootstrap complete")
    }

    public func replayOnboarding() {
        OnboardingWindowController.shared.show { [weak self] code in
            guard let self else { return }
            if let code { self.appState.updateSettings { $0.uiLanguage = code } }
            self.settingsStore.hasCompletedOnboarding = true
            self.settingsStore.flushPendingPersist()
        }
    }

    // MARK: - Capture flows

    public func startCaptureRegion(perCaptureLanguageOverride: Bool = false) {
        guard !appState.isCapturing, captureWindows.isEmpty else { return }
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
        guard !appState.isCapturing, captureWindows.isEmpty else { return }
        if perCaptureLanguageOverride {
            showPerCaptureLanguagePicker { [weak self] selectedLanguage in
                self?.presentCaptureOverlay(initialMode: .window, perCaptureLanguage: selectedLanguage)
            }
        } else {
            presentCaptureOverlay(initialMode: .window, perCaptureLanguage: nil)
        }
    }

  public func startAutoScrollCapture() {
    guard !appState.isCapturing, captureWindows.isEmpty else { return }
    pendingAutoScrollCapture = true
    presentCaptureOverlay(initialMode: .autoScroll, perCaptureLanguage: nil)
  }

    public func capturePreviousRegion() {
        guard !appState.isCapturing, captureWindows.isEmpty, let rect = previousRegion else { return }
        Task { await runCaptureRegion(rect) }
    }

    public func startCaptureFullScreen() {
        guard !appState.isCapturing, captureWindows.isEmpty else { return }
        Task {
            appState.pipelinePhase = .capturing
            await runFullScreenPipeline()
        }
    }

    public func startCapture(_ file: URL) {
        guard !appState.isCapturing, captureWindows.isEmpty else { return }
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
    public func runCaptureRegion(_ rect: CGRect, perCaptureLanguage: String? = nil, intent: CaptureIntent = CaptureIntent()) async {
        previousRegion = rect
        appState.isCapturing = true
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureRegion(rect)
            await runPipeline(for: capture, perCaptureLanguage: perCaptureLanguage, intent: intent)
        } catch {
            handleFailure(error: error, context: "region")
        }
        appState.isCapturing = false
    }

  public func runCaptureWindow(_ windowID: CGWindowID, perCaptureLanguage: String? = nil, intent: CaptureIntent = CaptureIntent()) async {
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
      await runPipeline(for: capture, perCaptureLanguage: perCaptureLanguage, intent: intent)
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
        guard !appState.isCapturing, captureWindows.isEmpty else { return }
        appState.isCapturing = true
        defer { appState.isCapturing = false }
        appState.pipelinePhase = .capturing
        do {
            let captures = try await ScreenshotService.shared.captureFromContinuityCamera()
            var pages: [String] = []
            for capture in captures {
                CaptureExtras.shared.beginCapture()
                await runPipeline(for: capture, perCaptureLanguage: nil)
                guard let text = CaptureExtras.shared.lastDeliveredText else {
                    throw ScreenshotError.processingFailed("Page \(pages.count + 1) of \(captures.count) could not be extracted. Review the scan and retry.")
                }
                pages.append(text)
            }
            if !appState.settings.additiveClipboard {
                guard ClipboardService.shared.copy(pages.joined(separator: "\n\n"), plainTextOnly: true) else {
                    throw ScreenshotError.processingFailed("Could not copy the scanned pages.")
                }
            }
            appState.pipelinePhase = .completed
            appState.toast = ToastState(kind: .info, headline: "Device import complete", body: "\(pages.count) of \(captures.count) pages copied.")
        } catch is CancellationError {
            appState.pipelinePhase = .idle
        } catch {
            handleFailure(error: error, context: "continuityCamera")
        }
    }

    // MARK: - Core pipeline

    @MainActor
    public func runPipeline(for capture: CapturedImage, perCaptureLanguage: String? = nil, intent: CaptureIntent = CaptureIntent()) async {
        let settings = intent.applying(to: appState.settings, languageOverride: perCaptureLanguage)

        let weirdness = settings.weirdness
        let vocab = settings.customVocabulary
        let telemetryEnabled = settings.localTelemetryEnabled
        let pasteAsPlainText = settings.pasteAsPlainText
        let wordWrapCaptured = settings.wordWrapCaptured
        let flattenText = settings.flattenText

        // MARK: - OCR ---------------------------------------------------------
        appState.pipelinePhase = .ocr
        let cgImage: CGImage
        do {
            cgImage = try loadCGImage(from: capture.fileURL)
        } catch {
            handleFailure(error: error, context: "loadImage")
            return
        }

        if settings.recognizeBarcodes {
            do {
                let payloads = try await Task.detached(priority: .userInitiated) {
                    try BarcodeRecognition.recognize(cgImage)
                }.value
                guard !payloads.isEmpty else {
                    throw ScreenshotError.processingFailed("No QR code or barcode found. Turn off barcode mode to capture text.")
                }
                let raw = payloads.joined(separator: "\n")
                let report = SensitiveDataDetector.scan(raw)
                let output = settings.piiRedactionEnabled ? SensitiveDataDetector.scrub(raw, report: report) : raw
                guard CaptureExtras.shared.deliver(output, settings: settings) else {
                    throw ScreenshotError.processingFailed("Could not copy barcode data. Clear the additive batch if it is full.")
                }
                appState.record(capture: capture, ocr: nil, analysis: nil, storedText: output)
                appState.pipelinePhase = .completed
                appState.toast = ToastState(kind: .info, headline: "Barcode copied", body: "\(payloads.count) distinct code(s)")
            } catch { handleFailure(error: error, context: "barcode") }
            return
        }

        // Honor the user's chosen language. Empty = Automatic (english-first
        // multi-language superset); non-empty = that exact language for both
        // UI and OCR.
        // Per-capture language override (⌥ + capture) takes precedence over settings.
        let ocrLanguages = settings.uiLanguage.isEmpty ? OCRService.automaticLanguages() : [settings.uiLanguage]
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
        let piiWasRedacted = settings.piiRedactionEnabled && !detectorReport.isClean
        let piiRedactionsApplied = detectorReport.byKind.count
        let scrubbedText = SensitiveDataDetector.scrub(ocrResult.joinedText, report: detectorReport)

        // MARK: - Success check (language-aware) ---------------------------------
        let englishVerdict = EnglishSuccessDetector.judge(
            ocrResult,
            preferredLanguage: settings.uiLanguage
        )

        // MARK: - English success path --------------------------------------
        if englishVerdict.success {
            let rawText = ocrResult.joinedText
            let finalText = settings.piiRedactionEnabled
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
            let tableMarkdown = (isWindow && settings.windowCaptureAsTable)
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

            if settings.sourceCodeMode {
                outputText = SourceCodeDetector.analyze(outputText).formatted
            }

            // Formatting (especially table reconstruction) can reintroduce raw text.
            outputText = TextFormatter.finalize(outputText, redactSensitiveData: settings.piiRedactionEnabled)

            // Build attributed string for rich paste
            let attributed: NSAttributedString? = {
                if pasteAsPlainText { return nil }
                if tableMarkdown != nil {
                    let p = NSMutableParagraphStyle()
                    p.lineSpacing = 2.5
                    return NSAttributedString(
                        string: outputText,
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
            let copyOk = CaptureExtras.shared.deliver(outputText, attributed: attributed, settings: settings)
            guard copyOk else {
                handleFailure(error: ScreenshotError.processingFailed("Copy failed. The clipboard may be unavailable or the additive batch may be full."), context: "clipboard")
                return
            }
            SoundManager.playCaptureComplete()

            // Save to CaptureStore (new visual knowledge library)
            if settings.knowledgeModeEnabled {
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
                let metadataEntities: [String] = ([.url, .email, .phone, .cryptoAddress, .trackingNumber, .apiKey, .creditCard, .ipAddress, .macAddress, .uuid, .filePath, .sshKey, .dockerId] as [MetadataType]).flatMap { metadata.values(for: $0) }
                let allEntities = Array(Set(entities + metadataEntities))
                
                let record = CaptureRecord(
                    mode: capture.mode.rawValue,
                    origin: capture.origin.rawValue,
                    rect: capture.rect,
                    filePath: capture.fileURL.path,
                    ocrText: ocrResult.joinedText,
                    language: settings.uiLanguage.isEmpty ? "auto" : settings.uiLanguage,
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
            appState.record(capture: capture, ocr: ocrResult, analysis: analysis, storedText: outputText)

            // Success toast
            appState.pipelinePhase = .completed
            guard settings.showSuccessNotifications else { return }
            // Capture text at creation time so the closures never read stale state.
let toastText = outputText
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
                    Task { await self.runPipeline(for: retryCapture, perCaptureLanguage: perCaptureLanguage, intent: intent) }
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
        picker.addItems(withTitles: ["Auto"] + AppSettings.availableOCRLanguages.map { "\($0.flag) \($0.name)" })
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
                let code = AppSettings.availableOCRLanguages[index - 1].code
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

    private func captureStatus() -> String {
        let settings = captureIntent.applying(to: appState.settings)
        return "Line breaks: \(settings.flattenText ? "off" : "on") · Additive: \(settings.additiveClipboard ? "on" : "off") · Speech: \(settings.readAloud ? "on" : "off")"
    }

    public func perform(_ action: CaptureAction) {
        defer { captureSession?.status = captureStatus() }
        switch action {
        case .capture: startCaptureRegion()
        case .previous: capturePreviousRegion()
        case .keepLines, .removeLines, .speakCapture, .barcode:
            guard !appState.isCapturing, captureWindows.isEmpty else { return }
            let intent = CaptureIntent(flatten: action == .keepLines ? false : action == .removeLines ? true : nil,
                                       speech: action == .speakCapture ? true : nil,
                                       barcode: action == .barcode)
            presentCaptureOverlay(initialMode: .crosshair, perCaptureLanguage: nil, intent: intent)
        case .stopSpeaking: CaptureExtras.shared.stopSpeaking()
        case .toggleAdditive, .overlayAdditive: appState.updateSettings { $0.additiveClipboard.toggle() }
        case .clearAdditive: CaptureExtras.shared.clearBatch()
        case .overlayLines:
            let current = captureIntent.applying(to: appState.settings).flattenText
            captureIntent.flatten = nil
            appState.updateSettings { $0.flattenText = !current; $0.wordWrapCaptured = false }
        case .overlaySpeech:
            let current = captureIntent.applying(to: appState.settings).readAloud
            captureIntent.speech = nil
            appState.updateSettings { $0.readAloud = !current }
        }
    }

    private func presentCaptureOverlay(initialMode: CaptureMode, perCaptureLanguage: String?, intent: CaptureIntent = CaptureIntent()) {
        guard captureWindows.isEmpty else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        // Sample global pointer BEFORE activation can move focus to another Space/display.
        let mouse = NSEvent.mouseLocation
        let activeIndex = CaptureDisplayGeometry.displayIndex(at: mouse, frames: screens.map(\.frame)) ?? 0
        captureIntent = intent
        let session = CaptureOverlaySession(mode: initialMode, status: captureStatus())
        captureSession = session
        statusBarController?.closePopover()
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            let window = CaptureOverlayWindow(frame: frame)
            window.title = "Capture display \(index + 1)"
            window.identifier = NSUserInterfaceItemIdentifier("capture.display.\(index)")
            let view = CaptureOverlayView(frame: frame, initialMode: initialMode,
                initialCursorPoint: mouse, session: session,
                onRegionCaptured: { [weak self] rect in
                    guard let self else { return }
                    let intent = self.captureIntent
                    self.dismissCaptureOverlay()
                    Task { await self.runCaptureRegion(rect, perCaptureLanguage: perCaptureLanguage, intent: intent) }
                },
                onWindowCaptured: { [weak self] windowID, mode in
                    guard let self else { return }
                    let intent = self.captureIntent
                    let autoScroll = mode == .autoScroll
                    self.dismissCaptureOverlay()
                    self.pendingAutoScrollCapture = autoScroll
                    Task { await self.runCaptureWindow(windowID, perCaptureLanguage: perCaptureLanguage, intent: intent) }
                },
                onCancel: { [weak self] in self?.dismissCaptureOverlay() },
                onContinuityCapture: { [weak self] in
                    self?.dismissCaptureOverlay()
                    Task { await self?.runContinuityCameraCapture() }
                },
                onDisplayChanged: { [weak window] _ in
                    // One stationary overlay per display; never compare local hover points to global frames.
                    guard let window, !window.isKeyWindow else { return }
                    window.makeKeyAndOrderFront(nil)
                },
                captureFrameProvider: { frame }, reduceMotion: appState.settings.reduceMotion,
                showLivePreview: false) // ScreenCaptureKit previews would capture the overlay itself.
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(frame, display: false)
            captureWindows.append(window)
            window.orderFrontRegardless()
        }
        captureKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.captureWindows.isEmpty else { return event }
            if event.keyCode == 53 { self.dismissCaptureOverlay(); return nil }
            let flags = ActionShortcuts.carbonModifiers(event.modifierFlags)
            for action in CaptureAction.allCases where action.overlayOnly {
                if self.appState.settings.shortcut(for: action)?.matches(keyCode: UInt32(event.keyCode), modifiers: flags) == true {
                    self.perform(action); return nil
                }
            }
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
        let active = captureWindows[activeIndex]
        active.makeKeyAndOrderFront(nil)
        active.makeFirstResponder(active.contentView)
    }

    private func dismissCaptureOverlay() {
        if let captureKeyboardMonitor { NSEvent.removeMonitor(captureKeyboardMonitor) }
        captureKeyboardMonitor = nil
        captureWindows.forEach { $0.orderOut(nil); $0.close() }
        captureWindows.removeAll()
        captureSession = nil
        captureIntent = CaptureIntent()
        pendingAutoScrollCapture = false
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
        _ = ActionShortcuts.shared.configure(appState.settings)
    }
}
