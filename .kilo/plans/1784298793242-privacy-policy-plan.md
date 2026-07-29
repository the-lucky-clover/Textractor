# Privacy Policy Implementation Plan

## Goal
Create a legally-complete privacy policy for the Textractor webapp that meets App Store and GDPR requirements.

## Context
- Textractor webapp uses Cloudflare Workers AI for OCR processing
- No persistent data storage on servers
- Minimal telemetry (opt-in, local only)
- Target deployment: App Store submission

## Required Sections (All Included in Draft Above)
1. **Purpose** - Clear statement of data handling intent
2. **Data Collection** - Limited to OCR output/text, opt-in telemetry
3. **No Third-Party Sharing** - Explicit statement about Cloudflare only
4. **Region Alignment** - Data processing location and GDPR basis

## Validation Steps
1. [ ] Save privacy policy text to `webapp/privacy-policy.md`
2. [ ] Add privacy policy link to webapp footer (`webapp/frontend/index.html`)
3. [ ] Create `/privacy-policy.html` route if needed (`webapp/frontend/_routes.json`)
4. [ ] Update `CHANGELOG.md` with privacy policy addition under v2.0
5. [ ] Verify policy covers all App Store Connect requirements

## Files Modified
- `webapp/privacy-policy.md` (new)
- `webapp/frontend/index.html` (add footer link)
- `CHANGELOG.md` (add entry)

## Legal Compliance Checklist
- [ ] GDPR Article 13/14 compliant (information provision)
- [ ] CCPA compliant (California Consumer Privacy Act)
- [ ] Children's Privacy (COPPA) addressed
- [ ] Data Retention period specified
- [ ] User Rights enumerated
- [ ] Contact information provided

## Open Questions
1. Should the policy be linked as `/privacy-policy.html` or `/privacy-policy.md`?
2. Does Cloudflare Workers AI require specific disclosure in the policy?

## Status
- Draft text provided above
- Ready for implementation