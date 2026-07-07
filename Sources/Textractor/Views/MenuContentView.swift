import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The popover content shown when the user clicks the men's bar icon.
///
/// Implements all manual capture entry points (Region / Window / Full Screen),
/// recent capture list, drag-and-drop ingestion (Continuity Camera + files),
/// mode toggle, settings, credits, auto-paste indicator, and quit.
public struct MenuContentView: View {

    @ObservedObject var appState: AppState
    var onCaptureRegion: () -> Void
    var onCaptureWindow: () -> Void
    var onCaptureFullScreen: () -> Void
    var onToggleMode: () -> Void
    var onOpenSettings: () -> Void
    var onShowCredits: () -> Void
    var onQuit: () -> Void
    var onShare: (ShareService.Provider) -> Void

    @State private var isDropTargeted: Bool = false

    public init(
        appState: AppState,
        onCaptureRegion: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onCaptureFullScreen: @escaping () -> Void,
        onToggleMode: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onShowCredits: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onShare: @escaping (ShareService.Provider) -> Void
    ) {
        self.appState = appState
        self.onCaptureRegion = onCaptureRegion
        self.onCaptureWindow = onCaptureWindow
        self.onCaptureFullScreen = onCaptureFullScreen
        self.onToggleMode = onToggleMode
        self.onOpenSettings = onOpenSettings
        self.onShowCredits = onShowCredits
        self.onQuit = onQuit
        self.onShare = onShare
    }

