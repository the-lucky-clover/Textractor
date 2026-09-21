import SwiftUI
import Combine

/// Shared, observable application state.  Holds the latest capture lifecycle data,
/// the toast flag that the menubar UI binds to, and the recovery context
/// surfaced to a failed-OCR toast.
///
/// This view-model intentionally uses `@Published` so any SwiftUI view can react.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Capture lifecycle
    public static let recentCapturesCap = 12

    @Published public var lastCapture: CapturedImage?
    @Published public var lastOCR: OCRResult?
    @Published public var lastAnalysis: AIInferenceService.Analysis?

    /// Latest toast lifecycle — `nil` when hidden.
    @Published public var toast: ToastState?

    /// `true` while a capture flow is running.
    @Published public var isCapturing: Bool = false
    @Published public var pipelinePhase: PipelinePhase = .idle

    /// Recent captures (newest first, capped).
    @Published public var recentCaptures: [RecentCaptureEntry] = []

    /// Counter for "you've extracted N words today" / streak nudge.
    @Published public var streakCount: Int = 0

    // MARK: - Settings observers

    @Published public var settings: AppSettings

    private let settingsStore: SettingsStore

    // MARK: - Init

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.current
        // Re-publish settings changes to the UI when they are written elsewhere.
        settingsStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.settings = self.settingsStore.current
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var s = settingsStore.current
        mutate(&s)
        settingsStore.update(s)
        self.settings = s
    }

    /// Resets every setting on `AppSettings` back to its factory default.
    public func resetSettingsToDefaults() {
        let defaults = AppSettings.default
        settingsStore.update(defaults)
        self.settings = defaults
    }

    // MARK: - Capture lifecycle helpers

    public func record(capture: CapturedImage,
                       ocr: OCRResult?,
                       analysis: AIInferenceService.Analysis?) {
        self.lastCapture = capture
        self.lastOCR = ocr
        self.lastAnalysis = analysis
        let preview = RecentCaptureEntry(
            id: capture.id,
            capturedAt: capture.capturedAt,
            textPreview: analysis?.cleanedText ?? ocr?.joinedText ?? "",
            mode: capture.mode,
            sentiment: analysis?.sentiment
        )
        recentCaptures.insert(preview, at: 0)
        if recentCaptures.count > Self.recentCapturesCap {
            recentCaptures = Array(recentCaptures.prefix(Self.recentCapturesCap))
        }
        streakCount += 1

        // Also record to history with OCR confidence
        let confidence = ocr?.averageConfidence
        HistoryStore.shared.record(
            capture: capture,
            text: analysis?.cleanedText ?? ocr?.joinedText ?? "",
            mode: capture.mode,
            ocrConfidence: confidence,
            limit: settings.historyEntryLimit
        )
    }
}

// MARK: - Pipeline phase

public enum PipelinePhase: Equatable {
    case idle
    case capturing
    case ocr
    case ai
    case clipboard
    case completed
    case failed(String)

    public var label: String {
        switch self {
        case .idle:       return T.s("pipeline.idle")
        case .capturing:  return T.s("pipeline.capturing")
        case .ocr:        return T.s("pipeline.ocr")
        case .ai:         return T.s("pipeline.ai")
        case .clipboard:  return T.s("pipeline.clipboard")
        case .completed:  return T.s("pipeline.completed")
        case .failed(let m): return String(format: T.s("pipeline.failed"), m)
        }
    }

