import AppKit

/// `AppDelegate` is responsible for application-policy tasks: making the
/// notification system aware of us, ensuring activation policy, and registering
/// the hotkey on first app active.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure we're a real accessory app (no Dock icon).
        NSApp.setActivationPolicy(.accessory)

        // Bring us to the foreground when needed.
        NSApp.activate(ignoringOtherApps: true)

        LoggerService.shared.info("App did finish launching")

        // Fallback: also call coordinator bootstrap here in case SwiftUI's
        // `init` had no chance to call it (e.g., scene-only builds).
        AppCoordinator.shared.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar even if no windows are open.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
