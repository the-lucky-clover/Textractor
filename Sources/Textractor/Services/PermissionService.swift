import Foundation
import AppKit
import CoreGraphics

/// Wraps the OS-level permission checks so the rest of the app can ask
/// `PermissionService.shared.screenRecordingGranted` declaratively.
///
/// Accessibility is intentionally not surfaced here — Textractor no longer
/// auto-pastes, so it has no need for the Accessibility permission.
public final class PermissionService {

    public static let shared = PermissionService()

    public struct Status: Equatable {
        public let screenRecording: Bool

        public var granted: Bool { screenRecording }
    }

    private init() {}

    // MARK: - Public

    public var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Returns a struct with the current screen-recording flag.
    public func check() -> Status {
        Status(screenRecording: screenRecordingGranted)
    }

    /// Triggers the OS-level permission prompt (one-time) for screen capture.
    /// Returns true if the request was sent.
    @discardableResult
    public func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens the right pane of System Settings so the user can flip the switch.
    @MainActor
    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens "Privacy & Security → Screen Recording" specifically.
    @MainActor
    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
