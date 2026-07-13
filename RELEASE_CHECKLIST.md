# Textractor Release Checklist

## Pre-Release Preparation
- [ ] Version bump in `Info.plist` and `Package.swift`
- [ ] Update `CHANGELOG.md` with new features and fixes
- [ ] Verify all TODO comments are resolved
- [ ] Confirm no console warnings/errors in build
- [ ] Final code review by team lead

## Multi-Display Support Verification
- [ ] Test cursor movement across all connected displays
- [ ] Verify OCR capture from secondary display (MacBook Pro)
- [ ] Verify OCR capture from TV/external monitor
- [ ] Confirm region selection coordinates map correctly across displays
- [ ] Test fullscreen capture returns individual display images

## UI/UX Validation
- [ ] Verify popover displays correctly on all display types
- [ ] Test 3D material glow effects on dark/light modes
- [ ] Confirm particle animations run smoothly (60fps target)
- [ ] Validate animation timing matches design specs
- [ ] Check rounded corners render crisply at all resolutions

## Code Quality Gates
- [ ] All unit tests pass (`xcodebuild test`)
- [ ] Integration tests pass for multi-display scenarios
- [ ] No SwiftLint warnings
- [ ] Memory usage within acceptable limits
- [ ] No deprecated API usage

## Documentation Updates
- [ ] README.md updated with multi-display usage
- [ ] ScreenshotService API documented
- [ ] AppState changes documented
- [ ] New theme/material system documented

## Build Verification
- [ ] Archive build succeeds
- [ ] Sparkle update manifest generated
- [ ] Release notes prepared for App Store
- [ ] DMG installer tested on clean system

---
**Release Manager:** _________________ Date: ___________
**QA Lead:** _________________ Date: ___________