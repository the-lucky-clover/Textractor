import Foundation
import SwiftUI
import Carbon.HIToolbox

// MARK: - AppSettings

/// User-facing configuration. Persisted with `UserDefaults` via `SettingsStore`.
///
/// Privacy posture (post-2.0): Textractor **always** runs OCR and discards the
/// screenshot. The user can opt into keeping failed-OCR screenshots for
/// recovery, but there is no "save every screenshot" mode. There is also no
/// "where should I save?" picker; failed screenshots land in
/// `~/Pictures/Textractor Screenshots/` so the user can still use macOS's
/// built-in screen capture if they want different storage.
public struct AppSettings: Codable, Sendable {
    /// Weirdness 0% = strict, 100% = lenient / creative correction.
    public var weirdness: Double

    /// User-vocab correction bias — Vision language-correction will favour these tokens.
    public var customVocabulary: [String]

    /// Single source of truth for both UI localization and OCR preference.
    /// Empty means "Automatic" — OCRService builds a multi-language superset.
    /// Non-empty selects that language for both UI and OCR.
    public var uiLanguage: String
/// Deprecated: use `uiLanguage` instead. Kept for backwards-compatible
/// decoding of older persisted settings.
@available(*, deprecated, message: "Use uiLanguage instead")
public var ocrLanguages: [String] = []

    /// If true, allow contributions of anonymous usage stats to local disk only.
    /// (No network is ever used — this just controls local logging.)
    public var localTelemetryEnabled: Bool

    /// Auto-show the menubar popover when capture completes (otherwise only the toast).
    public var openPopoverOnCapture: Bool

    /// When the user captures a window via the Window Capture button, attempt to
    /// detect tabular layouts and emit a Markdown table to the clipboard.
    public var windowCaptureAsTable: Bool

    /// Last time we checked for updates (for update auto-check logic).
    public var lastUpdateCheckAt: Date?

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
    /// pasting into apps that don"t render attributed string cleanly.
    public var pasteAsPlainText: Bool

    /// When `true`, captured text is flattened — single carriage returns and
    /// newlines are removed so lists/captured lines become a single paragraph of
    /// running text. Default OFF.
    public var flattenText: Bool

    /// When `true`, the banner shimmer and intro fly-in animations are disabled
    /// (accessibility / calm UI). Default OFF.
    public var reduceMotion: Bool

    /// When `true`, captured text is word-wrapped (flattened) before being
    /// written to the clipboard or shared. Default OFF — most users prefer
    /// original line breaks from the OCR pass.
    public var wordWrapCaptured: Bool

    /// Font scale factor for accessibility (0.75 to 2.5).
    public var fontScale: Double

    // MARK: - Dock / Menu bar presence
    
    /// Controls whether Textractor appears in the Dock, the menu bar, or both.
    /// - `menuBarOnly`: Traditional accessory app (no Dock icon, default)
    /// - `dockOnly`: Regular app with Dock icon, no menu bar item
    /// - `both`: Regular app with Dock icon AND menu bar item
    public var dockPresence: DockPresence

    /// When `true` (default), the menubar icon shows in full color.
    /// When `false`, the menubar icon is rendered as grayscale for a subtle look.
    public var menubarColorIcon: Bool

    // MARK: - Privacy

    /// PII redaction toggle. **Default ON** — passwords / credit-cards / SSNs /
    /// API keys etc. detected in the extracted text are replaced with
    /// `[REDACTED:KIND]` before the text ever reaches the pasteboard or the
    /// history store. Set to `false` ("Permit PII", a.k.a. **PPI**) to allow
    /// sensitive data through verbatim. The toast surfaces the current mode
    /// prominently so the user always knows which path was taken.
    public var piiRedactionEnabled: Bool

    // MARK: - History

    /// Maximum number of records retained in the persistent history.
    /// Slider-clamped to `10…1000` in the Settings UI.
    public var historyEntryLimit: Int

    // MARK: - Knowledge Mode

    /// When enabled, every capture is saved to the visual knowledge library
    /// with full image, OCR text, metadata, and AI-generated insights.
    /// Disabled by default to preserve the lightweight clipboard-only workflow.
    public var knowledgeModeEnabled: Bool

    // MARK: - Extended Logging

    /// When enabled, writes verbose logs to a file in `~/Library/Caches/Textractor/Logs/`.
    /// Useful for debugging OCR pipeline issues and ClipboardImageOCR monitoring.
    public var extendedLoggingEnabled: Bool

    // MARK: - Ahoy Mode (easter egg)

    /// Hidden toggle that decorates user-facing UI strings (toasts, hints,
    /// empty-state copy) with pirate flavor. OCR output is **never** touched
    /// — this only changes the chrome around the product.
    public var ahoyMode: Bool

    // MARK: - Phase 1 Improvements

