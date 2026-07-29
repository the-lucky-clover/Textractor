# Capture Overlay Navbar Reconstruction Plan

## Goal
Reconstruct the capture-mode navbar using `/Users/pounds_1/Desktop/textractor-navbar-final.png` as the background graphic, fix ESC/X button/keyboard issues, center the navbar near the top, and create a `/landingpage` marketing funnel.

## Issues to Fix

### 1. Navbar Background Graphic
- **Current**: Solid color `navbarIslandBackground` (R:13 G:16 B:11)
- **Fix**: Load `textractor-navbar-final.png` from bundle and use as navbar background
- **File**: `Sources/Textractor/Views/CaptureOverlayView.swift`
- **Method**: Replace `navbarSurface` view with image-based background

### 2. ESC Key Not Working
- **Current**: `.onKeyPress(.escape)` exists but view may not be first responder
- **Fix**: Add `.onAppear { NSApp.main.windows... }` or use `NSViewRepresentable` to force first responder
- **File**: `Sources/Textractor/Views/CaptureOverlayView.swift`

### 3. X Button Not Working
- **Current**: Button calls `onCancel()` but may not receive click events
- **Fix**: Ensure navbar has proper hit testing and the button is interactive
- **File**: `Sources/Textractor/Views/CaptureOverlayView.swift`

### 4. Navbar Not Centered Near Top
- **Current**: Positioned at `centerX = size.width / 3` (left third)
- **Fix**: Center horizontally: `centerX = size.width / 2`
- **File**: `Sources/Textractor/Views/CaptureOverlayView.swift`

### 5. Landing Page Creation
- **Location**: `/landingpage` directory
- **Content**: High-conversion marketing funnel page
- **Style**: Breaking Bad-inspired (without mentioning Breaking Bad)

## Implementation Steps

### Step 1: Update CaptureOverlayView.swift
- Load navbar background image from bundle
- Replace navbar surface with image-based background
- Fix ESC key handling (force first responder)
- Fix X button hit testing
- Center navbar horizontally near top

### Step 2: Update build.sh
- Add copy step for `textractor-navbar-final.png` to Resources

### Step 3: Create Landing Page
- Create `/landingpage/index.html` with hero headline and conversion elements

### Step 4: Build and Test
- Verify build compiles
- Test navbar appears correctly
- Test ESC and X button functionality

## Files to Modify
- `Sources/Textractor/Views/CaptureOverlayView.swift`
- `build.sh`

## Files to Create
- `landingpage/index.html`

## Status
- [ ] Step 1: Update CaptureOverlayView.swift
- [ ] Step 2: Update build.sh
- [ ] Step 3: Create landing page
- [ ] Step 4: Build and test