import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings window styled to match the menubar popover: same 232pt width, same
/// system typography (10pt section labels / 13pt rows), same dark rounded
/// background. Branded with the shimmer banner (no second header) and Breaking
/// Dad toxic-green accents. Elements fly in once with a framer-motion-style
/// intro (disabled when Reduce Motion is on). All prefs bind to `AppState`.
public struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @State private var aiVocabText: String = ""
    /// Drives the one-time fly-in / scale-up / fade intro.
    @State private var firstLoad: Bool = false

    public init() {}

    private static let headerBackground = textractorHeaderBackground
    private var animate: Bool { !appState.settings.reduceMotion && firstLoad }

    // MARK: - Banner (identical geometry to the menubar popover)

    private let bannerWidth: CGFloat = 232
    private var bannerAspect: CGFloat { 344.0 / 1280.0 }
    private var bannerDisplayWidth: CGFloat { bannerWidth * 1.05 }
    private var bannerHeight: CGFloat { bannerWidth * bannerAspect * 0.95 }

    @ViewBuilder private var banner: some View {
        if let nsImage = loadBannerImage() {
            ShimmerBanner(
                image: nsImage,
                width: bannerDisplayWidth,
                height: bannerHeight,
                animate: !appState.settings.reduceMotion
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: -(bannerDisplayWidth - bannerWidth) / 2)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            banner
                .background(Self.headerBackground)
                .introReveal(0, appeared: animate)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    sectionLabel("AI & Extraction").introReveal(1, appeared: animate)
                    weirdnessBlock.introReveal(1, appeared: animate)
                    vocabularyBlock.introReveal(1, appeared: animate)
                    Row("Reset to defaults", icon: "arrow.counterclockwise.circle.fill") { resetDefaults() }
                        .introReveal(1, appeared: animate)

                    sectionLabel("Sharing").introReveal(2, appeared: animate)
                    ToggleRow(title: "Paste as plain text", icon: "doc.on.clipboard", isOn: pasteAsPlainTextBinding)
                        .introReveal(2, appeared: animate)
                    Text("QUICK-SHARE CHIPS")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .kerning(0.6).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                        .introReveal(2, appeared: animate)
                    ForEach(QuickShareTarget.allCases) { target in
                        ToggleRow(title: target.label, icon: target.sfSymbol, isOn: quickShareBinding(target))
                            .introReveal(2, appeared: animate)
                    }

                    sectionLabel("Window Captures").introReveal(3, appeared: animate)
                    ToggleRow(title: "Convert to markdown tables", icon: "tablecells", isOn: windowCaptureBinding)
                        .introReveal(3, appeared: animate)

                    sectionLabel("Updates").introReveal(4, appeared: animate)
                    updatesBlock.introReveal(4, appeared: animate)

                    sectionLabel("History").introReveal(5, appeared: animate)
                    Row("Open History", icon: "clock.arrow.circlepath") { AppCoordinator.shared.showHistoryWindow() }
                        .introReveal(5, appeared: animate)

                    sectionLabel("Behaviour").introReveal(6, appeared: animate)
                    ToggleRow(title: "Flatten text (no line breaks)", icon: "paragraph", isOn: flattenBinding)
                        .introReveal(6, appeared: animate)
                    ToggleRow(title: "Reduce motion", icon: "decrease.quote.glass", isOn: reduceMotionBinding)
                        .introReveal(6, appeared: animate)
                    ToggleRow(title: "Local telemetry log", icon: "chart.bar", isOn: telemetryBinding)
                        .introReveal(6, appeared: animate)

                    sectionLabel("About").introReveal(7, appeared: animate)
                    aboutBlock.introReveal(7, appeared: animate)
                }
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 560)
        }
        .background(Self.headerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: bannerWidth)
        .onAppear {
            aiVocabText = appState.settings.customVocabulary.joined(separator: ", ")
            if !appState.settings.reduceMotion { firstLoad = true }
        }
    }

    // MARK: - Section label (matches the popover exactly)

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

    // MARK: - AI & extraction

    private var weirdnessBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text("Inference weirdness")
                    .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(Int(appState.settings.weirdness * 100))%")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(BreakingDad.toxicGreen)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            Slider(value: weirdnessBinding, in: 0...1).accentColor(BreakingDad.toxicGreen)
                .padding(.horizontal, 10)
            Text("0% strict · 100% aggressive correction & more retries.")
                .font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
    }

    private var vocabularyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "textformat")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text("Custom vocabulary (comma-separated)")
                    .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 10).padding(.top, 4)
            TextField("e.g. Textractor, visionOS, FRC", text: $aiVocabText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
            Row("Save vocabulary", icon: "checkmark") { commitVocab() }
        }
    }

    private func resetDefaults() {
        appState.resetSettingsToDefaults()
        aiVocabText = ""
    }

    // MARK: - Updates

    private var updatesBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Version  \(UpdateService.versionDescription)")
                        .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                    Text("Last checked: \(UpdateService.relativeLastChecked(appState.settings.lastUpdateCheckAt))")
                        .font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { checkForUpdates() } label: {
                    Text("Check now").font(.system(size: 11, weight: .semibold)).foregroundStyle(BreakingDad.toxicGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
    }

    private func checkForUpdates() {
        appState.updateSettings { $0.lastUpdateCheckAt = Date() }
        UpdateService.shared.presentUpToDateAlert()
    }

    // MARK: - About

    private var aboutBlock: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                .foregroundStyle(BreakingDad.toxicGreen)
            VStack(alignment: .leading, spacing: 0) {
                Text("Textractor · on-device OCR").font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                Text("Built for your privacy and your eyes.").font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.open(URL(string: "https://soundcloud.com/lucky-clover")!)
            } label: {
                Text("by Lucky Clover").font(.system(size: 11, weight: .semibold)).foregroundStyle(BreakingDad.toxicGreen).underline()
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    // MARK: - Bindings

    private var weirdnessBinding: Binding<Double> {
        Binding(get: { appState.settings.weirdness },
                set: { v in appState.updateSettings { $0.weirdness = v } })
    }
    private var pasteAsPlainTextBinding: Binding<Bool> {
        Binding(get: { appState.settings.pasteAsPlainText },
                set: { v in appState.updateSettings { $0.pasteAsPlainText = v } })
    }
    private var windowCaptureBinding: Binding<Bool> {
        Binding(get: { appState.settings.windowCaptureAsTable },
                set: { v in appState.updateSettings { $0.windowCaptureAsTable = v } })
    }
    private var flattenBinding: Binding<Bool> {
        Binding(get: { appState.settings.flattenText },
                set: { v in appState.updateSettings { $0.flattenText = v } })
    }
    private var reduceMotionBinding: Binding<Bool> {
        Binding(get: { appState.settings.reduceMotion },
                set: { v in appState.updateSettings { $0.reduceMotion = v } })
    }
    private var telemetryBinding: Binding<Bool> {
        Binding(get: { appState.settings.localTelemetryEnabled },
                set: { v in appState.updateSettings { $0.localTelemetryEnabled = v } })
    }
    private func quickShareBinding(_ target: QuickShareTarget) -> Binding<Bool> {
        Binding(
            get: { appState.settings.quickShareTargets.contains(target) },
            set: { v in appState.updateSettings { current in
                if v { current.quickShareTargets.insert(target) } else { current.quickShareTargets.remove(target) }
            } }
        )
    }

    private func commitVocab() {
        let tokens = aiVocabText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        appState.updateSettings { $0.customVocabulary = tokens }
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
                    $0.saveFolderBookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
            }
        }
    }
}

