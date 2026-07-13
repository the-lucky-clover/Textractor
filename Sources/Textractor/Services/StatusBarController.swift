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

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}
