import SwiftUI
import AppKit

/// First-launch onboarding with two skippable stages:
///   1. Language picker — USA + UK pinned at the top-left of the grid.
///   2. Permissions    — Screen Recording status with
///                       "Open System Settings" buttons (the user has to flip
///                       the switch manually since macOS won't grant these
///                       programmatically).
///
/// Tapping Skip on either stage, or completing both, marks onboarding done so
/// it never shows again — even after a factory reset.
public struct OnboardingRootView: View {

    /// Resolved keyboard-shortcut label for the screen-capture hotkey, sourced
    /// from the **live** `AppSettings` (honours the user's custom hotkey, if
    /// any). Captured once at onboarding construction so we don't depend on a
    /// global static that would always fall back to the factory default.
    let hotkeyLabel: String

    /// Called once the user finishes or skips both stages.
    /// `nil` = the user never picked a language (still gets automated OCR).
    var onComplete: (String?) -> Void

    enum Stage: Int, Comparable {
        case tour
        case language
        case permissions
        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let stageOrder: [Stage] = [.tour, .language, .permissions]

    @State private var stage: Stage = .tour
    @State private var chosenLanguage: String? = nil

    public init(hotkeyLabel: String, onComplete: @escaping (String?) -> Void) {
        self.hotkeyLabel = hotkeyLabel
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Stage 1 — tour / what we can do
            if stage == .tour {
                OnboardingTourView(hotkeyLabel: hotkeyLabel) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        stage = .language
                    }
                } onSkip: {
                    onComplete(chosenLanguage)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Stage 2 — language
            if stage == .language {
                OnboardingLanguageView { code in
                    chosenLanguage = code
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        stage = .permissions
                    }
                } onSkip: {
                    onComplete(chosenLanguage)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Stage 3 — permissions
            if stage == .permissions {
                OnboardingPermissionsView {
                    onComplete(chosenLanguage)
                } onBack: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        stage = .language
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(width: 540, height: 480)
        .background(Color(red: 0.043, green: 0.063, blue: 0.039))
        .overlay(alignment: .top) { stageIndicator }
    }

    /// Tiny progress dots at the very top — one per stage in `stageOrder`.
    private var stageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Self.stageOrder, id: \.rawValue) { s in
                Circle()
                    .fill(s == stage ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Stage 1: tour / capable features + keyboard shortcut

private struct OnboardingTourView: View {
    /// Live hotkey label captured at onboarding construction. Always non-empty
    /// because the window controller reads it from the live `AppSettings` at
    /// `show(...)` time.
    var hotkeyLabel: String

    var onContinue: () -> Void
    var onSkip: () -> Void

private var features: [(icon: String, title: String, detail: String)] {
        [
            ("viewfinder",             T.s("onboarding.feature.capture.title"),
                                                       T.s("onboarding.feature.capture.detail")),
            ("text.viewfinder",        T.s("onboarding.feature.ocr.title"),
                                                       T.s("onboarding.feature.ocr.detail")),
            ("sparkles",               T.s("onboarding.feature.ai.title"),
                                                       T.s("onboarding.feature.ai.detail")),
            ("doc.on.clipboard",       T.s("onboarding.feature.clipboard.title"),
                                                       T.s("onboarding.feature.clipboard.detail")),
            ("clock.arrow.circlepath", T.s("onboarding.feature.history.title"),
                                                       T.s("onboarding.feature.history.detail")),
            ("lock.shield",            "Privacy-first & offline",
                                                       "All OCR runs on your Mac. Zero network calls. Your text never leaves this device.")
        ]
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(T.s("onboarding.tour.title")).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.primary)
                Text(T.s("onboarding.tour.subtitle")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 16).padding(.horizontal, 24)

            // The hero shortcut — a single big key cap so the user can't miss it.
            VStack(spacing: 6) {
                Text(T.s("onboarding.tap_anywhere")).font(.system(size: 10, weight: .black, design: .monospaced)).kerning(0.8).foregroundStyle(.tertiary)
                Text(hotkeyLabel)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    )
                Text(T.s("onboarding.pick_capture_paste")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.title) { feature in
                        FeatureRow(icon: feature.icon, title: feature.title, detail: feature.detail)
                    }
                }.padding(.horizontal, 18)
            }

            HStack {
                Spacer()
                Button(T.s("onboarding.skip")) { onSkip() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.secondary.opacity(0.10)))
                    .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.8))
                Button(T.s("onboarding.continue_next")) { onContinue() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.20)))
                    .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 0.8))
                    .padding(.trailing, 16).padding(.bottom, 14)
            }
        }
    }
}

/// Single-capsule row used inside the tour stage.
private struct FeatureRow: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(Color.green.opacity(0.14)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.7))
        )
    }
}

