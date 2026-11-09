# Textractor Pro Privacy Policy

Last updated: November 9, 2026

This policy describes the native Textractor Pro applications for macOS and iOS.
The optional web companion in this repository is a separate service and has its own
policy. Before a store release, the publisher must review this policy, publish the
current version at the App Store privacy-policy URL, and complete the matching
App Store privacy answers.

## Text recognition and local storage

The native applications use Apple's Vision framework to recognize text on the
device. They do not send captured images or recognized text to an OCR server.
Text you capture or import can contain personal information, including information
about other people.

**On macOS**, the app can capture a selected screen region or window and import
images or Continuity Camera scans. It stores extracted text, capture timestamps,
confidence information and source paths in local history. Ordinary history is a
JSON file containing readable text; it is not protected by application-level
encryption. The history entry limit is configurable, up to 1,000 records.

Source images can remain in temporary storage for reprocessing. Images retained
after a failed extraction are placed in the app's recovery location so the user
can retry or remove them. Clearing text history does not promise to erase every
source image. There is no seven-day automatic image-deletion policy.

Optional additive-clipboard persistence saves a local JSON copy of the accumulated
text. Disabling that persistence removes its saved batch file. Text already copied
to the system clipboard can remain accessible to other applications until the
clipboard is changed or cleared.

Optional Knowledge Mode saves additional capture records. The OCR text field uses
AES-GCM encryption through Apple's CryptoKit, with the key in Keychain. Images,
ordinary history, and fields such as notes, entities, tags, summaries and source
paths are not all covered by that encryption. This app does not claim that every
stored capture or metadata field is encrypted.

The current implementation keeps decrypted OCR in memory and clears the legacy persisted
OCR cache when it can authenticate or recover those records. That cleanup does not securely
erase older SQLite pages, write-ahead logs, exports or backups. If the original encryption key
is missing or unavailable, the app retains the records and reports the problem; it does not
replace an existing key to make an unreadable library appear empty.

**On iOS**, selecting screenshots from Photos or Files copies the selected original
images into the app's local archive. The app stores extracted text, source-image
hashes, user corrections, speaker/date labels and a change history. Original
images and archive files use iOS file protection. This is operating-system
protection, not a separate password-encrypted archive provided by Textractor Pro.
The app does not access the Messages database.

Preferences such as language, shortcuts and onboarding completion are stored
locally. Native OCR and search do not require a Textractor account.

## Diagnostics

Local telemetry is off for a fresh installation and after resetting to defaults.
An existing saved choice is retained during an update. When enabled, diagnostic
events are written locally and can contain event times, capture mode, success or
failure, elapsed time, text counts and error details. These logs are not uploaded
by the native telemetry implementation.

Turning telemetry off stops new telemetry events. Use **Erase local diagnostics**
to remove existing local telemetry and aggregate diagnostic counters. Optional
file-based debug logs and the operating system's own logs have separate lifetimes.
Review diagnostic files before choosing to share them, because error details can
include file paths or information about a capture operation.

## Sharing, exports and external services

The app can copy text to the system clipboard and pass text or files to the native
share interface. You choose the receiving application or service. Exported PDF
packets, original images and audit files can include the source material and
corrections you selected. Copies outside the app are controlled by you and their
receiving applications.

Optional opening of recognized HTTP or HTTPS links is off by default. If enabled,
the links open in your chosen browser, where the destination site's own privacy
practices apply. Opening support, privacy or other external links also involves
the browser or operating system and the destination service.

Mac App Store builds direct update requests to the App Store. Development builds
can explicitly check the public GitHub release endpoint; GitHub receives the
network request and ordinary connection information. That request does not include
OCR text or screenshots. Native builds do not include an advertising or remote
analytics SDK.

Translation, shared-chat-link import and a working local language-model backend are
not provided by this release candidate. The app does not submit content to a
language-model service.

## Permissions

- **Screen Recording on macOS:** used to capture screen content for recognition.
  Permission can be changed in System Settings. Importing an image file does not
  require access to the screen.
- **Camera/Continuity Camera on macOS:** used when you choose to take a photo or
  scan with a supported Apple device.
- **User-selected files:** used for imports and exports.
- **Selected photos on iOS:** the system photo picker supplies the items you select.

The Mac App Store configuration does not use cross-application Accessibility
monitoring for automatic clipboard clearing or automate another app's scrolling.
Development builds retain experimental controls with different system-permission
requirements.

## Retention and deletion

History, preferences, recovery files and local archives remain until removed by
the appropriate app control or by you. Temporary and cache locations can also be
managed by the operating system. Removing the app does not necessarily remove
exports, clipboard contents, backups, or all macOS support files.

The Mac provides controls for clearing text history, clearing recovery images,
erasing local diagnostics and resetting the app. A reset does not erase copies
already exported to other locations or change system privacy permissions. A
corrupt history file is preserved and reported rather than silently replaced with
an empty history.

iOS export creates copies for sharing or printing. Deleting an original from
Photos does not delete the copy already imported into Textractor Pro. Device
backup, Files providers and sharing destinations may retain additional copies
according to your system settings and their policies. Textractor Pro does not
operate a native cloud-sync service.

## Contact and policy changes

General project support is available through the
[Textractor repository issue tracker](https://github.com/the-lucky-clover/Textractor/issues).
Do not attach private screenshots, transcripts or diagnostic files to a public issue.

Changes to native data handling should be accompanied by an updated policy and
App Store privacy disclosures. The release checklist requires the publisher to
verify its public support contact and policy URL before submission.
