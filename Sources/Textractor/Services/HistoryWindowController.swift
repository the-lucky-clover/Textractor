import AppKit
import SwiftUI

/// Owns the main "History" `NSWindow`. Created lazily as a singleton and
/// shown/hidden from the menubar menu. The window hosts `HistoryView`, which
/// drives its own intro/closing animations and calls back to actually dismiss.
@MainActor
final class HistoryWindowController: NSObject {

    static let shared = HistoryWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    /// Show the history window (creating it on first use), centring it and
    /// bringing it to the front.
    func show() {
        if window == nil {
            let view = HistoryView { [weak self] in
                self?.close()
            }
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Textractor History"
            win.contentViewController = hosting
            win.minSize = NSSize(width: 560, height: 420)
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        if let win = window {
            if !win.isVisible { win.center() }
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the window immediately.
    func close() {
        window?.close()
    }
}

extension HistoryWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Let the standard close button dismiss without the staggered exit
        // animation (the in-window ✕ button plays that). Either way, close now.
        return true
    }
}