    /// When enabled, translates captured text to the target language before pasting.
    /// Uses the `translationTargetLanguage` setting.
    public var translateAfterCapture: Bool

    /// When enabled, detects source code in OCR results and wraps output
    /// in fenced markdown code blocks with automatic language detection.
    /// This preserves indentation and adds syntax highlighting hints.
    public var sourceCodeMode: Bool

    /// Target language for snip-to-translate (BCP-47 like "es", "ja").
    /// Empty means translation is disabled.
    public var translationTargetLanguage: String

    /// When enabled, monitors the system pasteboard for copied images and
    /// automatically runs OCR on them, surfacing the result in the toast.
    /// This lets users copy a screenshot or photo from any app and get text
    /// without triggering a capture. Default OFF.
    public var clipboardImageOCR: Bool

    /// When enabled, shows a confidence badge in the toast and history UI
    /// so users can see how reliable each OCR result is. Default ON.
    public var showConfidenceBadge: Bool

    /// When enabled, structured export (JSON/CSV/Markdown) is available
    /// from the history context menu. Default ON.
    public var structuredExportEnabled: Bool

    /// When enabled, automatically saves each capture (image + text) to
    /// `~/Pictures/Textractor Captures/` with timestamped filenames.
    /// Default OFF — captures are clipboard-only by default.
    public var autoSaveCaptures: Bool

    public init(
        weirdness: Double = 0.45,
        customVocabulary: [String] = [],
        uiLanguage: String = "",
        localTelemetryEnabled: Bool = true,
        openPopoverOnCapture: Bool = false,
        lastUpdateCheckAt: Date? = nil,
        customHotkeyKeyCode: UInt32? = nil,
        customHotkeyModifiers: UInt32? = nil,
        customHotkeyLabel: String? = nil,
        soundEffectsEnabled: Bool = true,
        pasteAsPlainText: Bool = true,
        wordWrapCaptured: Bool = false,
        windowCaptureAsTable: Bool = true,
        flattenText: Bool = false,
        reduceMotion: Bool = false,
        fontScale: Double = 1.0,
        piiRedactionEnabled: Bool = true,
        historyEntryLimit: Int = 200,
        dockPresence: DockPresence = .menuBarOnly,
        menubarColorIcon: Bool = true,
        knowledgeModeEnabled: Bool = false,
        extendedLoggingEnabled: Bool = false,
        ahoyMode: Bool = false,
        clipboardImageOCR: Bool = false,
        showConfidenceBadge: Bool = true,
        structuredExportEnabled: Bool = true,
        sourceCodeMode: Bool = false,
        translateAfterCapture: Bool = false,
        translationTargetLanguage: String = "",
        autoSaveCaptures: Bool = false
    ) {
        self.weirdness = weirdness
        self.customVocabulary = customVocabulary
        self.uiLanguage = uiLanguage
        self.localTelemetryEnabled = localTelemetryEnabled
        self.openPopoverOnCapture = openPopoverOnCapture
        self.windowCaptureAsTable = windowCaptureAsTable
        self.lastUpdateCheckAt = lastUpdateCheckAt
        self.fontScale = fontScale
        self.customHotkeyKeyCode = customHotkeyKeyCode
        self.customHotkeyModifiers = customHotkeyModifiers
        self.customHotkeyLabel = customHotkeyLabel
        self.soundEffectsEnabled = soundEffectsEnabled
        self.pasteAsPlainText = pasteAsPlainText
        self.wordWrapCaptured = wordWrapCaptured
        self.flattenText = flattenText
        self.reduceMotion = reduceMotion
        self.piiRedactionEnabled = piiRedactionEnabled
        self.historyEntryLimit = historyEntryLimit
        self.dockPresence = dockPresence
        self.menubarColorIcon = menubarColorIcon
        self.knowledgeModeEnabled = knowledgeModeEnabled
        self.extendedLoggingEnabled = extendedLoggingEnabled
        self.ahoyMode = ahoyMode
        self.clipboardImageOCR = clipboardImageOCR
        self.showConfidenceBadge = showConfidenceBadge
        self.structuredExportEnabled = structuredExportEnabled
        self.sourceCodeMode = sourceCodeMode
        self.translateAfterCapture = translateAfterCapture
        self.translationTargetLanguage = translationTargetLanguage
        self.autoSaveCaptures = autoSaveCaptures
    }

