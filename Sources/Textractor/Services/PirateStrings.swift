import Foundation

/// Easter-egg flavor layer. When `AppSettings.ahoyMode` is on, user-facing
/// chrome strings (toast headlines, hints, empty-state copy) get a pirate
/// rewrite. **OCR output and clipboard payloads are never modified** —
/// the user's work product is always the real capture text.
///
/// Designed to be a drop-in replacement for `String` literals that already
/// pass through `Localizable.strings` (or inline `T.s(...)`). The plain
/// variant is the source of truth; the pirate variant is keyed on the
/// plain string so missing entries fall back to the plain text.
public enum PirateStrings {

    /// Pirate rewrite table. Look up by the **plain** key (the one passed
    /// to `flavor(_:)`). Add new entries at the bottom; no behavior change
    /// when absent — `flavor` returns the plain string unchanged.
    private static let table: [String: String] = [
        // Pipeline phase labels (toast copy).
        "pipeline.idle":       "Idle, like a becalmed sea",
        "pipeline.capturing":  "Spyin' through the spyglass…",
        "pipeline.ocr":        "Squintin' at the letters, arr",
        "pipeline.ai":         "Havin' the parrot think on it",
        "pipeline.clipboard":   "Stowin' the booty in yer clipboard",
        "pipeline.completed":  "Yo-ho-ho, captured clean",
        "pipeline.failed":     "Shiver me timbers: %@",

        // Capture mode menu.
        "menu.capture.region":        "Plunder a region, matey",
        "menu.capture.window":        "Board a window",
        "menu.capture.auto_scroll":   "Auto-scroll the decks",
        "menu.capture.full_screen":   "Capture every last plank",
        "menu.capture.continuity":    "Summon ye iPhone",

        // Empty states / hints.
        "history.empty":      "No booty captured yet, captain",
        "history.search.hint": "Search the hold",
        "toast.try.again":    "Try again, ye salty dog",
        "toast.cancel":       "Batten down the hatches",

        // Settings.
        "settings.title":           "Ship's Log",
        "section.ai":               "Parrot & Plunder",
        "section.formatting":       "Booty Formatting",
        "section.permissions":      "Letters o' Marque",
        "section.privacy":          "Dead Man's Chest",
        "settings.ahoy.toggle":     "Ahoy Mode (pirate UI copy)",
        "settings.ahoy.help":       "Decorates toasts an' menus with seafarin' flavor. OCR text stays clean.",
        "settings.factory.reset":   "Scuttle the ship an' start fresh",
        "settings.factory.help":    "Wipes settings, history, custom vocab, an' cached captures. Ye'll need to re-grant permissions in System Settings.",

        // Toasts.
        "toast.copied":     "Copied to clipboard, captain",
        "toast.saved":      "Saved to yer hold",
        "toast.failed":     "Avast — capture failed",
    ]

    /// Returns the pirate-flavored variant if `ahoyMode` is on AND a table
    /// entry exists for `key`; otherwise returns `plain` unchanged.
    /// The table lookup uses the key, not the plain text, so callers can
    /// stay on `T.s(...)` and we localize the pirate variant separately.
    public static func flavor(_ key: String, plain: String, ahoy: Bool) -> String {
        guard ahoy, let mapped = table[key] else { return plain }
        return mapped
    }
}
