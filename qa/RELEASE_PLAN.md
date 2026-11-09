# Textractor Pro release plan

Updated November 9, 2026. **Status: implementation candidate; submission is blocked until
current native, physical-device and Apple-account evidence is recorded.**

This is the canonical Mac-first release process. The public name is **Textractor Pro**.
The user reported that Textractor was unavailable in the App Store; acceptance or reservation
of Textractor Pro has not been verified. Do not mark that check passed from a source rename.

## Release scope and evidence

The macOS target is an OCR utility for macOS 14+. Its default version/build is **2.0.0 / 2000**;
the iOS 17+ screenshot-review target defaults to **1.0 / 1**. Check existing App Store Connect
builds before choosing the next build number. Public filenames change to `Textractor Pro.app`;
the macOS executable/module/scheme remains `Textractor` and bundle ID remains
`com.textractor.app`.

| Evidence level | What it establishes | What remains separate |
|---|---|---|
| Candidate validation | Source/configuration, resource and metadata checks | Native compilation, signing and operation |
| Native build and tests | Results for the exact tested source and environment | Physical displays, permissions, camera and representative accuracy |
| Device acceptance | Recorded behavior on identified devices and OS versions | App Store account settings and review |
| Signed archive validation | A particular archive's identity, resources and entitlements | Upload processing, Apple review and release |
| Submission acceptance | Apple received the selected version/build for review | Approval and storefront availability |

[VALIDATION.md](VALIDATION.md) records prior CI evidence. It is historical evidence for its
listed commit, not a fresh pass for subsequent source changes. [FEATURE_MATRIX.md](FEATURE_MATRIX.md)
contains implemented behavior and gaps. Scroll stitching, translation, shared LLM-link import,
invented model output, quantified superiority and court-admissibility claims are excluded from
the store description. Unfinished functionality must be unavailable in the submitted build,
or remain a blocker with its own acceptance evidence.

The `APP_STORE` build excludes System Events scrolling, its menu entry and overlay mode;
it also excludes the external paste-key monitor and its Accessibility prompt/control.
Saved preferences do not enable these paths in the store build. Update checks open the
installed App Store instead of contacting GitHub. Translation and local LLM generation are
unavailable; the unimplemented auto-save control is removed. Verify these boundaries on the
signed candidate, alongside the newly visible privacy-policy link.

The release record uses per-platform checks and per-check evidence. Keep pending entries
pending until the corresponding execution or account observation is recorded. A macOS
submission does not require pretending the independent iOS device checks passed.

## Phase 1 — Confirm the candidate and identity

1. Open the correct checkout and inspect local changes before updating it:

   ```sh
   git status --short
   git branch --show-current
   git log -1 --oneline
   ```

2. Record the commit selected for testing. Preserve unrelated local work. Record subsequent
   release-code changes and rerun the affected native/device checks; do not reuse stale evidence.
   The archive tool requires a clean checkout for provenance. Commit the intended candidate
   before archiving, or use an isolated clean checkout; do not discard unrelated files to pass it.
3. Confirm the generated project still uses `com.textractor.app` for macOS and
   `com.textractor.app.ios` for iOS. The different identifiers currently represent different
   targets; verify their Apple-account records before changing that arrangement.
4. Check the app filename, visible name, permission text, Settings/About text and store draft
   all use Textractor Pro. Retain compatibility identifiers for existing settings and history.
5. Confirm version/build in source, signed archive, metadata and release record agree. Do not
   derive a release build number from launch count or assume build 2000 is unused.

## Phase 2 — Build and test the current source

Run the structural gate and Python regression suite from the repository root:

```sh
python3 scripts/check_release_signoff.py --platform macos --stage candidate
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

Use a Mac with Xcode, matching command-line tools and XcodeGen for native verification:

```sh
mkdir -p qa-results
export TEXTRACTOR_QA_OUTPUT="$PWD/qa-results"
swift test --enable-code-coverage
python3 scripts/benchmark_report.py qa-results/ocr-measurements.json --output qa-results/ocr-summary.json
bash build.sh
xcodegen generate
xcodebuild test -project Textractor.xcodeproj -scheme Textractor \
  -destination 'platform=macOS' -resultBundlePath qa-results/playtests.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Use a fresh result-bundle path for each run because Xcode rejects an existing one. Keep logs,
XCTest results, screenshots and benchmark inputs with the exact commit, macOS version, Xcode
version, Mac model and architecture. Preserve failed results as well as the successful rerun.

The ad-hoc bundle from `build.sh` is a development artifact. Run the capture/privacy tests
again using the signed sandbox candidate that corresponds to the intended release configuration.
Unsigned UI tests do not establish TCC, provisioning or sandbox behavior. Synthetic OCR
fixtures establish regression behavior only; add the representative corpus in the feature matrix
before asserting product-wide accuracy.

## Phase 3 — Complete physical Mac acceptance

Use a separate macOS test account or controlled test profile where practical. Do not reset
the user's normal system permissions or delete their real capture history to simulate a clean install.
Use fictional test content, and record each result and any defect with a screenshot or log.

