import Foundation
import AppKit
import CoreGraphics
import Combine

/// Wraps the OS-level permission checks so the rest of the app can ask
/// `PermissionService.shared.screenRecordingGranted` declaratively.
///
/// Published as an `ObservableObject` so SwiftUI views can drop their
/// polling timers and react to real change events instead. The display-
/// configuration observer subscribes to
/// `NSApplication.didChangeScreenParametersNotification` — macOS emits
/// this whenever a display is connected, disconnected, or its resolution
/// changes — and re-polls the OS for screen-recording status. Combined
/// with a manual `refresh()` call from the `requestScreenRecording()`
/// prompt path, this gives us authoritative, event-driven updates with
/// no timer.
///
/// Accessibility is intentionally not surfaced here — Textractor no longer
/// auto-pastes, so it has no need for the Accessibility permission.
public final class PermissionService: ObservableObject {

    public static let shared = PermissionService()

    public struct Status: Equatable {
        public let screenRecording: Bool

        public var granted: Bool { screenRecording }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Seed the published value before installing the observer so the
        // first @Published emit isn't a no-op transition.
        self.screenRecordingGranted = CGPreflightScreenCaptureAccess()

        // Observe display-parameter changes (display connect / disconnect /
        // resolution change) and re-poll. The user lands back from System
        // Settings → Privacy → Screen Recording; the OS doesn't notify
        // apps directly when that toggle flips, but a display-config
        // change fires shortly after, which is good enough for our UX
        // and saves us the 1-second polling timer the views used to run.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Also re-poll when the app becomes active — macOS may update the
        // permission state after the user grants it and switches back.
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Public

    /// Published so SwiftUI views can `@ObservedObject` the service and
    /// re-render when the OS-level flag flips. Always reflects the latest
    /// `CGPreflightScreenCaptureAccess()` result.
    @Published public private(set) var screenRecordingGranted: Bool = false

    /// Re-poll the OS for the current screen-recording flag. Cheap — a
    /// single `CGPreflightScreenCaptureAccess` call. Call this after
    /// `requestScreenRecording()` or whenever you want a manual refresh.
    public func refresh() {
        let next = CGPreflightScreenCaptureAccess()
        if next != screenRecordingGranted {
            screenRecordingGranted = next
            LoggerService.shared.info("[permissions] screen-recording granted=\(next)")
        }
    }

    /// Returns a struct with the current screen-recording flag.
    public func check() -> Status {
        Status(screenRecording: CGPreflightScreenCaptureAccess())
    }

    /// Triggers the OS-level permission prompt (one-time) for screen capture.
    /// Returns true if the request was sent. Also kicks a `refresh()` so
    /// any observing view snaps to the new state once the user returns.
    @discardableResult
    public func requestScreenRecording() -> Bool {
        let requested = CGRequestScreenCaptureAccess()
        refresh()
        return requested
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
