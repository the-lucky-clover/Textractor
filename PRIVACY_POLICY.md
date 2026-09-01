# Textractor Privacy Policy

**Effective Date:** September 1, 2026  
**Last Updated:** September 1, 2026  
**Contact:** pounds.1@example.com

---

## 1. Overview

Textractor ("the App") is a macOS utility for capturing text from your screen via OCR (Optical Character Recognition). This privacy policy explains what data the App collects, how it is used, and your rights regarding that data.

**Key Principle:** Textractor runs entirely on your device. No OCR images, extracted text, or personal data ever leave your Mac unless you explicitly choose to share them.

---

## 2. Data We Collect

### 2.1 Data Processed Locally (Never Transmitted)

The following data is processed **exclusively on your device** and never transmitted to any server:

- **Screen captures** — Images captured via Screen Recording permission are processed locally by Apple's Vision framework for OCR. These images are saved only to your local cache directory (`~/Library/Caches/Textractor/`) and optionally to your chosen export location.
- **Extracted text** — OCR results remain on your device. They are copied to your clipboard (at your direction), stored in your local history database, and optionally exported to files you choose.
- **History records** — Timestamps, text previews, capture modes, and OCR confidence scores are stored in a local SQLite database (`~/Library/Application Support/Textractor/History/history.json`).
- **Application settings** — Your preferences (hotkeys, language selection, redaction settings, translation target, etc.) are stored in `~/Library/Preferences/com.example.textractor.plist`.

### 2.2 Optional Telemetry (Opt-In Only)

If you enable **"Local Telemetry"** in Settings → Behavior, the App collects **anonymous, aggregated usage statistics** stored locally on your device:

- Capture mode used (region, window, full screen)
- OCR success/failure rates
- Text length distributions
- Feature usage (translation, source code mode, PII redaction)

**This data never leaves your device.** It is viewable only in the App's debug log and is deleted when you disable the setting or reset the App.

### 2.3 Data You Explicitly Share

When you use the **Share** button in the capture toast, the extracted text is passed to macOS's native share sheet. You choose the destination (Mail, Messages, AirDrop, Notes, etc.). Textractor does not control or monitor what happens after the share sheet receives the data.

---

## 3. Data We Do NOT Collect

- No personally identifiable information (name, email, Apple ID, etc.)
- No network requests for analytics, tracking, or advertising
- No crash reports sent automatically (you can manually share logs if desired)
- No usage data sent to third parties
- No cloud synchronization of history or settings

---

## 4. Third-Party Services

### Apple Frameworks (On-Device Only)

Textractor uses the following Apple frameworks **entirely on-device**:

- **Vision.framework** — OCR text recognition (runs locally on Apple Silicon Neural Engine or CPU)
- **ScreenCaptureKit** — Screen/window capture (requires your explicit Screen Recording permission)
- **NaturalLanguage.framework** — Language detection for translation (runs locally)
- **CoreML / MLModel** — On-device translation (when available, macOS 14+)

No data is sent to Apple servers by these frameworks during normal operation.

### Open Source Dependencies

- **swift-crypto** (Apple) — Local AES-GCM encryption for CaptureStore
- **SwiftData** — Local persistence (SQLite on device)

These are compiled into the App binary and operate entirely locally.

---

## 5. Permissions

| Permission | Purpose | Required? |
|------------|---------|-----------|
| **Screen Recording** | Capture screen regions, windows, or full screen for OCR | **Yes** (core functionality) |
| **Accessibility** | *Not used* — Textractor does not auto-paste or control other apps | No |

You can revoke Screen Recording permission at any time in **System Settings → Privacy & Security → Screen Recording**. The App will prompt you to re-grant it when needed.

---

## 6. Data Retention

| Data Type | Retention |
|-----------|-----------|
| Capture images (cache) | 7 days (auto-cleaned), or until manually cleared |
| History records | Up to your configured limit (default 100, max 1000) |
| Exported files | Until you delete them |
| Settings / Preferences | Until you delete the App or reset settings |
| Telemetry logs | Until you disable Local Telemetry or reset the App |

You can clear all history and cache at any time via **Settings → Clear History** or **Settings → Factory Reset**.

---

## 7. Your Rights

Under GDPR, CCPA, and similar regulations, you have the right to:

- **Access** — View all data the App stores locally (history, settings, cache)
- **Rectification** — Edit or delete individual history entries
- **Erasure** — Use "Clear History" or "Factory Reset" to delete all App data
- **Portability** — Export history as JSON/CSV via the Structured Export feature
- **Restriction** — Disable features (telemetry, translation, knowledge mode) individually
- **Objection** — Opt out of all data processing by not using the App

To exercise these rights, use the App's built-in controls. No server-side request is needed because all data resides on your device.

---

## 8. Children's Privacy (COPPA)

Textractor is not directed at children under 13. The App does not knowingly collect personal information from children. If you believe a child has provided personal data, contact us and we will assist with deletion.

---

## 9. Security

- **Encryption at rest** — CaptureStore encrypts OCR text using AES-GCM with keys stored in macOS Keychain
- **No network exposure** — The App makes zero outbound network connections for core functionality
- **Sandboxed** — Runs in macOS App Sandbox with minimal entitlements (ScreenCapture, UserSelectedFile)
- **No code injection** — Does not inject code into other processes

---

## 10. International Transfers

Not applicable. All data processing occurs on your device within your jurisdiction.

---

## 11. Changes to This Policy

We may update this policy for new features or legal requirements. Changes will be posted in the App's release notes and on the GitHub repository. Continued use after changes constitutes acceptance.

---

## 12. Contact

For questions, concerns, or data requests:

**Email:** pounds.1@example.com  
**GitHub:** https://github.com/the-lucky-clover/Textractor

---

## 13. App Store Compliance Notes

- **App Store Review Guidelines § 5.1.1** — This policy is accessible from the App Store product page and within the App (Settings → Privacy Policy)
- **App Store Review Guidelines § 5.1.2** — No user data is transmitted without explicit consent
- **App Store Review Guidelines § 5.1.3** — Data collection is minimal and purpose-limited
- **App Store Review Guidelines § 5.2** — No third-party analytics or advertising SDKs
- **GDPR Art. 13/14** — Information provided at time of data collection (first launch, permission prompts)
- **CCPA § 1798.100-199** — No sale of personal information; opt-out not needed (no collection)

---

*Textractor is open source. You can audit the code at: https://github.com/the-lucky-clover/Textractor*