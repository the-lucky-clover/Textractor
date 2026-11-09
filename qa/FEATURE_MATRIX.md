# Feature coverage and measured improvement plan

Status: implementation candidate, **not production approved**. “Implemented” refers to source changes;
only an attached execution result can change a native test from pending to passed.
No comparison run against TextSniper has been completed. Percent improvement is therefore unverified.

Baseline sources: [TextSniper product](https://textsniper.app/),
[release history](https://textsniper.app/release), and
[Mac App Store listing](https://apps.apple.com/us/app/textsniper/id1528890965).
Baseline reviewed: TextSniper 1.13.0 (September 24, 2026). The current App Store listing is Mac-only.
The baseline describes behavior, not a promise to copy its branding or interface.

| Capability | Textractor Pro implementation / gap | Quantification and acceptance evidence |
|---|---|---|
| Screen OCR: region, window, full display | Existing native pipeline retained; useful short text and numeric strings no longer require three words | 15 measured OCR samples per run after three warm-ups; report character error rate and p50/p95; target CER ≤1% for clean prose, ≤5% code, p95 ≤1500 ms on the reference Mac; synthetic CI results are in VALIDATION, representative/reference-Mac targets remain pending |
| US English selection | Fresh installs and reset default to `en-US`; underscore/label migration; separate full-width picker; explicit Automatic preserved over stale legacy data | 20 × 5 preference transitions in regression test; target 100/100 persisted correctly plus UI relaunch test |
| Automatic / multiple languages | Use Vision's supported language list and automatic detection; explicit English remains isolated | Test every advertised catalog value; device gate: unsupported language must not be advertised as verified |
| Tiny, low-quality and vertical text | Explicit CJK reading order and bounded pixel reflow; the two-column Japanese fixture improved from 4/7 to 7/7 characters; full representative accuracy remains unverified | Required corpus: 20 small-font, 20 degraded, 20 vertical samples; measure each separately; no aggregate accuracy claim yet |
| File import | Existing image import; corrected file origin | PNG/JPEG/HEIC/TIFF import, cancel, corrupt file; 0 unexpected clipboard changes on failure |
| iPhone/iPad camera | Replaced file-picker substitute with AppKit Continuity Camera requestor | Physical-device photo, unavailable-device and cancel tests; 20/20 successful transfers target |
| Scanned documents | All returned PDF pages rendered in order; explicit 50-page limit | 1-, 3-, 10- and 50-page scans; 51 pages must give a limit error, not a partial success |
| QR and barcodes | Vision decoder; distinct payloads in reading order; optional HTTP(S) opening defaults off | Exact generated QR and Code 128 payload assertions; add 10 examples per retail symbology before certification |
| Read aloud / speed / stop | AVSpeechSynthesizer; user rate slider; stop action | Voice, non-English fallback and interruption tests; stop latency target ≤250 ms, pending device run |
| Additive clipboard | Bounded batch, undo append/clear, explicit clear, 1,000,000-character limit | Repeated identical messages must both survive; empty/overflow rejected; unit regression added |
| Persist additive clipboard / clear on paste | Opt-in atomic local persistence (0700 directory / 0600 file); opt-in Cmd-V clearing of owned content only | Restart, repeated Unicode entries, corrupt-file preservation, failed-copy, foreign-clipboard and clear/undo regressions; external Cmd-V monitoring needs Accessibility permission; menu paste/secure-input not detected |
| Line breaks / paragraphs | Existing flatten setting; formatting regression tests | Preserve exact original line breaks when disabled; preserve Markdown tables; Unicode tests |
| Source code / custom words | Custom vocabulary now reaches the first OCR pass; code formatting setting connected to output | Exact code-character error rate, identifiers, quotes and operators; 200 custom-word UI bound |
| Capture previous selection | Reuses last region in the current session | 20 repeated captures of changing content in fixed region; deny disabled action before a region exists |
| Custom capture shortcut | 9 global actions and 3 capture-overlay toggles, native recorder, Escape cancel, duplicate/conflict feedback and restoration | Native Carbon dispatch regression, Command-key recorder regression, 20 function-key labels, settings round-trip; physical conflict/wake testing remains |
| Right-click quick capture | Status-bar right-click opens region capture | One click → overlay; target 20/20 trials |
| Link opening | Opt-in automatic opening, at most 3 distinct explicit HTTP(S) links per capture; credentials and other schemes rejected | Policy tests cover schemes, credentials, duplicates and limit; default off; actual browser handoff pending |
| Sound / success popup controls | Settings expose sound and notification toggles; native success path respects popup setting | 0 success popups when disabled; failures must stay visible |
| Menu-bar / Dock placement | Existing placement control retained | All three placement modes; Cmd-drag menu icon removal enabled; physical reachability test pending |
| History / privacy | Duplicate standard-history insert removed; final output used for preview/history/share; reset clears history and additive batch | Persistence test replaces unconditional placeholder; additional raw-image/knowledge-store privacy audit still required |
| Onboarding | Four steps: capture, language, camera, options/permission; Skip every step, Back, replay from Settings | 1 click to skip from every step; replay begins at step 1; UI test covers replay, navigation and completion |
| BreakingDad styling | Existing dark lab palette, new Pro badge, inset wordmark, section spacing and native accessible switches | Header widths unchanged: menu 232 pt, Settings 252 pt; Settings/onboarding screenshots inspected; VoiceOver checks pending |
| Motion / multiple displays | One keyable stationary capture overlay per screen; pointer sampled before activation; shared mode/status; coordinate/crop corrections | Four synthetic display arrangements × two scale factors; invalid crop rejection; single-display activation/cancel UI test; physical secondary-screen/full-screen/Stage Manager checks remain |
| Scroll capture | Fixed nonincrementing loop; honors interval/overlap/limit; cancellation checks; max 50 scrolls / 32,000 pixels high / 32 million pixels total; bounded, throwing image assembly in source order | **Not signed off:** fixed-overlap stitching can duplicate or omit content, arrow scrolling depends on focus; needs image-registration work and a measured corpus |
| Updates | User-initiated GitHub stable-release check; installed version uses bundle build number | Numeric version/HTTP404(no published release)/HTTP403/malformed response tests; no automatic installer |
| Older macOS versions | Requires macOS 14; current TextSniper App Store listing supports macOS 12 (website also references Catalina) | **Gap:** no macOS 12/13 deployment target or device certification |
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
