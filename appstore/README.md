# Textractor Pro store submission materials

**Drafts only.** These files are not an App Store reservation, completed account setup,
upload or approved release. Follow [the release plan](../qa/RELEASE_PLAN.md).

| Draft | Target | Source version/build |
|---|---|---|
| [macos/en-US.json](macos/en-US.json) | `com.textractor.app` / macOS 14+ | `2.0.0` / `2000` |
| [ios/en-US.json](ios/en-US.json) | `com.textractor.app.ios` / iOS 17+ | `1.0` / `1` |

The name is **Textractor Pro** in both drafts. Name availability and the intended relationship
between these separate platform bundle IDs need Apple-account verification. No price,
subscription, trial, legal identity, contact or website is invented here.

## Finish each metadata draft

1. Compare `name`, `subtitle`, `description`, `keywords`, `promotional_text` and `review_notes`
   with the exact signed build and physical acceptance results. Remove internal pre-submission
   instructions from reviewer notes only after completing them.
2. Replace null `submission.support_url` and `submission.privacy_policy_url` with live, reviewed
   URLs. The support site must expose actual contact information. A private repository path or
   placeholder domain is not a working public policy/support page.
3. Supply the real reviewer contact's first name, last name, email and phone. Keep review-contact
   information out of public marketing copy. Apply the repository's access/privacy practices
   before committing personal contact details; these drafts are ordinary files, not secret storage.
4. Complete pricing/availability, age rating, privacy answers, export-compliance and content-rights
   decisions in the Apple account. Set the corresponding confirmation flags only after recording
   that decision. A flag does not choose the answer on the owner's behalf.
5. Supply reviewed screenshots and add their exact repository-relative paths to `screenshot_paths`.
   Use fictional content and redact personal OS/account information before retaining evidence.
6. Confirm version/build against earlier uploads. Change metadata status from `draft` to `ready`
   only after completing its fields and corresponding release evidence.

The candidate gate validates draft structure and length limits without requiring credentials.
The submission gate requires completed platform metadata and real evidence; do not mark draft
fields complete simply to pass it.

## Mac screenshot brief

Capture the real app. Apple accepts PNG/JPEG; this repository's reproducible validation uses
1–10 PNG files, each at an accepted 16:10 size:
1280×800, 1440×900, 2560×1600 or 2880×1800. A single consistent 2880×1800 set is a preparation
choice if the available display can produce genuine screenshots at that size; do not stretch
a smaller capture. The fields stay empty until real files exist and have been reviewed.

Suggested shots, in priority order:

| Shot | Content to capture | Claim supported |
|---|---|---|
| Region capture | Selection over readable fictional text with the actual overlay | Screen-region extraction workflow |
| Captured text | Result actions plus copied content in a text editor | Copy and review |
| History | Several fictional captures with a selected result | Revisit captured text |
| Settings | English (US), line-break and clipboard options visibly selected | User controls and language default |
| Image import | Actual imported sample and its OCR result | Image-to-text workflow |
| Optional camera | Successful real photo/scan import after device verification | Continuity Camera only if verified |

Do not show a translation result, scroll-capture success or model-generated summary as a
shipping feature when the store build does not provide it. Do not use simulated device UI
or generated imagery as proof that a flow was tested. Accessibility evidence should include
Settings and onboarding, but internal test screenshots need not all become store screenshots.

## iOS screenshots and claims

Use actual iPhone/iPad screens supported by the release target and consult Apple's current
device-specific dimensions. Show import, original-linked review, explicit overlap review,
search and the resulting PDF. Reconstructed message layouts must remain labeled. Do not use
the Mac 16:10 screenshot dimensions for iOS.

The iOS draft explicitly excludes direct Messages access, missing-date inference, sender
authentication and court-admissibility claims. File checksums and retained originals do not
establish the truth of the source conversation. Shared AI-conversation links and screen
recording import are not implemented.

## Source references

- [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Apple platform-version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple screenshot upload requirements](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
- [Source feature matrix](../qa/FEATURE_MATRIX.md) and [iOS scope](../qa/IOS_DIRECTION.md)
