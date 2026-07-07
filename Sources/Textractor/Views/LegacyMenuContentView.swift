import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Legacy macOS popover content shown when the user clicks the menu-bar icon.
///
/// Plain system chrome — no neon palette, no glow, no gradients. Layout follows
/// the standard macOS Settings/control-panel idiom: short rows, system
/// dividers, default body font. Both left- and right-click on the menu-bar
/// icon open this same view.
struct LegacyMenuContentView: View {

    let coordinator: AppCoordinator
    @ObservedObject var appState: AppState

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.appState = coordinator.appState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuRow("Capture Region",      icon: "viewfinder")                   { triggerTap { coordinator.startCaptureRegion() } }
            MenuRow("Capture Window",      icon: "macwindow")                    { triggerTap { coordinator.startCaptureWindow() } }
            MenuRow("Capture Full Screen", icon: "rectangle.dashed.badge.record") { triggerTap { coordinator.startCaptureFullScreen() } }

            Divider().padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { appState.settings.autoPasteEnabled },
                set: { v in appState.updateSettings { $0.autoPasteEnabled = v } }
            )) {
                Text("Auto-paste after capture")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 4)

            Divider().padding(.vertical, 4)

            MenuRow("Pick Image File…",    icon: "photo.on.rectangle") { SoundManager.playClick(); LegacyMenuContentView.pickImageFile() }
            MenuRow("Settings…",           icon: "gearshape")          { SoundManager.playClick(); coordinator.openSettings() }
            MenuRow("Check for Updates",   icon: "arrow.up.circle")    { SoundManager.playClick(); checkForUpdates() }

            Divider().padding(.vertical, 4)

            MenuRow("Quit Textractor",     icon: "power", key: "q") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 260)
    }

    // MARK: - Helpers

    private func triggerTap(_ action: () -> Void) {
        SoundManager.playClick()
        action()
    }

    static func pickImageFile() {
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
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Textractor is running the latest local build. No remote update channel is configured."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - Row primitive

/// A flat, single-line menu row with a leading SF Symbol, the title, and an
/// optional right-aligned keyboard hint. Hover state uses the system-selection
/// blue.
private struct MenuRow: View {

    let title: String
    let icon: String
    var key: String = ""
    let action: () -> Void

    @State private var isHovered: Bool = false

    init(_ title: String, icon: String, key: String = "", action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.key = key
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if !key.isEmpty {
                    Text(key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
