import AppKit
import SwiftUI
import Combine

/// Presents the capture-confirmation toast as a floating, non-activating panel
/// pinned to the top-right of the main display. It reacts to `AppState.toast`
/// (`nil` = hidden), fades in/out, and never steals focus from the app the user
/// was working in. Clicking **Copy** re-copies the full extracted text.
@MainActor
final class ToastWindowController: NSObject {

    static let shared = ToastWindowController()

    private var window: NSPanel?
    private var cancellable: AnyCancellable?
    private weak var appState: AppState?

    override private init() { super.init() }

    /// Begin observing the toast state. Call once during bootstrap.
    func configure(appState: AppState) {
        self.appState = appState
        cancellable = appState.$toast
            .receive(on: RunLoop.main)
            .sink { [weak self] toast in
                guard let self else { return }
                if let toast {
                    self.present(toast)
                } else {
                    self.dismiss()
                }
            }
    }

    // MARK: - Presentation

    private func present(_ toast: ToastState) {
        let root = ClipboardToastView(
            appState: appState!,
            toast: toast,
            onShare: { [weak self] provider in
                guard let self else { return }
                let text = self.appState?.toast?.analysis?.cleanedText
                    ?? self.appState?.toast?.bodyText
                    ?? ""
                AppCoordinator.shared.share(text: text, via: provider)
            },
            onCopy: { [weak self] in
                guard let self, let text = self.fullText else { return }
                _ = ClipboardService.shared.copy(
                    text,
                    plainTextOnly: self.appState?.settings.pasteAsPlainText ?? false
                )
                SoundManager.playClick()
            }
        )

        // Update in place if the panel is already on screen.
        if let win = window,
           let hosting = win.contentViewController as? NSHostingController<ClipboardToastView> {
            hosting.rootView = root
            resizeAndReposition(win, hosting: hosting)
            return
        }

        let hosting = NSHostingController(rootView: root)
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        win.hidesOnDeactivate = false
        win.contentViewController = hosting
        resizeAndReposition(win, hosting: hosting)
        win.orderFront(nil)
        win.contentView?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.contentView?.animator().alphaValue = 1
        }
        window = win
    }

    private var fullText: String? {
        appState?.toast?.analysis?.cleanedText ?? appState?.lastAnalysis?.cleanedText
    }

    private func resizeAndReposition(_ win: NSPanel, hosting: NSHostingController<ClipboardToastView>) {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.preferredContentSize
        let w = size.width > 0 ? size.width : 360
        let h = size.height > 0 ? size.height : 160
        win.setContentSize(NSSize(width: w, height: h))
        position(win)
    }

    private func position(_ win: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = win.frame.size
        let x = visible.maxX - size.width - 16
        let y = visible.maxY - size.height - 8
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Dismissal

    private func dismiss() {
        guard let win = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.contentView?.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }
}
