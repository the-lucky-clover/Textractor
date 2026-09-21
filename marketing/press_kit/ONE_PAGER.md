# Textractor Press Kit
# Version 2.0.0 — September 2026
# https://github.com/the-lucky-clover/Textractor/press-kit

---

## 📋 ONE-PAGER

### Textractor — Privacy-First OCR for macOS

**Tagline:** Extract text from any screen — 100% on-device, zero cloud.

**Launch Date:** September 2026  
**Price:** $12.99 (one-time, no subscription)  
**Platform:** macOS 14+ (Intel + Apple Silicon)  
**License:** MIT (open source)  
**Category:** Utilities / Developer Tools / Productivity

---

### The Problem
Every OCR tool sends screenshots to the cloud. For developers handling API keys, passwords, private code, and sensitive data — that's unacceptable.

### The Solution
Textractor uses Apple's Vision framework + Neural Engine. Everything runs locally on your Mac. Your screen, your text, your business.

### Key Differentiators
| Feature | Textractor | Others |
|---------|------------|--------|
| **On-device only** | ✅ | ❌ (mostly cloud) |
| **Source Code Mode** | ✅ (8 languages) | ❌ |
| **Offline Translation** | ✅ (21 languages) | ❌ |
| **Re-OCR History** | ✅ | ❌ |
| **PII Redaction** | ✅ (15+ patterns) | ❌ |
| **No Subscription** | ✅ | Often subscription |
| **Open Source** | ✅ (MIT) | ❌ |

---

### Core Features

**🎯 Region/Window/Full-Screen Capture**  
Drag to select, click a window, or capture all displays. Live OCR preview (250ms debounce) shows text before you commit.

**🧠 Source Code Mode**  
Auto-detects Swift, Python, JavaScript, Go, Rust, C, Bash, Ruby + JSON/XML/HTML. Wraps in fenced markdown blocks with proper indentation preserved. Paste directly into Xcode, VS Code, or any editor.

**🌍 Snip-to-Translate**  
Capture → auto-detects source language → translates to 21 target languages. Powered by NaturalLanguage framework, fully offline.

**📜 Searchable History + Re-OCR**  
Every capture saved with thumbnail. Change OCR settings (weirdness, language, code mode) → re-process any past capture instantly.

**🔒 PII Redaction**  
Auto-scrubs emails, API keys (AWS, GitHub, Stripe), credit cards, JWTs, SSH keys, Docker IDs, crypto addresses, and 10+ more patterns. Regex + ML hybrid.

**⚡ Quick Actions**  
Toast notification after capture includes one-click **Translate** and **Format as Code** buttons.

---

### Technical Architecture
- **Language:** Swift 5.9+
- **Frameworks:** Vision, ScreenCaptureKit, NaturalLanguage, SwiftData, CryptoKit
- **Storage:** Encrypted SQLite (AES-GCM via SwiftData)
- **Sandbox:** Full App Sandbox + Hardened Runtime
- **Notarization:** Apple notarized, Gatekeeper friendly
- **Distribution:** Mac App Store + direct download

---

### Privacy Promise
- **Zero network calls** for core OCR/capture/translation
- **No analytics** unless explicitly opted in (local only)
- **No accounts** — no email, no login, no tracking
- **Encrypted at rest** — AES-GCM keys in Keychain
- **Open source** — audit the code at github.com/the-lucky-clover/Textractor

---

### Target Audience
1. **Developers** — code capture, API key safety, documentation
2. **Security Researchers** — PII redaction, offline processing
3. **Writers/Researchers** — translation, history, multi-display
4. **Privacy Advocates** — zero-cloud, open source, auditable
4. **Power Users** — keyboard-driven, menu bar, shortcuts

---

### Quotes for Attribution

> "Finally, an OCR tool that respects developer privacy. Source Code Mode alone is worth the price."  
> — *Early beta tester*

> "The Re-OCR feature is a game changer. Capture once, reprocess with different settings forever."  
> — *Technical writer*

> "Open source, sandboxed, notarized, and actually useful. This is how Mac apps should be built."  
> — *macOS engineer*

---

### Contact
**Maker:** [Your Name]  
**Email:** pounds.1@example.com  
**GitHub:** https://github.com/the-lucky-clover/Textractor  
**Twitter:** @yourhandle  
**Press Kit:** https://github.com/the-lucky-clover/Textractor/tree/main/press-kit

---

## 🎨 BRAND ASSETS

