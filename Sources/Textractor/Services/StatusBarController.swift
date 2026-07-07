import AppKit
import SwiftUI

/// Owns the menu-bar status item. Replaces SwiftUI's `MenuBarExtra` so we get
/// full control over the click semantics and presentation. **Both left- and
/// right-click open the same legacy-styled `NSPopover`.**
///
/// The icon is the system "text.viewfinder" SF Symbol so it blends with the
/// rest of the macOS menu bar.
@MainActor
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureButton()
        configurePopover()
    }

    // MARK: - Configuration

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "text.viewfinder",
            accessibilityDescription: "Textractor"
        )
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        // Right-click is delivered as a regular mouse-up; both kinds should
        // open the same popover.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        guard let coordinator else { return }
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: AnyView(
            LegacyMenuContentView(coordinator: coordinator)
        ))
        host.view.frame = NSRect(x: 0, y: 0, width: 280, height: 1)
        popover.contentViewController = host
    }

    // MARK: - Click handling

    /// Both left-click and right-click open the same legacy-styled popover —
    /// the user prefers a single opening gesture.
    @objc private func handleClick(_ sender: AnyObject) {
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
