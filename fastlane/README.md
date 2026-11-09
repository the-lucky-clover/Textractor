# Textractor Pro: candidate archives and App Store delivery

The public product name is **Textractor Pro**. Existing identities remain
`com.textractor.app` (Mac), `com.textractor.app.ios` (iOS), modules `Textractor` /
`TextractorMobile`, and the same executable names. The app bundle is now
`Textractor Pro.app`.

The previous pipeline combined an ad-hoc app bundle, notarization, a ZIP upload,
and automatic release. This pipeline uses Xcode archives and App Store export.
A local development build, unsigned CI archive, signed candidate, exported
package, uploaded build and approved App Store release are different outcomes.

## 1. Validate source configuration

Run from the repository root:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/check_release_signoff.py --platform macos --stage candidate
python3 scripts/check_release_signoff.py --platform ios --stage candidate
```

Candidate validation does not require completed device testing or signing.
Submission validation requires platform-specific evidence recorded in
`qa/release-signoff.json`, including the actual archive version/build and source.
Listing drafts are in `appstore/macos/en-US.json` and `appstore/ios/en-US.json`.

## 2. Create a development build or compile-only archive

On a Mac with Xcode, Python 3 and XcodeGen (`brew install xcodegen`):

```sh
bash build.sh
open 'dist/Textractor Pro.app'
bash scripts/archive_appstore.sh --platform macos --unsigned
bash scripts/archive_appstore.sh --platform ios --unsigned
```

`build.sh` is an ad-hoc SPM development build; it does not exercise the App Store
sandbox. The unsigned Xcode archive compiles the Release configuration, including
the Mac `APP_STORE` code path, sandbox entitlements and bundled privacy manifest.
It cannot be exported or uploaded by this tooling. The unsigned archive is not
proof that a signed sandboxed app launches successfully on a device.

Current iOS App Store submissions require Xcode 26 or newer; the helper checks
that for iOS. macOS still requires a compatible Xcode supporting the app's macOS
14 deployment target. Use Xcode's current supported upload tools.

## 3. Create a signed candidate

Configure the existing app identifiers and your team in Xcode with appropriate
certificates and profiles, then export `TEAM_ID` in your shell. No Apple account,
team, keychain password or review contact is hard-coded in this repository.
The helper requires a clean working tree for signed archives.

```sh
export TEAM_ID='YOUR_10_CHARACTER_TEAM_ID'
bash scripts/archive_appstore.sh --platform macos
```

The default Mac version/build remains **2.0.0 (2000)**; iOS remains **1.0 (1)**.
Verify the next available build number in App Store Connect before overriding it:

```sh
bash scripts/archive_appstore.sh --platform macos --version 2.0.0 --build 2001
```

The example build `2001` is illustrative, not verified as unused. Overrides are
passed to Xcode and do not edit tracked files. Already existing archive paths
are rejected; choose a new build or `--archive-path` instead of overwriting them.

If Xcode needs to contact Apple to manage provisioning, add the explicit
`--allow-provisioning-updates` flag. API authentication is optional when Xcode
already has an authenticated account. For API authentication set all three:

- `ASC_API_KEY_PATH`: local path to your `.p8` key, outside the repository.
- `ASC_API_KEY_ID`: key identifier.
- `ASC_API_ISSUER_ID`: issuer identifier.

Partial or missing API key files cause an error. Without these variables,
Xcode uses its configured account and fails if that account cannot sign/export.
The helper does not create a keychain, install certificates or run `fastlane match`.

Default signed archive locations:

- Mac: `dist/appstore/macos/2.0.0-2000/Textractor Pro.xcarchive`
- iOS: `dist/appstore/ios/1.0-1/Textractor Pro.xcarchive`

Unsigned archives use a `-unsigned` suffix in the version directory. Archives
contain source and app hashes, commit, platform, actual versions, team and Xcode
version in `TextractorPro-provenance.json`. Export/upload rejects changed app
bytes, changed shipping inputs, wrong identity/team and unsigned CI archives.

## 4. Export for distribution validation

```sh
bash scripts/archive_appstore.sh --platform macos --action export
```

For a custom build/path, provide the same `--version` / `--build` or an explicit
`--archive-path`. The generated `ExportOptions.plist` uses `app-store-connect`
and the `export` destination. Xcode exports a Mac installer package (`.pkg`) or
an iOS app (`.ipa`). It does not upload here. Automatic version/build management
is disabled so the package retains the version recorded in the archive evidence.

Validate the signed, sandboxed result and complete the required device, privacy,
metadata and App Store validation checks before marking any signoff as passed.
Mac App Store packaging does not run Developer ID notarization or Gatekeeper
assessment; those belong to a separately configured direct-distribution path.

## 5. Explicitly upload an approved archive

```sh
bash scripts/archive_appstore.sh --platform macos --action upload
```

This reads the archive's actual version/build, verifies its provenance, and runs
the submission gate. Xcode then performs an export with destination `upload`.
The command stops if required release evidence is incomplete. Upload success
means Apple accepted the transfer; inspect processing and validation in App Store
Connect. The helper does not submit for review, publish, create tags or send
messages. App name acceptance is a separate App Store Connect check.

## Optional Fastlane wrappers

The shell/Python workflow needs no Ruby gems. Existing Fastlane users can run
`bundle install` from `fastlane/`, then:

```sh
bundle exec fastlane mac build
bundle exec fastlane mac build unsigned:true
bundle exec fastlane mac export
bundle exec fastlane mac upload
bundle exec fastlane mac build platform:ios
```

`mac release` is now an archive-only compatibility alias. `deploy_appstore.sh`
also defaults to archive only and accepts the same explicit action flags.
No legacy notarization, automatic-review, automatic-release or Slack lane remains.

## Screenshot evidence

`bash scripts/capture_screenshots.sh` runs the existing `SettingsPlaytests` UI
tests and exports their real XCTest attachments into a unique directory under
`dist/screenshots/`. Use `--list` to list tests or `--test TEST_NAME` for one flow.
The Swift runner delegates to the same script. Missing result bundles, missing
PNG attachments and failing tests return an error. These Debug UI attachments
are labeled QA evidence and are not approved listing screenshots. The press-kit
generator produces artwork and a pending capture plan, not UI evidence.

## CI

`Textractor Pro QA` validates candidate configuration and release logic before
starting native jobs. macOS and iOS jobs compile unsigned Release archives in
addition to unit/UI checks. Mac UI tests use the Debug configuration and do not
constitute sandbox testing. The manual `Prepare Textractor Pro App Store
Candidate` workflow only compiles and preserves an unsigned archive, including
provenance. It has no signing secrets and cannot upload or publish.

## Primary references

- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Archive export files](https://help.apple.com/xcode/mac/current/en.lproj/deva1f2ab5a2.html)
- [Uploading builds and supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Xcode 15 API-key upload support](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes)

Use `xcodebuild -help` on the build Mac for the export options supported by the
installed Xcode. Signing and App Store acceptance have not been verified by
static checks or unsigned CI builds.