// MARK: - Row (matches the popover menu row)

private struct Row: View {
    enum Role { case normal, destructive }
    let title: String
    let icon: String
    var role: Role = .normal
    let action: () -> Void
    @State private var isHovered: Bool = false

    init(_ title: String, icon: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.role = role; self.action = action
    }

    private var accent: Color { role == .destructive ? .red : BreakingDad.toxicGreen }
    private var baseTitle: Color { role == .destructive ? .red : .primary }
    private var baseIcon: Color { role == .destructive ? .red : BreakingDad.toxicGreen }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isHovered ? Color.white : baseIcon)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isHovered ? Color.white : baseTitle)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovered ? accent : Color.clear))
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

// MARK: - Toggle row

private struct ToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(isHovered ? Color.white : BreakingDad.toxicGreen)
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? Color.white : .primary)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).toggleStyle(BdToggleStyle()).labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovered ? BreakingDad.toxicGreen : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Breaking Dad toggle style

struct BdToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.label
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { configuration.isOn.toggle() }
            } label: {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isOn ? BreakingDad.toxicGreen : BreakingDad.chalk.opacity(0.22))
                    .frame(width: 34, height: 20)
                    .overlay(
                        Circle()
                            .fill(configuration.isOn ? Color.black.opacity(0.85) : BreakingDad.chalk.opacity(0.7))
                            .frame(width: 14, height: 14)
                            .offset(x: configuration.isOn ? 7 : -7)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - One-time intro (framer-motion-style fly-in / scale-up / fade)

private struct IntroReveal: ViewModifier {
    let index: Int
    let appeared: Bool
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.44, dampingFraction: 0.78).delay(Double(index) * 0.04), value: appeared)
    }
}

private extension View {
    func introReveal(_ index: Int, appeared: Bool) -> some View {
        modifier(IntroReveal(index: index, appeared: appeared))
    }
}
