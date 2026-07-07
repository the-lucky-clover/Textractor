# Textractor

> **On-device, privacy-first OCR for macOS.** A cyberpunk menubar/TUI app that
> extracts text from any region, window, full screen, file, or Continuity Camera
> image, runs Vision OCR + NaturalLanguage inference locally, and places a
> perfectly-formatted payload on your clipboard — ready to paste with ⌘V.

---

## ✨ Feature set

| Trigger | What happens |
|---|---|
| **⌘⇧2** | Global hotkey opens the crosshair capture overlay from anywhere |
| **Region button** | Freeform crosshair drag — capture any rectangle |
| **Window button** | Hover highlights windows; click to extract all text (optional markdown-table mode) |
| **Full Screen button** | Captures every display, sweeps every text block |
| **Drop file / pick…** | Process any image (PNG / JPG / HEIC / TIFF) — works seamlessly with Continuity Camera |
| **SPACE** | Inside overlay: toggle crosshair ↔ window mode |
| **ESC** | Cancel a capture |
| **Auto ⌘V** | After extraction, synthesise Cmd-V into the frontmost app (Accessibility) |
| **Mail / Message / AirDrop** | One-click share — wired through `NSSharingService` |
| **Toast** | "Selected text was successfully added to clipboard." neon confirmation |

### Storage modes (per user choice, set in Settings → Screenshots)

* **Ask each time** — toast shows `Save / Pick Where… / Delete / Always Save` buttons (8s default = delete)
* **Auto-delete** — screenshot moves to Trash the moment text is copied
* **Save to folder** — `~/Pictures/Textractor Screenshots/` (or your chosen folder)

### Inference weirdness

A 0% → 100% slider that bends Vision's behavior: stricter at 0% (higher text-height threshold, no vocab, no aggressive correction) and aggressive at 100% (multi-language hints, retry on empty results, vocabulary bias, de-hyphenation across line-breaks). Use the **Reset to defaults** button to flip back to the curated baseline.

### Window → markdown table

When the user enables "Convert window captures to Markdown tables," Textractor clusters `TextObservation`s into rows + columns by spatial alignment, emits a `| col1 | col2 |` table, and writes it as the pasteboard payload. Falls back to flat text when the alignment doesn't look tabular.

### Typography-first output

`TextFormatter` produces an `NSAttributedString` with rounded font, monospace preformatted table rows, highlighted URLs/emails (teal underline), and shaded keyword callouts — written to the pasteboard as both `.string` and `.rtf`.

### Festive/psychological nudges

* Streak counter ("X in session")
* Toast chip with sentiment (positive = lime, negative = red, neutral = cyan, mixed = violet)
* Letters (T · X · T) animating inside the menubar beaker
* Glassmorphic bento with neon Blade-Runner-2049 rim-lighting
* Click anywhere on the toast with haptic-feeling spring animation

---

## 🎨 Design system

| Tile | Value |
|---|---|
| Background | `#0A0B18` noir |
| Cyber cyan | `#37F2FF` |
| Magenta neon | `#FF3DCD` |
| Acid lime | `#9DFF42` |
| Holo violet | `#9E5BFF` |
| Hazard red | `#FF2F4C` |
| Amber laser | `#FFA41D` |
| Type | SF Pro Rounded (headlines) · SF Mono (chips) |

Surfaces use `.ultraThinMaterial` with stacked neon strokes for skeuomorphic depth; glow is implemented via `shadow(color:radius:)` modifiers.

---

## 🚀 Build & Run

```bash
git clone <repo> textractor
cd textractor
./build.sh              # release build → dist/Textractor.app
open dist/Textractor.app
```

Or install to /Applications:

```bash
./install.sh
```

### Required permissions (one time only)

> **System Settings → Privacy & Security → Screen Recording → enable Textractor**
> **System Settings → Privacy & Security → Accessibility → enable Textractor** *(for auto-⌘V)*

Without these, OCR returns empty and the toast surfaces a "Permissions" card.

