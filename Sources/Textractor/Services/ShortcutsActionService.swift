import AppKit
import Foundation
import Combine

/// Exposes Textractor's capture modes as Apple Shortcuts actions.
/// This allows users to trigger captures from Siri, the Shortcuts app,
/// automation tools, and other system integrations.
///
/// The Shortcuts app can call the `NSUserActivity`-based actions
/// and also expose them as Siri voice commands.
@MainActor
public final class ShortcutsActionService: ObservableObject {

    public static let shared = ShortcutsActionService()

    private weak var coordinator: AppCoordinator?

    private init() {}

    public func configure(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        registerUserActivities()
    }

    // MARK: - User Activities (Shortcuts Integration)

    private func registerUserActivities() {
        // Register the activities so they appear in Shortcuts
        let activities: [NSUserActivity] = [
            createActivity(
                identifier: "app.textractor.capture.region",
                title: "Capture Region"
            ),
            createActivity(
                identifier: "app.textractor.capture.window",
                title: "Capture Window"
            ),
            createActivity(
                identifier: "app.textractor.capture.fullscreen",
                title: "Capture Full Screen"
            ),
            createActivity(
                identifier: "app.textractor.clipboard.ocr",
                title: "OCR from Clipboard"
            )
        ]

        for activity in activities {
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    private func createActivity(identifier: String, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: identifier)
        activity.title = title
        activity.keywords = [title.lowercased()]
        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch = false
        return activity
    }

    // MARK: - Public Action Handlers

    /// Triggers a region capture (crosshair).
    public func captureRegion() {
        guard let coordinator else { return }
        coordinator.startCaptureRegion()
    }

    /// Triggers a window capture.
    public func captureWindow() {
        guard let coordinator else { return }
        coordinator.startCaptureWindow()
    }

    /// Triggers a full screen capture.
    public func captureFullScreen() {
        guard let coordinator else { return }
        coordinator.startCaptureFullScreen()
    }

    /// OCRs the current clipboard image.
    public func ocrClipboard() async {
        guard let coordinator else { return }
        await ClipboardImageOCRService.shared.processCurrentClipboard()
    }

    /// Opens the history window.
    public func openHistory() {
        guard let coordinator else { return }
        coordinator.showHistoryWindow()
    }

    /// Opens the settings window.
    public func openSettings() {
        guard let coordinator else { return }
        coordinator.openSettings()
    }

    /// Copies the last captured text to the clipboard.
    public func copyLastCapture() -> Bool {
        guard let text = coordinator?.appState.lastAnalysis?.cleanedText
            ?? coordinator?.appState.lastOCR?.joinedText else {
            return false
        }
        return ClipboardService.shared.copy(
            text,
            plainTextOnly: coordinator?.appState.settings.pasteAsPlainText ?? true
        )
    }
}

// MARK: - URL Scheme Handling
// Shortcuts can open URLs like `textractor://capture/region`

extension ShortcutsActionService {

    /// Handle a URL scheme request from Shortcuts or other apps.
    public static func handleURL(_ url: URL) async -> Bool {
        guard url.scheme == "textractor" else { return false }

        switch url.host {
        case "capture":
            switch url.pathComponents.dropFirst().first {
            case "region": ShortcutsActionService.shared.captureRegion(); return true
            case "window": ShortcutsActionService.shared.captureWindow(); return true
            case "fullscreen": ShortcutsActionService.shared.captureFullScreen(); return true
            default: return false
            }
        case "clipboard":
            await ShortcutsActionService.shared.ocrClipboard()
            return true
        case "history":
            ShortcutsActionService.shared.openHistory()
            return true
        case "settings":
            ShortcutsActionService.shared.openSettings()
            return true
        case "copy":
            return ShortcutsActionService.shared.copyLastCapture()
        default: return false
        }
    }
}