import AppKit
import Carbon.HIToolbox

@MainActor
final class ActionShortcuts: ObservableObject {
    static let shared = ActionShortcuts()
    @Published private(set) var errors: [String] = []
    var onAction: ((CaptureAction) -> Void)?
    private var managers: [CaptureAction: HotkeyManager] = [:]

    @discardableResult
    func configure(_ settings: AppSettings) -> [String] {
        if let conflict = settings.shortcutConflict() { errors = [conflict]; return errors }
        var failures: [String] = []
        for (index, action) in CaptureAction.allCases.enumerated() where !action.overlayOnly {
            let manager = managers[action] ?? (action == .capture ? HotkeyManager.shared : HotkeyManager(id: UInt32(index + 1)))
            managers[action] = manager
            manager.onHotkey = { [weak self] in Task { @MainActor in self?.onAction?(action) } }
            if let binding = settings.shortcut(for: action) {
                let result = manager.register(keyCode: binding.keyCode, modifiers: binding.modifiers, label: binding.label)
                if !result.ok { failures.append("\(action.title): \(result.description)") }
            } else { manager.unregister() }
        }
        errors = failures
        return failures
    }
    func unregister() { managers.values.forEach { $0.unregister() } }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        return value
    }
}