| Check | Steps and acceptance evidence |
|---|---|
| First launch and identity | Open `Textractor Pro.app`; verify name/icon, a reachable menu-bar entry, onboarding skip on every step and replay. Quit/relaunch; preserve the user's selected OCR language. |
| Screen Recording | Before granting access, try image import and then screen capture. Verify an actionable explanation for denial. Grant access using macOS, retry as instructed, revoke and retry. No blank success or unrelated clipboard replacement on failure. |
| Region, window and full display | Capture prose, a short label, six digits, source code and a table. Compare copied text against the source. Cancel using Escape and retry; empty content must not be reported as a valid extraction. |
| Multiple displays | Use the Mac's internal display plus an external display at different scale factors. Place it left/right/above/below, activate from each pointer location, capture content near edges, switch full-screen Spaces/Stage Manager and disconnect a display during selection. Record the selected display and actual captured pixels. |
| Language persistence | Select French → English (US) → Automatic → English (US), closing Settings and restarting between transitions. Check displayed selection and recognition behavior. |
| Shortcuts and reachability | Test default ⌘⇧2, custom shortcuts, conflict handling, Escape, right-click activation, previous-region capture and each Dock/menu-bar mode. Verify configured shortcut labels match live behavior. |
| Continuity Camera | On the user's compatible paired iPhone/iPad, complete a photo and a three-page document scan. Verify every page in order. Cancel on each device, try an unavailable device and retry. Test scan limits with fixtures before claiming larger documents. |
| Clipboard and output | Verify ordinary copy, additive append, duplicate text, undo, clear and relaunch persistence. A failed extraction must leave unrelated clipboard text unchanged. Verify opt-in links remain off by default and honor allowed schemes/limits. |
| Accessibility | Navigate the menu, Settings, onboarding, permission explanation and result actions with keyboard and VoiceOver. Inspect focus, labels, contrast, text-size behavior and Reduce Motion. Attach Settings/onboarding screenshots from this candidate. |
| Privacy and storage | Verify history retention, cache/recovery files, additive-file removal when disabled, export paths and reset boundaries using test data. Confirm the published policy describes what actually remains in each store. A redaction option does not establish that every raw image or store is redacted. |
| App Store feature scope | Confirm the signed store build exposes only supported features. Verify store update routing and the treatment of scroll capture, external paste observation and unavailable translation/model functionality. Do not request Accessibility permission for a disabled store feature. |
| Stability and quality | Exercise repeated capture/cancel/import/relaunch cycles; run the representative OCR corpus and inspect memory/latency on the reference Mac. Record failures and use explicit acceptance criteria from the feature matrix. |

Continuity Camera requires a compatible device/OS configuration. Apple's setup requirements
should be checked against the actual test devices; a simulator cannot complete this check.
The automated geometry tests do not replace physical secondary-display capture.

## Phase 4 — Finish Apple-account and store materials

1. Sign in to the intended Apple Developer and App Store Connect team. Verify membership,
   agreements, App ID, certificates/profiles and the existing Mac app record. Do not create a
   duplicate app record to avoid investigating an identity mismatch.
2. Set or verify **Textractor Pro** as the localized app name in the correct editable record.
   Save and confirm that App Store Connect accepts it. Record evidence without credentials or
   private keys. If unavailable, stop the name-specific submission and obtain the next name.
3. Confirm `com.textractor.app` matches the record. Apple does not allow a bundle ID change
   after uploading a build. Check any earlier uploads before choosing the next build number.
4. Review [appstore/macos/en-US.json](../appstore/macos/en-US.json). Replace null support and
   privacy URLs only with live, reviewed pages. The support page must contain real contact
   information. Check both URLs in a signed-out browser and from the app where linked.
5. Add actual review-contact details. Review the privacy questionnaire against the final app,
   SDKs, optional network paths, storage and sharing. Record explicit owner decisions for
   pricing/availability, age rating, content rights and export compliance. No price, encryption
   exemption, privacy answer or legal identity is inferred by this plan.
6. Capture the real release UI with fictional content. Mac screenshots must use one of Apple's
   accepted 16:10 sizes: 1280×800, 1440×900, 2560×1600 or 2880×1800. Apple accepts JPEG/PNG;
   this repository's reproducible screenshot gate uses 1–10 PNG files.
   Use the intended UI, without unfinished features or unverified claims. Add exact repository-
   relative files to `screenshot_paths` only after review; see [screenshot brief](../appstore/README.md).
7. Reconcile the description, screenshots and reviewer notes with physical test results.
   Remove an unverified advertised capability or complete its test before submission. Set
   metadata status to ready only after the required fields and evidence are complete.

The version defaults and bundle IDs in this checkout do not prove anything is reserved,
configured, purchasable or approved in Apple's account systems.

## Phase 5 — Archive, export and upload

The canonical tool is `scripts/archive_appstore.sh`. `archive` is the default action;
`export` and `upload` must be selected explicitly. Read its current help before configuring
paths or authentication. Keep certificates, passwords and App Store Connect API keys outside git.

```sh
bash scripts/archive_appstore.sh --help
TEAM_ID='YOUR_APPLE_TEAM_ID' bash scripts/archive_appstore.sh --platform macos --action archive
```

