import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Wraps the OS-level permission checks so the rest of the app can ask
/// `PermissionService.shared.screenRecordingGranted` declaratively.
public final class PermissionService {

    public static let shared = PermissionService()

    public struct Status: Equatable {
        public let screenRecording: Bool
        public let accessibility: Bool

        public var bothGranted: Bool { screenRecording && accessibility }
    }

    private init() {}

    // MARK: - Public

    public var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public var accessibilityGranted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns a struct with both flags.
    public func check() -> Status {
        Status(
            screenRecording: screenRecordingGranted,
            accessibility: accessibilityGranted
        )
    }

    /// Triggers the OS-level permission prompt (one-time) for the missing
    /// permission. Returns true if the request was sent.
    @discardableResult
    public func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Triggers the OS-level prompt for accessibility. Returns true if promp
    /// was honored (the user may still decline).
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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

    /// Opens "Privacy & Security → Accessibility" specifically.
    @MainActor
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
