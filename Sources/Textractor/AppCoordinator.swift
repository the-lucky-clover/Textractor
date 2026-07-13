import AppKit
import SwiftUI
import Combine
import ImageIO
import CoreGraphics

/// Top-level coordinator that owns the application lifecycle:
///   • registers the global hotkey
///   • presents capture overlays (crosshair / window)
///   • runs the capture → OCR → AI → clipboard pipeline
///   • pops the menubar `MenuContentView` panels
@MainActor
public final class AppCoordinator: ObservableObject {

    public static let shared = AppCoordinator()

    // MARK: - State

    public let settingsStore = SettingsStore()
    public let appState: AppState

    /// Currently presented capture overlay (the fullscreen NSWindow).
    private var captureWindow: NSWindow?

    /// The menu-bar status item controller (replaces SwiftUI's `MenuBarExtra`).
    private var statusBarController: StatusBarController?

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        self.appState = AppState(settingsStore: settingsStore)
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
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

        // Menu-bar status item (replaces `MenuBarExtra`).
        statusBarController = StatusBarController(coordinator: self)

        // Telemetry
        TelemetryService.shared.record(
            TelemetryEvent(kind: .sessionStart),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )

        LoggerService.shared.info("Textractor bootstrap complete")
    }

    // MARK: - Capture flows

    public func startCaptureRegion() {
        presentCaptureOverlay(initialMode: .crosshair)
        TelemetryService.shared.record(
            TelemetryEvent(kind: .hotkeyPressed),
            telemetryEnabled: appState.settings.localTelemetryEnabled
        )
    }

    public func startCaptureWindow() {
        presentCaptureOverlay(initialMode: .window)
    }

    public func startCaptureFullScreen() {
        Task {
            appState.pipelinePhase = .capturing
            await runFullScreenPipeline()
        }
    }

    public func startCapture(_ file: URL) {
        Task { await ingestFile(at: file) }
    }

    // MARK: - Pipeline (file ingestion, fullscreen, region/window via overlay)

    public func ingestFile(at url: URL) async {
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureFromFile(at: url)
            await runPipeline(for: capture)
        } catch {
            handleFailure(error: error, context: "ingestFile")
        }
    }

    private func runFullScreenPipeline() async {
        do {
            let captures = try await ScreenshotService.shared.captureFullScreen()
            for capture in captures {
                await runPipeline(for: capture)
            }
            appState.pipelinePhase = .completed
        } catch {
            handleFailure(error: error, context: "fullScreen")
        }
    }

    /// Captures a region via a CG rect (returned by overlay).
    public func runCaptureRegion(_ rect: CGRect) async {
        appState.pipelinePhase = .capturing
        do {
            let capture = try await ScreenshotService.shared.captureRegion(rect)
            await runPipeline(for: capture)
        } catch {
            handleFailure(error: error, context: "region")
        }
    }

    public func runCaptureWindow(_ windowID: CGWindowID) async {
        appState.pipelinePhase = .capturing
        do {
            let (capture, _) = try await ScreenshotService.shared.captureWindow(windowID)
            await runPipeline(for: capture)
        } catch {
            handleFailure(error: error, context: "window")
        }
    }

    @MainActor
    public func runPipeline(for capture: CapturedImage) async {
        let weirdness = appState.settings.weirdness
        let vocab = appState.settings.customVocabulary
        let telemetryEnabled = appState.settings.localTelemetryEnabled
        let pasteAsPlainText = appState.settings.pasteAsPlainText
        let wordWrapCaptured = appState.settings.wordWrapCaptured

        // "Save raw image only" is a privacy mode: skip OCR / AI / clipboard
        // entirely and just persist the screenshot. Nothing about the text is
        // ever read, analysed, or placed on the pasteboard.
        if appState.settings.storageMode == .safeOnlyScreenshot {
            appState.pipelinePhase = .completed
            _ = try? StorageService.shared.saveToDefaultFolder(capture)
            TelemetryService.shared.record(
                TelemetryEvent(kind: .storageSaved, success: true, meta: ["mode": "safeOnlyScreenshot"]),
                telemetryEnabled: telemetryEnabled
            )
            return
        }

        // OCR
        appState.pipelinePhase = .ocr
        let cgImage: CGImage
        do {
            cgImage = try loadCGImage(from: capture.fileURL)
        } catch {
            // Don't silently OCR an empty placeholder and report success —
            // surface the load failure so the user sees a real error.
            handleFailure(error: error, context: "loadImage")
            return
        }
        let ocr = await OCRService.shared.recognizeText(
            in: cgImage,
            weirdness: weirdness,
            customVocabulary: vocab
        )

        // AI inference
        appState.pipelinePhase = .ai
        let cleaned = ocr.joinedText
        let analysis = await AIInferenceService.shared.analyze(
            cleaned,
            weirdness: weirdness
        )

        // If the user opted into window-table mode and this is a window capture,
        // check whether the OCR alignment looks tabular.
        let isWindow = capture.mode == .window
        let tableMarkdown = (isWindow && appState.settings.windowCaptureAsTable)
            ? TableFormatter.toMarkdownTable(observations: ocr.rawObservations)
            : nil
        let rawFinalText = tableMarkdown ?? analysis.cleanedText

        // Apply word-wrap flattening if the user wants it (default OFF).
        var finalText: String = wordWrapCaptured
            ? Self.flattenWordWrap(rawFinalText, columns: 80)
            : rawFinalText

        // Flatten text: drop carriage returns / newlines so list items become a
        // single running paragraph. Default OFF.
        if appState.settings.flattenText {
            finalText = finalText.replacingOccurrences(of: "\r\n", with: " ")
                          .replacingOccurrences(of: "\n", with: " ")
                          .replacingOccurrences(of: "\r", with: " ")
            finalText = finalText.split(separator: " ").filter { !$0.isEmpty }.joined(separator: " ")
        }

        // Build rich NSAttributedString for the pasteboard. If we have a table,
        // ship the markdown string verbatim — pasting into a markdown editor
        // produces perfect tables. Otherwise apply typography-rich formatting.
        let attributed: NSAttributedString? = {
            if pasteAsPlainText { return nil }
            if let tableMarkdown {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 2.5
                return NSAttributedString(string: tableMarkdown, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                    .paragraphStyle: paragraph,
                    .foregroundColor: NSColor.labelColor
                ])
            }
            return TextFormatter.attributed(from: analysis.cleanedText, analysis: analysis, weirdness: weirdness)
        }()

        // Clipboard
        appState.pipelinePhase = .clipboard
        LoggerService.shared.debug("Copying to clipboard: \(finalText.prefix(100))…")
        let ok = ClipboardService.shared.copy(finalText, attributed: attributed, plainTextOnly: pasteAsPlainText)
        LoggerService.shared.debug("Clipboard copy result: \(ok)")
        SoundManager.playCaptureComplete()

        // Update app state + persist a text-only history entry (timestamped).
        appState.record(capture: capture, ocr: ocr, analysis: analysis)
        HistoryStore.shared.record(capture: capture, text: finalText, mode: capture.mode)

        // Begin storage decision flow (only if "ask each time").
        let isAsk = appState.settings.storageMode == .ask
        let storageRequest: StorageDecisionRequest? = isAsk
            ? StorageService.shared.beginDecisionFlow(for: capture, mode: .ask)
            : nil

        // Build toast with resolveStorage closure in ask mode.
        appState.toast = ToastState(
            kind: ok ? .success : .failure,
            headline: ok
                ? "Selected text was successfully added to clipboard."
                : "Clipboard write failed",
            body: ok ? String(finalText.prefix(180)) : "Try a different region.",
            capture: capture,
            ocr: ocr,
            analysis: analysis,
            storageQuestion: isAsk ? .askKeepOrDelete : .none,
            resolveStorage: isAsk ? { decision in
                guard let request = storageRequest else { return }
                StorageService.shared.resolvePending(decision, requestID: request.id)
            } : nil
        )

        // Now govern storage.
        if let request = storageRequest {
            // Wait for the user's click, defaulting to delete after 8s so a
            // temp screenshot is never left behind if the toast is ignored.
            let decision = await resolveStorageDecision(for: request, timeoutSeconds: 8.0)
            applyStorageDecision(decision, for: capture)
        } else {
            // Apply non-ask modes immediately.
            await governStorageSynchronous(for: capture)
        }

        appState.pipelinePhase = .completed

        // Telemetry
        TelemetryService.shared.record(
            TelemetryEvent(kind: .clipboardWrite, success: ok, meta: [
                "bytes": "\(finalText.count)",
                "table": tableMarkdown != nil ? "1" : "0"
            ]),
            telemetryEnabled: telemetryEnabled
        )

        // Auto-dismiss toast after a while (only if no storage question remains open).
        scheduleToastDismiss()
    }

    // MARK: - Storage governance

    private func governStorageSynchronous(for capture: CapturedImage) async {
        let mode = appState.settings.storageMode
        switch mode {
        case .autoDelete:
            _ = StorageService.shared.trash(capture)
            TelemetryService.shared.record(
                TelemetryEvent(kind: .storageDeleted),
                telemetryEnabled: appState.settings.localTelemetryEnabled
            )

        case .safe, .safeOnlyScreenshot:
            do {
                _ = try StorageService.shared.saveToDefaultFolder(capture)
                TelemetryService.shared.record(
                    TelemetryEvent(kind: .storageSaved),
                    telemetryEnabled: appState.settings.localTelemetryEnabled
                )
            } catch {
                LoggerService.shared.warning("save failed: \(error.localizedDescription)")
            }

        case .ask:
            // Handled separately via StorageDecisionRequest in runPipeline.
            break
        }
    }

    public func applyStorageDecision(_ decision: StorageDecision, for capture: CapturedImage) {
        switch decision {
        case .delete:
            _ = StorageService.shared.trash(capture)
            TelemetryService.shared.record(
                TelemetryEvent(kind: .storageDeleted),
                telemetryEnabled: appState.settings.localTelemetryEnabled
            )
        case .keepInDefaultFolder:
            do { _ = try StorageService.shared.saveToDefaultFolder(capture) } catch {
                LoggerService.shared.warning("default save failed")
            }
            TelemetryService.shared.record(
                TelemetryEvent(kind: .storageSaved),
                telemetryEnabled: appState.settings.localTelemetryEnabled
            )
        case .saveTo(let url):
            do { _ = try StorageService.shared.save(capture, to: url) } catch {
                LoggerService.shared.warning("save-to failed")
            }
            TelemetryService.shared.record(
                TelemetryEvent(kind: .storageSaved),
                telemetryEnabled: appState.settings.localTelemetryEnabled
            )
        case .ignored:
            _ = StorageService.shared.trash(capture)
        }
    }

    // MARK: - Sharing

    public func share(text: String, via provider: ShareService.Provider) {
        ShareService.shared.share(text: text, caption: "Text from Textractor", via: provider)
    }

    // MARK: - UI

    public func openSettings() {
        // Use our own window controller rather than `NSApp.sendAction("showSettingsWindow:")`
        // — the latter routes through the responder chain and frequently does nothing
        // for an accessory (LSUIElement) app. This mirrors showHistoryWindow().
        SettingsWindowController.shared.show(appState: appState)
    }

    public func showCredits() {
        // Credits modal is presented inside the menu popover's MainView; this
        // method is a hook in case we want a separate window in future versions.
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
        guard let screen = NSScreen.main else { return }

        let view = CaptureOverlayView(
            frame: screen.frame,
            initialMode: initialMode,
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

        // Activate first so the .screenSaver-level window can actually become key.
        NSApp.activate(ignoringOtherApps: true)

        window.makeKeyAndOrderFront(nil)
        // Re-establish the responder chain now that the window is key — the view
        // only becomes first responder after the window is key+main.
        window.makeFirstResponder(hosting)

        LoggerService.shared.info("[capture.window] post-show isKeyWindow=\(window.isKeyWindow) isMainWindow=\(window.isMainWindow) firstResponder==hosting=\(window.firstResponder === hosting)")

        captureWindow = window
    }

    private func dismissCaptureOverlay() {
        captureWindow?.orderOut(nil)
        captureWindow = nil
    }

    // MARK: - Toast auto-dismiss

    private func scheduleToastDismiss() {
        let messenger = appState
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_500_000_000)
            // If the user hasn't engaged with the storage question, default to delete.
            if let toast = messenger.toast, toast.storageQuestion == .none {
                withAnimation(.easeOut(duration: 0.4)) {
                    messenger.toast = nil
                }
            }
        }
    }

    // MARK: - Failure helper

    private func handleFailure(error: Error, context: String) {
        LoggerService.shared.error("\(context) failure", error: error)
        appState.toast = ToastState(
            kind: .failure,
            headline: "Capture failed",
            body: error.localizedDescription
        )
        appState.pipelinePhase = .failed(error.localizedDescription)
    }

    // MARK: - Utility

    private func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotError.fileLoadFailed(url)
        }
        return img
    }

    /// Await the user's storage decision, defaulting to `.delete` after
    /// `timeoutSeconds`. This genuinely races the user's click against a
    /// timeout — the previous `firstOf(await request.await(), …)` form
    /// evaluated the await *before* the race, so the timeout never applied and
    /// an ignored toast left the pipeline hung with an un-cleaned temp file.
    ///
    /// On timeout the still-pending request is cancelled so its continuation is
    /// resumed (no leak) before we fall back to `.delete`.
    private func resolveStorageDecision(
        for request: StorageDecisionRequest,
        timeoutSeconds: Double
    ) async -> StorageDecision {
        await withTaskGroup(of: StorageDecision?.self) { group in
            group.addTask { await request.await() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            if let winner {
                return winner
            }
            // Timeout won: resume the suspended continuation (Task cancellation
            // alone won't, since CheckedContinuation isn't cancellation-aware)
            // so the awaiting child finishes and nothing leaks.
            if !request.isResolved {
                StorageService.shared.cancelPending(requestID: request.id, with: .delete)
            }
            return .delete
        }
    }

    /// Flatten paragraphs so each fits within `columns` characters per line.
    /// Empty lines are preserved as paragraph breaks. Long single words are
    /// left intact (we don't hyphenate).
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
            // Break into whitespace-separated tokens, keeping the whitespace.
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
            if !currentLine.isEmpty {
                out.append(currentLine)
            }
            if idx < paragraphs.count - 1 {
                out.append("\n")
            }
        }
        return out
    }
}

// MARK: - Window helpers

/// `NSWindow` subclass that opts the borderless capture overlay into being
/// the key window. Without this, AppKit refuses to make the overlay key,
/// and downstream SwiftUI `.onKeyPress`, `.focusable`, and the click-to-drag
/// React-style gesture never see their first responder.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension NSWindow {
    /// Convenience for `NSWindow.makeFirstResponder(_:)` against an NSHostingView.
    func makeFirstHostingViewFirstResponder(_ hosting: NSHostingView<some View>) {
        hosting.window?.makeFirstResponder(hosting)
    }
}

extension AppCoordinator {
    /// Re-registers the global hotkey — useful if the user revoked/regranted permissions.
    public func wake() {
        HotkeyManager.shared.register()
    }
}
