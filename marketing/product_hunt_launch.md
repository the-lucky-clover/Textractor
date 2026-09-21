# Textractor — Product Hunt Launch Page Copy
# Launch Date: Tuesday (optimal), 12:01 AM PST
# https://www.producthunt.com/posts/textractor

---

## 🎯 HEADLINE (60 chars max)
**Textractor: Privacy-first OCR for Mac**

---

## 🎯 TAGLINE (255 chars max)
**Extract text from any screen — 100% on-device, zero cloud. Built for developers who value privacy.**

---

## 📝 DESCRIPTION (Full)

### The Problem
Every OCR tool I tried sent my screenshots to the cloud. API keys, passwords, private messages — all uploaded to some server for "processing." As a developer, that's a non-starter.

### The Solution
Textractor uses Apple's Vision framework + Neural Engine. Everything runs locally on your Mac. Your screen, your text, your business.

### Key Features

**⚡ Live OCR Preview**
Drag to select a region → see extracted text in real-time (250ms debounce). No guesswork, no retries.

**🧠 Source Code Mode**
Detects 8 languages (Swift, Python, JS, Go, Rust, C, Bash, Ruby + JSON/XML/HTML). Wraps in fenced markdown blocks with proper indentation preserved. Paste directly into your IDE.

**🌍 Snip-to-Translate (21 languages)**
Capture → auto-detects source language → translates to your target language. Offline via NaturalLanguage framework. Great for docs, Stack Overflow, foreign UI.

**📜 History with Re-OCR**
Every capture saved with thumbnail. Change settings (weirdness, language, code mode) → re-OCR any past capture instantly. No need to re-capture.

**🔒 PII Redaction**
Auto-scrubs emails, API keys, credit cards, JWTs, AWS keys, SSH keys, and 15+ patterns. Regex + ML hybrid. Toggle per-capture or globally.

**⚡ Quick Actions in Toast**
Capture → toast appears → one-click **Translate** or **Format as Code**. No menu diving.

**🔑 Privacy-First Architecture**
- Zero network calls for core features
- Encrypted local storage (AES-GCM via SwiftData)
- Sandboxed, hardened runtime, notarized
- Screen Recording permission only (no Accessibility needed)
- Open source: audit every line

---

## 🎬 DEMO GIFS NEEDED
1. Region capture with live preview → paste
2. Window capture → code block formatted
3. Translate to Spanish → paste
4. History → re-OCR with new settings
5. Settings → enable PII redaction

---

## 🏷️ TOPICS/TAGS
- macOS
- Productivity
- Developer Tools
- Privacy
- Open Source
- OCR
- Text Extraction

---

## 💰 PRICING
**$12.99** (one-time purchase, no subscription)
Launch week: **$9.99** (20% off)

---

## 🔗 LINKS
- **Mac App Store:** [to be added after approval]
- **GitHub:** https://github.com/the-lucky-clover/Textractor
- **Privacy Policy:** https://github.com/the-lucky-clover/Textractor/blob/main/PRIVACY_POLICY.md
- **Source Code:** https://github.com/the-lucky-clover/Textractor

---

## 🎁 MAKER COMMENT (Post at launch)
> Hey Product Hunt! 👋
> 
> I built Textractor because every OCR tool I found uploaded my screenshots to the cloud. As a developer working with API keys, passwords, and private code, that was a dealbreaker.
> 
> Textractor runs entirely on your Mac using Apple's Vision framework and Neural Engine. Your data never leaves your device.
> 
> **What makes it different for developers:**
> - 🧠 **Source Code Mode** — detects language, wraps in ```fenced blocks``` with indentation preserved
> - 🌍 **Offline Translation** — 21 languages, auto-detects source
> - 📜 **Re-OCR History** — change settings, re-process old captures
> - 🔒 **PII Redaction** — emails, keys, cards auto-scrubbed
> - ⚡ **Quick Actions** — translate/format from the toast
> 
> It's a one-time purchase ($12.99, $9.99 launch week), no subscription, open source (MIT).
> 
> 🎁 **First 50 comments get a promo code for free lifetime access.**
> 
> Happy to answer questions about the Vision framework, sandboxing, SwiftData encryption, or why I chose SPM over Xcode project!
> 
> — [Your Name]

---

## 📱 SOCIAL PREVIEW IMAGE SPECS
- 1200x630px (OG image)
- Include: App icon, "Textractor", "Privacy-first OCR for Mac", Mac App Store badge
- Background: Dark mode aesthetic (matching app)

---

## 📊 LAUNCH CHECKLIST
- [ ] Submit to Product Hunt (2 weeks before)
- [ ] Prepare 5 demo GIFs (15s each, <10MB)
- [ ] Create OG image (1200x630)
- [ ] Generate 100 promo codes in App Store Connect
- [ ] Schedule launch tweet/thread
- [ ] Prepare HN "Show HN" post
- [ ] Email beta testers for reviews
- [ ] Set up analytics (Plausible/Fathom - privacy friendly)

---

## 🎯 SUCCESS METRICS (Day 1)
- **Upvotes:** 200+
- **Comments:** 50+
- **Product Hunt rank:** Top 5
- **Website visits:** 5,000+
- **Mac App Store downloads:** 200+
- **Newsletter signups:** 100+

---

## 💬 COMMUNITY RESPONSE TEMPLATES

### For "How is this different from TextSniper/OwlOCR?"
> Great question! TextSniper is excellent for pure OCR. Textractor adds:
> 1. **Source Code Mode** — detects language, outputs ```fenced blocks```
> 2. **Offline Translation** — 21 langs, auto-detects source
> 3. **Re-OCR** — change settings, reprocess history
> 4. **PII Redaction** — regex+ML for keys/emails/cards
> 5. **Zero cloud** — fully sandboxed, notarized, open source
> 
> Different tools for different workflows!

### For "Why not free?"
> Building and maintaining a native Mac app with sandboxing, notarization, Vision framework integration, and ongoing macOS compatibility takes significant time. $12.99 one-time (no subscription) supports sustainable development. The code is MIT-licensed — you can build it yourself from source!

### For "Does it work on Apple Silicon only?"
> Works on both Intel and Apple Silicon! Vision framework uses Neural Engine on M-series (faster) but falls back to CPU on Intel. Tested on M1-M3 and Intel Macs.

---

## 📅 LAUNCH TIMELINE

| Time | Action |
|------|--------|
| T-14 days | Submit to PH, prepare assets |
| T-7 days | Final testing, promo codes ready |
| T-1 day | Schedule tweets, prepare HN post |
| **T-0 (12:01 AM PST)** | **LAUNCH** - PH goes live |
| T+1 hour | Post HN, tweet thread, email list |
| T+4 hours | Respond to every PH comment |
| T+24 hours | Share metrics, thank supporters |
| T+1 week | Version 2.0.1 with top feedback |

---

## 🚨 CONTINGENCY
- **PH rejection:** Have backup launch on HN + Twitter same day
- **App Store delay:** Launch with direct download + "Coming to Mac App Store" badge
- **Bad bugs:** Hotfix within 4 hours, communicate transparently