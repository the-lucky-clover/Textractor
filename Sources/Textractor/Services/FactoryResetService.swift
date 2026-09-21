import Foundation
import AppKit

/// One-shot factory reset. Wipes settings, history, custom vocabulary,
/// cached captures, and recovery images. **Cannot** re-prompt for TCC
/// permissions from inside the app — the user must hand-walk that in
/// System Settings (Screen Recording / Accessibility / etc.) after the
/// reset, because macOS does not let apps re-trigger their own prompts.
///
/// Used by the Settings → "Reset Textractor to factory defaults…" button,
/// which guards with a confirmation dialog so the user always sees what
/// they're about to lose before it runs.
public enum FactoryResetService {

    public struct Report {
        public let settingsReset: Bool
        public let capturesDeleted: Int
        public let cacheFreedBytes: Int
        public let historyCleared: Bool
        public let vocabCleared: Bool
    }

    /// Run the full reset on the main actor. Returns a report describing
    /// what was actually wiped (so the UI can summarize it).
    @MainActor
    @discardableResult
    public static func run(appState: AppState) -> Report {
        LoggerService.shared.info("[factory-reset] starting")

        // 1. Settings → defaults (clears uiLanguage, customVocabulary, ahoyMode, etc.)
        appState.resetSettingsToDefaults()
        let settingsReset = true

        // 2. Capture store (SwiftData) — delete every record.
        var capturesDeleted = 0
        do {
            let before = CaptureStore.shared.totalCount
            try CaptureStore.shared.deleteAll()
            capturesDeleted = before
        } catch {
            LoggerService.shared.warning("[factory-reset] deleteAll failed: \(error.localizedDescription)")
        }

        // 3. Cache folder — empty `~/.Library/Caches/Textractor/`.
        let cacheFreedBytes = CacheService.shared.clearCache()

        // 4. In-memory history list (the UI's "recent captures" sidebar).
        appState.recentCaptures.removeAll()
        appState.streakCount = 0
        appState.lastCapture = nil
        appState.lastOCR = nil
        appState.lastAnalysis = nil

        // 5. Reset hotkey registration (so it picks up any new defaults).
        HotkeyManager.shared.register()

        LoggerService.shared.info("[factory-reset] complete — captures=\(capturesDeleted), bytesFreed=\(cacheFreedBytes)")

        return Report(
            settingsReset: settingsReset,
            capturesDeleted: capturesDeleted,
            cacheFreedBytes: cacheFreedBytes,
            historyCleared: true,
            vocabCleared: true
        )
    }
}
