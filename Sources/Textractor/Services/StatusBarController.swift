import AppKit
import SwiftUI

/// Owns the menu-bar status item. Replaces SwiftUI's `MenuBarExtra` so we get
/// full control over the click semantics and presentation. **Both left- and
/// right-click open the same legacy-styled `NSPopover`.**
///
/// The icon is the system "text.viewfinder" SF Symbol so it blends with the
/// rest of the macOS menu bar.
@MainActor
public final class StatusBarController: NSObject {

    public let statusItem: NSStatusItem
    public let popover: NSPopover
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
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        guard let coordinator else { return }
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: AnyView(
            MenuContentView(
                appState: coordinator.appState,
                onCaptureRegion: { [weak self] in
                    self?.closePopover()
                    coordinator.startCaptureRegion()
                },
                onCaptureWindow: { [weak self] in
                    self?.closePopover()
                    coordinator.startCaptureWindow()
                },
                onCaptureFullScreen: { [weak self] in
                    self?.closePopover()
                    coordinator.startCaptureFullScreen()
                },
                onOpenSettings: { [weak self] in
                    self?.closePopover()
                    coordinator.openSettings()
                },
                onShowHistory: { [weak self] in
                    self?.closePopover()
                    coordinator.showHistoryWindow()
                },
                onQuit: { [weak self] in
                    self?.closePopover()
                    coordinator.quitApp()
                },
                onClose: { [weak self] in
                    self?.closePopover()
                }
            )
        ))
        // Don't force a fixed height — let the hosting controller size the
        // popover to the SwiftUI content so the whole menu fits with no scroll.
        popover.contentViewController = host
    }

    // MARK: - Click handling

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


    /// The menu-bar button's rectangle in screen coordinates, used to anchor
    /// the Settings window at the same spot as the popover.
    var statusItemScreenRect: NSRect? {
        guard let button = statusItem.button else { return nil }
        return button.window?.convertToScreen(button.frame) ?? button.frame
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    /// Open the popover programmatically (e.g. when the Dock icon is clicked in
    /// menubar-and-dock mode). This reveals the same top menu-bar `MenuContentView`
    /// rather than a separate floating window, so it carries the header, brings
    /// Textractor to the foreground, and its close button works as expected.
    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Open the popover anchored just above the Dock, pointing *down* at the
    /// Textractor Dock icon — the vertical mirror of the menu-bar popover. Uses
    /// only screen geometry (no Accessibility API, so it never triggers a
    /// "access data from other apps" TCC prompt). The pointer sits at the
    /// bottom of the menu and the body floats above the Dock.
    @MainActor func showPopoverFromDock() {
        if popover.isShown { return }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // Anchor a 1pt-tall rect a little above the screen's bottom edge,
        // horizontally centered, and open the popover upward (.maxY) toward it
        // so the pointer ends at the bottom, pointing down at the Dock.
        let anchor = NSRect(
            x: screen.frame.midX - 120,
            y: screen.frame.minY + 4,
            width: 240,
            height: 1
        )
        let anchorView = NSView()
        popover.show(relativeTo: anchor, of: anchorView, preferredEdge: .maxY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Cleanup

    /// Properly removes the status item from the menu bar and cleans up the
    /// popover. Must be called before setting `statusBarController = nil` to
    /// ensure the menu bar icon disappears immediately.
    func cleanup() {
        // Close any open popover first
        if popover.isShown {
            popover.performClose(nil)
        }
        // Clear the button's target/action so it stops receiving events
        if let button = statusItem.button {
            button.target = nil
            button.action = nil
        }
        // Remove the status item from the system status bar
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    deinit {
        // Ensure the status item is removed even if cleanup() wasn't called
        // explicitly (e.g., when switching to .dockOnly mode).
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
