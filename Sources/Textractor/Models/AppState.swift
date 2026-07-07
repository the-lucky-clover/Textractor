import SwiftUI
import Combine

/// Shared, observable application state.  Holds the latest capture lifecycle data,
/// pending storage decisions, and the toast / progress overlay flags that the
/// menubar UI binds to.
///
/// This view-model intentionally uses `@Published` so any SwiftUI view can react.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Capture lifecycle

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

    public func resetSettingsToDefaults() {
        settingsStore.update(.default)
        self.settings = .default
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
        if recentCaptures.count > 12 {
            recentCaptures = Array(recentCaptures.prefix(12))
        }
        streakCount += 1
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
        case .idle:       return "Standby"
        case .capturing:  return "Capturing…"
        case .ocr:        return "Reading text…"
        case .ai:         return "Cleansing & analyzing…"
        case .clipboard:  return "Pasting…"
        case .completed:  return "Done"
        case .failed(let m): return "Failed: \(m)"
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

public struct ToastState: Identifiable, Equatable {
    public enum Kind: Equatable {
        case success
        case failure
        case info
    }

    public enum StorageQuestion: Equatable {
        case none
        case askKeepOrDelete
        case askWhere
    }

    public let id: UUID
    public var kind: Kind
    public var headline: String
    public var bodyText: String
    public var capture: CapturedImage?
    public var ocr: OCRResult?
    public var analysis: AIInferenceService.Analysis?
    public var storageQuestion: StorageQuestion
    /// Resolver callback set by `StorageService`. nil after consumption.
    public var resolveStorage: ((StorageDecision) -> Void)?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        headline: String,
        body: String,
        capture: CapturedImage? = nil,
        ocr: OCRResult? = nil,
        analysis: AIInferenceService.Analysis? = nil,
        storageQuestion: StorageQuestion = .none,
        resolveStorage: ((StorageDecision) -> Void)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.bodyText = body
        self.capture = capture
        self.ocr = ocr
        self.analysis = analysis
        self.storageQuestion = storageQuestion
        self.resolveStorage = resolveStorage
    }

    public static func == (lhs: ToastState, rhs: ToastState) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.headline == rhs.headline
    }
}

public enum StorageDecision: Equatable {
    case keepInDefaultFolder
    case saveTo(URL)
    case delete
    case ignored            // user dismissed without deciding → service applies default
}
