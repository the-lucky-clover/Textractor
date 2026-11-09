# Native QA and production signoff

## November 9 verified macOS release candidate

Source candidate: `a49bee68f3ca4a7ceb33167a007f3c6b7b1050d7`.
[CI run 42697333842](https://github.com/the-lucky-clover/Textractor/actions/runs/42697333842)
completed successfully in all four jobs: release configuration, security, native macOS and iOS.

GitHub tested synthetic PR merge `c458b6ef05c3d79078adcffc4c8ee1585addc546`. Its full Git tree is
identical to the source candidate (`c1df57ec938eb6f8295ad7320acae794b17ff7b8`). The local macOS
shipping-input digest also matches the archive provenance:
`7086fa6e73a14061268bb01c54effba7ce514a7196fef86a0d360b1d640e3935`.
Subsequent changes limited to this report and `release-signoff.json` record evidence without
changing the tested shipping inputs.

### Verified results

| Check | Result |
|---|---|
| Portable release, metadata, provenance, benchmark and packaging checks | 51 tests passed locally and in CI |
| Candidate configuration and release shell syntax | macOS and iOS passed |
| Secret scan | Passed |
| Native macOS suite | 118 tests passed; zero failures |
| `APP_STORE` policy/settings suite | 16 tests passed; zero failures |
| macOS UI playtests | 4 tests passed; zero failures |
| Standalone app and development signature | Build, packaged-resource check and strict signature verification passed |
| Mac App Store compile archive | Version 2.0.0, build 2000; unsigned; both arm64 and x86_64 slices passed verification |
| iOS regression target | 10 unit tests, 1 UI playtest and unsigned App Store archive passed |

[Native job](https://github.com/the-lucky-clover/Textractor/actions/runs/42697333842/job/129432722247)
used macOS 15.8.2 on arm64, Xcode 26.3 (17C529), and the macOS 26.2 SDK. The standalone bundle
uses an ad-hoc development signature. No production certificate, provisioning profile or
App Store upload was exercised.

The native suite includes nine capture-library storage/key tests, three Dock lifecycle tests,
and nine release-safety tests. It exercises transient OCR storage across saves/reopens, legacy
cache cleanup/recovery, locked/missing keys, unavailable storage, recovery-image collisions,
corrupt history, diagnostics opt-in and unavailable model behavior. Existing language, OCR,
geometry, shortcut, clipboard, barcode and output-policy regressions remain passing.

The 15-sample synthetic OCR smoke corpus matched exactly: CER 0%, p50 595.22 ms, p95 625.04 ms.
These results apply to those clean CI fixtures. They do not establish representative accuracy
or a comparison with another product. The representative-corpus acceptance check remains open.

Six exported macOS screenshots were inspected: the 252 pt Settings panel shows Textractor Pro
and English (US); welcome steps retain readable text and navigation; the capture-overlay HUD
and Continuity import dialog are visible and readable. The runner's Screen Recording permission
is **not granted**, so the overlay test verifies activation/cancellation, not actual screen
extraction. Camera-dialog cancellation is covered; an actual paired-device capture is not.
The screenshots are QA evidence, not approved App Store marketing assets.

### Release work included

The candidate separates App Store archive/export/upload from development builds; applies the
Textractor Pro name, sandbox entitlements and root privacy manifest; validates built resources
and universal architecture slices; and checks signing identity/team before signed export.
App Store compilation excludes experimental scrolling and external paste observation. The
macOS pass also restores Dock-only launch/reopen, corrects shortcut labels, respects Reduce
Motion in the capture menu, and avoids fatal installed-app SwiftPM resource fallbacks.

The capture library no longer persists new decrypted OCR caches. Existing cached plaintext is
logically cleared after successful recovery/authentication. This is not secure erasure of
previous SQLite pages, write-ahead logs or backups. An unavailable optional library no longer
terminates app startup, and Keychain failures do not silently replace encryption keys.

Previously staged iOS metadata, privacy and opaque-icon work is included and passed the iOS
regression job. [ICON.md](../appstore/ios/ICON.md) retains its source record.

### Still required before release

`qa/release-signoff.json` remains blocked on signed sandbox launch, actual multi-display and
Screen Recording permission behavior, paired Continuity Camera capture/cancel, VoiceOver,
representative OCR, and real existing-user migration. Development/CI fixtures do not establish
migration between a nonsandboxed support folder and a signed sandbox container.

Apple-account verification must supply the accepted product name and build number, production
signing assets, completed support/privacy URLs and review contact, actual store screenshots,
account declarations and App Store validation. No upload, review submission or public release
has occurred. Follow [RELEASE_PLAN.md](RELEASE_PLAN.md) for those remaining actions.

## Prior native evidence (November 7)

At source/test commit `f6250f3ded365f956347ac034399161d77020b59`,
[CI run 42376263273](https://github.com/the-lucky-clover/Textractor/actions/runs/42376263273)
completed successfully in all three jobs:

- Python measurement/release-gate suite: **12 passed**. The gate additionally requires
  representative OCR quality evidence; synthetic smoke results alone cannot satisfy it.
- Secret scan: **passed**.
- macOS: **96 unit tests and 4 UI playtests passed**, standalone release build and
  development-signature verification passed. This is 24 more unit tests and one more UI
  flow than the prior 72/3 baseline. Counts are coverage inventory, not a quality score.
- UI coverage includes US English defaults, French → US English → relaunch, onboarding
  skip/replay preserving French, camera-dialog cancel, capture overlay activation, Escape,
  reopening and the Cmd-L option toggle. The borderless overlay is an AX Dialog.
- Geometry regressions cover four synthetic display arrangements at two scale factors,
  crop conversion/rejection and keyable negative-coordinate windows. Native Carbon event
  dispatch reaches two registered action handlers; shortcut recording, F1–F20 labels,
  capture-intent overrides, clipboard persistence/undo/ownership, URL policy, update
  responses, table redaction and scroll image order/bounds also pass.
- OCR smoke corpus: **15/15 exact synthetic samples; CER 0%; p50 626.65 ms; p95 758.92 ms**.
  These are three clean cases repeated five times. They are not real-world accuracy,
  a same-hardware baseline comparison or evidence of superiority over TextSniper.
- Separate vertical Japanese fixture: initially only `文字認識` was returned (4 of 7
  characters); the final run returns `日本語文字認識` (7 of 7) in column order after bounded
  original-pixel reflow. QR and Code 128 generated payload tests also pass. One fixture
  does not certify general vertical, degraded-text or barcode accuracy.
- iOS: build, **10 unit tests and 1 UI playtest passed**. The UI flow covers fixture import,
  review, the typo query `libary`, keyboard dismissal, export options, English (US), and
  onboarding replay/skip. Actual external sharing and Photos/Files permission flows remain
  physical-device checks. Synthetic unit-test import took **3288.34 ms** in this simulator;
  this single cold measurement is not a latency distribution or comparative speed claim.
- iOS regressions retain weekday-starting messages containing numbers and distinct long
  messages sharing the first 1,000 characters. Original image export matches imported
  bytes; source tampering stops export. PDF transcript/reconstruction and source appendix
  checks pass. Four fixture pages were visually inspected in the earlier renderer iteration
  at `23597d5`; that renderer is unchanged. This is not a physical print test.
- Settings and overlay screenshots were visually inspected: the 252 pt Settings panel
  shows English (US), and the overlay HUD has readable instructions and option states.
  The runner displays Screen Recording permission as not granted; the overlay UI test
  therefore establishes interaction, not actual ScreenCaptureKit extraction.
- Physical iPhone camera/import, VoiceOver, actual multi-display capture, representative
  OCR/search corpora, reliable scroll-overlap estimation, physical printing, commercial
  signing and App Store name acceptance remain unverified.

GitHub artifacts retain XCTest results, screenshots, PDF fixtures, logs and benchmark
measurements for 14 days. Documentation-only updates after this commit do not change the
tested implementation. The [parity and bug audit](PARITY_AUDIT.md) records defects, changes,
quantification limits and remaining gates; it does not claim a total product bug count.

Earlier runs exposed the overlay test's incorrect AX role, missing vertical text and a
Swift type-checking limit in the new fallback. Those failures remain in CI history; the
original exact Japanese assertion was retained and passes in the final run.

## Execute on a Mac

Requires Xcode with command-line tools, macOS 14 or newer, and XcodeGen.
Run from the repository root:

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

`build.sh` builds an ad-hoc development bundle; it no longer installs, invokes sudo,
or deletes an existing installation. It is not a notarized release.
The Xcode project is generated and intentionally ignored by git. The old screenshot
examples in `Sources/TextractorUITests` are not wired to a test target and are not counted
as coverage. Executable UI tests live in `Tests/TextractorUITests`.

The native workflow keeps standalone-build and UI diagnostics running after a unit-test
failure, while preserving the failed overall result. Screenshot export has a two-minute
timeout so cleanup cannot wait indefinitely on an incomplete XCTest bundle.

UI tests use a unique preferences suite and skip normal bootstrap. They do not click
factory reset, open external privacy settings, request a device camera, or change system
permissions. Unit tests use isolated stores. Test success does not replace VoiceOver,
physical camera, display-topology or signing validation.

## Physical playtesting

1. First launch: skip each of the four onboarding steps independently; relaunch; replay
   from Settings; complete with US English. Confirm existing preferences survive replay.
2. Settings: switch French → English (US) → Automatic → English (US); close/reopen and
   quit/relaunch. Repeat with Reduce Motion, light/dark system appearance, keyboard and VoiceOver.
3. Capture normal text, one word, six digits, code, a table, multilingual and vertical text.
   Copy rich/plain into TextEdit; inspect exact content. Try no-text and permission-denied cases.
4. Import a real iPhone photo and multi-page scan; verify every page and its order. Cancel
   on both devices. Test unavailable device and retry. No separate iOS app is required for this.
5. QR/barcode: compare payload byte-for-byte; no URL opening with the default setting.
   Opt in to automatic links and verify only HTTP(S), at most three distinct links. Switch back to OCR.
6. Read aloud: change speed, language and stop mid-sentence. Add three captures, undo once,
   clear/undo the batch, and test the capacity boundary. Enable persistence, relaunch,
   disable it and verify the saved file is removed. Test owned vs unrelated clipboard Cmd-V.
7. Capture previous region, shortcut cancellation/conflict, right-click capture and all
   Dock modes. Use two displays with different scale factors and disconnect one.
   Place the pointer on each display before activation; test left/right/above/below,
   full-screen apps, separate Spaces and Stage Manager. Repeat Escape and mode toggles.
   Verify one-shot line-break/speech/barcode actions and recording Command-key combinations.
8. Scroll capture: test repeated rows, fixed headers and slow loading. Current overlap
   algorithm is not certified. Do not sign off while text can be omitted/duplicated.
9. History: clear with confirmation, cancel clearing, restart persistence, factory reset,
   redaction and knowledge-mode storage. Verify all sensitive content handling separately.

## Benchmark comparison

The native fixture writes 15 samples: 3 cases × 5 measured iterations, with one excluded
warm-up per case. This is a harness smoke corpus, not a representative product benchmark.
Add the full corpus in FEATURE_MATRIX before marketing an accuracy claim.

```sh
python3 scripts/benchmark_report.py qa-results/candidate.json \
  --baseline qa-results/baseline.json --output qa-results/comparison.json
```

Both inputs must use matching environment metadata, case IDs, iteration numbers and
expected text. Report failed imports explicitly; never drop them to improve scores.
The script reports CER, exact-match rate, p50/p95 and relative latency reduction.
It does not perform or invent a TextSniper run.

## Release gate

`qa/release-signoff.json` remains blocked. Record the exact tested commit, evidence links,
and passed checks only after those executions. Release workflow runs
`python3 scripts/check_release_signoff.py` before packaging/upload. The gate rejects
pending checks, absent evidence and changes to tested source. An App Store name is only
verified after App Store Connect accepts it. A clean CI run is not App Store approval.
