import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The popover content shown when the user clicks the men's bar icon.
/// 
/// Plain system chrome — a quiet, legacy macOS menu list with the Textractor
/// wordmark banner pinned to the top. No neon palette, no glow, no gradients:
/// just short rows, system dividers, and the default system font.
public struct MenuContentView: View {

    @ObservedObject var appState: AppState
    var onCaptureRegion: () -> Void
    var onCaptureWindow: () -> Void
    var onCaptureFullScreen: () -> Void
    var onOpenSettings: () -> Void
    var onShowHistory: () -> Void
    var onQuit: () -> Void
    var onClose: () -> Void

    public init(
        appState: AppState,
        onCaptureRegion: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onCaptureFullScreen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onShowHistory: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.appState = appState
        self.onCaptureRegion = onCaptureRegion
        self.onCaptureWindow = onCaptureWindow
        self.onCaptureFullScreen = onCaptureFullScreen
        self.onOpenSettings = onOpenSettings
        self.onShowHistory = onShowHistory
        self.onQuit = onQuit
        self.onClose = onClose
    }

    /// Popover header background — R:13 G:16 B:11 (shared with Settings).
    private static let headerBackground = textractorHeaderBackground

    /// Drives the staggered fly-in / scale-up / fade intro. Reset on close so
    /// the animation replays every time the popover opens.
    @State private var appeared = false

    public var body: some View {
        VStack(spacing: 0) {
            // Banner pinned to the top of the popover.  Width is the banner's
            // natural image size with 5 points of breathing room on either side
            // so the popover edges hug the artwork instead of clipping it.
            banner
                .background(Self.headerBackground)
                .introReveal(0, appeared: appeared)

            // The full menu — sized to fit the popover with no internal scroll.
            // Quit is pinned below so it's always visible.
            VStack(alignment: .leading, spacing: 1) {
                sectionLabel("Capture").introReveal(1, appeared: appeared)
                MenuRow("Region",      icon: "viewfinder")                     { onClose(); onCaptureRegion() }
                    .introReveal(2, appeared: appeared)
                MenuRow("Window",      icon: "macwindow")                      { onClose(); onCaptureWindow() }
                    .introReveal(3, appeared: appeared)
                MenuRow("Full Screen", icon: "rectangle.dashed.badge.record") { onClose(); onCaptureFullScreen() }
                    .introReveal(4, appeared: appeared)

                sectionLabel("Library").introReveal(5, appeared: appeared)
                MenuRow("Pick Image File…", icon: "photo.on.rectangle") { pickImageFile() }
                    .introReveal(6, appeared: appeared)
                MenuRow("History",          icon: "clock.arrow.circlepath") { onClose(); onShowHistory() }
                    .introReveal(7, appeared: appeared)

                sectionLabel("App").introReveal(8, appeared: appeared)
                MenuRow("Settings…",         icon: "gearshape")         { onClose(); onOpenSettings() }
                    .introReveal(9, appeared: appeared)
            }
            .padding(.horizontal, 8)
            .padding(.top, 0)
            .padding(.bottom, 4)

            // Quit is pinned to the bottom of the popover — always reachable
            // without scrolling.
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
                .introReveal(10, appeared: appeared)
            MenuRow("Quit Textractor", icon: "power", role: .destructive) { onClose(); onQuit() }
                .introReveal(11, appeared: appeared)
                .padding(.horizontal, 8)

            // Subtle version footer for visual closure — also pinned, never cut.
            Text(UpdateService.versionDescription)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .introReveal(12, appeared: appeared)
        }
        .background(Self.headerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: bannerWidth)  // popover hugs banner edge-to-edge
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Banner

    /// The Textractor wordmark banner pinned to the very top. A single banner —
    /// no separate text header — sized to fill the popover width with rounded
    /// corners. This is the only branding element in the popover.
    private var bannerAspect: CGFloat { 344.0 / 1280.0 }
    /// Desired banner image width. The banner takes the full popover content
    /// width minus 5 points of horizontal padding on each side (total 10).
    private var bannerWidth: CGFloat { 232 }
    /// Banner is rendered slightly larger (5%) and bled past the popover edges
    /// so its sides fill the gaps and the top sits flush with the popover top.
    private var bannerDisplayWidth: CGFloat { bannerWidth * 1.05 }
    /// Height derived from the banner's natural image aspect ratio.
    private var bannerHeight: CGFloat { bannerWidth * bannerAspect * 0.95 }

    @ViewBuilder private var banner: some View {
        if let nsImage = loadBannerImage() {
            ShimmerBanner(image: nsImage, width: bannerDisplayWidth, height: bannerHeight * 1.05, animate: !AppCoordinator.shared.appState.settings.reduceMotion)
                .frame(maxWidth: .infinity, alignment: .center)
                // Bleed the banner to the popover edges: center it horizontally
                // so it spills 5/2% on each side, and push the top to the popover
                // top so there are no gaps above or beside the artwork.
                .offset(x: 0, y: -(bannerDisplayWidth - bannerWidth) / 2)
        }
    }

    // MARK: - Helpers

    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                Task { @MainActor in
                    await AppCoordinator.shared.ingestFile(at: url)
                }
            }
        }
    }

    private func checkForUpdates() {
        appState.updateSettings { $0.lastUpdateCheckAt = Date() }
        UpdateService.shared.presentUpToDateAlert()
    }
}

// MARK: - Row primitive

/// A flat, single-line menu row with a leading SF Symbol and title. On hover it
/// fills with the system accent (or red for destructive rows) and its content
/// turns white — matching the native macOS menu highlight idiom.
private struct MenuRow: View {

    enum Role { case normal, destructive }

    let title: String
    let icon: String
    var role: Role = .normal
    let action: () -> Void

    @State private var isHovered: Bool = false

    init(_ title: String, icon: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }

    private var accent: Color { role == .destructive ? .red : .accentColor }
    private var baseTitleColor: Color { role == .destructive ? .red : .primary }
    private var baseIconColor: Color { role == .destructive ? .red : .secondary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isHovered ? Color.white : baseIconColor)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isHovered ? Color.white : baseTitleColor)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Intro reveal (staggered fly-in / scale-up / fade)

/// framer-motion–style staggered entrance. Each element flies up, scales up, and
/// fades in, delayed by its `index` so the popover assembles top-to-bottom.
private struct IntroReveal: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94, anchor: .center)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .spring(response: 0.44, dampingFraction: 0.78)
                    .delay(Double(index) * 0.035),
                value: appeared
            )
    }
}

private extension View {
    func introReveal(_ index: Int, appeared: Bool) -> some View {
        modifier(IntroReveal(index: index, appeared: appeared))
    }
}
