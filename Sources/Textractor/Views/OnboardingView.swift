import SwiftUI
import AppKit

/// Every step can be skipped; replay never resets settings or requests permissions implicitly.
public struct OnboardingRootView: View {
    let hotkeyLabel: String
    var onComplete: (String?) -> Void
    @State private var step = 0
    @State private var language = "en-US"
    @State private var choseLanguage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hotkeyLabel: String, initialLanguage: String = "en-US", onComplete: @escaping (String?) -> Void) {
        self.hotkeyLabel = hotkeyLabel
        self._language = State(initialValue: initialLanguage)
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Textractor Pro").font(.title2.bold())
                Spacer()
                Text("\(step + 1) of 4").font(.caption.monospacedDigit())
                    .accessibilityIdentifier("onboarding.progress")
            }
            ProgressView(value: Double(step + 1), total: 4).tint(BreakingDad.toxicGreen)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case 0:
                        Label("Capture. Review. Copy.", systemImage: "text.viewfinder").font(.title2.bold())
                        Text("Press \(hotkeyLabel), select text on screen, then paste it wherever you work. Review captures in History. OCR runs on your Mac.")
                        Text("For screenshots, grant Screen Recording when you are ready. Importing an image does not require that permission.")
                    case 1:
                        Label("Choose your recognition language", systemImage: "globe").font(.title2.bold())
                        Picker("Language", selection: $language) {
                            Text("Automatic").tag("")
                            ForEach(AppSettings.ocrLanguageCatalog, id: \.code) { item in
                                Text(item.name).tag(item.code)
                            }
                        }.accessibilityIdentifier("onboarding.language")
                        Text("English (US) uses en-US. Automatic uses languages supported by this Mac. You can change this in Settings.")
                    case 2:
                        Label("Bring your iPhone or iPad", systemImage: "iphone.and.arrow.forward").font(.title2.bold())
                        Text("Choose Import from iPhone or iPad in the capture menu, then Take Photo or Scan Documents in Apple's device menu.")
                        Text("Use the same Apple Account with two-factor authentication. Keep devices nearby with Wi-Fi and Bluetooth enabled. Your Mac must support Continuity Camera.")
                        Text("If no device appears, cancel and import a saved image. This does not require a separate Textractor iOS app.")
                    default:
                        Label("Make it yours", systemImage: "slider.horizontal.3").font(.title2.bold())
                        Text("Settings includes line-break control, QR and barcode recognition, read aloud, additive clipboard, and privacy options. Replay this tour any time from Settings.")
                        Button("Open Screen Recording settings") {
                            PermissionService.shared.openScreenRecordingSettings()
                        }
                        Text("Permission is optional until you capture the screen. Skip now and return later.").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Skip tour") { onComplete(choseLanguage ? language : nil) }
                    .accessibilityIdentifier("onboarding.skip")
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }.accessibilityIdentifier("onboarding.back")
                }
                Button(step == 3 ? "Done" : "Continue") {
                    if step == 1 { choseLanguage = true }
                    if step == 3 { onComplete(choseLanguage ? language : nil) }
                    else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding(28).frame(width: 540, height: 480)
        .background(textractorHeaderBackground).preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: step)
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    static let shared = OnboardingWindowController()

    private var panel: NSPanel?
    /// `true` once we've already completed (Skip / Done / language picked).
    /// Used to ensure the close-button path doesn't double-fire `completion`.
    private var hasFinished = false
    /// Stored completion closure so the window delegation can fire it when
    /// the user closes the panel via the red close button.
    private var pendingCompletion: ((String?) -> Void)?

    /// Convenience entry point that the AppDelegate calls on first launch.
    /// `completion` fires with the chosen language code (`nil` if the user
    /// skipped without picking one).
    func run(completion: @escaping (String?) -> Void) {
        show { code in
            completion(code)
        }
    }

    /// Show the onboarding panel. `completion` fires once when the user
    /// finishes or skips both stages (or dismisses the window via the close
    /// button — which we treat as an implicit Skip).
    func show(completion: @escaping (String?) -> Void) {
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil); return }
        // Latch the completion up front so the close-button delegate path
        // can fire it even if the panel closes before any in-view callback.
        self.hasFinished = false
        self.pendingCompletion = completion

        // Read the resolved hotkey label from the live AppSettings so a
        // user-customized hotkey shortens the cycle; the factory `AppSettings.default`
        // would always show the app's hard-coded default.
        let liveHotkeyLabel = AppCoordinator.shared.appState.settings.resolvedHotkeyLabel
        let view = OnboardingRootView(hotkeyLabel: liveHotkeyLabel, initialLanguage: AppCoordinator.shared.appState.settings.uiLanguage, onComplete: { [weak self] chosen in
            guard let self else { return }
            self.finish(with: chosen)
        })
        let hosting = NSHostingController(rootView: view)
        let size = NSSize(width: 540, height: 480)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = T.s("onboarding.window.title")
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()
        hosting.view.frame = NSRect(origin: .zero, size: size)

        // Become the window's delegate so windowWillClose can clean up if the
        // user dismisses the panel without using an in-view Skip / Done button.
        panel.delegate = self

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let panel {
            panel.delegate = nil
            panel.orderOut(nil)
        }
        panel = nil
    }

    // MARK: - Completion gating

    /// Single completion path used by both the in-view callback and the
    /// close-button path. Whichever fires first runs `completion`; the
    /// other is a no-op.
    private func finish(with chosen: String?) {
        guard !hasFinished else { return }
        hasFinished = true
        let completion = pendingCompletion
        pendingCompletion = nil
        close()
        completion?(chosen)
    }

    // MARK: - NSWindowDelegate

    /// Treat user-initiated dismissals (red close button / ⌘W) as an
    /// implicit Skip so the bootstrap path never gets stuck waiting on an
    /// onboarding result that will never arrive.
    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }
}
