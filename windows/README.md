# Textractor Windows Port

This is a Windows port of the Textractor macOS app, built with WinUI 3 and .NET 8.

## Features

- **Global Hotkey**: Ctrl+Shift+2 to start capture (configurable)
- **Region Capture**: Crosshair overlay with drag-to-select
- **Window Capture**: Hover to highlight windows, click to capture
- **Full Screen Capture**: Capture all displays
- **File Import**: Drag & drop or pick image files
- **OCR**: Tesseract-based on-device text recognition
- **AI Analysis**: Sentiment, language detection, keyword extraction, entity recognition
- **Clipboard Integration**: Plain text and RTF with rich formatting
- **Toast Notifications**: Success/failure with actions (copy, share, retry)
- **System Tray**: Menu with all capture modes, settings, history
- **Settings Window**: Matches macOS design with BreakingDad theme
- **History Window**: View and manage capture history
- **Splash Screen**: Animated launch splash matching macOS

## Design System

The Windows port faithfully reproduces the macOS BreakingDad design system:

- **Colors**: Toxic Green (#6BB534), Deep Green (#2E5C1C), Meth Blue (#29ABE0), Hazmat Yellow (#F5C714), Rust Red (#B8291F), Chalk (#E6EADC), Green-Black (#0B100A)
- **Typography**: Segoe UI Variable (rounded), Cascadia Mono (monospace)
- **Components**: HUD cards, pill buttons, toggle switches, menu rows, toast cards
- **Animations**: Spring-based entrance animations, pulse effects, fade in/out

## Building

```powershell
# Build and publish
.\build.ps1

# Create installer (requires Inno Setup)
iscc installer.iss
```

## Requirements

- Windows 10 1809+ (build 17763) or Windows 11
- .NET 8 Runtime (included in self-contained build)
- Tesseract OCR data files in `tessdata/` directory

## Project Structure

```
Textractor.Windows/
├── App.xaml / App.xaml.cs           # Application entry point
├── Resources/
│   └── BreakingDadTheme.xaml        # Complete theme resources
├── Models/                          # Data models
├── Services/                        # Core services
│   ├── OCRService.cs               # Tesseract OCR
│   ├── ScreenshotService.cs        # Windows Graphics Capture
│   ├── HotkeyManager.cs            # Global hotkeys
│   ├── ClipboardService.cs         # Clipboard with RTF
│   ├── AIInferenceService.cs       # Text analysis
│   ├── SystemTrayService.cs        # System tray + menu
│   └── ...
├── Views/
│   ├── SplashScreenWindow.xaml     # Launch splash
│   ├── CaptureOverlayWindow.xaml   # Crosshair/window overlay
│   ├── ToastNotificationWindow.xaml # Toast notifications
│   ├── SettingsWindow.xaml         # Settings (matches macOS)
│   └── HistoryWindow.xaml          # History viewer
└── installer.iss                   # Inno Setup script
```

## Differences from macOS

| Feature | macOS | Windows |
|---------|-------|---------|
| OCR | Apple Vision | Tesseract |
| NLP | NaturalLanguage | Custom implementation |
| Screen Capture | ScreenCaptureKit | Graphics Capture API |
| Hotkeys | Carbon | Low-level keyboard hook |
| UI | SwiftUI/AppKit | WinUI 3 |
| Menu Bar | NSStatusItem | NotifyIcon (system tray) |
| Notifications | Custom NSPanel | Custom Window |
| Installer | DMG + Sparkle | Inno Setup (.exe) |

## License

Same as macOS version.