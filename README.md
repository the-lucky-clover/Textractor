# Textractor Pro

Native text extraction for macOS 14+, with a separate iOS 17+ screenshot-review target.
English (US), `en-US`, is the default OCR language.

**Release status: implementation candidate.** The current release work, outstanding device
checks, Apple-account requirements and archive commands are in the
[release plan](qa/RELEASE_PLAN.md). The public name is **Textractor Pro**; availability in
App Store Connect has not been verified. A passing source check is not a signed build,
device signoff or App Store approval.

## macOS capabilities

- Extract text from a selected region, window, full display or imported image using Apple Vision.
- Import iPhone/iPad photos and document scans through macOS Continuity Camera.
- Read QR/barcodes, hear extracted text aloud, and combine captures in an additive clipboard.
- Reuse a previous region, configure capture shortcuts, control line breaks, add recognition
  vocabulary and review capture history.
- Use a separate stationary capture overlay on each connected display.
- Skip onboarding or replay it from Settings without resetting the saved language.

The [feature matrix](qa/FEATURE_MATRIX.md) and [parity audit](qa/PARITY_AUDIT.md) describe
source implementation and remaining limits. Physical multi-display capture, Continuity Camera,
VoiceOver and representative OCR quality still require evidence for this release candidate.
Scroll stitching and translation are not advertised release capabilities. No measured
accuracy advantage or full TextSniper parity is claimed.

The App Store configuration excludes automatic scrolling and external paste-key observation,
including their permission prompts. It routes update checks to the installed App Store.
Development builds retain the experimental scroll/paste controls. Translation and local LLM
generation report unavailable instead of supplying placeholder results.

## Name and compatibility

| Property | Value |
|---|---|
| Public name / macOS bundle filename | `Textractor Pro` / `Textractor Pro.app` |
| macOS bundle identifier | `com.textractor.app` |
| macOS scheme, Swift module and executable | `Textractor` |
| macOS version / build defaults | `2.0.0` / `2000` |
| iOS bundle identifier / scheme | `com.textractor.app.ios` / `TextractorMobile` |
| iOS version / build defaults | `1.0` / `1` |

Existing preferences and storage identifiers retain the original identity. The two platform
targets currently have different bundle identifiers; do not assume an existing universal
purchase or shared App Store Connect record. Verify the actual Apple-account records before
creating or changing them. Build numbers must also be checked against prior uploads.

## Develop on a Mac

Run from the repository root using a Mac with Xcode, its command-line tools and XcodeGen:

```sh
swift test --enable-code-coverage
bash build.sh
open 'dist/Textractor Pro.app'
xcodegen generate
open Textractor.xcodeproj
```

Choose `Textractor` for macOS or `TextractorMobile` for iOS. `build.sh` creates an ad-hoc
development bundle; it does not install the app or produce an App Store submission. Screen
capture requires Screen Recording permission. File import provides a separate OCR path.

For source/configuration checks, including metadata and privacy-manifest structure:

```sh
python3 scripts/check_release_signoff.py --platform macos --stage candidate
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

Candidate validation does not require signing credentials or invent passed native/device
checks. [Validation evidence](qa/VALIDATION.md) identifies previously tested commits; new
implementation changes require fresh evidence.

## Prepare a Mac App Store archive

The signed App Store path is separate from the development bundle. Configure your actual
Apple team and signing assets locally, then run:

```sh
TEAM_ID='YOUR_APPLE_TEAM_ID' bash scripts/archive_appstore.sh --platform macos --action archive
```

`YOUR_APPLE_TEAM_ID` is an example to replace, not a configured credential. The script's
default action is `archive`; `export` and `upload` are explicit actions. Follow the
[release plan](qa/RELEASE_PLAN.md) for native QA, signing, evidence, metadata, export and
upload. App Store review submission and public release are separate Apple-account actions.

[Store metadata drafts](appstore/README.md) use the Textractor Pro name and leave unverified
contact details, URLs, screenshots and account decisions incomplete. The submission gate
rejects incomplete signoff. The short [release checklist](RELEASE_CHECKLIST.md) links to the
same plan rather than defining a second release process.

## iOS screenshot review

The `TextractorMobile` target imports user-selected screenshots from Photos or Files. It
preserves imported source bytes, extracts text on device, supports logged corrections and
reviewable overlap suggestions, and creates numbered US Letter PDF packets. Search includes
exact and fuzzy matching plus related-meaning search where Apple's English sentence model
is available. Onboarding is skippable and replayable.

This target does not read the Messages database, control Messages scrolling, infer missing
dates, authenticate a conversation or certify court admissibility. Shared LLM-link import is
not implemented. See [iOS capabilities and limits](qa/IOS_DIRECTION.md). iOS device and
submission checks are tracked independently of the Mac release.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/Textractor/` | macOS app, services, views and resources |
| `Tests/` | macOS unit tests and executable UI playtests |
| `ios/TextractorMobile/` | iOS import, OCR, review, search and PDF export |
| `ios/TextractorMobileTests/`, `ios/TextractorMobileUITests/` | iOS regression and UI coverage |
| `qa/` | Release plan, feature scope, evidence and signoff records |
| `appstore/` | Draft platform-specific store metadata and screenshot instructions |
| `scripts/` | Validation, benchmarks and explicit archive/export/upload tooling |
| `fastlane/` | Wrapper lanes for the documented App Store process |
| `webapp/`, `windows/` | Separate companion projects, outside native App Store signoff |

The native OCR implementation uses Apple frameworks on device. Captures, extracted text,
history, recovery files and exports can contain sensitive information. Review the
[privacy policy](PRIVACY_POLICY.md), actual storage behavior and intended sharing destination
before release. Source-level privacy declarations do not establish device-tested deletion
or encryption across every storage path.

Made by [Lucky Clover](https://soundcloud.com/lucky-clover).
