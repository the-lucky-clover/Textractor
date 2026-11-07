# Feature coverage and measured improvement plan

Status: implementation candidate, **not production approved**. “Implemented” refers to source changes;
only an attached execution result can change a native test from pending to passed.
No comparison run against TextSniper has been completed. Percent improvement is therefore unverified.

Baseline sources: [TextSniper product](https://textsniper.app/),
[release history](https://textsniper.app/release), and
[Mac App Store listing](https://apps.apple.com/us/app/textsniper/id1528890965).
The baseline describes behavior, not a promise to copy its branding or interface.

| Capability | Textractor Pro implementation / gap | Quantification and acceptance evidence |
|---|---|---|
| Screen OCR: region, window, full display | Existing native pipeline retained; useful short text and numeric strings no longer require three words | 15 measured OCR samples per run after three warm-ups; report character error rate and p50/p95; target CER ≤1% for clean prose, ≤5% code, p95 ≤1500 ms on the reference Mac; not measured yet |
| US English selection | Fresh installs and reset default to `en-US`; underscore/label migration; separate full-width picker; explicit Automatic preserved over stale legacy data | 20 × 5 preference transitions in regression test; target 100/100 persisted correctly plus UI relaunch test |
| Automatic / multiple languages | Use Vision's supported language list and automatic detection; explicit English remains isolated | Test every advertised catalog value; device gate: unsupported language must not be advertised as verified |
| Tiny, low-quality and vertical text | Vision path exists; vertical CJK and degraded image behavior not yet established | Required corpus: 20 small-font, 20 degraded, 20 vertical samples; measure each separately; no aggregate accuracy claim yet |
| File import | Existing image import; corrected file origin | PNG/JPEG/HEIC/TIFF import, cancel, corrupt file; 0 unexpected clipboard changes on failure |
| iPhone/iPad camera | Replaced file-picker substitute with AppKit Continuity Camera requestor | Physical-device photo, unavailable-device and cancel tests; 20/20 successful transfers target |
| Scanned documents | All returned PDF pages rendered in order; explicit 50-page limit | 1-, 3-, 10- and 50-page scans; 51 pages must give a limit error, not a partial success |
| QR and barcodes | Vision decoder; distinct payloads in reading order; does not launch links | Exact generated QR payload assertion; add 10 examples per retail symbology before certification |
| Read aloud / speed / stop | AVSpeechSynthesizer; user rate slider; stop action | Voice, non-English fallback and interruption tests; stop latency target ≤250 ms, pending device run |
| Additive clipboard | Session batch, undo last capture, explicit clear, 1,000,000-character limit | Repeated identical messages must both survive; empty/overflow rejected; unit regression added |
| Persist additive clipboard / clear on paste | **Gap:** session batch deliberately does not persist across quit; automatic clear-on-paste is not implemented | Define consent and retention before adding persistence; do not claim TextSniper parity here |
| Line breaks / paragraphs | Existing flatten setting; formatting regression tests | Preserve exact original line breaks when disabled; preserve Markdown tables; Unicode tests |
| Source code / custom words | Custom vocabulary now reaches the first OCR pass; code formatting setting connected to output | Exact code-character error rate, identifiers, quotes and operators; 200 custom-word UI bound |
| Capture previous selection | Reuses last region in the current session | 20 repeated captures of changing content in fixed region; deny disabled action before a region exists |
| Custom capture shortcut | Native recorder with Escape cancel and conflict feedback; restores previous registration on conflict | Test 10 combinations, one conflict and one restart; secondary per-action global shortcuts remain a gap |
| Right-click quick capture | Status-bar right-click opens region capture | One click → overlay; target 20/20 trials |
| Link opening | Existing deliberate URL action; **gap:** automatic link opening not implemented | No automatic navigation from barcode content; validate http/https actions before expansion |
| Sound / success popup controls | Settings expose sound and notification toggles; native success path respects popup setting | 0 success popups when disabled; failures must stay visible |
| Menu-bar / Dock placement | Existing placement control retained | All three placement modes; permission dialogs and Settings remain reachable |
| History / privacy | Duplicate standard-history insert removed; final output used for preview/history/share; reset clears history and additive batch | Persistence test replaces unconditional placeholder; additional raw-image/knowledge-store privacy audit still required |
| Onboarding | Four steps: capture, language, camera, options/permission; Skip every step, Back, replay from Settings | 1 click to skip from every step; replay begins at step 1; UI test covers replay, navigation and completion |
| BreakingDad styling | Existing dark lab palette, new Pro badge, inset wordmark, section spacing and native accessible switches | Header widths unchanged: menu 232 pt, Settings 252 pt; screenshot and VoiceOver checks pending |
| Motion / multiple displays | Banner task cancels with view lifecycle; system Reduce Motion respected; Settings anchor uses correct display | 0 recurring banner tasks after close; 0 clipped controls at supported display sizes; native checks pending |
| Scroll capture | Fixed nonincrementing loop; honors interval/overlap/limit; cancellation checks; max 50 scrolls / 32,000 pixels | **Not signed off:** fixed-overlap stitching can duplicate or omit content, arrow scrolling depends on focus; needs image-registration work and a measured corpus |
| Updates | Installed version uses bundle build number; no false “up to date” claim | **Gap:** no remote update feed configured |
| Licensing / store distribution | Display name changed; app identity retained | **Gap:** App Store reservation, commercial entitlements and signed distribution require account verification |
| Translation | Placeholder output disabled; unavailable state shown | 0 fabricated translations in clipboard; real translation backend is a separate unfinished feature |

## Meaning of improvement

Code-level changes such as “an unbounded counter is now capped at 50” are inspectable.
Claims about speed, accuracy, user preference or superiority need measurements. Compare
identical images and the same hardware/OS, excluding warm-up consistently. Do not treat
Apple Vision confidence as measured OCR accuracy. The scorer rejects unmatched cases,
changed ground truth, different environments and duplicate measurements.

## iOS extension

See [iOS implementation and limits](IOS_DIRECTION.md) for screenshot extraction, optional
timestamps, overlap review, reconstructed message layout, search and numbered black-and-white
packets. Shared-link import remains a proposal. Simulator tests do not constitute device or
court-use approval.
