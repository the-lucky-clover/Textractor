import AppKit
import Foundation

/// Centralised update-checking logic.
///
/// Textractor is currently a local, on-device build with **no remote update
/// channel** configured, so a "check" simply reports the running version. The
/// service is deliberately structured so a future remote endpoint can be slotted
/// in here (e.g. comparing `bundleVersion` against a version feed) without
/// touching the Settings UI or the launch path.
public final class UpdateService {

    public static let shared = UpdateService()

    private init() {}

    // MARK: - Version info

    public static var bundleShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Human-readable version string, e.g. `v2.0.0 (build 2000)`.
    public static var versionDescription: String {
        "v\(bundleShortVersion) (build \(bundleVersion))"
    }

    /// Whether a remote update feed is wired up. Today the app ships as a
    /// self-contained local build, so this is `false`. Flip to `true` (and
    /// implement `fetchLatestVersion`) once a remote channel exists.
    public static var hasRemoteChannel: Bool { false }

    // MARK: - Checking

    /// Present an "up to date" alert describing the running build. Must be
    /// called on the main actor — it blocks on `NSAlert.runModal()`.
    @MainActor
    public func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        if Self.hasRemoteChannel {
            alert.informativeText = "Textractor \(Self.versionDescription) is the latest version."
        } else {
            alert.informativeText = "Textractor \(Self.versionDescription) is the latest local build. " +
                "No remote update channel is configured."
        }
        alert.alertStyle = .informational
        alert.runModal()
    }

    /// A short, human-friendly rendering of the last-check timestamp, or a
    /// placeholder when never checked.
    public static func relativeLastChecked(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
