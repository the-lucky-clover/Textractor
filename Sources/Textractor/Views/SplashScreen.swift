import SwiftUI
import AppKit

/// A one-time launch splash: the Textractor logo rendered with rounded corners
/// that fades in from 0 opacity, holds, then fades out to 0 opacity before the
/// menubar is bootstrapped. Shown only on app launch.
///
/// Targets macOS 14.

// MARK: - Timing

private enum SplashTiming {
    static let fadeIn: Double  = 0.25   // 0 → 1 opacity
    static let hold: Double    = 3.0    // logo dwell
    static let fadeOut: Double = 0.25   // 1 → 0 opacity
}

// MARK: - Splash view

private struct SplashView: View {
    let image: NSImage
    var onFinished: () -> Void

    @State private var opacity: Double = 0

    /// Size of the floating splash image.
    private let cardSize = NSSize(width: 460, height: 460)

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .opacity(opacity)
            .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        // Fade in from 0 → 1.
        withAnimation(.easeInOut(duration: SplashTiming.fadeIn)) {
            opacity = 1
        }
        // Hold, then fade out 1 → 0, then dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + SplashTiming.fadeIn + SplashTiming.hold) {
            withAnimation(.easeInOut(duration: SplashTiming.fadeOut)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + SplashTiming.fadeOut + 0.05) {
                onFinished()
            }
        }
    }
}

// MARK: - Window controller

/// Owns the borderless, non-activating splash panel and drives the
/// fade-in/hold/fade-out sequence. `completion` fires once the splash has
/// fully faded out.
@MainActor
final class SplashWindowController {

    private var panel: NSPanel?

    /// Shows the splash. `completion` is called on the main thread after the
    /// fade-out finishes.
    func show(image: NSImage, completion: @escaping () -> Void) {
        let splash = SplashView(image: image) { [weak self] in
            self?.close()
            completion()
        }

        let size = NSSize(width: 460, height: 460)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // System-top level so the splash sits above every other window and
        // app, including full-screen ones.
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = false
        // Stay on screen even if the user switches to another application.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        let hosting = NSHostingView(rootView: splash)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.frame
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        // Bring the app forward, then show the splash above everything.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Image resolution

    /// Loads the bundled splash image resource. Returns `nil` when the resource
    /// is missing (e.g. running the raw `swift build` binary before `build.sh`
    /// copies resources in), in which case the splash is simply skipped.
    static func loadSplashImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "textractor-splash", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
