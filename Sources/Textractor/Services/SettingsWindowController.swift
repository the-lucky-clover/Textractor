import AppKit
import SwiftUI

/// Owns the Settings `NSWindow`. We use an explicit window controller instead of
/// SwiftUI's `Settings` scene because, for an accessory (`LSUIElement`) app,
/// `NSApp.sendAction("showSettingsWindow:")` routes through the responder chain
/// unreliably and often does nothing. Hosting `SettingsView` in our own window
/// (the same approach as `HistoryWindowController`) makes it deterministic.
///
/// **Positioning**: the Settings window is anchored to the menu-bar status
/// item so it appears "directly above" the popover menu — same X column as
/// the popover (centered on the status item), with its top edge flush against
/// the menu bar. Effect: when the user taps "Settings" in the popover, the
/// popover closes and the Settings window opens in exactly the same screen
/// slot, so the experience feels like drilling *down* into a sub-panel of
/// the menu rather than a disconnected dialog floating in space.
@MainActor
final class SettingsWindowController: NSObject {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    /// Show the settings window (creating it on first use), positioning it
    /// directly above the popover via the supplied `anchor` rect (the status
    /// bar item's screen-space frame), then bringing it to the front.
    func show(appState: AppState, anchor: NSRect? = nil) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(appState)
            )
            // Width matches the popover + a few points of breathing room so
            // the stylized scrollbar sits comfortably without compressing the
            // rows. Height is taken from the SwiftUI content once laid out
            // and capped so the window never exceeds the screen.
            let popWidth: CGFloat = 252
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: popWidth, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Settings"
            win.contentViewController = hosting
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            // Stay above normal document/app windows so it doesn't get
            // buried behind whatever the user is reading.
            win.level = .floating
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.preferredContentSize
            let w = popWidth
            let h = min(size.height > 0 ? size.height : 640, 720)
            win.setContentSize(NSSize(width: w, height: h))
            if let anchor {
                positionAbovePopover(win, anchor: anchor)
            } else {
                win.center()
            }
            window = win
        }
        if let win = window {
            if !win.isVisible {
                if let anchor {
                    positionAbovePopover(win, anchor: anchor)
                } else {
                    win.center()
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }

    /// Place `win` directly above the popover menu:
    ///   • horizontally centered on the status item's `midX` (matches the
    ///     popover's X column exactly),
    ///   • top edge flush against the menu bar (i.e. right under the menu
    ///     bar icon, the same vertical band the popover occupies).
    ///
    /// Result: the Settings window visually replaces the popover in place —
    /// the user perceives it as a sub-panel growing downward from the
    /// status item, hence "directly above the popover menu".
    private func positionAbovePopover(_ win: NSWindow, anchor: NSRect) {
        let size = win.frame.size
        var originX = anchor.midX - size.width / 2
        // The popover sits with its TOP at the bottom of the menu bar.
        // We want the Settings window to share that vertical band — its top
        // edge should land roughly where the popover's top edge does.
        var originY = anchor.minY - size.height - 6

        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            originX = min(max(originX, vis.minX), vis.maxX - size.width)
            // If the screen is short and the window would poke above the
            // visible frame, slide its bottom down to the screen bottom.
            let maxY = vis.maxY - size.height
            if originY > maxY { originY = maxY }
            if originY < vis.minY { originY = vis.minY }
        }
        win.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    /// Close the window immediately.
    func close() {
        window?.close()
    }
}
