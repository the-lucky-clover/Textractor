import AppKit
import SwiftUI

/// Owns the Settings `NSWindow`. We use an explicit window controller instead of
/// SwiftUI's `Settings` scene because, for an accessory (`LSUIElement`) app,
/// `NSApp.sendAction("showSettingsWindow:")` routes through the responder chain
/// unreliably and often does nothing. Hosting `SettingsView` in our own window
/// (the same approach as `HistoryWindowController`) makes it deterministic.
@MainActor
final class SettingsWindowController: NSObject {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    /// Show the settings window (creating it on first use), centring it and
    /// bringing it to the front.
    func show(appState: AppState) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(appState)
            )
            // Start at a sane size; we resize to the SwiftUI content below so
            // the whole panel fits with no internal scroll.
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Textractor Settings"
            win.contentViewController = hosting
            win.isReleasedWhenClosed = false
            // Size the window to the SwiftUI content so nothing is clipped.
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.preferredContentSize
            let height = size.height > 0 ? size.height : 760
            win.setContentSize(NSSize(width: 900, height: height))
            win.center()
            window = win
        }
        if let win = window {
            if !win.isVisible { win.center() }
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
