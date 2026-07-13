import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon.HIToolbox

/// Window-pane settings UI (rendered inside the App's `Settings { ... }` scene
/// binding). Implements every global option the user requested.
public struct SettingsView: View {

    @EnvironmentObject var appState: AppState

    @State private var aiVocabText: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            NeonPalette.noirDeep
                .ignoresSafeArea()
                .overlay(NeonPalette.scanlines)
            ScrollView {
                VStack(spacing: 12) {
                    header
                    captureSection
                    aiSection
                    sharingSection
                    windowTableSection
                    permissionsSection
                    creditsSection
                    footer
                }
                .padding(16)
                .frame(maxWidth: 560)
            }
        }
        .frame(width: 600, height: 740)
        .onAppear {
            aiVocabText = appState.settings.customVocabulary.joined(separator: ", ")
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 14) {
            BeakerIcon.hero(size: 56)
                .modifier(NeonGlow.outer(NeonPalette.cyberCyan, radius: 22, opacity: 0.6))
            VStack(alignment: .leading, spacing: 4) {
                Text("Textractor Settings")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(NeonPalette.gradientPrimary)
                Text("On-device OCR · privacy-first")
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.inkMid)
            }
            Spacer()
        }
    }

    // MARK: - Capture section

    @ViewBuilder private var captureSection: some View {
        SettingsCard(title: "Screenshots", icon: "rectangle.dashed.badge.record", tinkle: NeonPalette.cyberCyan) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(StorageMode.allCases) { mode in
                    storageModeRow(mode)
                }
                if appState.settings.storageMode == .safe || appState.settings.storageMode == .safeOnlyScreenshot {
                    folderRow
                }
            }
        }
    }

    private func storageModeRow(_ mode: StorageMode) -> some View {
        let active = appState.settings.storageMode == mode
        return Button {
            appState.updateSettings { $0.storageMode = mode }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(active ? NeonPalette.cyberCyan : NeonPalette.inkLow.opacity(0.5), lineWidth: 1.2)
                        .frame(width: 18, height: 18)
                    if active {
                        Circle()
                            .fill(NeonPalette.cyberCyan)
                            .frame(width: 10, height: 10)
                            .modifier(NeonGlow.outer(NeonPalette.cyberCyan, radius: 8, opacity: 0.9))
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: mode.symbolName)
                        Text(mode.label)
                    }
                    .font(NeonFont.roundedHeadline(13))
                    .foregroundStyle(active ? NeonPalette.inkHigh : NeonPalette.inkMid)
                    Text(mode.description)
                        .font(NeonFont.mono(10))
                        .foregroundStyle(NeonPalette.inkLow)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? NeonPalette.cyberCyan.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var folderRow: some View {
        let path = appState.settings.saveFolderPath ?? AppSettings.defaultSaveFolder().path
        return HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(NeonPalette.amberLaser)
            VStack(alignment: .leading, spacing: 1) {
                Text("Default folder")
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.inkMid)
                Text(path)
                    .font(NeonFont.mono(10))
                    .foregroundStyle(NeonPalette.inkHigh)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button("Choose…") { chooseFolder() }
                .font(NeonFont.monoCaps(10))
                .foregroundStyle(NeonPalette.cyberCyan)
                .buttonStyle(.plain)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(NeonPalette.inkMid)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                appState.updateSettings {
                    $0.saveFolderPath = url.path
                    $0.saveFolderBookmark = try? url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
            }
        }
    }

    // MARK: - AI section

    @ViewBuilder private var aiSection: some View {
        SettingsCard(title: "AI & extraction", icon: "sparkles", tinkle: NeonPalette.magentaNeon) {
            VStack(alignment: .leading, spacing: 14) {
                weirdnessRow
                vocabularyRow
                HStack {
                    Spacer()
                    Button {
                        appState.resetSettingsToDefaults()
                        aiVocabText = ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text("Reset to defaults")
                        }
                        .font(NeonFont.monoCaps(11))
                        .foregroundStyle(NeonPalette.amberLaser)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var weirdnessRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(NeonPalette.magentaNeon)
                Text("Inference weirdness")
                    .font(NeonFont.roundedHeadline(13))
                Spacer()
                Text("\(Int(appState.settings.weirdness * 100))%")
                    .font(NeonFont.monoCaps(11))
                    .foregroundStyle(NeonPalette.magentaNeon)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { appState.settings.weirdness },
                    set: { v in appState.updateSettings { $0.weirdness = v } }
                ),
                in: 0.0...1.0
            )
            .accentColor(NeonPalette.magentaNeon)

            Text("0% strict & conservative · 100% aggressive correction, more retries, larger vocab influence.  Increase if text keeps failing.")
                .font(NeonFont.mono(10))
                .foregroundStyle(NeonPalette.inkLow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var vocabularyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "textformat")
                    .foregroundStyle(NeonPalette.holoViolet)
                Text("Custom vocabulary (comma-separated)")
                    .font(NeonFont.roundedHeadline(12))
            }
            TextField("e.g. Textractor, visionOS, FRC", text: $aiVocabText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitVocab() }
            HStack {
                Spacer()
                Button("Save vocabulary") { commitVocab() }
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.holoViolet)
                    .buttonStyle(.plain)
            }
        }
    }

    private func commitVocab() {
        let tokens = aiVocabText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        appState.updateSettings { $0.customVocabulary = tokens }
    }

    // MARK: - Sharing section

    @ViewBuilder private var sharingSection: some View {
        SettingsCard(title: "Sharing", icon: "square.and.arrow.up", tinkle: NeonPalette.acidLime) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { appState.settings.autoPasteEnabled },
                    set: { v in appState.updateSettings { $0.autoPasteEnabled = v } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-paste into active app")
                            .font(NeonFont.roundedHeadline(13))
                        Text("After copying, synthesise ⌘V into the frontmost app. Requires Accessibility permission.")
                            .font(NeonFont.mono(10))
                            .foregroundStyle(NeonPalette.inkLow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().background(NeonPalette.inkLow.opacity(0.3))
                Text("Quick-share chips")
                    .font(NeonFont.monoCaps(11))
                    .foregroundStyle(NeonPalette.inkMid)
                ForEach(QuickShareTarget.allCases) { target in
                    sharingRow(target)
                }
            }
        }
    }

    private func sharingRow(_ target: QuickShareTarget) -> some View {
        let active = appState.settings.quickShareTargets.contains(target)
        return Button {
            appState.updateSettings { current in
                if current.quickShareTargets.contains(target) {
                    current.quickShareTargets.remove(target)
                } else {
                    current.quickShareTargets.insert(target)
                }
            }
        } label: {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? NeonPalette.acidLime : NeonPalette.inkLow.opacity(0.5), lineWidth: 1.4)
                        .frame(width: 16, height: 16)
                    if active {
                        Image(systemName: "checkmark")
                            .foregroundStyle(NeonPalette.acidLime)
                            .font(.system(size: 10, weight: .heavy))
                    }
                }
                Image(systemName: target.sfSymbol)
                    .foregroundStyle(active ? NeonPalette.acidLime : NeonPalette.inkLow)
                Text(target.label)
                    .font(NeonFont.roundedHeadline(13))
                    .foregroundStyle(active ? NeonPalette.inkHigh : NeonPalette.inkMid)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window → table section

    @ViewBuilder private var windowTableSection: some View {
        SettingsCard(title: "Window captures", icon: "tablecells", tinkle: NeonPalette.amberLaser) {
            Toggle(isOn: Binding(
                get: { appState.settings.windowCaptureAsTable },
                set: { v in appState.updateSettings { $0.windowCaptureAsTable = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convert window captures to markdown tables")
                        .font(NeonFont.roundedHeadline(13))
                    Text("When alignment looks tabular (rows of consistent columns), Textractor exports a Markdown table instead of flat text.")
                        .font(NeonFont.mono(10))
                        .foregroundStyle(NeonPalette.inkLow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Permissions

    @ViewBuilder private var permissionsSection: some View {
        SettingsCard(title: "Permissions", icon: "checkmark.shield", tinkle: NeonPalette.acidLime) {
            let status = PermissionService.shared.check()
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    label: "Screen Recording",
                    ok: status.screenRecording,
                    approve: { PermissionService.shared.requestScreenRecording() },
                    open: { PermissionService.shared.openScreenRecordingSettings() }
                )
                permissionRow(
                    label: "Accessibility",
                    ok: status.accessibility,
                    approve: { PermissionService.shared.requestAccessibility() },
                    open: { PermissionService.shared.openAccessibilitySettings() }
                )
            }
        }
    }

    private func permissionRow(
        label: String,
        ok: Bool,
        approve: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? NeonPalette.acidLime : NeonPalette.hazardRed)
            Text(label)
                .font(NeonFont.roundedHeadline(13))
                .foregroundStyle(.primary)
            Spacer()
            if !ok {
                Button("Approve", action: approve)
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.acidLime)
                    .buttonStyle(.plain)
            }
            Button("System Settings", action: { open() })
                .font(NeonFont.monoCaps(10))
                .foregroundStyle(NeonPalette.cyberCyan)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ok ? NeonPalette.acidLime.opacity(0.06) : NeonPalette.hazardRed.opacity(0.06))
        )
    }

    // MARK: - Credits

    @ViewBuilder private var creditsSection: some View {
        SettingsCard(title: "About", icon: "heart.fill", tinkle: NeonPalette.magentaNeon) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Textractor v1.0.0 · on-device")
                        .font(NeonFont.mono(11))
                        .foregroundStyle(.primary)
                    Text("Built with care for your privacy and your eyes.")
                        .font(NeonFont.mono(10))
                        .foregroundStyle(NeonPalette.inkLow)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://soundcloud.com/lucky-clover")!)
                } label: {
                    HStack(spacing: 4) {
                        Text("Made with")
                            .font(NeonFont.mono(11))
                        Text("❤️")
                        Text("by Lucky Clover")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .underline()
                    }
                    .foregroundStyle(NeonPalette.gradientPrimary)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { appState.settings.localTelemetryEnabled },
                set: { v in appState.updateSettings { $0.localTelemetryEnabled = v } }
            )) {
                Text("Local writing of telemetry log to disk")
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.inkMid)
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { appState.settings.festiveFeedback },
                set: { v in appState.updateSettings { $0.festiveFeedback = v } }
            )) {
                Text("Festive nudges in toast")
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(NeonPalette.inkMid)
            }
        }
    }
}

// MARK: - Settings card

struct SettingsCard<Content: View>: View {
    var title: String
    var icon: String
    var tinkle: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(tinkle)
                Text(title.uppercased())
                    .font(NeonFont.monoCaps(11))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content()
                .padding(.horizontal, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tinkle.opacity(0.7), tinkle.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .modifier(NeonGlow.outer(tinkle, radius: 14, opacity: 0.35))
    }
}
