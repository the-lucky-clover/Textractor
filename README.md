# Textractor Pro

Native OCR for macOS, with an iOS screenshot-review and conversation-packet target.
Both default to **English (US)** (`en-US`). This branch is an implementation candidate:
**no production signoff or App Store name reservation has been verified**.

The display name is Textractor Pro. The Mac Swift package, executable, bundle identifier,
and existing settings/history locations retain their original identifiers for compatibility.

## macOS

- Region, window, screen and image-file extraction through Apple Vision.
- Native Continuity Camera requestor for iPhone/iPad photos and multipage scans.
- QR/barcode extraction, read aloud, additive clipboard with undo, previous-region capture,
  custom capture shortcut, formatting and history.
- BreakingDad styling within the existing 232 pt menu and 252 pt Settings widths.
- US English defaults and preference migration; skippable four-step onboarding, replayable
  from Settings without discarding the saved language choice.

The [feature matrix](qa/FEATURE_MATRIX.md) distinguishes implemented behavior from gaps.
Scroll stitching, physical-device capture, accessibility and other release checks remain
unfinished. Translation is explicitly unavailable and no remote update feed is configured.
Full TextSniper feature parity and quantified superiority are not claimed.

## iOS

The `TextractorMobile` target (iOS 17+) imports screenshots selected from Photos or Files.
It preserves source bytes, extracts text on device, and supports:

- Original-linked review, optional transcript timestamps and logged corrections.
- Reviewable overlap suggestions, reversible exclusions and labeled message reconstruction.
- Exact, fuzzy and on-device related-meaning search, with an explicit fuzzy fallback when
  the English sentence model is unavailable.
- Numbered US Letter PDF packets with black text on white, optional grayscale source pages,
  original image exports and audit JSON.
- Skippable onboarding replayable from Settings.

It does not access the Messages database, control scrolling in Messages, infer missing dates,
certify authenticity or certify court admissibility. Shared LLM-link import remains a proposal.
See [iOS capabilities, limits and acceptance targets](qa/IOS_DIRECTION.md).

## Build and test

Use a Mac with Xcode and command-line tools. The generated Xcode project requires XcodeGen.

```sh
swift test --enable-code-coverage
bash build.sh
open dist/Textractor.app
xcodegen generate
open Textractor.xcodeproj
```

Choose the `Textractor` scheme for macOS or `TextractorMobile` for iOS. `build.sh` creates
an ad-hoc development bundle; it does not install the app or produce a notarized release.
Use a simulator for mobile development; physical-device deployment needs your Apple signing
configuration. Screen capture on a Mac requires the relevant Screen Recording permission.

[Validation evidence and playtest instructions](qa/VALIDATION.md) list exact tested commits,
results, benchmark limits and outstanding device checks. CI runs native builds, unit tests,
UI playtests, a small OCR fixture benchmark and a secret scan. The release workflow checks
[the release record](qa/release-signoff.json) and rejects incomplete signoff.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/Textractor/` | macOS app, services, views, theme and localized resources |
| `Tests/` | macOS unit tests and executable UI playtests |
| `ios/TextractorMobile/` | iOS screenshot archive, OCR, review, search and PDF export |
| `ios/TextractorMobileTests/` | Mobile OCR, provenance, overlap, search and PDF regressions |
| `ios/TextractorMobileUITests/` | Mobile import/review/search/export-options playtest |
| `qa/` | Coverage, quantitative targets, evidence and release gates |
| `scripts/` | Benchmark scoring and signoff validation |
| `webapp/` | Separate optional web companion; not validated by this native-app signoff |

The native OCR and mobile search implementations use Apple frameworks on device. Imported
screenshots, OCR output and review history are sensitive local data; retention, backup and
sharing behavior require review before release. The optional web companion is a separate
service and has its own data handling and deployment requirements.

Made by [Lucky Clover](https://soundcloud.com/lucky-clover).
