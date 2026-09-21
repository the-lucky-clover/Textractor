# Textractor fastlane Setup Guide

## Overview
This directory contains fastlane configuration for automated Mac App Store deployments.

## Prerequisites

### 1. Apple Developer Account
- Active Apple Developer Program membership ($99/year)
- Access to App Store Connect

### 2. Certificates & Profiles
Create these in Apple Developer Portal:
- **3rd Party Mac Developer Application** certificate
- **3rd Party Mac Developer Installer** certificate
- **Mac App Store** provisioning profile for `com.textractor.app`

### 3. App Store Connect API Key
1. Go to: https://appstoreconnect.apple.com/access/api
2. Create a new key with **App Manager** role
3. Download the `.p8` file (only once!)
4. Note: **Issuer ID**, **Key ID**

### 4. Match Repository (for certificate sync)
Create a **private** Git repository:
```bash
# Example: https://github.com/yourorg/textractor-certificates
# This stores encrypted certificates/profiles
```

## Local Setup

### 1. Install fastlane
```bash
# Via Homebrew (recommended)
brew install fastlane

# Or via RubyGems
sudo gem install fastlane -v 2.220.0
```

### 2. Install dependencies
```bash
cd fastlane
bundle install
```

### 3. Configure environment
```bash
cp .env.example .env
# Edit .env with your values
```

Required `.env` variables:
```bash
# App Store Connect API (preferred)
ASC_API_ISSUER_ID="your-issuer-id"
ASC_API_KEY_ID="your-key-id"
ASC_API_KEY_PATH="/absolute/path/to/AuthKey_XXXXXXXXXX.p8"

# Match
MATCH_PASSWORD="your-match-repo-passphrase"
MATCH_GIT_URL="https://github.com/yourorg/textractor-certificates.git"

# App
APP_IDENTIFIER="com.textractor.app"
TEAM_ID="YOUR_TEAM_ID"
```

### 4. Initialize match
```bash
# First time only - creates certs/profiles in match repo
fastlane match appstore
```

### 5. Test build
```bash
fastlane mac build
```

## Available Lanes

| Lane | Description |
|------|-------------|
| `fastlane mac release` | Full pipeline: build → sign → notarize → upload → tag |
| `fastlane mac build` | Build .app bundle only |
| `fastlane mac notarize` | Notarize existing build |
| `fastlane mac upload` | Upload to App Store Connect |
| `fastlane mac screenshots` | Capture App Store screenshots |

## CI/CD (GitHub Actions)

The workflows in `.github/workflows/` handle automated releases:

### `.github/workflows/release.yml`
Triggers on: `git push origin v2.0.0` (tag push)
- Builds, tests, notarizes, uploads
- Creates GitHub Release
- Sends Slack notifications

### `.github/workflows/ci.yml`
Triggers on: push to main, pull requests
- Linting, tests, security scan
- Release candidate verification on tag push

### Required GitHub Secrets
Configure in: Settings → Secrets → Actions

| Secret | Description |
|--------|-------------|
| `ASC_API_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_API_KEY_ID` | App Store Connect API Key ID |
| `ASC_API_KEY` | Base64-encoded AuthKey_XXXXXXXXXX.p8 |
| `MATCH_PASSWORD` | Match repository passphrase |
| `MATCH_GIT_URL` | Private cert repo URL |
| `APPLE_ID` | Your Apple ID email |
| `TEAM_ID` | Apple Developer Team ID |
| `SLACK_WEBHOOK_URL` | (optional) Slack notifications |

### Base64-encode the API key:
```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
# Paste into ASC_API_KEY secret
```

## Manual Release Process

If you prefer manual control:

```bash
# 1. Ensure clean git state
git status

# 2. Update version in Info.plist (or let fastlane handle it)
# /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.0.0" Sources/Textractor/Info.plist

# 3. Run full release
fastlane mac release

# Or step by step:
fastlane mac build
fastlane mac notarize
fastlane mac upload
fastlane mac tag_release
```

## Troubleshooting

### "No matching provisioning profile found"
```bash
# Regenerate profiles
fastlane match appstore --force
```

### "Notarization failed"
```bash
# Check notarytool log
xcrun notarytool log <submission-id> \
  --issuer $ASC_API_ISSUER_ID \
  --key-id $ASC_API_KEY_ID \
  --key $ASC_API_KEY_PATH
```

### "Code signing failed"
```bash
# Verify certificates in keychain
security find-identity -v -p codesigning

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/Textractor-*
```

### "App Store Connect upload failed"
```bash
# Check Transporter logs
xcrun transporter logs
```

## Version Management

Fastlane reads version from:
1. Git tags (`git describe --tags`)
2. Info.plist (`CFBundleShortVersionString`)

Build number = git commit count (`git rev-list --count HEAD`)

To release v2.0.0:
```bash
git tag -a v2.0.0 -m "Release 2.0.0"
git push origin v2.0.0
# GitHub Actions triggers release workflow
```

## Security Notes

- **Never commit** `.env`, `AuthKey_*.p8`, or match repo credentials
- Use GitHub Secrets for CI/CD
- Rotate API keys periodically
- Match repo should be private with limited access

## Resources

- [fastlane docs](https://docs.fastlane.tools)
- [App Store Connect API](https://developer.apple.com/app-store-connect/api/)
- [notarytool guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Transporter](https://developer.apple.com/app-store/transporter/)
- [Match](https://docs.fastlane.tools/actions/match/)