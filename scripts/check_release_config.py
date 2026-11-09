#!/usr/bin/env python3
"""Portable source preflight; final signed archive verification remains separate."""
import argparse
import json
import plistlib
import re
import struct
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
PRODUCT = "Textractor Pro"
MANIFESTS = {
    "macos": "Sources/Textractor/Resources/PrivacyInfo.xcprivacy",
    "ios": "ios/TextractorMobile/PrivacyInfo.xcprivacy",
}
CONFIRMATIONS = (
    "pricing_confirmed", "age_rating_confirmed", "privacy_answers_confirmed",
    "export_compliance_confirmed", "content_rights_confirmed",
)


def valid_public_url(value):
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    host = (parsed.hostname or "").lower()
    return (parsed.scheme == "https" and bool(host) and not parsed.username and not parsed.password
            and host not in {"localhost", "example.com", "example.org", "example.net"}
            and not host.endswith((".example.com", ".invalid", ".test")))


def metadata_errors(data, submission=False):
    errors = []
    if not isinstance(data, dict):
        return ["App Store metadata must be an object"]
    if data.get("name") != PRODUCT:
        errors.append(f"App Store name must be {PRODUCT}")
    for field, limit in (("name", 30), ("subtitle", 30), ("description", 4000),
                         ("promotional_text", 170)):
        value = data.get(field)
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            errors.append(f"Metadata {field} must be nonempty and at most {limit} characters")
    keywords = data.get("keywords")
    if not isinstance(keywords, str) or not keywords.strip() or len(keywords.encode("utf-8")) > 100:
        errors.append("Metadata keywords must be nonempty and at most 100 UTF-8 bytes")
    if not isinstance(data.get("review_notes"), str) or not data["review_notes"].strip():
        errors.append("App Review notes are required")
    if submission:
        if data.get("status") != "ready":
            errors.append("Metadata is still a draft; review it and set status to ready")
        details = data.get("submission", {})
        if not isinstance(details, dict):
            return errors + ["Metadata submission details must be an object"]
        for field in ("support_url", "privacy_policy_url"):
            if not valid_public_url(details.get(field)):
                errors.append(f"A real HTTPS {field} is required")
        contact = details.get("review_contact", {})
        if not isinstance(contact, dict):
            contact = {}
        for field in ("first_name", "last_name", "phone", "email"):
            value = contact.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"App Review contact {field} is required")
        email = contact.get("email", "")
        if not isinstance(email, str) or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email) or "example." in email.lower():
            errors.append("App Review contact email must not be a placeholder")
        for field in CONFIRMATIONS:
            if details.get(field) is not True:
                errors.append(f"Account declaration {field} is not confirmed")
        shots = data.get("screenshot_paths")
        if not isinstance(shots, list) or not 1 <= len(shots) <= 10 or any(
            not isinstance(item, str) or not item.strip() for item in shots
        ):
            errors.append("Provide 1–10 actual App Store screenshot paths")
    return errors


def manifest_errors(data, platform):
    if not isinstance(data, dict):
        return ["Privacy manifest must be a property-list dictionary"]
    errors = []
    if data.get("NSPrivacyTracking") is not False:
        errors.append("Privacy manifest must explicitly declare NSPrivacyTracking false")
    if not isinstance(data.get("NSPrivacyTrackingDomains", []), list):
        errors.append("Privacy manifest NSPrivacyTrackingDomains must be an array when present")
    for field in ("NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"):
        if not isinstance(data.get(field), list):
            errors.append(f"Privacy manifest {field} must be an array")
    apis = data.get("NSPrivacyAccessedAPITypes", [])
    entries = {}
    for item in apis if isinstance(apis, list) else []:
        if not isinstance(item, dict) or not isinstance(item.get("NSPrivacyAccessedAPITypeReasons"), list):
            errors.append("Malformed required-reason API entry")
            continue
        kind = item.get("NSPrivacyAccessedAPIType")
        if not isinstance(kind, str) or kind in entries:
            errors.append("Required-reason API categories must be named and unique")
            continue
        entries[kind] = item["NSPrivacyAccessedAPITypeReasons"]
    required = {"NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1"}
    if platform == "macos":
        required["NSPrivacyAccessedAPICategoryFileTimestamp"] = "C617.1"
    for kind, reason in required.items():
        if reason not in entries.get(kind, []):
            errors.append(f"Privacy manifest must declare {kind} reason {reason} for current API use")
    return errors


def png_dimensions(path):
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 33 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG image: {path.name}")
    return struct.unpack(">II", header[16:24])


