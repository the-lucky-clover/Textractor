import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings window styled to match the menubar popover: same 252pt width, same
/// system typography, same dark rounded background. Branded with the shimmer
/// banner (no second header) and Breaking Dad toxic-green accents. Elements fly
/// in once with a framer-motion-style intro (disabled when Reduce Motion is on).
public struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @State private var firstLoad: Bool = false
    @State private var confirmFactoryReset: Bool = false
    @State private var confirmClearHistory = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var lastFactoryReset: FactoryResetService.Report?

    public init() {}

    private static let headerBackground = textractorHeaderBackground
    private var appeared: Bool { firstLoad }
    private var reduceMotion: Bool { appState.settings.reduceMotion || systemReduceMotion }
    /// Observable binding to `PermissionService`. Drops the previous
    /// `Timer.publish(...).autoconnect()` poll — the service now updates
    /// its `@Published` flag in response to display-config events.
    @ObservedObject private var permissions = PermissionService.shared
    private var screenRecordingGranted: Bool { permissions.screenRecordingGranted }

    // MARK: - Banner

    private let bannerWidth: CGFloat = 252
    private var banner: some View {
        ProductBanner(width: bannerWidth, animate: !reduceMotion)
    }

    public var body: some View {
        VStack(spacing: 0) {
            banner
                .background(Self.headerBackground)
                .introReveal(0, appeared: firstLoad, animate: !reduceMotion)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Replay welcome tour") { AppCoordinator.shared.replayOnboarding() }
                        .accessibilityIdentifier("settings.onboarding.replay")
                        .padding(.horizontal, 10).padding(.vertical, 8)

                    // Permissions at top ONLY if not yet granted — critical for capture to work
                    if !screenRecordingGranted {
                        sectionLabel(T.s("section.permissions")).introReveal(1, appeared: firstLoad, animate: !reduceMotion)
                        permissionRow(open: { PermissionService.shared.openScreenRecordingSettings() })
                            .introReveal(1, appeared: firstLoad, animate: !reduceMotion)
                    }

                    sectionLabel(T.s("section.ai")).introReveal(screenRecordingGranted ? 1 : 2, appeared: firstLoad, animate: !reduceMotion)
                    weirdnessBlock.introReveal(screenRecordingGranted ? 1 : 2, appeared: firstLoad, animate: !reduceMotion)
                    Row(T.s("reset.defaults"), icon: "arrow.counterclockwise.circle.fill") { resetDefaults() }
                        .introReveal(screenRecordingGranted ? 1 : 2, appeared: firstLoad, animate: !reduceMotion)

sectionLabel(T.s("language")).introReveal(screenRecordingGranted ? 2 : 3, appeared: firstLoad, animate: !reduceMotion)
            languagePicker.introReveal(screenRecordingGranted ? 2 : 3, appeared: firstLoad, animate: !reduceMotion)
            
            // Keep unavailable functionality explicit; never offer simulated output.
            if TranslationService.isAvailable {
            // MARK: - Snip-to-translate (auto-detect source, pick target)
            ToggleRow(
                title: T.s("translate.after.capture"),
                icon: "arrow.left.arrow.right",
                isOn: translateAfterCaptureBinding
            )
            .introReveal(screenRecordingGranted ? 2 : 3, appeared: firstLoad, animate: !reduceMotion)
            
            Picker(selection: translationTargetBinding) {
                Text(T.s("translation.target.automatic")).tag("")
                ForEach(TranslationService.supportedTargets, id: \.code) { loc in
                    Text("\(loc.name)").tag(loc.code)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                        .foregroundStyle(BreakingDad.toxicGreen)
                    Text(T.s("translation.target"))
                        .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .pickerStyle(.menu)
            .introReveal(screenRecordingGranted ? 2 : 3, appeared: firstLoad, animate: !reduceMotion)

            } else {
                Text(T.s("translation.unavailable"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }

                    sectionLabel(T.s("section.formatting")).introReveal(screenRecordingGranted ? 3 : 4, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("paste.plain"), icon: "doc.on.clipboard", isOn: pasteAsPlainTextBinding)
                        .introReveal(screenRecordingGranted ? 3 : 4, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("flatten.text"), icon: "paragraph", isOn: flattenBinding)
                        .introReveal(screenRecordingGranted ? 3 : 4, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("table.markdown"), icon: "tablecells", isOn: windowCaptureBinding)
                        .introReveal(screenRecordingGranted ? 3 : 4, appeared: firstLoad, animate: !reduceMotion)

                    CaptureOptionsView()

                    sectionLabel(T.s("section.updates")).introReveal(screenRecordingGranted ? 4 : 5, appeared: firstLoad, animate: !reduceMotion)
                    updatesBlock.introReveal(screenRecordingGranted ? 4 : 5, appeared: firstLoad, animate: !reduceMotion)

                    sectionLabel(T.s("section.privacy")).introReveal(screenRecordingGranted ? 5 : 6, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("privacy.pii"), icon: "eye.slash", isOn: piiBinding)
                        .introReveal(screenRecordingGranted ? 5 : 6, appeared: firstLoad, animate: !reduceMotion)
                    piiStatusRow.introReveal(screenRecordingGranted ? 5 : 6, appeared: firstLoad, animate: !reduceMotion)

                    sectionLabel(T.s("section.history")).introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)
                    Row(T.s("history.open"), icon: "clock.arrow.circlepath") { AppCoordinator.shared.showHistoryWindow() }
                        .introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)
                    historyLimitBlock.introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)
                    Row(T.s("history.clear"), icon: "trash", role: .destructive) { confirmClearHistory = true }
                        .accessibilityIdentifier("settings.history.clear")
                        .introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)
                    Row(T.s("history.cache.clear"), icon: "tray.2", role: .destructive) { CacheService.shared.clearCache() }
                        .introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)
                    cacheSizeRow.introReveal(screenRecordingGranted ? 6 : 7, appeared: firstLoad, animate: !reduceMotion)

                    // Permissions section — shown alphabetically when already granted
                    if screenRecordingGranted {
                        sectionLabel(T.s("section.permissions")).introReveal(7, appeared: firstLoad, animate: !reduceMotion)
                        permissionRow(open: { PermissionService.shared.openScreenRecordingSettings() })
                            .introReveal(7, appeared: firstLoad, animate: !reduceMotion)
                    }

                    sectionLabel(T.s("section.behaviour")).introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("reduce.motion"), icon: "decrease.quote.glass", isOn: reduceMotionBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("telemetry"), icon: "chart.bar", isOn: telemetryBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("knowledge.mode"), icon: "brain.head.profile", isOn: knowledgeModeBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("extended.logging"), icon: "doc.text.magnifyingglass", isOn: extendedLoggingBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    ToggleRow(title: T.s("menubar.color.icon"), icon: "paintpalette", isOn: menubarColorIconBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)

                    ToggleRow(title: T.s("auto.save.captures"), icon: "square.and.arrow.down", isOn: autoSaveCapturesBinding)
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)

                    // Hidden easter-egg: Ahoy Mode. Decorates toasts / menu copy
                    // with pirate flavor (real OCR + clipboard output untouched).
                    ToggleRow(
                        title: PirateStrings.flavor("settings.ahoy.toggle", plain: T.s("settings.ahoy.toggle"), ahoy: appState.settings.ahoyMode),
                        icon: "sailboat.fill",
                        isOn: ahoyBinding
                    )
                    .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    if appState.settings.ahoyMode {
                        Text(PirateStrings.flavor("settings.ahoy.help", plain: T.s("settings.ahoy.help"), ahoy: true))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 36)
                            .padding(.bottom, 4)
                    }

                    // Factory reset — wipes settings, history, vocab, cache. The
                    // user must re-grant TCC permissions in System Settings by
                    // hand; the OS does not let apps re-prompt themselves.
                    Row(
                        PirateStrings.flavor("settings.factory.reset", plain: T.s("settings.factory.reset"), ahoy: appState.settings.ahoyMode),
                        icon: "exclamationmark.octagon.fill",
                        role: .destructive
                    ) {
                        confirmFactoryReset = true
                    }
                    .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    // Open log folder button
                    if appState.settings.extendedLoggingEnabled {
                        Row(T.s("settings.open.log.folder"), icon: "folder.badge.gearshape") {
                            openLogFolder()
                        }
                        .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)
                    }

                    // Dock Presence picker — label on row 1, picker menu below and to the right
                    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(BreakingDad.toxicGreen)
            Text(T.s("settings.dock.title"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
        HStack(spacing: 10) {
            Spacer(minLength: 20) // indent: icon placeholder
            Menu {
                ForEach(AppSettings.DockPresence.allCases, id: \.self) { presence in
                    Button(presence.displayName) {
                        dockPresenceBinding.wrappedValue = presence
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(appState.settings.dockPresence.displayName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .menuStyle(.borderlessButton)
        }
    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.secondary.opacity(0.04))
                    )
                    .introReveal(screenRecordingGranted ? 8 : 7, appeared: firstLoad, animate: !reduceMotion)

                    sectionLabel(T.s("section.about")).introReveal(screenRecordingGranted ? 9 : 8, appeared: firstLoad, animate: !reduceMotion)
                    aboutBlockV2.introReveal(screenRecordingGranted ? 9 : 8, appeared: firstLoad, animate: !reduceMotion)
                }
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 560)
        }
        .background(Self.headerBackground)
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: bannerWidth)
        .accessibilityIdentifier("settings.root")
        .confirmationDialog(T.s("history.clear.confirm"), isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(T.s("history.clear"), role: .destructive) { HistoryStore.shared.clearAll() }
            Button(T.s("settings.factory.confirm.cancel"), role: .cancel) {}
        }
        .onAppear {
            firstLoad = true
        }
        .confirmationDialog(
            Text(PirateStrings.flavor("settings.factory.confirm.title", plain: T.s("settings.factory.confirm.title"), ahoy: appState.settings.ahoyMode)),
            isPresented: $confirmFactoryReset,
            titleVisibility: .visible
        ) {
            Button(
                PirateStrings.flavor("settings.factory.confirm.action", plain: T.s("settings.factory.confirm.action"), ahoy: appState.settings.ahoyMode),
                role: .destructive
            ) {
                runFactoryReset()
            }
            Button(T.s("settings.factory.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(PirateStrings.flavor("settings.factory.confirm.body", plain: T.s("settings.factory.confirm.body"), ahoy: appState.settings.ahoyMode))
        }
    }

    // MARK: - Section label (matches the popover exactly)

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kerning(0.6)
            .foregroundStyle(BreakingDad.chalk.opacity(0.72))
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI & extraction

    private var weirdnessBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text(T.s("weirdness.label"))
                    .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(Int(appState.settings.weirdness * 100))%")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(BreakingDad.toxicGreen)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            Slider(value: weirdnessBinding, in: 0...1).accentColor(BreakingDad.toxicGreen)
                .padding(.horizontal, 10)
            Text(T.s("weirdness.help"))
                .font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
    }

    // MARK: - Language (single source of truth for UI + OCR)

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(T.s("language"), systemImage: "globe")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BreakingDad.chalk)
            Picker(T.s("language"), selection: languageBinding) {
                Text(T.s("language.automatic")).tag("")
                if !appState.settings.uiLanguage.isEmpty,
                   !AppSettings.availableOCRLanguages.contains(where: { $0.code == appState.settings.uiLanguage }) {
                    Text(appState.settings.uiLanguage + " (unavailable on this Mac)").tag(appState.settings.uiLanguage).disabled(true)
                }
                ForEach(AppSettings.availableOCRLanguages, id: \.code) { loc in
                    Text(loc.name).tag(loc.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("settings.language")
            Text(appState.settings.uiLanguage.isEmpty
                 ? T.s("language.automatic.help")
                 : T.s("language.selected.help", args: appState.settings.uiLanguage))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(BreakingDad.chalk.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.language.status")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(BreakingDad.deepGreen.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(BreakingDad.toxicGreen.opacity(0.35)))
    }

    // MARK: - History & Privacy blocks

    private var piiStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.settings.piiRedactionEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                .foregroundStyle(appState.settings.piiRedactionEnabled ? Color.green : Color.red)
            Text(appState.settings.piiRedactionEnabled
                 ? T.s("privacy.pii.redacted")
                 : T.s("privacy.pii.permit"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(appState.settings.piiRedactionEnabled ? Color.green : Color.red)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
    }

    private var historyLimitBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text(String(format: T.s("history.limit"), appState.settings.historyEntryLimit))
                    .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            Slider(value: historyLimitBinding,
                   in: Double(AppSettings.historyLimitRange.lowerBound)...Double(AppSettings.historyLimitRange.upperBound),
                   step: 10)
                .accentColor(BreakingDad.toxicGreen)
                .padding(.horizontal, 10)
        }
    }

    private var cacheSizeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.2")
                .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                .foregroundStyle(BreakingDad.toxicGreen)
            Text("\(T.s("history.cache.label")) \(cacheSizeDescription)")
                .font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
    }

    private var cacheSizeDescription: String {
        let bytes = CacheService.shared.byteCount
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Updates

    private var updatesBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 13, weight: .medium)).frame(width: 20, alignment: .center)
                    .foregroundStyle(BreakingDad.toxicGreen)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(T.s("version.label"))  \(UpdateService.versionDescription)")
                        .font(.system(size: 13, weight: .regular)).foregroundStyle(.primary)
                    Text("\(T.s("version.last_checked")) \(UpdateService.relativeLastChecked(appState.settings.lastUpdateCheckAt))")
                        .font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { checkForUpdates() } label: {
                    Text(T.s("version.check_now")).font(.system(size: 11, weight: .semibold)).foregroundStyle(BreakingDad.toxicGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
    }

    private func checkForUpdates() {
        UpdateService.shared.presentUpToDateAlert()
    }

    // MARK: - About (footer)

private var aboutBlockV2: some View {
        VStack(spacing: 16) {
            Divider()
                .foregroundStyle(.white.opacity(0.08))

            // 1) Pulsing heart icon — centered, its own row
            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BreakingDad.toxicGreen)
                .symbolEffect(.pulse, options: .repeat(3), value: firstLoad && !reduceMotion)

// 2) Tagline + sub — stacked vertically, full width breathing room
            VStack(alignment: .center, spacing: 4) {
                Text(T.s("about.tagline"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(T.s("about.sub"))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // 3) Credits — "Made with <3 by Lucky Clover"
            HStack(spacing: 6) {
                Text(T.s("about.made_with"))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("<3")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(BreakingDad.cautionOrange)

                Button {
                    if let url = URL(string: "https://soundcloud.com/lucky-clover") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Lucky Clover")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BreakingDad.toxicGreen)
                        .underline()
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)

            // 4) Version footer — its own row, full width
            Text(T.s("about.version", args: UpdateService.versionDescription))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
    private var piiBinding: Binding<Bool> {
        Binding(get: { appState.settings.piiRedactionEnabled },
                set: { v in appState.updateSettings { $0.piiRedactionEnabled = v } })
    }
    private var historyLimitBinding: Binding<Double> {
        Binding(get: { Double(appState.settings.historyEntryLimit) },
                set: { v in
                    let clamped = max(AppSettings.historyLimitRange.lowerBound,
                                      min(AppSettings.historyLimitRange.upperBound, Int(v)))
                    appState.updateSettings { $0.historyEntryLimit = clamped }
                    HistoryStore.shared.enforceLimit(clamped)
                })
    }
    private var languageBinding: Binding<String> {
        Binding(get: { appState.settings.uiLanguage },
                set: { v in appState.updateSettings { $0.uiLanguage = v } })
    }
    private var dockPresenceBinding: Binding<AppSettings.DockPresence> {
        Binding(get: { appState.settings.dockPresence },
                set: { v in appState.updateSettings { $0.dockPresence = v } })
    }
    private var knowledgeModeBinding: Binding<Bool> {
        Binding(get: { appState.settings.knowledgeModeEnabled },
                set: { v in appState.updateSettings { $0.knowledgeModeEnabled = v } })
    }
    private var extendedLoggingBinding: Binding<Bool> {
        Binding(get: { appState.settings.extendedLoggingEnabled },
                set: { v in appState.updateSettings { $0.extendedLoggingEnabled = v } })
    }
    private var menubarColorIconBinding: Binding<Bool> {
        Binding(get: { appState.settings.menubarColorIcon },
                set: { v in
                    appState.updateSettings { $0.menubarColorIcon = v }
                    // Reconfigure the status bar icon immediately
                    StatusBarController.shared?.reconfigureIcon()
                })
    }
    private var ahoyBinding: Binding<Bool> {
        Binding(get: { appState.settings.ahoyMode },
                set: { v in appState.updateSettings { $0.ahoyMode = v } })
    }
    private var translateAfterCaptureBinding: Binding<Bool> {
        Binding(get: { appState.settings.translateAfterCapture },
                set: { v in appState.updateSettings { $0.translateAfterCapture = v } })
    }
    private var translationTargetBinding: Binding<String> {
        Binding(get: { appState.settings.translationTargetLanguage },
                set: { v in appState.updateSettings { $0.translationTargetLanguage = v } })
    }
    private var autoSaveCapturesBinding: Binding<Bool> {
        Binding(get: { appState.settings.autoSaveCaptures },
                set: { v in appState.updateSettings { $0.autoSaveCaptures = v } })
    }

    private func openLogFolder() {
        LoggerService.shared.openLogFolder()
    }

    private func resetDefaults() {
        appState.resetSettingsToDefaults()
    }

    private func runFactoryReset() {
        lastFactoryReset = FactoryResetService.run(appState: appState)
    }

    // MARK: - Permissions

    @ViewBuilder private func permissionRow(open: @escaping () -> Void) -> some View {
        let granted = screenRecordingGranted
        let tint: Color = granted ? Color.green : Color.red
        let statusText = granted ? T.s("permission.granted") : T.s("permission.denied")
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.25)).frame(width: 16, height: 16)
                Circle().fill(tint).frame(width: 9, height: 9)
                    .shadow(color: tint.opacity(0.95), radius: granted ? 5 : 2)
                    .shadow(color: tint.opacity(0.7), radius: granted ? 9 : 3)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(T.s("permission.screen_recording")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text(statusText).font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 8)
            Button(T.s("permission.open"), action: open)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .buttonStyle(.plain)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(.secondary.opacity(0.15)))
                .overlay(Capsule().stroke(.secondary.opacity(0.5), lineWidth: 0.8))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(granted ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 0.8))
        )
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
                    .fixedSize(horizontal: false, vertical: true)
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
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(BreakingDad.toxicGreen)
        .accessibilityLabel(title)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(BreakingDad.deepGreen.opacity(0.12)))
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
    let animate: Bool
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
            .offset(y: appeared ? 0 : 10)
            .animation(animate ? .spring(response: 0.44, dampingFraction: 0.78).delay(Double(index) * 0.04) : nil, value: appeared)
    }
}

private extension View {
    func introReveal(_ index: Int, appeared: Bool, animate: Bool) -> some View {
        modifier(IntroReveal(index: index, appeared: appeared, animate: animate))
    }
}