### Logo Files (in press-kit/logos/)
```
logos/
├── icon-1024.png          # App Store icon (1024x1024)
├── icon-512.png           # 512x512
├── icon-256.png           # 256x256
├── icon-128.png           # 128x128
├── icon-64.png            # 64x64
├── icon-32.png            # 32x32
├── icon-16.png            # 16x16
├── logo-horizontal.png    # Horizontal lockup (1200x400)
├── logo-vertical.png      # Vertical lockup (400x800)
├── logo-white.png         # White version for dark backgrounds
├── logo-black.png         # Black version for light backgrounds
├── favicon.ico            # 16/32/48/64 multi-res
└── favicon.svg            # Vector
```

### Color Palette
```css
/* Primary */
--brand-green: #6BB534;      /* Primary actions, success */
--brand-green-dark: #2E5C1C; /* Headers, emphasis */

/* Secondary */
--brand-blue: #29ABE0;       /* Links, secondary actions */
--brand-amber: #F5C714;      /* Warnings, highlights */

/* Neutrals */
--ink: #0B100A;              /* Near-black backgrounds */
--ivory: #E6EADC;            /* Off-white text */
--rust: #B8291F;             /* Errors, destructive */

/* Semantic */
--success: #6BB534;
--warning: #F5C714;
--error: #B8291F;
--info: #29ABE0;
```

### Typography
- **Headings:** System Font (SF Pro Display), Bold, -apple-system
- **Body:** System Font (SF Pro Text), Regular, -apple-system
- **Code:** SF Mono, Regular, -apple-system
- **Scale:** 12px base, modular scale 1.25

### Screenshots (in press-kit/screenshots/)
```
screenshots/
├── 01-capture-overlay.png       # Region capture with live preview
├── 02-window-capture.png        # Window picker mode
├── 03-history-grid.png          # History with thumbnails
├── 04-source-code-mode.png      # Settings: code mode enabled
├── 05-translation-settings.png  # Translation target picker
├── 06-toast-actions.png         # Toast with quick actions
├── 07-pii-redaction.png         # Privacy settings
├── hero-dark.png                # 1200x630 OG image (dark)
├── hero-light.png               # 1200x630 OG image (light)
└── app-store-*.png              # 1280x800 App Store screenshots
```

---

## 📦 DOWNLOAD LINKS
- **Mac App Store:** [link after approval]
- **Direct Download (DMG):** [GitHub Releases]
- **Source Code:** https://github.com/the-lucky-clover/Textractor
- **Homebrew:** `brew install --cask textractor` (planned)

---

## 📋 FACT SHEET

| Attribute | Value |
|-----------|-------|
| **Name** | Textractor |
| **Version** | 2.0.0 |
| **Release Date** | September 2026 |
| **Price** | $12.99 (one-time) |
| **Launch Discount** | $9.99 (first 2 weeks) |
| **Size** | ~15 MB |
| **Min macOS** | 14.0 (Sonoma) |
| **Architecture** | Universal (ARM64 + x86_64) |
| **Languages** | EN (localization ready) |
| **License** | MIT |
| **Privacy Policy** | https://github.com/the-lucky-clover/Textractor/blob/main/PRIVACY_POLICY.md |

---

## 🏷️ APP STORE METADATA

### Keywords (100 char limit)
`OCR,text extraction,screen capture,privacy,productivity,developer tools,translate,code,screen recording,vision framework`

### Category
Primary: **Utilities**  
Secondary: **Productivity** / **Developer Tools**

### Age Rating
4+ (No objectionable content)

---

## 📸 SCREENSHOT CAPTIONS (App Store)

1. **Capture Overlay** — "Drag to select any region. Live OCR preview updates in real-time."
2. **Window Capture** — "Click any window for instant text extraction. No region selection needed."
3. **History Grid** — "Every capture saved with thumbnail. Search, re-OCR, export."
4. **Source Code Mode** — "Auto-detects 8 languages. Outputs fenced markdown blocks."
5. **Translation** — "21 languages offline. Auto-detects source language."
6. **Toast Actions** — "One-click Translate or Format as Code from the toast."
7. **PII Redaction** — "Auto-scrubs emails, API keys, cards, and 15+ patterns."

---

## 🔗 USEFUL LINKS
- **Product Hunt:** [to be added]
- **Hacker News:** [to be added]
- **GitHub Repo:** https://github.com/the-lucky-clover/Textractor
- **Issues/Feedback:** https://github.com/the-lucky-clover/Textractor/issues
- **Changelog:** https://github.com/the-lucky-clover/Textractor/blob/main/CHANGELOG.md
- **Privacy Policy:** https://github.com/the-lucky-clover/Textractor/blob/main/PRIVACY_POLICY.md