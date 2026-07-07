import Foundation
import SwiftUI

// MARK: - StorageMode

/// Where captured screenshots are persisted.
public enum StorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// After OCR, show a toast with `Keep` / `Delete` buttons. Default after timeout = delete.
    case ask

    /// Always move screenshot to Trash after text extraction.
    case autoDelete

    /// Always save to `defaultFolder`. Defaults to `~/Pictures/Textractor Screenshots/`.
    case safe

    /// Skip OCR / clipboard entirely — just save the screenshot file. Useful privacy mode.
    case safeOnlyScreenshot

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ask:                return "Ask each time"
        case .autoDelete:         return "Auto-delete"
        case .safe:               return "Save to folder"
        case .safeOnlyScreenshot: return "Save raw image only (no extraction)"
        }
    }

    public var description: String {
        switch self {
        case .ask:
            return "Show Save / Delete choices in the toast after each capture"
        case .autoDelete:
            return "Trash the screenshot the moment text is copied"
        case .safe:
            return "Permanently write every screenshot to the chosen folder"
        case .safeOnlyScreenshot:
            return "Save the image and skip text extraction entirely"
        }
    }

    public var symbolName: String {
        switch self {
        case .ask:                return "questionmark.circle"
        case .autoDelete:         return "trash"
        case .safe:               return "folder.fill"
        case .safeOnlyScreenshot: return "photo.fill"
        }
    }
}

// MARK: - QuickShareTarget

public enum QuickShareTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case email
    case message     // macOS Messages / SMS
    case airDrop

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .email:   return "Mail"
        case .message: return "Message"
        case .airDrop: return "AirDrop"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .email:   return "envelope.fill"
        case .message: return "message.fill"
        case .airDrop: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - AppSettings

/// User-facing configuration. Persisted with `UserDefaults` via `SettingsStore`.
public struct AppSettings: Codable, Sendable {
    public var storageMode: StorageMode
    public var saveFolderBookmark: Data?       // security-scoped or absolute path
    public var saveFolderPath: String?         // resolved for display (non-Authoritative)

    /// Weirdness 0% = strict, 100% = lenient / creative correction.
    public var weirdness: Double

    /// When `true`, after a successful extraction Textractor synthesises ⌘V
    /// into the frontmost app.  **Default is OFF** — manual paste remains the
    /// baseline behaviour.  Requires Accessibility permission.
    public var autoPasteEnabled: Bool

    /// Quick-action chips visible in the toast (Mail / Message / AirDrop).
    public var quickShareTargets: Set<QuickShareTarget>

    /// User-vocab correction bias — Vision language-correction will favour these tokens.
    public var customVocabulary: [String]

    /// If true, show a celebratory “streak”/“addictive” toast animation each capture.
    public var festiveFeedback: Bool

    /// If true, allow contributions of anonymous usage stats to local disk only.
    /// (No network is ever used — this just controls local logging.)
    public var localTelemetryEnabled: Bool

    /// Auto-show the menubar popover when capture completes (otherwise only the toast).
    public var openPopoverOnCapture: Bool

    /// When the user captures a window via the Window Capture button, attempt to
    /// detect tabular layouts and emit a Markdown table to the clipboard.
    public var windowCaptureAsTable: Bool

    // MARK: - Hotkey remapping

    /// User-customisable keycode for the ⌘⇧2 hotkey. `nil` means "use default".
    public var customHotkeyKeyCode: UInt32?
    /// User-customisable modifier mask for the ⌘⇧2 hotkey. `nil` means default (Cmd+Shift).
    public var customHotkeyModifiers: UInt32?
    /// Human-readable label of the custom hotkey, used in the Settings UI.
    public var customHotkeyLabel: String?

    // MARK: - Sound

    /// Master toggle for the brief UI sound effects (capture start, mode tick,
    /// cancellation, etc.). Default ON.
    public var soundEffectsEnabled: Bool

    // MARK: - Clipboard output

    /// When `true` (default), Textractor writes only plain text to the
    /// pasteboard — the rich typography formatting is skipped. Useful for
    /// pasting into apps that don't render attributed string cleanly.
    public var pasteAsPlainText: Bool

    /// When `true`, captured text is word-wrapped (flattened) before being
    /// written to the clipboard or shared. Default OFF — most users prefer
    /// original line breaks from the OCR pass.
    public var wordWrapCaptured: Bool

    public init(
        storageMode: StorageMode = .ask,
        saveFolderBookmark: Data? = nil,
        saveFolderPath: String? = nil,
        weirdness: Double = 0.45,
        autoPasteEnabled: Bool = false,
        quickShareTargets: Set<QuickShareTarget> = [.email, .message, .airDrop],
        customVocabulary: [String] = [],
        festiveFeedback: Bool = true,
        localTelemetryEnabled: Bool = true,
        openPopoverOnCapture: Bool = false,
        windowCaptureAsTable: Bool = true,
        customHotkeyKeyCode: UInt32? = nil,
        customHotkeyModifiers: UInt32? = nil,
        customHotkeyLabel: String? = nil,
        soundEffectsEnabled: Bool = true,
        pasteAsPlainText: Bool = true,
        wordWrapCaptured: Bool = false
    ) {
        self.storageMode = storageMode
        self.saveFolderBookmark = saveFolderBookmark
        self.saveFolderPath = saveFolderPath
        self.weirdness = weirdness
        self.autoPasteEnabled = autoPasteEnabled
        self.quickShareTargets = quickShareTargets
        self.customVocabulary = customVocabulary
        self.festiveFeedback = festiveFeedback
        self.localTelemetryEnabled = localTelemetryEnabled
        self.openPopoverOnCapture = openPopoverOnCapture
        self.windowCaptureAsTable = windowCaptureAsTable
        self.customHotkeyKeyCode = customHotkeyKeyCode
        self.customHotkeyModifiers = customHotkeyModifiers
        self.customHotkeyLabel = customHotkeyLabel
        self.soundEffectsEnabled = soundEffectsEnabled
        self.pasteAsPlainText = pasteAsPlainText
        self.wordWrapCaptured = wordWrapCaptured
    }

    public static let `default` = AppSettings()
}

extension AppSettings {
    /// Default screen-capture hotkey: ⌘⇧2 (`kVK_ANSI_2` with cmdKey|shiftKey).
    public static let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_2)
    public static let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    public static let defaultHotkeyLabel: String = "⌘⇧2"

    public var resolvedHotkeyKeyCode: UInt32 {
        customHotkeyKeyCode ?? Self.defaultHotkeyKeyCode
    }
    public var resolvedHotkeyModifiers: UInt32 {
        customHotkeyModifiers ?? Self.defaultHotkeyModifiers
    }
    public var resolvedHotkeyLabel: String {
        customHotkeyLabel ?? Self.defaultHotkeyLabel
    }
    public var hotkeyIsCustom: Bool {
        customHotkeyKeyCode != nil
            || customHotkeyModifiers != nil
            || customHotkeyLabel != nil
    }

// MARK: - Sensible defaults

public extension AppSettings {
    /// ~/Pictures/Textractor Screenshots/  — created lazily on first save.
    static func defaultSaveFolder() -> URL {
        let pics = (FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        return pics.appendingPathComponent("Textractor Screenshots", isDirectory: true)
    }
}
