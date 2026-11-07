# Proposed iOS direction — not implemented or validated

Product hypothesis: Textractor Pro is a private, reviewable capture-to-document workspace
for conversations and research, complementary to the native Mac utility. Live Text already
covers simple copy-from-image tasks. Business viability has not been established.

## Shared LLM conversations first

Proposed flow: iOS Share Sheet or pasted link → provider-specific import → review →
Markdown, searchable PDF or JSON. Preserve message order, speaker roles, code fences,
links, source URL and import time. Keep downloaded text distinct from generated summaries.
Show captured message count and unsupported/missing attachments explicitly. Never describe
an import as the entire account history: it can only contain what that shared page exposes.

ChatGPT may share a snapshot or one response, and workspace links may require membership.
Claude shared snapshots exclude attached files and raw MCP data. Gemini links contain a
shared snapshot. Each provider requires its own fixtures and live compatibility tests;
page structure can change. No reliable importer has been verified in this implementation.
Do not bypass sign-in, workspace access, CAPTCHA or deleted links. Offer user-provided
export files, copied text or screenshots as explicit fallbacks.

Initial target corpus: 20 authorized sample links per provider, including long chats,
Unicode, code/tables, deleted links, restricted links and partial shares. Acceptance targets
(not results): 100% role/order preservation, zero silently omitted messages in fixtures,
100% code-text preservation, explicit error for every unsupported case. Measure p50/p95
against transcript size. Start with one provider before claiming cross-provider support.

## Screenshot / recording conversation imports

Proposed flow: user selects overlapping screenshots or a recording made while manually
scrolling → suggest joins → inspect/correct overlap → searchable transcript and source images.
Do not promise direct Messages database access or autonomous control of another app.
Never infer missing dates, speakers or text as facts. Preserve legitimate repeated messages;
flag ambiguous joins. User-selected originals remain available beside any derived transcript.

Targets: 30 synthetic message threads; zero silently missing/duplicated messages; 100% of
ambiguous joins flagged; exports maintain image/text source mapping. Real-device tests are
required for memory, capture compatibility and performance. Competing screenshot-stitching
products already exist; stitching alone is not a demonstrated differentiator.

## Camera relationship

The Mac code adds the native Continuity Camera import service. It uses the existing iOS
system camera workflow; it is not an iOS app. A standalone iOS companion would be a separate
SwiftUI target with Photos/file import, local OCR, archive review and explicit export.

## Sources checked 2026-11-07

- [Apple Live Text](https://support.apple.com/en-ca/guide/iphone/iph37fdd714b/ios)
- [Apple app sandboxing](https://support.apple.com/en-ca/guide/security-pdf/sec15bfe098e/web)
- [Apple Messages framework](https://developer.apple.com/documentation/messages)
- [ChatGPT sharing](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt)
- [Claude sharing](https://support.claude.com/en/articles/10593882-share-and-unshare-chats)
- [Gemini sharing](https://support.google.com/gemini/answer/13743730?hl=en)
- [Picsew listing](https://apps.apple.com/us/app/picsew-screenshot-stitching/id1208145167)