---

## 📁 Source layout

```
Sources/Textractor/
├── Resources/Info.plist
├── Theme/
│   ├── NeonTheme.swift           # color, gradient, motion tokens
│   └── BeakerIcon.swift          # vector beaker + floating "T·X·T"
├── Models/
│   ├── CaptureMode.swift
│   ├── CapturedImage.swift
│   ├── OCRResult.swift
│   ├── TelemetryEvent.swift
│   ├── AppSettings.swift
│   └── AppState.swift            # @Published state, ToastState, StorageDecision
├── Services/
│   ├── LoggerService.swift
│   ├── TelemetryService.swift
│   ├── SettingsStore.swift
│   ├── HotkeyManager.swift       # Carbon RegisterEventHotKey ⌘⇧2
│   ├── ScreenshotService.swift   # region / window / fullscreen / file
│   ├── OCRService.swift          # Vision + self-healing retries
│   ├── AIInferenceService.swift  # NaturalLanguage sentiment + cleanup + keywords
│   ├── TextFormatter.swift       # typography NSAttributedString
│   ├── TableFormatter.swift      # OCR observations → Markdown table
│   ├── ClipboardService.swift    # .string + .rtf + auto-⌘V
│   ├── StorageService.swift      # save / trash / ask flow
│   ├── ShareService.swift        # NSSharingService Mail/Message/AirDrop
│   └── PermissionService.swift   # CGPreflight*, AXIsProcessTrusted
├── Views/
│   ├── CaptureOverlayView.swift  # full-screen crosshair + window picker
│   ├── ClipboardToastView.swift  # animated neon toast, storage/share chips
│   ├── CreditsModalView.swift    # skeuomorphic 3D popover → soundcloud
│   ├── MenuContentView.swift     # the menubar popover
│   └── SettingsView.swift        # full settings window
├── TextractorApp.swift           # @main, MenuBarExtra, Settings scene
├── AppCoordinator.swift          # pipeline, hotkey bridge, storage flow
└── AppDelegate.swift             # LSUIElement runtime policy
```

---

## 🩹 Self-healing pipeline

```
capture (region / window / screen / file)
   ↓
OCR (Vision)
   ├── Step 1: accurate + weirdness-derived minTextHeight
   ├── Step 2 (on empty): fast + no threshold
   ├── Step 3 (on empty + permissive): latin language hints + vocab
   └── Step 4 (on empty + vocab): vocab-only accurate
   ↓
AI.clean()            strip zero-width, smart-quote, de-hyphenate, collapse blanks
   ↓
TableFormatter        if windowCaptureAsTable && observations look tabular → MD table
   ↓
TextFormatter         wrap in NSAttributedString (rounded + mono + entity highlight)
   ↓
ClipboardService.copy(plain, attributed)   → .string + .rtf on the pasteboard
ClipboardService.autoPasteIntoFrontmostApp()  → ⌘V synthesised via CGEvent
   ↓
governStorage
   ├── ask      → wait for toast button (8s timeout default = delete)
   ├── delete   → trash immediately
   └── folder   → save to ~/Pictures/Textractor Screenshots/ (or chosen folder)
   ↓
Toast (kind=success|failure, sentiment chip, language, tokens)
```

Telemetry events fire at every step. No network is ever touched.

---

## 🧰 Privacy posture

* `LSUIElement` — no Dock icon, no app menu
* `NSPrincipalClass` = `NSApplication`, single window
* **Zero** network code in the entire binary
* All OCR → Apple's `Vision` (offline, on-device)
* All NLP → Apple's `NaturalLanguage` (offline, on-device)
* No third-party dependencies
* Telemetry is JSONL to `~/Library/Application Support/Textractor/telemetry.jsonl`
  (Settings → Footer toggle to disable; "Made with ❤️ by Lucky Clover" credits link
  to https://soundcloud.com/lucky-clover)

---

Made with ❤️ by **Lucky Clover** — https://soundcloud.com/lucky-clover
