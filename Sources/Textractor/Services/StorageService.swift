import Foundation
import AppKit
import UniformTypeIdentifiers

/// `StorageService` decides where each capture lands (auto-save folder, trash,
/// or "ask the user").  All file ops happen synchronously off the main queue.
public final class StorageService {

    public static let shared = StorageService()

    private init() {}

    // MARK: - Folder lifecycle

    /// Ensures the default save folder exists. Idempotent.
    @discardableResult
    public func ensureFolder(_ url: URL) -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return true
        } catch {
            LoggerService.shared.error("Folder creation failed: \(url.path)", error: error)
            return false
        }
    }

    /// Move a captured image to the default ~/Pictures/Textractor Screenshots/.
    /// Renames it in `Textractor-YYYY-MM-DD-HHMMSS.png` style.
    public func saveToDefaultFolder(_ capture: CapturedImage) throws -> URL {
        let folder = AppSettings.defaultSaveFolder()
        try ensureSaveFolder(folder)
        return try save(capture, to: folder)
    }

    /// Save to an arbitrary URL, used when the user explicitly picks via NSOpenPanel.
    public func save(_ capture: CapturedImage, to folder: URL) throws -> URL {
        ensureFolder(folder)
        let dest = folder
            .appendingPathComponent(capture.suggestedFilename)
            .appendingPathExtension("png")

        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: capture.fileURL, to: dest)
        return dest
    }

    /// Move `capture` to ~/.Trash and remove the original.
    @discardableResult
    public func trash(_ capture: CapturedImage) -> Bool {
        do {
            let trash = try FileManager.default.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let dest = trash
                .appendingPathComponent(capture.suggestedFilename + ".png")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: capture.fileURL, to: dest)
            return true
        } catch {
            LoggerService.shared.warning("Trash failed: \(error.localizedDescription). Removing capture directly.")
            try? FileManager.default.removeItem(at: capture.fileURL)
            return false
        }
    }

    // MARK: - Async decision flow

    /// Drives the toast/menu decision flow. The caller is expected to feed
    /// user decisions back through `resolvePending(_:)`.
    public func beginDecisionFlow(
        for capture: CapturedImage,
        mode: StorageMode
    ) -> StorageDecisionRequest {
        let request = StorageDecisionRequest(id: UUID(), capture: capture, mode: mode)
        pendingRequests[request.id] = request
        return request
    }

    public func resolvePending(_ decision: StorageDecision, requestID: UUID) {
        guard let request = pendingRequests[requestID] else { return }
        request.continuation?.resume(returning: decision)
        request.markResolved()
        pendingRequests.removeValue(forKey: requestID)
    }

    public func cancelPending(requestID: UUID, with reason: StorageDecision) {
        resolvePending(reason, requestID: requestID)
    }

    // MARK: - Internal state

    private var pendingRequests: [UUID: StorageDecisionRequest] = [:]

    private func ensureSaveFolder(_ folder: URL) throws {
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Pending request

/// Carrier used between AI pipeline and the SwiftUI toast UI.
public final class StorageDecisionRequest: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let capture: CapturedImage
    public let mode: StorageMode
    public var continuation: CheckedContinuation<StorageDecision, Never>?
    public private(set) var isResolved: Bool = false

    init(id: UUID, capture: CapturedImage, mode: StorageMode) {
        self.id = id
        self.capture = capture
        self.mode = mode
    }

    /// Awaitable, used by the pipeline.
    @MainActor
    public func await() async -> StorageDecision {
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    @MainActor
    public func resolve(_ decision: StorageDecision) {
        StorageService.shared.resolvePending(decision, requestID: id)
    }

    /// Mark the request as resolved. Called by `StorageService.resolvePending`.
    fileprivate func markResolved() {
        isResolved = true
    }
}
