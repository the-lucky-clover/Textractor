import Foundation

/// A single persisted capture in the user's history. Stores the raw extracted
/// text and the capture timestamp (screenshots are not retained — history is a
/// text log, independent of the per-capture storage mode).
public struct HistoryRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let textPreview: String
    public let mode: CaptureMode
    /// Average OCR confidence (0.0-1.0), if available.
    public let ocrConfidence: Float?
    /// Absolute path to the retained raw-text `.txt` in the history directory.
    public let textPath: String?
    /// Absolute path to the original screenshot image (PNG).
    /// Used for re-OCR functionality.
    public let imagePath: String?

    public init(
        id: UUID,
        capturedAt: Date,
        textPreview: String,
        mode: CaptureMode,
        ocrConfidence: Float? = nil,
        textPath: String? = nil,
        imagePath: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.textPreview = textPreview
        self.mode = mode
        self.ocrConfidence = ocrConfidence
        self.textPath = textPath
        self.imagePath = imagePath
    }
}
