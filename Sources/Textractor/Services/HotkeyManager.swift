import AppKit
import Carbon
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// SwiftUI does not provide a public global-hotkey API on macOS, so we go
/// through Carbon. The hotkey is configurable through `AppSettings`; the
/// default binding is ⌘⇧2 (`kVK_ANSI_2` with `cmdKey | shiftKey`).
public final class HotkeyManager {

    public static let shared = HotkeyManager()

    /// Signature 'TRC2' — uniquely identifies our hotkey in the OS event stream.
    private let signature: OSType = 0x54524332
    private let hotKeyIDValue: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Invoked on the main queue when the configured hotkey is pressed
    /// anywhere on the system.
    public var onHotkey: (() -> Void)?

    private init() {}

    // MARK: - Public registration

    /// Register with the default ⌘⇧2 binding.
    public func register() {
        _ = register(
            keyCode: AppSettings.defaultHotkeyKeyCode,
            modifiers: AppSettings.defaultHotkeyModifiers,
            label: AppSettings.defaultHotkeyLabel
        )
    }

    /// Register with a custom keyCode + modifier mask.
    ///
    /// Returns a `RegistrationResult` so callers can surface conflict warnings
    /// to the user. We attempt the registration twice (once as a probe for
    /// `isConflicted`, then again as the live binding) because Carbon does
    /// not expose a pre-flight check.
    public func register(keyCode: UInt32, modifiers: UInt32, label: String) -> RegistrationResult {
        unregister()

        // Install event handler once.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            TextractorHotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIDValue)

        // Probe: try a transient registration with a throwaway ID to detect
        // conflicts without affecting our true hot key ref. If Carbon rejects
        // it we know the binding collides with another registered hot key.
        var probeRef: EventHotKeyRef?
        let probeStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: signature, id: UInt32(0xFF)),
            GetApplicationEventTarget(),
            0,
            &probeRef
        )
        if let probeRef { UnregisterEventHotKey(probeRef) }
        let conflict = probeStatus != noErr

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            LoggerService.shared.error("Hotkey registration failed: status=\(status) keyCode=\(keyCode) modifiers=\(modifiers)")
            return RegistrationResult(
                ok: false,
                conflict: conflict,
                description: Self.describe(status: status, conflict: conflict, label: label)
            )
        }

        LoggerService.shared.info("Hotkey registered: \(label) (keyCode=\(keyCode), modifiers=\(modifiers))")
        return RegistrationResult(ok: true, conflict: false, description: label)
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    /// Translate Carbon registration errors into something a user can read.
    private static func describe(status: OSStatus, conflict: Bool, label: String) -> String {
        if conflict {
            return "“\(label)” is in use by another app or by macOS itself."
        }
        switch Int(status) {
        case -9878:  // eventInternalErr / paramErr on bad key code
            return "“\(label)” isn't a valid key combination."
        case paramErr:  // -50
            return "“\(label)” isn't a valid key combination."
        default:
            return "Could not bind “\(label)” (Carbon error \(status))."
        }
    }

    // MARK: - Conflict detection helper

    /// Probe a candidate (keyCode, modifiers) without permanently registering.
    /// We do this by trying a throwaway registration and immediately
    /// unregistering. `true` means another binding is already holding the combo.
    public static func isConflicted(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: 0x54524332, id: UInt32(0xFE)),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { UnregisterEventHotKey(ref) }
        return status != noErr
    }

    /// Translate a key combination into a human-readable label such as
    /// "⌃⌥⌘P".  Used by the Settings UI while the user is recording.
    public static func labelFor(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        parts.append(Self.keyCodeLabel(Int(keyCode)))
        return parts.joined()
    }

    private static func keyCodeLabel(_ keyCode: Int) -> String {
        // Subset mirroring common Carbon→displayable labels. We flatten the
        // switch over a typed `Int` so we don't fight the bridging types of
        // `kVK_*` constants (which come in as `Int32` from Carbon.HIToolbox).
        let map: [Int: String] = [
            Int(kVK_ANSI_A): "A",  Int(kVK_ANSI_B): "B",  Int(kVK_ANSI_C): "C",
            Int(kVK_ANSI_D): "D",  Int(kVK_ANSI_E): "E",  Int(kVK_ANSI_F): "F",
            Int(kVK_ANSI_G): "G",  Int(kVK_ANSI_H): "H",  Int(kVK_ANSI_I): "I",
            Int(kVK_ANSI_J): "J",  Int(kVK_ANSI_K): "K",  Int(kVK_ANSI_L): "L",
            Int(kVK_ANSI_M): "M",  Int(kVK_ANSI_N): "N",  Int(kVK_ANSI_O): "O",
            Int(kVK_ANSI_P): "P",  Int(kVK_ANSI_Q): "Q",  Int(kVK_ANSI_R): "R",
            Int(kVK_ANSI_S): "S",  Int(kVK_ANSI_T): "T",  Int(kVK_ANSI_U): "U",
            Int(kVK_ANSI_V): "V",  Int(kVK_ANSI_W): "W",  Int(kVK_ANSI_X): "X",
            Int(kVK_ANSI_Y): "Y",  Int(kVK_ANSI_Z): "Z",
            Int(kVK_ANSI_0): "0",  Int(kVK_ANSI_1): "1",  Int(kVK_ANSI_2): "2",
            Int(kVK_ANSI_3): "3",  Int(kVK_ANSI_4): "4",  Int(kVK_ANSI_5): "5",
            Int(kVK_ANSI_6): "6",  Int(kVK_ANSI_7): "7",  Int(kVK_ANSI_8): "8",
            Int(kVK_ANSI_9): "9",
            Int(kVK_Space):       "Space",
            Int(kVK_Return):      "↩",
            Int(kVK_Tab):         "⇥",
            Int(kVK_Escape):      "⎋",
            Int(kVK_Delete):      "⌫",
            Int(kVK_LeftArrow):   "←",
            Int(kVK_RightArrow):  "→",
            Int(kVK_UpArrow):     "↑",
            Int(kVK_DownArrow):   "↓"
        ]
        if let label = map[keyCode] { return label }
        let f1 = Int(kVK_F1)
        let f12 = Int(kVK_F12)
        if keyCode >= f1 && keyCode <= f12 {
            return "F\(keyCode - f1 + 1)"
        }
        return "Key \(keyCode)"
    }

    // MARK: - Carbon callback (bridged via @_cdecl at file scope)

    fileprivate static func handleCarbonEventRefPublic(
        eventRef: EventRef?,
        userData: UnsafeMutableRawPointer?
    ) -> OSStatus {
        guard let eventRef, let userData else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        if hotKeyID.signature == 0x54524332 && hotKeyID.id == 1 {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.fireHotkey()
            }
        }

        return noErr
    }

    private func fireHotkey() {
        onHotkey?()
    }
}

/// Compact diagnostic returned by `HotkeyManager.register(...)`.
public struct RegistrationResult: Equatable {
    public let ok: Bool
    public let conflict: Bool
    public let description: String

    public init(ok: Bool, conflict: Bool, description: String) {
        self.ok = ok
        self.conflict = conflict
        self.description = description
    }
}

// MARK: - Carbon C-callable trampoline

/// Swift 6 no longer exposes `CarbonEventHandlerUPP`. A `@_cdecl` free
/// function is the supported way to bridge a Swift callback to Carbon's
/// `EventHandlerProcPtr` signature required by `InstallEventHandler`.
@_cdecl("TextractorHotKeyCallback")
private func TextractorHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    HotkeyManager.handleCarbonEventRefPublic(eventRef: eventRef, userData: userData)
}
