# Textractor Release Checklist (v2.0)

> Track readiness for shipping **Textractor 2.0**. Each item is owned by the role listed in parentheses.
>
> Roles: **RM** = Release Manager · **TL** = Tech Lead · **QA** = Quality Assurance · **DOC** = Documentation · **SEC** = Security Engineer · **DSE** = Distribution & Storefront Engineer

## 1. Pre-Release Preparation
- [x] Version bump in `Info.plist` ✅ (CFBundleShortVersionString = 2.0.0, CFBundleVersion = 2000)  *(TL)*
- [x] Remove Breaking Dad / Breaking Bad verbiage from Swift sources ✅   *(TL)*
- [x] Replace `CoreAnimation` import with `QuartzCore` in particle system ✅  *(TL)*
- [x] Rename theme files BreakingBad* → Capture* ✅  *(TL)*
- [x] Build compiles with zero errors ✅   *(TL)*
- [ ] `CHANGELOG.md` updated with new features and fixes  *(DOC)*
- [ ] No outstanding FIXME / TODO in source  *(TL)*
- [ ] No console warnings during a clean `./build.sh --release` run  *(TL)*

## 2. Multi-Display OCR Verification
- [ ] Freeform region cursor can move to any connected display  *(QA)*
- [ ] Region captured on secondary display OCR-confirms correct content  *(QA)*
- [ ] Window-list capture from TV / external monitor produces correct bounds  *(QA)*
- [ ] Coordinate remap (`window.displayBounds → capture frame`) validated across 2+ display configurations *(QA)*
- [ ] Fullscreen capture returns a per-display image, not a single stretched frame  *(QA)*

## 3. Continuity Camera & Video Capture
- [ ] iOS Continuity Camera / iPhone as webcam detected automatically  *(QA)*
- [ ] Stream to OCR pipeline produces text with no extra round-trip  *(QA)*
- [ ] Frame extractor handles drop-outs without stalling pipeline  *(QA)*

## 4. UI / UX Validation
- [ ] Popover opens cleanly from menu bar and from Dock icon  *(QA)*
- [ ] Pinned popover on Dock click re-uses anchor at the correct screen half  *(QA)*
- [ ] Settings rows no longer truncate (`fixedSize(horizontal: false, vertical: true)` regression check)  *(QA)*
- [ ] Toggles align below+right of their label  *(QA)*
- [ ] Build counter updates once per launch, persists across rebuilds  *(QA)*

## 5. Marketing Webapp (Cloudflare Pages + Workers AI)
- [ ] Palette references Breaking-Bad-free ✅ (verified via grep)  *(DOC)*
- [ ] `npm install && npm run dev` boots wrangler at http://localhost:8788  *(DSE)*
- [ ] `/api/pricing` endpoint returns the Free + Pro payloads from `Workers AI`  *(DSE)*
- [ ] `/api/ocr` endpoint handles base64 image input and plain text input  *(DSE)*
- [ ] `wrangler.toml` committed with deployment target set  *(DSE)*

## 6. Code Quality Gates
- [ ] All unit tests pass  *(TL)*
- [ ] No new `swift build` warnings introduced in v2.0 branch  *(TL)*
- [ ] No deprecated API usage (`CGWindowListCreateImage` on macOS 14+, etc.)  *(TL)*
- [ ] Static analysis (`swiftlint` if configured) clean  *(TL)*

## 7. Security & App Store Gating
- [ ] App Sandbox entitlement (`com.apple.security.app-sandbox = true`) configured for App Store / notarization builds  *(SEC)*
- [ ] Hardened runtime + notarization ticket attached to signed `.app`  *(SEC)*
- [ ] Screen Recording + Camera entitlements reviewed and minimized  *(SEC)*
- [ ] Local telemetry file writes confined to app container when sandboxed  *(SEC)*
- [ ] Privacy Policy URL ready for App Store Connect  *(DSE)*
- [ ] No human / library blockers reported by App Store Review guidelines  *(DSE)*

## 8. Documentation Updates
- [ ] `README.md` updated with multi-display usage and Continuity Camera  *(DOC)*
- [ ] `webapp/README.md` documents Cloudflare Pages + Workers AI setup  *(DOC)*
- [ ] `Info.plist` keys documented in repo (`MICROPHONE_USAGE_DESCRIPTION`, etc.)  *(DOC)*

## 9. Build & Distribution
- [ ] `./build.sh --release` produces a signed `.app` bundle  *(TL)*
- [ ] DMG installer tested on a clean macOS box  *(QA)*
- [ ] Sparkle update manifest regenerated with v2.0 metadata  *(DSE)*
- [ ] Release notes prepared (App Store + GitHub)  *(DOC)*

---

| Role | Owner | Date |
|---|---|---|
| Release Manager | _________________ | ___________ |
| QA Lead | _________________ | ___________ |
| Security Engineer | _________________ | ___________ |
| Distribution Engineer | _________________ | ___________ |
