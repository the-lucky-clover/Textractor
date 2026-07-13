import AppKit

/// `AppDelegate` is responsible for application-policy tasks: making the
/// notification system aware of us, ensuring activation policy, and registering
/// the hotkey on first app active.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Retained for the splash's lifetime so its window can be dismissed after
    /// the fade-out finishes (a temporary would be deallocated immediately).
    private var splashController: SplashWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure we're a real accessory app (no Dock icon).
        NSApp.setActivationPolicy(.accessory)

        // Bring us to the foreground when needed.
        NSApp.activate(ignoringOtherApps: true)

        LoggerService.shared.info("App did finish launching")

        // Show a one-time launch splash (fade in → hold → fade out), then
        // bootstrap the menubar once the splash has fully faded out.
        MainActor.assumeIsolated {
            if let splashImage = SplashWindowController.loadSplashImage() {
                let controller = SplashWindowController()
                self.splashController = controller
                controller.show(image: splashImage) {
                    MainActor.assumeIsolated {
                        self.splashController = nil
                        AppCoordinator.shared.bootstrap()
                    }
                }
            } else {
                AppCoordinator.shared.bootstrap()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar even if no windows are open.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure any debounced UserDefaults writes from the last 250 ms land.
        AppCoordinator.shared.settingsStore.flushPendingPersist()
        HotkeyManager.shared.unregister()
    }
}
