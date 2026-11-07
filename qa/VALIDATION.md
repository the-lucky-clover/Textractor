# Native QA and production signoff

## Current evidence

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
