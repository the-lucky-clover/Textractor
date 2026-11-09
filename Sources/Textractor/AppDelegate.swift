import AppKit
import SwiftUI

/// `AppDelegate` is responsible for application-policy tasks: making the
/// notification system aware of us, ensuring activation policy, and registering
/// the hotkey on first app active.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Injectable lifecycle effects keep launch/reopen regressions independent
    /// of the user's defaults, screen permissions, and persistent capture store.
    @MainActor struct Lifecycle {
        var dockPresence: @MainActor () -> AppSettings.DockPresence = { SettingsStore.shared.current.dockPresence }
        var setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }
        var activate: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
        var bootstrap: @MainActor () -> Void = { AppCoordinator.shared.bootstrap() }
        var presentInterface: (@MainActor () -> Void)?
        var showsLaunchSplash = true
    }

    private let lifecycle: Lifecycle

    /// Retained for the splash's lifetime so its window can be dismissed after
    /// the fade-out finishes (a temporary would be deallocated immediately).
    private var splashController: SplashWindowController?
    private var dockMenuWindow: NSWindow?

    override convenience init() {
        self.init(lifecycle: Lifecycle())
    }

    init(lifecycle: Lifecycle) {
        self.lifecycle = lifecycle
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TEXTRACTOR_UI_TEST_SUITE"]?.hasPrefix("com.textractor.uitest.") == true {
            NSApp.setActivationPolicy(.regular)
            SettingsWindowController.shared.show(appState: AppCoordinator.shared.appState)
            return
        }
        #endif
        // Settings may already have restored .dockOnly/.both while the app
        // graph initialized. Do not overwrite that preference with .accessory.
        lifecycle.setActivationPolicy(SettingsStore.activationPolicy(for: lifecycle.dockPresence()))

        // Bring us to the foreground when needed.
        lifecycle.activate()

        LoggerService.shared.info("App did finish launching")

        // Show a one-time launch splash (fade in → hold → fade out), then
        // bootstrap the menubar once the splash has fully faded out.
        MainActor.assumeIsolated {
            if lifecycle.showsLaunchSplash, let splashImage = SplashWindowController.loadSplashImage() {
                let controller = SplashWindowController()
                self.splashController = controller
                controller.show(image: splashImage) {
                    MainActor.assumeIsolated {
                        self.splashController = nil
                        self.completeLaunch()
                    }
                }
            } else {
                completeLaunch()
            }
        }
    }

    private func completeLaunch() {
        lifecycle.bootstrap()
        // Dock-only mode has no status item, so launch with usable capture
        // controls instead of leaving the user looking for a hidden menu.
        if lifecycle.dockPresence() == .dockOnly {
            presentMainInterface()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        presentMainInterface()
        return false
    }

    private func presentMainInterface() {
        if let present = lifecycle.presentInterface {
            present()
            return
        }
        let coordinator = AppCoordinator.shared
        if let statusBar = coordinator.statusBarController {
            dockMenuWindow?.orderOut(nil)
            statusBar.showPopover()
            return
        }
        if dockMenuWindow == nil {
            let host = NSHostingController(rootView: StatusBarController.menuContent(
                coordinator: coordinator,
                onClose: { [weak self] in self?.dockMenuWindow?.orderOut(nil) }
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 232, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Textractor Pro"
            window.identifier = NSUserInterfaceItemIdentifier("textractor.dock.capture")
            window.isReleasedWhenClosed = false
            window.contentViewController = host
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            window.setContentSize(NSSize(width: 232, height: size.height > 0 ? size.height : 640))
            window.center()
            dockMenuWindow = window
        }
        lifecycle.activate()
        dockMenuWindow?.deminiaturize(nil)
        dockMenuWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar even if no windows are open.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure any debounced UserDefaults writes from the last 250 ms land.
        AppCoordinator.shared.settingsStore.flushPendingPersist()
        ActionShortcuts.shared.unregister()
    }
}
