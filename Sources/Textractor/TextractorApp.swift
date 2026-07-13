import SwiftUI
import AppKit

@main
struct TextractorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared

    // NOTE: Do NOT call `AppCoordinator.bootstrap()` here. It is invoked once
    // from `AppDelegate.applicationDidFinishLaunching`. Calling it from both
    // paths previously produced two menu-bar status items.

    var body: some Scene {
        // The menu-bar entry point is owned by `StatusBarController` (an
        // `NSStatusItem`), initialized inside `AppCoordinator.bootstrap()`.
        // We intentionally do NOT use SwiftUI `MenuBarExtra` here because:
        //   • `MenuBarExtra` does not support right-click context menus.
        //   • `MenuBarExtra(.window)` defaults to a heavily-styled custom
        //     popover; we want a plain legacy macOS popover.
        // See `Sources/Textractor/Services/StatusBarController.swift`.

        // Built-in Settings scene wired to the global ⌘, shortcut (auto-created
        // by AppKit even though we are LSUIElement).  SwiftUI also picks this
        // up when `openSettings()` is called from any view.
        Settings {
            SettingsView()
                .environmentObject(coordinator.appState)
        }
    }
}
