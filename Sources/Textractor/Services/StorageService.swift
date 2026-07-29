import Foundation
import AppKit

/// Minimal disk I/O for Textractor's captured screenshots.
///
/// In Textractor 2.x the only lifecycle is:
///   • On OCR success: trash the temp file via `trash(_:)`.
///   • On OCR failure: move the temp file into the recovery folder so the
///     user can re-run OCR / pick it up manually. Removal is offered in the
///     recovery toast's "Cancel" button and in Settings → Clear cache.
public final class StorageService {

    public static let shared = StorageService()

    private init() {}

    /// Move a captured image to `~/.Trash` and remove the original. Returns
    /// `true` on success (the file is gone from disk either way).
    @discardableResult
    public func trash(_ capture: CapturedImage) -> Bool {
        CacheService.trash(url: capture.fileURL)
    }

    /// Move a captured image into the recovery folder so the user can later
    /// retry OCR on it. Returns the on-disk path of the recovery copy.
    @discardableResult
    public func saveAsRecoveryCopy(_ capture: CapturedImage) throws -> URL {
        try CacheService.shared.saveRecoveryImage(capture)
    }
}
