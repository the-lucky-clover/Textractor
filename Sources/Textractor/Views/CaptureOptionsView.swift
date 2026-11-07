import SwiftUI

struct CaptureOptionsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var extras = CaptureExtras.shared

    private func binding<Value>(_ key: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { appState.settings[keyPath: key] }, set: { value in
            appState.updateSettings { $0[keyPath: key] = value }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Replay welcome tour") { AppCoordinator.shared.replayOnboarding() }
                .accessibilityIdentifier("settings.onboarding.replay")
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
                Text("This batch lasts until you quit. Clearing it keeps your current clipboard unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Undo last") { extras.undoBatch() }
                    Button("Clear batch") { extras.clearBatch() }
                }.disabled(extras.batch.entries.isEmpty)
            }
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
