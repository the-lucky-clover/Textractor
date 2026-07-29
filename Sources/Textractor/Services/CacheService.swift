import Foundation
import AppKit

/// Owns the `~/Pictures/Textractor Screenshots/` recovery directory. Holds
/// every screenshot Textractor failed to extract so the user can re-run OCR
/// with a different weirdness value (or pick the image up manually).
///
/// This is separate from history. History is text-only; the cache is the
/// "we couldn't read this one — try again" backup. Settings exposes its on-
/// disk size and a delete-everything button.
public final class CacheService {

    public static let shared = CacheService()

    /// Folder for un-trashable captured screenshots (failed OCR).
    public var recoveryFolder: URL { AppSettings.defaultRecoveryFolder() }

    /// Live, computed byte size of the recovery folder.
    public var byteCount: Int {
        Self.directoryBytes(at: recoveryFolder)
    }

    private init() {
        try? FileManager.default.createDirectory(
            at: recoveryFolder,
            withIntermediateDirectories: true
        )
    }

    /// Save a captured image into the recovery folder, returning the on-disk
    /// path. The caller's `capture.fileURL` is removed on success; the file
    /// lives in the recovery folder until either OCR succeeds, the user
    /// Cancels, or the cache is cleared.
    @discardableResult
    public func saveRecoveryImage(_ capture: CapturedImage) throws -> URL {
        try? FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true)
        let dest = recoveryFolder
            .appendingPathComponent(capture.suggestedFilename)
            .appendingPathExtension("png")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: capture.fileURL, to: dest)
        } catch {
            // move can fail if the source is gone (e.g. already trashed). Fall
            // back to copy + delete so recovery still lands the image.
            try FileManager.default.copyItem(at: capture.fileURL, to: dest)
            try? FileManager.default.removeItem(at: capture.fileURL)
        }
        return dest
    }

    /// Trash a file currently in the recovery folder (or anywhere on disk).
    @discardableResult
    public func trash(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return Self.trash(url: url)
    }

    /// Empty the recovery folder. Returns the number of bytes freed.
    @discardableResult
    public func clearCache() -> Int {
        let fm = FileManager.default
        let before = byteCount
        guard let contents = try? fm.contentsOfDirectory(
            at: recoveryFolder,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return 0
        }
        for f in contents {
            _ = Self.trash(url: f)
        }
        return before - byteCount
    }

    /// Open Finder with the recovery image selected.
    public func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Helpers

    /// Recursive sum of the file sizes under `dir`. Symlinks are not followed.
    static func directoryBytes(at dir: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += size
        }
        return total
    }

    @discardableResult
    static func trash(url: URL) -> Bool {
        let fm = FileManager.default
        do {
            let trash = try fm.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let dest = trash.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: url, to: dest)
            return true
        } catch {
            let removed = (try? fm.removeItem(at: url)) != nil
            return removed
        }
    }
}

public extension AppSettings {
    /// Recovery screenshots land here when OCR fails. The folder also doubles
    /// as the user-visible "cache" surface from Settings.
    static func defaultRecoveryFolder() -> URL {
        let pics = (FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        return pics.appendingPathComponent("Textractor Screenshots", isDirectory: true)
    }
}
