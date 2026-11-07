# Native QA and production signoff

## Current evidence

- Local Python measurement/release-gate suite: **12 passed**.
- Shell, plist, workflow and XcodeGen-spec parsing: passed locally.
- Swift tree-sitter grammar check: 78/79 files parsed without errors at the initial pass;
  the existing async getter in CaptureProvider is a grammar limitation / unresolved parse
  result, not an Xcode compilation result. Subsequent files need native compilation too.
- First CI execution was cancelled before checkout: retired macOS 14 runner configuration.
  Workflows now target macOS 15.
- Native compilation, XCTest, UI screenshots, OCR timing and physical-device testing must
  be judged from the latest CI result. This document does not claim they passed.
- The initial secret scan crashed on the repository's invalid glob-shaped regexes.
  Configuration now extends default detectors and excludes only generated/binary files.

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
5. QR/barcode: compare payload byte-for-byte; no automatic URL opening. Switch back to OCR.
6. Read aloud: change speed, language and stop mid-sentence. Add three captures, undo once,
   clear the batch, and test the capacity boundary. The batch is session-only.
7. Capture previous region, shortcut cancellation/conflict, right-click capture and all
   Dock modes. Use two displays with different scale factors and disconnect one.
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
