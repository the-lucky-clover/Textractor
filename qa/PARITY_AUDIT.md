# TextSniper parity and regression audit

Candidate branch: `codex/textractor-pro-readiness`. No production signoff and no
measured superiority over TextSniper. English (US) remains the default.

## Baseline

Reviewed on November 7, 2026:

- https://textsniper.app/
- https://textsniper.app/release — 1.13.0, dated September 24, 2026.
- https://apps.apple.com/us/app/textsniper/id1528890965 — Mac-only listing.

The release history includes secondary action shortcuts, overlay Cmd-L/H/S,
persistent additive history, undo clear, clear on Cmd-V, optional URL opening,
speech controls, QR/barcodes, previous selection, Continuity Camera and custom words.
This implementation adds the missing controls while keeping existing app identity
and the user's US English default. Features and acceptance targets are mapped in
[FEATURE_MATRIX.md](FEATURE_MATRIX.md).

## Defects investigated in this iteration

These are scoped regression cases, not an estimate of all bugs in the product.
Final execution counts and commit IDs are in [VALIDATION.md](VALIDATION.md).

| Case | Failure mechanism | Change and regression evidence |
|---|---|---|
| Secondary-screen activation | Local overlay hover coordinates were compared with global screen frames; a single borderless window was moved across screens | One stationary, keyable overlay per screen; pointer sampled before activation; tests cover left/right/above/below arrangements and 1×/2× crops. Physical two-monitor verification remains pending. |
| Full-screen / Stage Manager overlay | Capture windows lacked explicit participation behavior for other applications | `canJoinAllApplications` and `fullScreenAuxiliary`; exact flags tested; physical Spaces/Stage Manager playtest pending. |
| Wrong screenshot extent | Window capture mixed display-relative and global coordinates; missing display could fall back to another screen | Desktop-independent window filter; dimensions derived from filter point-to-pixel scale; missing display/invalid crop fails explicitly. Real ScreenCaptureKit/TCC capture remains a device check. |
| Capture-mode drift | Independent per-display mode state; stale scroll flag could survive cancellation | Shared overlay session, explicit mode passed to callback, cancellation resets state, display changes dismiss overlays. |
| Hotkey routing | A Carbon handler could consume an event intended for a different registered action | Return `eventNotHandledErr` for other IDs; real Carbon event dispatch test reaches both registered handlers. |
| Shortcut recorder interception | Command combinations could go to app menus or existing global bindings | Recorder consumes key equivalents, suspends capture shortcuts and restores registration on finish/cancel/blur; Command-W and Escape regression. |
| Function-key labels | Assumed contiguous Carbon key codes | Explicit F1–F20 mapping; all 20 labels asserted. Handler-install errors now return failure and manager teardown unregisters callbacks. |
| Retry option loss | Retry discarded per-capture language and action options | Retry carries language and capture intent through to the new pipeline invocation. |
| Per-capture language judged as default | Non-English override was recognized in its selected language but judged using saved English | One settings snapshot applies the override consistently to OCR, verdict, speech and metadata; explicit Japanese/Automatic override regressions preserve the saved US default. |
| Redaction bypass through table formatting | Table reconstruction used raw observations after the initial scrub; rich paste used the raw table string | Final output is scrubbed after formatting, and the table rich-text representation uses that same final string; regression preserves table structure while removing an email. |
| Vertical reading-order metadata | OCR result discarded selected language before reconstruction | Explicit language retained; CJK column-order regression and actual Vision image fixture. Bounded pixel reflow is attempted only for upright vertical glyphs on a nearly uniform background when another vertical column was recognized; no characters are inserted. See final evidence for recognition limits. |
| Scroll page order / allocation | Bitmap drawing placed the first page below the second and force-unwrapped allocations | Pixel-level page-order/overlap test; mismatched widths and invalid overlap rejected; 32,000-pixel height and 32-million-pixel total bounds; throwing allocation path. Overlap estimation itself remains unfinished. |
| False clipboard success / destructive undo | New batch persistence and undo paths needed failure/ownership checks | Isolated pasteboard tests cover failed copy, restart, corrupt file preservation, repeated entries, clear/undo and unrelated clipboard content. |
| False update status | No comparison with a published remote release | Explicit stable-release query; HTTP404 is no published release, HTTP403 is failure; malformed/prerelease versions are rejected. |

Removed the unreferenced alternate `DefaultCaptureOrchestrator` and unused coordinator
helper pipeline. The app now has one active capture-output path instead of retaining
hundreds of lines of divergent, unused clipboard/history code.

The first overlay UI test failed because it queried an AX Window while macOS exposes
the borderless overlay as an AX Dialog. The exported hierarchy showed the overlay at
1024×768. The query now uses its actual dialog identifier. This was a test defect,
not evidence that capture activation failed in that CI run.

## Quantification rules

- Prior source baseline: 72 macOS unit tests and 3 UI playtests. Candidate suite: 96 unit tests and 4 UI playtests (24 additional unit tests, one additional UI flow).
- Test additions exercise behavior and failure paths; a test count is not a quality score.
- Geometry cases are simulations, not eight physical monitor configurations.
- Synthetic OCR timing measures this app on a CI runner. No same-device TextSniper
  comparison has been executed; no percentage-faster or percentage-more-accurate claim.
- The synthetic two-column Japanese fixture initially returned 4 of 7 characters; bounded original-pixel reflow recovered all 7 in order. A passing single fixture cannot establish general vertical/degraded-text accuracy.
- Batch storage is bounded at 1,000,000 characters. Clear-on-paste monitors Cmd-V and
  clipboard ownership; it cannot observe every application's menu-based paste operation.
- Automatic opening is off by default and accepts at most three distinct explicit
  HTTP(S) URLs per capture. It does not bypass browser or operating-system controls.

## Remaining production gates

1. Real secondary-display activation, different scale factors, full-screen apps,
   Stage Manager, Spaces, display disconnect/reconnect and Screen Recording denial.
2. Physical Continuity Camera photo/multipage/cancel and unavailable-device testing.
3. VoiceOver, actual speech interruption/rate, permission and shortcut conflict testing.
4. Representative OCR, tiny/degraded/vertical text, barcode and search corpora.
5. Scroll-overlap estimation with fixed headers, repeated rows and asynchronous loading.
6. iOS Photos/Files/device sharing, physical black-and-white printing and provenance review.
7. App Store name acceptance, signed/notarized distribution and commercial licensing.
8. macOS 12/13 compatibility if matching the competitor's current store deployment floor
   is required; Textractor currently requires macOS 14.

The release record stays blocked while these checks are outstanding. No automatic
installer, license activation/transfer, direct Messages-database extraction, shared-LLM
link importer or translation backend is represented as complete.
