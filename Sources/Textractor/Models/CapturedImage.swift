import Foundation
import CoreGraphics

/// In-memory snapshot of a captured screen region, written to disk as a PNG.
///
/// Owns the on-disk URL once persisted, `~/.Library/Caches/Textractor/<uuid>.png`.
public struct CapturedImage: Identifiable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case region
        case window
        case fullscreen
        case video
        case videoURL
        case autoScroll
        case continuityCamera
        case file
        case clipboard
        case hotkey
    }

    public let id: UUID
    public let mode: CaptureMode
    public let origin: Origin
    public let rect: CGRect
    public let fileURL: URL
    public let capturedAt: Date
    public let screenIndex: Int

    public init(
        id: UUID = UUID(),
        mode: CaptureMode,
        origin: Origin,
        rect: CGRect,
        fileURL: URL,
        capturedAt: Date = Date(),
        screenIndex: Int = 0
    ) {
        self.id = id
        self.mode = mode
        self.origin = origin
        self.rect = rect
        self.fileURL = fileURL
        self.capturedAt = capturedAt
        self.screenIndex = screenIndex
    }

    /// Pretty file name suitable for a new user-visible capture export.
    public var suggestedFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Textractor-Pro-\(f.string(from: capturedAt))"
    }
}
