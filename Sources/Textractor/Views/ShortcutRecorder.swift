import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Records a physical key and modifiers, with Escape to cancel and visible conflict feedback.
struct ShortcutRecorder: NSViewRepresentable {
    var label: String
    var onRecord: (UInt32, UInt32, String) -> String?
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: label, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        button.onRecord = onRecord
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onRecord = onRecord
        view.savedTitle = label
        if !view.recording { view.title = label }
    }
    final class RecorderButton: NSButton {
        var onRecord: ((UInt32, UInt32, String) -> String?)?
        var savedTitle = "Record shortcut"
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        @objc func beginRecording() {
            savedTitle = title
            recording = true
            title = "Press keys… Esc cancels"
            window?.makeFirstResponder(self)
        }
        override func resignFirstResponder() -> Bool {
            recording = false
            title = savedTitle
            return super.resignFirstResponder()
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) { recording = false; title = savedTitle; return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.control) else {
                title = "Include ⌘ or Control"; return
            }
            var carbon: UInt32 = 0
            var glyphs = ""
            if flags.contains(.control) { carbon |= UInt32(controlKey); glyphs += "⌃" }
            if flags.contains(.option) { carbon |= UInt32(optionKey); glyphs += "⌥" }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey); glyphs += "⇧" }
            if flags.contains(.command) { carbon |= UInt32(cmdKey); glyphs += "⌘" }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            let label = glyphs + key
            if let error = onRecord?(UInt32(event.keyCode), carbon, label) {
                title = "Shortcut unavailable"
                toolTip = error
                NSAccessibility.post(element: self, notification: .valueChanged)
            } else {
                recording = false
                savedTitle = label
                title = label
            }
        }
    }
}
