# iOS conversation packets — implementation candidate

The `TextractorMobile` XcodeGen target (iOS 17+) implements a screenshot-to-document
workflow. It is not a production-approved app and has not been installed on a physical
user device. `Textractor Pro` is a working display name, not a verified App Store reservation.

## Implemented source

- Ordered Photos selection and image-file import; English (US), `en-US`, by default.
- On-device Vision OCR into source-linked blocks. These are **OCR blocks, not verified
  message boundaries**. Speakers and incoming/outgoing direction stay unassigned until review.
- Imported bytes, SHA-256, source filename, import time, original OCR and review changes
  remain separate. Checksums identify imported bytes; they do not authenticate a conversation.
- Editable transcript; original OCR retained; user-entered timestamps explicitly labeled.
  Visible timestamp classification is a heuristic and can be corrected. Relative labels such
  as “Today” are not converted into invented calendar dates.
- Adjacent screenshot overlap proposals require at least two matching blocks and 24 characters.
  Differing numbers reject fuzzy overlap matches. Nonidentical blocks over 1,000 characters
  are rejected rather than compared using a truncated prefix. Nothing is excluded automatically.
  Keep-both decisions and reversible exclusions are logged. Identical source files are flagged.
- Reconstructed message layout with user-assigned left/right direction; this is labeled as a
  reconstruction and does not masquerade as an original iMessage screenshot.
- Exact and typo-tolerant search. Related-meaning search uses Apple's on-device English
  sentence embedding where available; otherwise the UI explicitly falls back to fuzzy search.
  Ranking scores are similarity measures, not truth or OCR accuracy scores.
- Numbered US Letter PDFs: black text, white backgrounds and outlined bubbles. Optional
  transcript timestamps, grayscale source appendix, original image files and full audit JSON.
  Timestamp hiding affects the transcript only; originals and audit JSON retain source content.
- Original checksums verified before export; changed/missing sources stop export.
- Skippable three-step welcome tour, replayable from Settings.

## Boundaries

The app imports screenshots selected by the user. It does not read the Messages database,
control scrolling in Messages, authenticate senders, infer missing timestamps, or certify
court admissibility. It does not yet import screen recordings or shared LLM links.

Current limits: 20 images per Photos selection, 50 screenshots per working packet, 50 MB and
30 megapixels per source, 500 PDF pages. OCR downsampling is capped at 4096 pixels; the
supplied source bytes are retained separately. A full multi-packet browser, encryption review,
physical-device performance, accessibility and large-corpus quality testing remain unfinished.

## Quantitative acceptance plan — targets, not claimed results

| Feature | Automated coverage / required evidence |
|---|---|
| OCR import | Synthetic image through Vision; exact source-byte retention; record import latency. Expand to 30 threads covering light/dark mode, text size, emoji and long messages. |
| Timestamps | Positive and negative classification fixtures; hiding timestamps leaves stored OCR untouched. No inferred dates. |
| Overlap | Repeated “Yes” retained; two-block overlap proposed; changed amounts and mismatched long-block tails rejected. Require zero silently omitted blocks over the expanded corpus. |
| Review | Before/after edit log, original OCR persistence, reversible exclusions. |
| Search | Exact source references, typo fixture and cosine mathematics. Real semantic relevance needs a labeled query corpus and device model availability checks. |
| PDF | 612×792 pt media boxes, every-page numbering, searchable text, long-message pagination and Unicode wrapping. Both synthetic layouts were rendered and visually inspected (see VALIDATION); physical print and representative-content checks remain. |
| Provenance | Exact imported bytes and original exports match; tampering stops export. |
| UI | Simulator import fixture → review → fuzzy search → export options; US English and onboarding replay. Real Photos/Files permission and sharing flows remain device gates. |

Run `xcodegen generate`, then `xcodebuild test -project Textractor.xcodeproj -scheme
TextractorMobile -destination 'platform=iOS Simulator,name=<available iPhone>'
CODE_SIGNING_ALLOWED=NO`. CI chooses an available simulator and preserves XCTest results,
PDF test attachments and screenshots. No external service receives the imported conversation
for OCR or search in this implementation.

## Shared LLM conversations — proposed, not implemented

Proposed flow: Share Sheet/pasted link → provider-specific import → review → Markdown,
searchable PDF or JSON. Preserve roles, order, code blocks, links, source URL and import time.
Show missing/unsupported content explicitly. “Entire” can only mean the content exposed by
that shared page; it cannot mean the creator's whole account history.

ChatGPT links can expose a snapshot or just one response; managed workspace links may be
restricted. Claude snapshots omit attached files and raw MCP data. Gemini sharing exposes a
shared conversation snapshot. Each provider requires authorized fixtures and live compatibility
tests. Do not bypass sign-in, workspace access, deleted links or CAPTCHA. Accept user-supplied
export files/copied text/screenshots as explicit fallbacks.

Initial target: 20 authorized links per provider, including long chats, code, tables, Unicode,
partial shares and unavailable links. Target complete role/order and code-text preservation,
zero silent omissions in fixtures, explicit failures and measured p50/p95 by transcript size.

## Sources checked 2026-11-07

- [Apple Live Text](https://support.apple.com/en-ca/guide/iphone/iph37fdd714b/ios)
- [Apple app sandboxing](https://support.apple.com/en-ca/guide/security-pdf/sec15bfe098e/web)
- [Apple Messages framework](https://developer.apple.com/documentation/messages)
- [Apple sentence embeddings](https://developer.apple.com/documentation/naturallanguage/nlembedding)
- [Apple Photos picker](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)
- [Apple PDF renderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer)
- [ChatGPT sharing](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt)
- [Claude sharing](https://support.claude.com/en/articles/10593882-share-and-unshare-chats)
- [Gemini sharing](https://support.google.com/gemini/answer/13743730?hl=en)
