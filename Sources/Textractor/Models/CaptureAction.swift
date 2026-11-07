import Foundation
import Carbon.HIToolbox

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String
    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public func matches(keyCode: UInt32, modifiers: UInt32) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }
}

public enum CaptureAction: String, CaseIterable, Codable, Identifiable {
    case capture, previous, keepLines, removeLines, speakCapture, barcode, stopSpeaking, toggleAdditive, clearAdditive
    case overlayLines, overlayAdditive, overlaySpeech
    public var id: String { rawValue }
    public var overlayOnly: Bool { [.overlayLines, .overlayAdditive, .overlaySpeech].contains(self) }
    public var title: String {
        switch self {
        case .capture: return "Capture text"
        case .previous: return "Capture previous selection"
        case .keepLines: return "Capture with line breaks"
        case .removeLines: return "Capture without line breaks"
        case .speakCapture: return "Capture and read aloud"
        case .barcode: return "Read QR / barcode"
        case .stopSpeaking: return "Stop speaking"
        case .toggleAdditive: return "Toggle additive clipboard"
        case .clearAdditive: return "Clear additive history"
        case .overlayLines: return "Toggle line breaks in capture"
        case .overlayAdditive: return "Toggle additive in capture"
        case .overlaySpeech: return "Toggle speech in capture"
        }
    }
    public var defaultBinding: ShortcutBinding? {
        let key: UInt32
        switch self {
        case .overlayLines: key = UInt32(kVK_ANSI_L)
        case .overlayAdditive: key = UInt32(kVK_ANSI_H)
        case .overlaySpeech: key = UInt32(kVK_ANSI_S)
        default: return nil
        }
        return .init(keyCode: key, modifiers: UInt32(cmdKey), label: HotkeyManager.labelFor(keyCode: key, modifiers: UInt32(cmdKey)))
    }
}

public struct CaptureIntent: Equatable {
    public var flatten: Bool?
    public var speech: Bool?
    public var barcode: Bool?
    public init(flatten: Bool? = nil, speech: Bool? = nil, barcode: Bool? = nil) {
        self.flatten = flatten; self.speech = speech; self.barcode = barcode
    }
    public func applying(to settings: AppSettings) -> AppSettings {
        var result = settings
        if let flatten { result.flattenText = flatten; result.wordWrapCaptured = false }
        if let speech { result.readAloud = speech }
        if let barcode { result.recognizeBarcodes = barcode }
        return result
    }
}

public extension AppSettings {
    func shortcut(for action: CaptureAction) -> ShortcutBinding? {
        if action == .capture {
            return .init(keyCode: resolvedHotkeyKeyCode, modifiers: resolvedHotkeyModifiers, label: resolvedHotkeyLabel)
        }
        if disabledShortcuts.contains(action.rawValue) { return nil }
        return actionShortcuts[action.rawValue] ?? action.defaultBinding
    }
    func shortcutConflict() -> String? {
        var seen: [String: CaptureAction] = [:]
        for action in CaptureAction.allCases {
            guard let binding = shortcut(for: action) else { continue }
            let key = "\(binding.keyCode):\(binding.modifiers)"
            if let existing = seen[key] { return "\(action.title) conflicts with \(existing.title)." }
            seen[key] = action
        }
        return nil
    }
}