    public var body: some View {
        ZStack {
            NeonPalette.noirDeep.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                hotkeyHint
                modeToggle
                captureButtons
                dropZone
                if let toast = appState.toast {
                    ClipboardToastView(
                        appState: appState,
                        toast: toast,
                        onShare: onShare
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
                }
                recent
                bottomBar
            }
            .padding(14)
        }
        .frame(width: 380)
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            BeakerIcon(size: 26, glyphs: ["T","X","T"], style: .neon, showLiquid: true)
                .modifier(NeonGlow.outer(NeonPalette.cyberCyan, radius: 14, opacity: 0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text("TEXTRACTOR")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(NeonPalette.gradientPrimary)
                Text("On-device OCR · privacy-first")
                    .font(NeonFont.mono(9))
                    .foregroundStyle(NeonPalette.inkLow)
            }
            Spacer()
            phaseBadge
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NeonPalette.gradientPrimary, lineWidth: 1.0)
        )
    }

    @ViewBuilder private var phaseBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)
                .modifier(NeonGlow.outer(phaseColor, radius: 6, opacity: 0.9))
            Text(appState.pipelinePhase.label)
                .font(NeonFont.monoCaps(10))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(phaseColor.opacity(0.7), lineWidth: 0.8))
    }

    private var phaseColor: Color {
        switch appState.pipelinePhase {
        case .idle:         return NeonPalette.inkLow
        case .completed:    return NeonPalette.acidLime
        case .failed:       return NeonPalette.hazardRed
        default:            return NeonPalette.cyberCyan
        }
    }

    // MARK: - Hotkey hint

    @ViewBuilder private var hotkeyHint: some View {
        HStack(spacing: 8) {
            kbdChip(icon: "command", label: "⌘")
            kbdChip(icon: "shift", label: "⇧")
            kbdChip(icon: "number", label: "2")
            Spacer()
            Text("Global hotkey — captures anywhere")
                .font(NeonFont.mono(10))
                .foregroundStyle(NeonPalette.inkMid)
        }
        .padding(.horizontal, 4)
    }

    private func kbdChip(icon: String, label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.primary.opacity(0.30), lineWidth: 0.6)
            )
    }

    // MARK: - Mode toggle (manual loop avoids SwiftUI's ForEach overload ambiguity on macOS 14)

    @ViewBuilder private var modeToggle: some View {
        HStack(spacing: 6) {
            let entries = Array(CaptureMode.allCases.enumerated())
            ForEach(entries, id: \.offset) { _, m in
                let active = isCaptureModeActive(m)
                Button {
                    if !active { onToggleMode() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.symbolName)
                        Text(m.label.uppercased())
                    }
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(active ? NeonPalette.noirDeep : NeonPalette.inkMid)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active
                                  ? AnyShapeStyle(NeonPalette.cyberCyan)
                                  : AnyShapeStyle(Material.ultraThinMaterial))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(active ? NeonPalette.cyberCyan : NeonPalette.inkLow.opacity(0.3), lineWidth: 1)
                    )
                    .modifier(NeonGlow.inner(active ? NeonPalette.cyberCyan : .clear, radius: 10, opacity: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isCaptureModeActive(_ m: CaptureMode) -> Bool {
        // For demo purposes use a simple heuristic — the user can tap SPACE in
        // the overlay to switch modes.
        _ = m; return m == .crosshair
    }

    // MARK: - Capture buttons (three)

    @ViewBuilder private var captureButtons: some View {
        VStack(spacing: 8) {
            captureRow(
                title: "Region Capture",
                subtitle: "Freeform crosshair — drag to select",
                icon: "viewfinder",
                tint: NeonPalette.cyberCyan,
                action: onCaptureRegion
            )
            captureRow(
                title: "Window Capture",
                subtitle: appState.settings.windowCaptureAsTable ? "Convert result to a markdown table" : "Click a window to extract all text",
                icon: "macwindow",
                tint: NeonPalette.magentaNeon,
                action: onCaptureWindow
            )
            captureRow(
                title: "Full Screen Capture",
                subtitle: "Iterate entire screen — every text block",
                icon: "rectangle.dashed.badge.record",
                tint: NeonPalette.acidLime,
                action: onCaptureFullScreen
            )
        }
    }

    private func captureRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15))
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(NeonFont.roundedHeadline(12))
                        .foregroundStyle(NeonPalette.inkHigh)
                    Text(subtitle)
                        .font(NeonFont.mono(10))
                        .foregroundStyle(NeonPalette.inkMid)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(tint.opacity(0.7))
                    .font(.system(size: 11, weight: .heavy))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1)
            )
            .modifier(NeonGlow.inner(tint, radius: 10, opacity: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drop zone (image / Continuity Camera)

    @ViewBuilder private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                style: StrokeStyle(
                    lineWidth: 1.6,
                    dash: [4, 4]
                )
            )
            .foregroundStyle(isDropTargeted ? NeonPalette.cyberCyan : NeonPalette.inkMid.opacity(0.6))
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted ? NeonPalette.cyberCyan.opacity(0.10) : Color.clear)
            )
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(NeonPalette.cyberCyan)
                    Text(isDropTargeted
                         ? "Release to extract"
                         : "Drop image · Continuity Camera · pick a file…")
                        .font(NeonFont.monoCaps(10))
                        .foregroundStyle(.primary)
                }
            )
            .onTapGesture { pickFile() }
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDropped(providers: providers)
            }
    }

    private func pickFile() {
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

    private func handleDropped(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    if let img = obj as? NSImage, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).png")
                        let rep = NSBitmapImageRep(cgImage: cg)
                        if let data = rep.representation(using: .png, properties: [:]) {
                            try? data.write(to: url)
                            Task { @MainActor in await AppCoordinator.shared.ingestFile(at: url) }
                        }
                    }
                }
                return true
            }
            if let id = provider.registeredTypeIdentifiers.first {
                provider.loadItem(forTypeIdentifier: id, options: nil) { data, _ in
                    if let url = data as? URL {
                        Task { @MainActor in await AppCoordinator.shared.ingestFile(at: url) }
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Recent

    @ViewBuilder private var recent: some View {
        if !appState.recentCaptures.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RECENT EXTRACTIONS")
                        .font(NeonFont.monoCaps(9))
                        .foregroundStyle(NeonPalette.inkLow)
                    Spacer()
                    Text("\(appState.streakCount) in session")
                        .font(NeonFont.mono(9))
                        .foregroundStyle(NeonPalette.acidLime)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.recentCaptures.prefix(6)) { entry in
                            recentRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private func recentRow(_ entry: RecentCaptureEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sentimentTint(entry.sentiment))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.textPreview.prefix(60))
                    .font(NeonFont.mono(10))
                    .foregroundStyle(NeonPalette.inkHigh)
                    .lineLimit(1)
                Text(entry.capturedAt, style: .time)
                    .font(NeonFont.mono(9))
                    .foregroundStyle(NeonPalette.inkLow)
            }
            Spacer()
            Image(systemName: entry.mode.symbolName)
                .foregroundStyle(NeonPalette.inkLow)
                .font(.system(size: 9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NeonPalette.glass)
        )
    }

    private func sentimentTint(_ s: AIInferenceService.Sentiment?) -> Color {
        guard let s else { return NeonPalette.inkLow }
        switch s {
        case .positive: return NeonPalette.acidLime
        case .negative: return NeonPalette.hazardRed
        case .neutral:  return NeonPalette.cyberCyan
        case .mixed:    return NeonPalette.holoViolet
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            Divider().background(NeonPalette.inkLow.opacity(0.3))
            HStack {
                Button(action: onOpenSettings) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Settings")
                    }
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onShowCredits) {
                    Image(systemName: "heart.circle.fill")
                        .foregroundStyle(NeonPalette.magentaNeon)
                }
                .buttonStyle(.plain)
                .help("Made with ❤️ by Lucky Clover")

                Spacer()

                Button(action: onQuit) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.hazardRed)
                }
                .buttonStyle(.plain)
            }
            permissionRow
        }
    }

    @ViewBuilder private var permissionRow: some View {
        let status = PermissionService.shared.check()
        HStack(spacing: 8) {
            permissionChip(
                ok: status.screenRecording,
                label: "Screen Recording"
            )
            permissionChip(
                ok: status.accessibility,
                label: "Accessibility"
            )
            Spacer()
            if !status.bothGranted {
                Button("Open Settings") {
                    PermissionService.shared.openPrivacySettings()
                }
                .font(NeonFont.monoCaps(9))
                .buttonStyle(.plain)
                .foregroundStyle(NeonPalette.amberLaser)
            }
        }
    }

    private func permissionChip(ok: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text(label)
        }
        .font(NeonFont.monoCaps(9))
        .foregroundStyle(ok ? NeonPalette.acidLime : NeonPalette.hazardRed)
    }
}
