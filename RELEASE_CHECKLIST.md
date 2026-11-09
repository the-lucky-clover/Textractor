# Textractor Pro release checklist

**Status: pending release verification.** The single detailed process is
[qa/RELEASE_PLAN.md](qa/RELEASE_PLAN.md). This checklist is a navigation aid; it does not
record test passes. Machine-readable evidence belongs in
[qa/release-signoff.json](qa/release-signoff.json), with results tied to the tested source.

## Mac release sequence

- [ ] Review the release scope and Textractor Pro identity in [Phase 1](qa/RELEASE_PLAN.md#phase-1--confirm-the-candidate-and-identity).
- [ ] Run source/configuration checks, native tests and the signed sandbox candidate in
  [Phase 2](qa/RELEASE_PLAN.md#phase-2--build-and-test-the-current-source).
- [ ] Complete permission, capture, multi-display, Continuity Camera, accessibility and
  storage checks in [Phase 3](qa/RELEASE_PLAN.md#phase-3--complete-physical-mac-acceptance).
- [ ] Verify App Store Connect name/identity, public URLs, metadata, screenshots, privacy,
  contact, age rating, content rights, export compliance and pricing in
  [Phase 4](qa/RELEASE_PLAN.md#phase-4--finish-apple-account-and-store-materials).
- [ ] Archive, validate signing and attach per-check evidence in
  [Phase 5](qa/RELEASE_PLAN.md#phase-5--archive-export-and-upload).
- [ ] Pass the macOS submission gate, upload the intended build and complete App Review
  submission in [Phase 6](qa/RELEASE_PLAN.md#phase-6--submit-and-confirm-the-result).

## iOS is a separate release decision

- [ ] Complete the [iOS-specific plan](qa/RELEASE_PLAN.md#ios-follow-on) and its own signoff.
- [ ] Verify the existing `com.textractor.app.ios` record and name availability; do not assume
  it shares the Mac record, purchase or approval.

App Store distribution uses the Xcode archive/export path. Developer ID notarization,
DMG distribution, Sparkle updates and the optional web companion are not steps in this
Mac App Store checklist. Old CI success or a generated archive alone does not complete it.
