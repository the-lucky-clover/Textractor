import Foundation
import AppKit

/// Minimal disk I/O for Textractor's captured screenshots.
///
/// Explicit removal and recovery helpers. The active pipeline retains success
/// images in temporary storage for history re-OCR, and moves failed images to
/// the recovery folder. Recovery removal is offered in the failure toast and
/// Settings → Clear cache.
public final class StorageService {

    public static let shared = StorageService()

    private init() {}

    /// Trash a captured image, or remove it when the system Trash is unavailable.
    /// Returns false when neither operation succeeds.
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