// MARK: - Stage 1: language picker

private struct OnboardingLanguageView: View {

    /// Called with the BCP-47 code the user tapped, or with `nil` if Skip.
    var onPick: (String) -> Void
    var onSkip: () -> Void

    @State private var query: String = ""
    private let pinned: [String] = ["en-US", "en-GB"]

    private var visible: [AppSettings.CatalogEntry] {
        let all = AppSettings.ocrLanguageCatalog
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.code.lowercased().contains(q) ||
            $0.flag.contains(q)
        }
    }
    private var pinnedEntries: [AppSettings.CatalogEntry] {
        AppSettings.ocrLanguageCatalog.filter { pinned.contains($0.code) }
    }
    private var unpinned: [AppSettings.CatalogEntry] {
        visible.filter { !pinned.contains($0.code) }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(T.s("onboarding.language.title"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(T.s("onboarding.language.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField(T.s("onboarding.language.search"), text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(T.s("onboarding.language.top"))
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .kerning(0.6).foregroundStyle(.tertiary)
                        Spacer()
                    }.padding(.horizontal, 16)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(pinnedEntries, id: \.code) { sphere($0, isPinned: true) }
                        ForEach(unpinned, id: \.code)          { sphere($0, isPinned: false) }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }

            HStack {
                Spacer()
                Button(T.s("onboarding.language.skip")) { onSkip() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
                    .overlay(Capsule().stroke(.secondary.opacity(0.5), lineWidth: 0.8))
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder private func sphere(_ entry: AppSettings.CatalogEntry, isPinned: Bool) -> some View {
        Button { onPick(entry.code) } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.white, Color.secondary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: isPinned ? 2 : 0.7)
                        .frame(width: 56, height: 56)
                    Text(entry.flag).font(.system(size: 30))
                }
                Text(entry.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(entry.name)
    }
}

// MARK: - Stage 2: permissions

private struct OnboardingPermissionsView: View {
    var onDone: () -> Void
    var onBack: () -> Void

    @State private var screenGranted: Bool = PermissionService.shared.screenRecordingGranted
    /// A short, transient label rendered after the user lands back from
    /// System Settings (so they can confirm Textractor was added manually).
    @State private var manualGrantHint: String? = nil

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text(T.s("onboarding.permissions.title"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(T.s("onboarding.permissions.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 16)

            VStack(spacing: 10) {
                permissionRow(
                    title: T.s("onboarding.permission.screen_recording.title"),
                    detail: T.s("onboarding.permission.screen_recording.detail"),
                    granted: screenGranted,
                    open: { PermissionService.shared.openScreenRecordingSettings() }
                )
            }
            .padding(.horizontal, 18)

            if let manualGrantHint {
                Text(manualGrantHint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .transition(.opacity)
            }

            // Tiny note on how to grant manually — Screen Recording can't be
            // granted programmatically; the user must flip the switch.
            Text(T.s("onboarding.permissions.manual_hint"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            HStack {
                Button(T.s("onboarding.back")) { onBack() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.secondary.opacity(0.10)))
                    .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.8))
                Spacer()
                Button(screenGranted ? T.s("onboarding.done") : T.s("onboarding.skip")) { onDone() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
                    .overlay(Capsule().stroke(.secondary.opacity(0.5), lineWidth: 0.8))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .onReceive(refreshTimer) { _ in
            let sgr = PermissionService.shared.screenRecordingGranted
            if sgr != screenGranted {
                screenGranted = sgr
                if sgr && manualGrantHint == nil {
                    manualGrantHint = T.s("onboarding.screen_recording_granted")
                }
            }
        }
    }

    @ViewBuilder private func permissionRow(title: String, detail: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(granted ? .green : .yellow)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(T.s("onboarding.open_system_settings")) { open() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.secondary.opacity(0.15)))
                .overlay(Capsule().stroke(.secondary.opacity(0.5), lineWidth: 0.8))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 0.8))
        )
    }
}

// MARK: - Window controller

/// Drives the first-launch onboarding (language + permissions), then dismisses.
/// Both stages are skippable — the user can complete or skip at any point and
/// onboarding is recorded as done.
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
        // Latch the completion up front so the close-button delegate path
        // can fire it even if the panel closes before any in-view callback.
        self.hasFinished = false
        self.pendingCompletion = completion

        // Read the resolved hotkey label from the live AppSettings so a
        // user-customized hotkey shortens the cycle; the factory `AppSettings.default`
        // would always show the app's hard-coded default.
        let liveHotkeyLabel = AppCoordinator.shared.appState.settings.resolvedHotkeyLabel
        let view = OnboardingRootView(hotkeyLabel: liveHotkeyLabel, onComplete: { [weak self] chosen in
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
