using System;
using System.Collections.Generic;

namespace Textractor.Windows.Models;

public enum DockPresence
{
    MenuBarOnly,
    DockOnly,
    Both
}

/// <summary>
/// Storage decision for captured screenshots.
/// </summary>
public enum StorageDecision
{
    Ask,
    Delete,
    SaveToFolder
}

public class AppSettings
{
    public double Weirdness { get; set; } = 0.45;
    public List<string> CustomVocabulary { get; set; } = new();
    public string UILanguage { get; set; } = "";
    public bool LocalTelemetryEnabled { get; set; } = true;
    public bool OpenPopoverOnCapture { get; set; } = false;
    public bool WindowCaptureAsTable { get; set; } = true;
    public DateTimeOffset? LastUpdateCheckAt { get; set; }
    public int? CustomHotkeyKeyCode { get; set; }
    public string? CustomHotkeyModifiers { get; set; }
    public string? CustomHotkeyLabel { get; set; }
    public bool SoundEffectsEnabled { get; set; } = true;
    public bool PasteAsPlainText { get; set; } = true;
    public bool FlattenText { get; set; } = false;
    public bool ReduceMotion { get; set; } = false;
    public bool WordWrapCaptured { get; set; } = false;
    public double FontScale { get; set; } = 1.0;
    public DockPresence DockPresence { get; set; } = DockPresence.MenuBarOnly;
    public bool PiiRedactionEnabled { get; set; } = true;
    public int HistoryEntryLimit { get; set; } = 200;
    public bool KnowledgeModeEnabled { get; set; } = false;
    public bool ExtendedLoggingEnabled { get; set; } = false;

    // Storage settings
    public StorageDecision StorageDecision { get; set; } = StorageDecision.Ask;
    public int StorageDecisionTimeoutSeconds { get; set; } = 8;
    public string? CustomScreenshotsFolder { get; set; }

    // Hotkey settings
    // Alt+Shift+2 = Region capture (0x0005 = MOD_ALT | MOD_SHIFT)
    public uint RegionCaptureModifiers { get; set; } = 0x0005; // MOD_ALT | MOD_SHIFT
    public uint RegionCaptureKeyCode { get; set; } = 0x32; // '2' key
    
    // Alt+Shift+3 = Window capture (0x0005 = MOD_ALT | MOD_SHIFT)
    public uint WindowCaptureModifiers { get; set; } = 0x0005; // MOD_ALT | MOD_SHIFT
    public uint WindowCaptureKeyCode { get; set; } = 0x33; // '3' key

    // Auto-paste
    public bool AutoPasteEnabled { get; set; } = true;

    // OCR Language
    public string OcrLanguage { get; set; } = "eng";

    public static AppSettings Default => new();

    public static readonly List<(string Code, string Name, string Flag)> OcrLanguageCatalog = new()
    {
        ("eng", "English", "🇺🇸"),
        ("spa", "Spanish", "🇪🇸"),
        ("fra", "French", "🇫🇷"),
        ("deu", "German", "🇩🇪"),
        ("ita", "Italian", "🇮🇹"),
        ("por", "Portuguese", "🇧🇷"),
        ("nld", "Dutch", "🇳🇱"),
        ("rus", "Russian", "🇷🇺"),
        ("jpn", "Japanese", "🇯🇵"),
        ("kor", "Korean", "🇰🇷"),
        ("chi_sim", "Chinese (Simplified)", "🇨🇳"),
        ("ara", "Arabic", "🇸🇦"),
    };
}