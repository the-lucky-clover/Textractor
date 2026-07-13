import Foundation

/// A single persisted capture in the user's history. Stores the extracted text
/// plus a copy of the screenshot PNG so the history window can show thumbnails
/// across app launches (independent of the per-capture storage mode).
public struct HistoryRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let textPreview: String
    public let mode: CaptureMode
    /// Absolute path to the copied screenshot PNG in the history directory.
    /// `nil` when no screenshot could be retained (e.g. an already-deleted file).
    public let screenshotPath: String?

    public init(
        id: UUID,
        capturedAt: Date,
        textPreview: String,
        mode: CaptureMode,
        screenshotPath: String?
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.textPreview = textPreview
        self.mode = mode
        self.screenshotPath = screenshotPath
    }
}
