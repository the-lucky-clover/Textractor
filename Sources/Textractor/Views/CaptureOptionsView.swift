import SwiftUI
import ApplicationServices

struct CaptureOptionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var shortcutError: String?
    @ObservedObject private var extras = CaptureExtras.shared

    private func binding<Value>(_ key: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { appState.settings[keyPath: key] }, set: { value in
            appState.updateSettings { $0[keyPath: key] = value }
        })
    }

    private func saveShortcuts(_ candidate: AppSettings) -> String? {
        let errors = ActionShortcuts.shared.configure(candidate)
        if let error = errors.first {
            _ = ActionShortcuts.shared.configure(appState.settings)
            shortcutError = error
            return error
        }
        appState.updateSettings { $0 = candidate }
        shortcutError = nil
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Capture text now") { AppCoordinator.shared.startCaptureRegion() }
                .accessibilityIdentifier("settings.capture.test")
            DisclosureGroup("Keyboard shortcuts") {
                ForEach(CaptureAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title).font(.caption)
                        ShortcutRecorder(label: appState.settings.shortcut(for: action)?.label ?? "Set shortcut") { key, modifiers, label in
                            var candidate = appState.settings
                            if action == .capture {
                                candidate.customHotkeyKeyCode = key; candidate.customHotkeyModifiers = modifiers; candidate.customHotkeyLabel = label
                            } else {
                                candidate.disabledShortcuts.removeAll { $0 == action.rawValue }
                                candidate.actionShortcuts[action.rawValue] = .init(keyCode: key, modifiers: modifiers, label: label)
                            }
                            return saveShortcuts(candidate)
                        }.frame(height: 30).accessibilityLabel(action.title + " shortcut")
                        .accessibilityIdentifier("shortcut." + action.rawValue)
                        if action != .capture {
                            Button("Remove shortcut") {
                                var candidate = appState.settings
                                candidate.disabledShortcuts.append(action.rawValue)
                                _ = saveShortcuts(candidate)
                            }.font(.caption)
                        }
                    }
                }
                Button("Reset shortcuts") {
                    var candidate = appState.settings
                    candidate.actionShortcuts = [:]; candidate.disabledShortcuts = []
                    candidate.customHotkeyKeyCode = nil; candidate.customHotkeyModifiers = nil; candidate.customHotkeyLabel = nil
                    _ = saveShortcuts(candidate)
                }
            }.accessibilityIdentifier("settings.shortcuts")
            if let shortcutError { Text(shortcutError).font(.caption).foregroundStyle(.orange) }

            Button("Import from iPhone or iPad…") {
                Task { await AppCoordinator.shared.runContinuityCameraCapture() }
            }.accessibilityIdentifier("settings.continuity")
            Toggle("Read QR and barcodes", isOn: binding(\.recognizeBarcodes))
            Toggle("Read captures aloud", isOn: binding(\.readAloud))
            if appState.settings.readAloud {
                Slider(value: binding(\.speechRate), in: 0...1) { Text("Speech speed") }
                Button("Stop speaking") { extras.stopSpeaking() }
            }
            Toggle("Additive clipboard", isOn: binding(\.additiveClipboard))
            if appState.settings.additiveClipboard {
                Text("\(extras.batch.entries.count) captures · \(extras.batch.text.count) characters")
                    .font(.caption.monospacedDigit())
                Text("Clear keeps the current clipboard unchanged. Undo restores the previous batch edit; undo after clear restores history only.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Undo batch edit") { extras.undoBatch() }.disabled(!extras.canUndo)
                    Button("Clear batch") { extras.clearBatch() }.disabled(extras.batch.entries.isEmpty)
                }
            }
            Toggle("Keep additive history after quit", isOn: binding(\.persistAdditiveClipboard))
                .accessibilityIdentifier("settings.batch.persist")
            Text("Optional local file, readable by your Mac account. Turning this off removes the saved file; the current session stays available.").font(.caption).foregroundStyle(.secondary)
            #if !APP_STORE
            Toggle("Clear additive history on ⌘V", isOn: binding(\.clearAdditiveOnPaste))
                .accessibilityIdentifier("settings.batch.paste")
            if appState.settings.clearAdditiveOnPaste {
                Text("Clears only when this app still owns the pasted text. Requires Accessibility access for paste keys in other apps; secure-input fields may suppress events. Menu-based Paste is not detected.").font(.caption)
                Button("Enable paste-key observation…") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
            #endif
            if let error = extras.persistenceError {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("Retry history storage") { extras.retryPersistence(settings: appState.settings) }
            }
            Toggle("Open captured web links", isOn: binding(\.automaticallyOpenLinks))
                .accessibilityIdentifier("settings.links.auto")
            Text("When enabled, opens up to three explicit HTTP(S) links from each new capture after copying. Other URL schemes are ignored.").font(.caption).foregroundStyle(.secondary)
            Toggle("Success notifications", isOn: binding(\.showSuccessNotifications))
            Toggle("Capture sounds", isOn: binding(\.soundEffectsEnabled))
            Toggle("Source code formatting", isOn: binding(\.sourceCodeMode))
            Text("Custom words (one per line)").font(.caption)
            TextEditor(text: Binding(get: { appState.settings.customVocabulary.joined(separator: "\n") }, set: { value in
                appState.updateSettings {
                    $0.customVocabulary = Array(value.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(200))
                }
            }))
            .frame(height: 72).accessibilityLabel("Custom recognition words")
        }
        .toggleStyle(.switch).controlSize(.small)
        .tint(BreakingDad.toxicGreen)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(BreakingDad.deepGreen.opacity(0.15)))
    }
}