    // MARK: - Codable migration

private enum CodingKeys: String, CodingKey {
        case weirdness, customVocabulary, uiLanguage, localTelemetryEnabled, openPopoverOnCapture, lastUpdateCheckAt
        case customHotkeyKeyCode, customHotkeyModifiers, customHotkeyLabel, soundEffectsEnabled
        case pasteAsPlainText, wordWrapCaptured, windowCaptureAsTable, flattenText, reduceMotion
        case fontScale, piiRedactionEnabled, historyEntryLimit, ocrLanguages, dockPresence, menubarColorIcon, knowledgeModeEnabled, extendedLoggingEnabled
        case ahoyMode, clipboardImageOCR, showConfidenceBadge, structuredExportEnabled, sourceCodeMode, translateAfterCapture, translationTargetLanguage, autoSaveCaptures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weirdness = try container.decode(Double.self, forKey: .weirdness)
        customVocabulary = try container.decode([String].self, forKey: .customVocabulary)
        var decodedUiLanguage = try container.decode(String.self, forKey: .uiLanguage)
        // Migration: older builds stored the OCR language list in `ocrLanguages`.
        // If `uiLanguage` is empty but legacy `ocrLanguages` has entries, promote
        // the first one so the user does not lose their language preference.
        if decodedUiLanguage.isEmpty,
           let legacyLangs = try container.decodeIfPresent([String].self, forKey: .ocrLanguages),
           let first = legacyLangs.first,
           !first.isEmpty {
            decodedUiLanguage = first
        }
        self.uiLanguage = decodedUiLanguage
        localTelemetryEnabled = try container.decode(Bool.self, forKey: .localTelemetryEnabled)
        openPopoverOnCapture = try container.decode(Bool.self, forKey: .openPopoverOnCapture)
        lastUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        customHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .customHotkeyKeyCode)
        customHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .customHotkeyModifiers)
        customHotkeyLabel = try container.decodeIfPresent(String.self, forKey: .customHotkeyLabel)
        soundEffectsEnabled = try container.decode(Bool.self, forKey: .soundEffectsEnabled)
        pasteAsPlainText = try container.decode(Bool.self, forKey: .pasteAsPlainText)
        wordWrapCaptured = try container.decode(Bool.self, forKey: .wordWrapCaptured)
        windowCaptureAsTable = try container.decode(Bool.self, forKey: .windowCaptureAsTable)
        flattenText = try container.decode(Bool.self, forKey: .flattenText)
        reduceMotion = try container.decode(Bool.self, forKey: .reduceMotion)
        fontScale = try container.decode(Double.self, forKey: .fontScale)
        piiRedactionEnabled = try container.decode(Bool.self, forKey: .piiRedactionEnabled)
        historyEntryLimit = try container.decode(Int.self, forKey: .historyEntryLimit)
        dockPresence = try container.decodeIfPresent(DockPresence.self, forKey: .dockPresence) ?? .menuBarOnly
        menubarColorIcon = try container.decodeIfPresent(Bool.self, forKey: .menubarColorIcon) ?? true
        knowledgeModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .knowledgeModeEnabled) ?? false
        extendedLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .extendedLoggingEnabled) ?? false
        ahoyMode = try container.decodeIfPresent(Bool.self, forKey: .ahoyMode) ?? false
        clipboardImageOCR = try container.decodeIfPresent(Bool.self, forKey: .clipboardImageOCR) ?? false
        showConfidenceBadge = try container.decodeIfPresent(Bool.self, forKey: .showConfidenceBadge) ?? true
        structuredExportEnabled = try container.decodeIfPresent(Bool.self, forKey: .structuredExportEnabled) ?? true
        sourceCodeMode = try container.decodeIfPresent(Bool.self, forKey: .sourceCodeMode) ?? false
        translateAfterCapture = try container.decodeIfPresent(Bool.self, forKey: .translateAfterCapture) ?? false
        translationTargetLanguage = try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? ""
        autoSaveCaptures = try container.decodeIfPresent(Bool.self, forKey: .autoSaveCaptures) ?? false
        self.ocrLanguages = [] // deprecated; cleared after migration
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weirdness, forKey: .weirdness)
        try container.encode(customVocabulary, forKey: .customVocabulary)
        try container.encode(uiLanguage, forKey: .uiLanguage)
        try container.encode(localTelemetryEnabled, forKey: .localTelemetryEnabled)
        try container.encode(openPopoverOnCapture, forKey: .openPopoverOnCapture)
        try container.encodeIfPresent(lastUpdateCheckAt, forKey: .lastUpdateCheckAt)
        try container.encodeIfPresent(customHotkeyKeyCode, forKey: .customHotkeyKeyCode)
        try container.encodeIfPresent(customHotkeyModifiers, forKey: .customHotkeyModifiers)
        try container.encodeIfPresent(customHotkeyLabel, forKey: .customHotkeyLabel)
        try container.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
        try container.encode(pasteAsPlainText, forKey: .pasteAsPlainText)
        try container.encode(wordWrapCaptured, forKey: .wordWrapCaptured)
        try container.encode(windowCaptureAsTable, forKey: .windowCaptureAsTable)
        try container.encode(flattenText, forKey: .flattenText)
        try container.encode(reduceMotion, forKey: .reduceMotion)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(piiRedactionEnabled, forKey: .piiRedactionEnabled)
        try container.encode(historyEntryLimit, forKey: .historyEntryLimit)
        try container.encode(dockPresence, forKey: .dockPresence)
        try container.encode(menubarColorIcon, forKey: .menubarColorIcon)
        try container.encode(knowledgeModeEnabled, forKey: .knowledgeModeEnabled)
        try container.encode(extendedLoggingEnabled, forKey: .extendedLoggingEnabled)
        try container.encode(ahoyMode, forKey: .ahoyMode)
        try container.encode(clipboardImageOCR, forKey: .clipboardImageOCR)
        try container.encode(showConfidenceBadge, forKey: .showConfidenceBadge)
        try container.encode(structuredExportEnabled, forKey: .structuredExportEnabled)
        try container.encode(autoSaveCaptures, forKey: .autoSaveCaptures)
        // `ocrLanguages` is deprecated and intentionally omitted from new encodes.
    }

    /// Backwards-compatible decoder: 2.x dropped `storageMode`, `saveFolder*`
    /// entirely. Older plists still decode fine because the synthesized
    /// `Decodable` ignores absent keys; this is here purely for the
    /// documentation breadcrumb.
    public static let `default` = AppSettings(
        weirdness: 0.45,
        customVocabulary: [],
        uiLanguage: "",
        localTelemetryEnabled: true,
        openPopoverOnCapture: false,
        lastUpdateCheckAt: nil,
        customHotkeyKeyCode: nil,
        customHotkeyModifiers: nil,
        customHotkeyLabel: nil,
        soundEffectsEnabled: true,
        pasteAsPlainText: true,
        wordWrapCaptured: false,
        windowCaptureAsTable: true,
        flattenText: false,
        reduceMotion: false,
        fontScale: 1.0,
        piiRedactionEnabled: true,
        historyEntryLimit: 200,
        dockPresence: .menuBarOnly,
        menubarColorIcon: true,
        knowledgeModeEnabled: false,
        extendedLoggingEnabled: false,
        ahoyMode: false,
        clipboardImageOCR: false,
        showConfidenceBadge: true,
        structuredExportEnabled: true,
        autoSaveCaptures: false
    )
}