Replace `YOUR_APPLE_TEAM_ID` with the verified team. Inspect the generated archive in Xcode
Organizer and confirm the executable/bundle identity, version/build, icon, privacy resources,
signed sandbox entitlement, intended architectures and provisioning team. Retain the archive
and validation output. Confirm this is an application archive, not a generic archive containing
extra installed helper products.

The archive command checks the actual app resources and both `arm64` and `x86_64` executable
slices. For signed archives it also checks a certificate-backed signature, the bundle identifier,
the selected Apple team and the signed sandbox entitlement. These checks do not replace launch
and permission testing on a Mac.

The default Mac archive path is `dist/appstore/macos/2.0.0-2000/Textractor Pro.xcarchive`.
`--version` and `--build` provide explicit overrides; `--archive-path` selects a particular
archive. Use the same selected archive on later export/upload commands. Existing archive and
export paths are not overwritten. `--unsigned` creates a separate compile-only artifact which
cannot be exported or uploaded by this tool. `--allow-provisioning-updates` explicitly permits
Xcode provisioning updates; it is not enabled by default. See [signing setup](../fastlane/README.md)
for supported local Xcode-account/API-key authentication. Never put keys in the metadata JSON.

Export is available after candidate validation so that Apple's package validation can be
completed before final submission signoff:

```sh
TEAM_ID='YOUR_APPLE_TEAM_ID' bash scripts/archive_appstore.sh --platform macos --action export
```

Inspect the exported package and record Apple's validation output. Archive/export actions
perform no upload and do not claim that physical testing or store metadata is complete.

Complete the macOS platform record in `qa/release-signoff.json`: the exact tested commit,
matching version/build, each passed check and its own evidence references. Mark status approved
only when all required checks have evidence. Run:

```sh
python3 scripts/check_release_signoff.py --platform macos --stage submission
```

The submission gate checks this platform's required evidence and source consistency, including
dirty/untracked release changes. Resolve failures by supplying real evidence or correcting the
implementation, not by deleting checks. Account metadata and screenshots must be complete.

When the signed artifact is reviewed and the submission gate passes, upload is a separate
explicit operation with the same selected candidate and local authentication:

```sh
TEAM_ID='YOUR_APPLE_TEAM_ID' bash scripts/archive_appstore.sh --platform macos --action upload
```

A successful upload command establishes delivery only; check Apple's processing result.
An upload is not a request for App Review and is not a public release. Mac App Store distribution
uses Apple's store signing/export route. Developer ID notarization and DMG distribution belong
to a separate distribution process.

## Phase 6 — Submit and confirm the result

1. Wait for the uploaded build to finish processing in App Store Connect. Resolve any warnings
   or errors relevant to the submission; select the exact intended version/build.
2. Confirm all required metadata, screenshots, privacy details, reviewer contact and compliance
   answers. Paste the reviewed notes from the Mac metadata draft and verify they match the build.
3. Choose the release mode intentionally. Record whether release is manual, automatic after
   approval, or scheduled; do not assume public launch was authorized by preparing a candidate.
4. Submit the completed version for App Review when the owner authorizes that account action.
   Record the status and submission time shown by Apple.
5. If Apple requests changes, preserve the message, address the concrete issue, increment the
   build where required, and repeat affected checks. Do not claim approval from a clean build
   or attempt to predict a guaranteed review time.
6. After approval/release, verify the product page name, selected version and actual install from
   the store. Preserve the submitted archive, source commit, metadata snapshot and acceptance evidence.

## iOS follow-on

The iOS target uses `com.textractor.app.ios`, not the Mac bundle ID. Decide its App Store record
and commercial relationship separately. The draft is [appstore/ios/en-US.json](../appstore/ios/en-US.json).

Run the candidate gate with `--platform ios`, build/test `TextractorMobile` on an available
iOS simulator, then test Photos/Files import, sharing, source retention, review corrections,
overlap handling, search, accessibility and physical PDF printing on the intended iPhone/iPad.
Confirm originals are retained separately from reconstructed transcripts and user-supplied
timestamps. The product must not claim conversation authentication or court admissibility.

Use `scripts/archive_appstore.sh --platform ios --action archive` with the verified team, then
export for validation and complete the independent iOS submission gate before upload. iOS submissions
also need current Apple-required SDKs, its own screenshots, account metadata and build-number check.
See [IOS_DIRECTION.md](IOS_DIRECTION.md) for current limits and acceptance criteria.

## Apple references checked November 9, 2026

- [App information: name, bundle ID and privacy policy](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Mac App Store requirements, section 2.4.5](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [App privacy details and on-device processing](https://developer.apple.com/app-store/app-privacy-details/)
- [Distribution-signed Mac code and Xcode archives](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Upload builds and supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Upcoming SDK requirements](https://developer.apple.com/news/upcoming-requirements/)
- [Platform version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

Apple's current Xcode 26 minimum notice names iOS/iPadOS/tvOS/visionOS/watchOS; its upload
matrix lists different minimums for macOS. Use a toolchain capable of building this repository
and check the current platform-specific upload requirements before the actual submission.