    public var symbolName: String {
        switch self {
        case .idle:       return "circle.dotted"
        case .capturing:  return "viewfinder.circle.fill"
        case .ocr:        return "text.viewfinder"
        case .ai:         return "sparkles"
        case .clipboard:  return "doc.on.clipboard"
        case .completed:  return "checkmark.seal.fill"
        case .failed:     return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Recent capture preview

public struct RecentCaptureEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let capturedAt: Date
    public let textPreview: String
    public let mode: CaptureMode
    public let sentiment: AIInferenceService.Sentiment?

    public init(
        id: UUID,
        capturedAt: Date,
        textPreview: String,
        mode: CaptureMode,
        sentiment: AIInferenceService.Sentiment? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.textPreview = textPreview
        self.mode = mode
        self.sentiment = sentiment
    }
}

// MARK: - Toast state

/// What the toast exposes. Three kinds:
///   • `.success` — clean extraction; copy + share chips on the bottom row.
///   • `.failure` — extraction surface (text missing / image-only fallback).
///     The toast gets the recovery row instead: image preview, weirdness
///     slider, Try-Again, Cancel.
///   • `.info`    — neutral message (e.g. update available, screen-recording
///     revoked).
public struct ToastState: Identifiable, Equatable {
    public enum Kind: Equatable {
        case success
        case failure
        case info
    }

    public let id: UUID
    public var kind: Kind
    public var headline: String
    public var bodyText: String
    public var capture: CapturedImage?
    public var ocr: OCRResult?
    public var analysis: AIInferenceService.Analysis?
    /// Path the recovery toast uses to render the screenshot preview. `nil`
    /// when there is no recovery pending.
    public var recoveryImagePath: String?
    /// Why the English-success detector failed (`nil` for non-failure toasts
    /// or for failures not driven by the detector).
    public var failureReason: String?
    /// True iff the most recent pipeline run scrubbed PII from the output
    /// (because the user is in default-redact mode and matches were found).
    public var piiWasRedacted: Bool
    /// Number of PII matches scrubbed in the most recent pipeline run.
    public var piiRedactionsApplied: Int
    /// True when the failure is a Screen Recording permission denial. The toast
    /// then shows a reassurance that no data leaves the device plus an
    /// "Open Settings" action, instead of a generic error body.
    public var screenRecordingDenied: Bool

    /// Tap handler for Copy in success mode. The toast controller wires this
    /// to the clipboard helper (re-copy the extracted text on demand).
    public var copy: (() -> Void)?
    /// Tap handler for share chips.
    public var share: ((ShareService.Provider) -> Void)?
    /// Tap handler for **Try again** in the failure toast — runs OCR again on
    /// the saved screenshot at the chosen weirdness.
    public var tryAgain: (() -> Void)?
    /// Tap handler for **Cancel** — trashes the screenshot, dismisses toast.
    public var cancel: (() -> Void)?
    /// Tap handler for **Open recovery screenshot** (Reveal in Finder).
    public var revealRecovery: (() -> Void)?
    /// Tap handler for **Open Settings** — jumps to System Settings → Screen
    /// Recording when a capture failed due to missing permission.
    public var openSettings: (() -> Void)?

    /// Tap handler for the **Translate** quick action. Re-translates the
    /// captured text to the user's configured target language. Only shown
    /// when translateAfterCapture is off but a target language is set.
    public var onTranslate: (() -> Void)?

    /// Tap handler for the **Format as Code** quick action. Wraps the
    /// captured text in a fenced code block with detected language hint.
    public var onFormatCode: (() -> Void)?

    /// Tap handler for the **Open URL** quick action. Opens the first
    /// detected URL in the default browser.
    public var onOpenURL: (() -> Void)?

    /// Tap handler for the **Compose Email** quick action. Opens the
    /// default mail client with the first detected email address.
    public var onComposeEmail: (() -> Void)?

    /// Tap handler for the **Format as Code Block** quick action. Detects
    /// source code in the text and wraps it in a fenced markdown block.
    public var onFormatCodeBlock: (() -> Void)?

    /// Tap handler for the **Undo** quick action. Reverts the last capture
    /// by removing it from history and restoring previous clipboard.
    public var onUndo: (() -> Void)?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        headline: String,
        body: String,
        capture: CapturedImage? = nil,
        ocr: OCRResult? = nil,
        analysis: AIInferenceService.Analysis? = nil,
        recoveryImagePath: String? = nil,
        failureReason: String? = nil,
        piiWasRedacted: Bool = false,
        piiRedactionsApplied: Int = 0,
        screenRecordingDenied: Bool = false,
        copy: (() -> Void)? = nil,
        share: ((ShareService.Provider) -> Void)? = nil,
        tryAgain: (() -> Void)? = nil,
        cancel: (() -> Void)? = nil,
        revealRecovery: (() -> Void)? = nil,
        openSettings: (() -> Void)? = nil,
        onTranslate: (() -> Void)? = nil,
        onFormatCode: (() -> Void)? = nil,
        onOpenURL: (() -> Void)? = nil,
        onComposeEmail: (() -> Void)? = nil,
        onFormatCodeBlock: (() -> Void)? = nil,
        onUndo: (() -> Void)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.bodyText = body
        self.capture = capture
        self.ocr = ocr
        self.analysis = analysis
        self.recoveryImagePath = recoveryImagePath
        self.failureReason = failureReason
        self.piiWasRedacted = piiWasRedacted
        self.piiRedactionsApplied = piiRedactionsApplied
        self.screenRecordingDenied = screenRecordingDenied
        self.copy = copy
        self.share = share
        self.tryAgain = tryAgain
        self.cancel = cancel
        self.revealRecovery = revealRecovery
        self.openSettings = openSettings
        self.onTranslate = onTranslate
        self.onFormatCode = onFormatCode
        self.onOpenURL = onOpenURL
        self.onComposeEmail = onComposeEmail
        self.onFormatCodeBlock = onFormatCodeBlock
        self.onUndo = onUndo
    }

    public static func == (lhs: ToastState, rhs: ToastState) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.headline == rhs.headline
            && lhs.bodyText == rhs.bodyText
    }
}
