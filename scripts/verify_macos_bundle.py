#!/usr/bin/env python3
"""Inspect the built Mac app's identity, runtime resources and architecture slices.

This does not verify signing, notarization, provisioning or runtime behavior.
It catches packaging failures that a successful Swift compile cannot detect.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import re
import struct

from check_release_config import manifest_errors

LOCALIZATIONS = ("ar", "de", "en", "es", "fr", "it", "ja", "ko", "nl", "pt", "ru", "zh")
REQUIRED_RESOURCES = (
    "textractor.icns", "textractor-type.png", "textractor-splash.png",
    "textractor-navbar-final.png", "textractor-beaker.png",
    "MenuBar/textractor-menubar@1x.png", "MenuBar/textractor-menubar@2x.png",
    "PrivacyInfo.xcprivacy",
    *(f"{language}.lproj/Localizable.strings" for language in LOCALIZATIONS),
)
CPU_NAMES = {0x01000007: "x86_64", 0x0100000C: "arm64"}


def mach_o_architectures(path: Path) -> set[str]:
    """Read only the Mach-O architecture headers, not executable code."""
    with path.open("rb") as stream:
        size = os.fstat(stream.fileno()).st_size
        header = stream.read(8)
        if len(header) != 8:
            raise ValueError("Executable has a truncated Mach-O header")
        magic = header[:4]
        if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
            if size < 32:
                raise ValueError("Executable has a truncated 64-bit Mach-O header")
            endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
            cpu = struct.unpack(endian + "I", header[4:])[0]
            return {CPU_NAMES.get(cpu, f"unknown-{cpu:x}")}
        formats = {
            b"\xca\xfe\xba\xbe": (">", 20), b"\xbe\xba\xfe\xca": ("<", 20),
            b"\xca\xfe\xba\xbf": (">", 32), b"\xbf\xba\xfe\xca": ("<", 32),
        }
        if magic not in formats:
            raise ValueError("Executable is not a supported 64-bit Mach-O binary")
        endian, entry_size = formats[magic]
        count = struct.unpack(endian + "I", header[4:])[0]
        if not 1 <= count <= 16:
            raise ValueError("Executable has an invalid architecture count")
        entries = []
        for _ in range(count):
            entry = stream.read(entry_size)
            if len(entry) != entry_size:
                raise ValueError("Executable has a truncated universal Mach-O header")
            cpu = struct.unpack(endian + "I", entry[:4])[0]
            if entry_size == 20:
                offset, slice_size = struct.unpack(endian + "II", entry[8:16])
            else:
                offset, slice_size = struct.unpack(endian + "QQ", entry[8:24])
            if offset < 8 + count * entry_size or slice_size < 32 or offset + slice_size > size:
                raise ValueError("Executable has an out-of-bounds architecture slice")
            entries.append((cpu, offset))
        architectures = set()
        for cpu, offset in entries:
            stream.seek(offset)
            slice_header = stream.read(8)
            if slice_header[:4] not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
                raise ValueError("Universal executable contains a non-Mach-O slice")
            slice_endian = "<" if slice_header[:4] == b"\xcf\xfa\xed\xfe" else ">"
            if struct.unpack(slice_endian + "I", slice_header[4:])[0] != cpu:
                raise ValueError("Universal executable architecture header does not match its slice")
            architectures.add(CPU_NAMES.get(cpu, f"unknown-{cpu:x}"))
        return architectures


def bundle_errors(app: Path, *, require_universal: bool = False) -> list[str]:
    app = Path(app).resolve()
    errors = []
    if app.name != "Textractor Pro.app":
        errors.append("Built app must be named Textractor Pro.app")
    try:
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if not isinstance(info, dict):
            raise ValueError("Info.plist must be a dictionary")
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        return errors + [f"Built Info.plist: {error}"]
    expected = {
        "CFBundleIdentifier": "com.textractor.app", "CFBundleName": "Textractor Pro",
        "CFBundleDisplayName": "Textractor Pro", "CFBundleExecutable": "Textractor",
        "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            errors.append(f"Built {key} must be {value}")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", str(info.get(key, ""))):
            errors.append(f"Built {key} must contain an expanded numeric version")
    executable = app / "Contents/MacOS/Textractor"
    if not executable.resolve().is_relative_to(app) or not executable.is_file() or not os.access(executable, os.X_OK):
        errors.append("Built app is missing its executable or executable permission")
    else:
        try:
            architectures = mach_o_architectures(executable)
            if not architectures.issubset({"arm64", "x86_64"}):
                errors.append(f"Unsupported executable architectures: {sorted(architectures)}")
            if require_universal and not {"arm64", "x86_64"}.issubset(architectures):
                errors.append("App Store Mac archive must include both arm64 and x86_64")
        except (OSError, ValueError) as error:
            errors.append(str(error))
    resources = app / "Contents/Resources"
    for relative in REQUIRED_RESOURCES:
        path = resources / relative
        if not path.resolve().is_relative_to(app) or not path.is_file() or path.stat().st_size == 0:
            errors.append(f"Missing or external runtime resource: {relative}")
    try:
        with (resources / "PrivacyInfo.xcprivacy").open("rb") as stream:
            errors.extend(manifest_errors(plistlib.load(stream), "macos"))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        errors.append(f"Built privacy manifest: {error}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--require-universal", action="store_true")
    args = parser.parse_args()
    errors = bundle_errors(args.app, require_universal=args.require_universal)
    if errors:
        parser.exit(1, "Mac app packaging failed:\n- " + "\n- ".join(errors) + "\n")
    print(f"Mac app identity, executable and runtime resources passed: {args.app}")
    print("Signing, provisioning and runtime acceptance remain separate checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
