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
        register(
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

        var hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIDValue)

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
        switch status {
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
        // Subset mirroring common Carbon→displayable labels.
        switch Int32(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:       return "Space"
        case kVK_Return:      return "↩"
        case kVK_Tab:         return "⇥"
        case kVK_Escape:      return "⎋"
        case kVK_Delete:      return "⌫"
        case kVK_LeftArrow:   return "←"
        case kVK_RightArrow:  return "→"
        case kVK_UpArrow:     return "↑"
        case kVK_DownArrow:   return "↓"
        case kVK_F1 ... kVK_F12:
            return "F\(keyCode - Int(kVK_F1) + 1)"
        default:
            return "Key \(keyCode)"
        }
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