def png_has_alpha(path):
    """Reject alpha channels and palette transparency in an App Store icon."""
    with path.open("rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Not a PNG image: {path.name}")
        while True:
            header = stream.read(8)
            if len(header) != 8:
                raise ValueError(f"Truncated PNG image: {path.name}")
            size, kind = struct.unpack(">I4s", header)
            if size > 32_000_000:
                raise ValueError("Icon PNG chunk exceeds expected size")
            data = stream.read(size)
            crc = stream.read(4)
            if len(data) != size or len(crc) != 4:
                raise ValueError(f"Truncated PNG image: {path.name}")
            if kind == b"IHDR" and (len(data) != 13 or data[9] in (4, 6)):
                return True
            if kind == b"tRNS":
                return True
            if kind == b"IEND":
                return False


def check_configuration(root, platform, submission=False):
    root = Path(root).resolve()
    if platform not in MANIFESTS:
        return ["Unknown release platform"]
    errors = []

    def load_plist(relative):
        try:
            with (root / relative).open("rb") as stream:
                return plistlib.load(stream)
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            errors.append(f"{relative}: {error}")
            return {}

    errors.extend(manifest_errors(load_plist(MANIFESTS[platform]), platform))
    if platform == "macos":
        info = load_plist("Sources/Textractor/Info.plist")
        expected = {"CFBundleName": PRODUCT, "CFBundleDisplayName": PRODUCT,
                    "CFBundleIdentifier": "com.textractor.app", "CFBundleExecutable": "Textractor"}
        for key, value in expected.items():
            if info.get(key) != value:
                errors.append(f"macOS {key} must remain {value}")
        for key in ("NSScreenCaptureUsageDescription", "NSCameraUsageDescription"):
            if PRODUCT not in str(info.get(key, "")):
                errors.append(f"macOS {key} must describe access using {PRODUCT}")
        entitlement = load_plist("Sources/Textractor/Resources/Textractor.release.entitlements")
        if entitlement.get("com.apple.security.app-sandbox") is not True:
            errors.append("Mac App Store release requires App Sandbox")
        for key in ("com.apple.security.get-task-allow", "com.apple.security.cs.allow-jit",
                    "com.apple.security.cs.disable-library-validation"):
            if entitlement.get(key):
                errors.append(f"Unexpected distribution entitlement: {key}")
        icon = root / "Sources/Textractor/Resources/textractor.icns"
        if not icon.is_file() or icon.stat().st_size < 8:
            errors.append("macOS app icon is missing")
    else:
        icons = root / "ios/TextractorMobile/Assets.xcassets/AppIcon.appiconset"
        try:
            items = json.loads((icons / "Contents.json").read_text())["images"]
            filenames = [item["filename"] for item in items if item.get("filename")]
            if not filenames:
                errors.append("iOS app icon has no image")
            for filename in filenames:
                icon = (icons / filename).resolve()
                if not icon.is_relative_to(icons.resolve()) or png_dimensions(icon) != (1024, 1024):
                    errors.append("iOS app icon must be a local 1024×1024 PNG")
                elif png_has_alpha(icon):
                    errors.append("iOS App Store primary icon must be opaque, without an alpha channel")
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f"iOS app icon configuration: {error}")

    metadata_path = root / f"appstore/{platform}/en-US.json"
    try:
        metadata = json.loads(metadata_path.read_text())
        errors.extend(metadata_errors(metadata, submission))
        if submission and isinstance(metadata, dict):
            shots = metadata.get("screenshot_paths", [])
            for value in shots if isinstance(shots, list) else []:
                if not isinstance(value, str):
                    continue
                screenshot = (root / value).resolve()
                if not screenshot.is_relative_to(root) or not screenshot.is_file():
                    errors.append(f"Missing repository screenshot: {value}")
                elif screenshot.suffix.lower() == ".png":
                    try:
                        dimensions = png_dimensions(screenshot)
                        if platform == "macos" and dimensions not in {(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)}:
                            errors.append(f"Incorrect Mac App Store screenshot dimensions: {value}")
                    except (OSError, ValueError) as error:
                        errors.append(str(error))
                else:
                    errors.append(f"Use PNG screenshot assets for reproducible validation: {value}")
    except (OSError, ValueError) as error:
        errors.append(f"{metadata_path.relative_to(root)}: {error}")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=MANIFESTS, default="macos")
    parser.add_argument("--submission", action="store_true")
    args = parser.parse_args()
    problems = check_configuration(ROOT, args.platform, args.submission)
    if problems:
        raise SystemExit("Configuration errors:\n- " + "\n- ".join(problems))
    print(f"{args.platform} source configuration passed; final archive and device validation remain separate.")