// MARK: - Hotkey

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
}

// MARK: - OCR languages

public extension AppSettings {
    /// Curated list of OCR languages offered in the Settings UI. Apple Vision
    /// supports many more, this list covers the most commonly requested.
static let ocrLanguageCatalog: [(code: String, name: String, flag: String)] = [
        ("en-US", "English (US)", "🇺🇸"),
        ("en-GB", "English (UK)", "🇬🇧"),
        ("es-ES", "Spanish", "🇪🇸"),
        ("fr-FR", "French", "🇫🇷"),
        ("de-DE", "German", "🇩🇪"),
        ("it-IT", "Italian", "🇮🇹"),
        ("pt-BR", "Portuguese (Brazil)", "🇧🇷"),
        ("nl-NL", "Dutch", "🇳🇱"),
        ("ru-RU", "Russian", "🇷🇺"),
        ("pl-PL", "Polish", "🇵🇱"),
        ("el-GR", "Greek", "🇬🇷"),
        ("tr-TR", "Turkish", "🇹🇷"),
        ("th-TH", "Thai", "🇹🇭"),
        ("vi-VN", "Vietnamese", "🇻🇳"),
        ("id-ID", "Indonesian", "🇮🇩"),
        ("ms-MY", "Malay", "🇲🇾"),
        ("hi-IN", "Hindi", "🇮🇳"),
        ("he-IL", "Hebrew", "🇮🇱"),
        ("ar-SA", "Arabic", "🇸🇦"),
        ("ja-JP", "Japanese", "🇯🇵"),
        ("ko-KR", "Korean", "🇰🇷"),
        ("zh-Hans", "Chinese (Simplified)", "🇨🇳"),
        ("zh-Hant", "Chinese (Traditional)", "🇹🇼"),
    ]

    /// Bounded range exposed in the Settings slider.
    static let historyLimitRange: ClosedRange<Int> = 10...1000

    /// Convenience alias for the OCR language catalog tuple.
    typealias CatalogEntry = (code: String, name: String, flag: String)
    
    // MARK: - Dock Presence

    /// Controls where Textractor appears in the system UI.
    enum DockPresence: String, Codable, CaseIterable, Sendable {
        /// Menu bar only (traditional accessory app, no Dock icon).
        case menuBarOnly
        /// Dock only (regular app with Dock icon, no menu bar item).
        case dockOnly
        /// Both Dock and menu bar.
        case both

        public var displayName: String {
            switch self {
            case .menuBarOnly: return T.s("settings.dock.menuBarOnly")
            case .dockOnly: return T.s("settings.dock.dockOnly")
            case .both: return T.s("settings.dock.both")
            }
        }
    }
}
