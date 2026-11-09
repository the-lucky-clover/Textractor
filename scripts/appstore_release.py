#!/usr/bin/env python3
"""Archive/export Textractor Pro with Xcode; upload is an explicit, gated action."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

from check_release_signoff import PLATFORM_PATHS
from verify_macos_bundle import bundle_errors

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = {
    "macos": {"scheme": "Textractor", "destination": "generic/platform=macOS",
              "bundle_id": "com.textractor.app", "version": "2.0.0", "build": "2000"},
    "ios": {"scheme": "TextractorMobile", "destination": "generic/platform=iOS",
            "bundle_id": "com.textractor.app.ios", "version": "1.0", "build": "1"},
}
PROVENANCE_NAME = "TextractorPro-provenance.json"


def run(command: list[str], *, capture: bool = False, capture_stderr: bool = False) -> str:
    result = subprocess.run(command, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.STDOUT if capture_stderr else None)
    return result.stdout.strip() if capture else ""


def marketing_version(value: str) -> str:
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value):
        raise argparse.ArgumentTypeError("Use two or three numeric marketing version components")
    return value


def build_number(value: str) -> str:
    if not re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", value):
        raise argparse.ArgumentTypeError("Use a positive build number with up to three numeric components")
    return value


def export_options(team_id: str, *, upload: bool) -> dict:
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("TEAM_ID must be your 10-character Apple Developer team identifier")
    return {"method": "app-store-connect", "destination": "upload" if upload else "export",
            "teamID": team_id, "signingStyle": "automatic",
            "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
            "generateAppStoreInformation": True}


def authentication_args(env: dict[str, str]) -> list[str]:
    names = ("ASC_API_KEY_PATH", "ASC_API_KEY_ID", "ASC_API_ISSUER_ID")
    present = [bool(env.get(name)) for name in names]
    if any(present) and not all(present):
        raise ValueError("Set all of ASC_API_KEY_PATH, ASC_API_KEY_ID and ASC_API_ISSUER_ID, or none for Xcode account authentication")
    if not any(present):
        return []
    key_path = Path(env[names[0]]).expanduser().resolve()
    if not key_path.is_file():
        raise ValueError("ASC_API_KEY_PATH does not identify a readable .p8 key")
    return ["-authenticationKeyPath", str(key_path), "-authenticationKeyID", env[names[1]],
            "-authenticationKeyIssuerID", env[names[2]]]


def directory_digest(directory: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            digest.update(path.relative_to(directory).as_posix().encode() + b"\0link\0")
            digest.update(os.readlink(path).encode() + b"\0")
        elif path.is_file():
            digest.update(path.relative_to(directory).as_posix().encode() + b"\0file\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
    return digest.hexdigest()


def source_digest(platform: str) -> str:
    digest = hashlib.sha256()
    names = run(["git", "ls-files", "-z", "--", *PLATFORM_PATHS[platform]], capture=True).split("\0")
    for name in sorted(filter(None, names)):
        digest.update(name.encode() + b"\0")
        path = ROOT / name
        digest.update(path.read_bytes() if path.exists() else b"\0deleted\0")
        digest.update(b"\0")
    return digest.hexdigest()


def require_clean_source() -> None:
    if run(["git", "status", "--porcelain", "--untracked-files=all"], capture=True):
        raise ValueError("Commit or stash local changes before producing a signed release archive")


def archive_app(archive: Path) -> Path:
    app = archive / "Products/Applications/Textractor Pro.app"
    if not app.is_dir():
        raise ValueError(f"Xcode archive is missing its application: {app}")
    return app


def app_info(app: Path, platform: str) -> dict:
    info = app / ("Contents/Info.plist" if platform == "macos" else "Info.plist")
    with info.open("rb") as stream:
        result = plistlib.load(stream)
    if result.get("CFBundleIdentifier") != PLATFORMS[platform]["bundle_id"]:
        raise ValueError("Archive bundle identifier differs from the existing app identity")
    if result.get("CFBundleDisplayName", result.get("CFBundleName")) != "Textractor Pro":
        raise ValueError("Archive does not use the public name Textractor Pro")
    manifest = app / ("Contents/Resources/PrivacyInfo.xcprivacy" if platform == "macos" else "PrivacyInfo.xcprivacy")
    with manifest.open("rb") as stream:
        plistlib.load(stream)
    return result


def verified_archive_app(archive: Path, platform: str) -> tuple[Path, dict]:
    app = archive_app(archive)
    if platform == "macos":
        errors = bundle_errors(app, require_universal=True)
        if errors:
            raise ValueError("Mac archive packaging failed:\n- " + "\n- ".join(errors))
    return app, app_info(app, platform)


def validate_signature_identity(details: str, platform: str, team_id: str) -> None:
    """A valid ad-hoc signature is not an Apple-account signed archive."""
    values = details.splitlines()
    if "Signature=adhoc" in values or not any(line.startswith("Authority=") for line in values):
        raise ValueError("Archive requires an Apple signing certificate; ad-hoc signatures cannot be exported")
    if f"TeamIdentifier={team_id}" not in values:
        raise ValueError("Archive signing team differs from TEAM_ID")
    if f"Identifier={PLATFORMS[platform]['bundle_id']}" not in values:
        raise ValueError("Code signature identifier differs from the app identity")


def verify_signature(app: Path, platform: str, team_id: str) -> None:
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    details = run(["codesign", "--display", "--verbose=4", str(app)], capture=True, capture_stderr=True)
    validate_signature_identity(details, platform, team_id)
    if platform == "macos":
        data = run(["codesign", "--display", "--entitlements", ":-", str(app)], capture=True)
        if plistlib.loads(data.encode()).get("com.apple.security.app-sandbox") is not True:
            raise ValueError("Mac App Store archive is not signed with App Sandbox")
    # Xcode may use a development identity for the archive, then distribution-sign
    # during export. The exported package and its profile still need device signoff.


def validate_provenance(record: dict, *, platform: str, digest: str,
                        app_digest: str, version: str, build: str, team_id: str) -> None:
    expected = {"schema": 1, "platform": platform, "signed": True,
                "source_sha256": digest, "app_sha256": app_digest,
                "version": version, "build": build, "team_id": team_id}
    for key, value in expected.items():
        if record.get(key) != value:
            raise ValueError(f"Archive provenance does not match {key}; create a new signed archive from this source")


def check_gate(platform: str, stage: str, version: str, build: str) -> None:
    command = [sys.executable, str(ROOT / "scripts/check_release_signoff.py"),
               "--platform", platform, "--stage", stage]
    if stage == "submission":
        command += ["--version", version, "--build", build]
    run(command)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=PLATFORMS, default="macos")
    parser.add_argument("--action", choices=("archive", "export", "upload"), default="archive")
    parser.add_argument("--unsigned", action="store_true", help="Compile an archive for CI only; it cannot be exported or uploaded")
    parser.add_argument("--version", type=marketing_version, help="Explicit marketing version; overrides the checked-in default for archive")
    parser.add_argument("--build", type=build_number, help="Explicit build number; does not modify source files")
    parser.add_argument("--archive-path", type=Path, help="Specific archive; existing archives are never overwritten")
    parser.add_argument("--allow-provisioning-updates", action="store_true", help="Allow Xcode to contact Apple to manage signing profiles")
    args = parser.parse_args(argv)
    try:
        if args.unsigned and args.action != "archive":
            raise ValueError("Unsigned CI archives cannot be exported or uploaded")
        config = PLATFORMS[args.platform]
        version, build = args.version or config["version"], args.build or config["build"]
        name = f"{version}-{build}" + ("-unsigned" if args.unsigned else "")
        default_archive = ROOT / "dist/appstore" / args.platform / name / "Textractor Pro.xcarchive"
        archive = (args.archive_path or default_archive).expanduser().resolve()
        team = os.environ.get("TEAM_ID", "")
        auth = authentication_args(dict(os.environ)) if not args.unsigned else []
        if not args.unsigned:
            export_options(team, upload=args.action == "upload")
            require_clean_source()
        if sys.platform != "darwin":
            raise ValueError("App Store archives require macOS with Xcode; static checks: python3 -m unittest discover -s scripts")
        for tool in ("xcodebuild", "xcodegen", "codesign", "git"):
            if not shutil.which(tool):
                raise ValueError(f"Required tool is missing: {tool}")
        xcode_version = run(["xcodebuild", "-version"], capture=True)
        if args.platform == "ios":
            match = re.search(r"Xcode (\d+)", xcode_version)
            if not match or int(match[1]) < 26:
                raise ValueError("Current iOS App Store submissions require Xcode 26 or later")
        provision_args = (["-allowProvisioningUpdates"] if args.allow_provisioning_updates else []) + auth

        if args.action == "archive":
            check_gate(args.platform, "candidate", version, build)
            if archive.exists():
                raise ValueError(f"Archive already exists. Choose a new --archive-path or build number: {archive}")
            archive.parent.mkdir(parents=True, exist_ok=True)
            before = source_digest(args.platform)
            run(["xcodegen", "generate", "--spec", str(ROOT / "project.yml")])
            command = ["xcodebuild", "-project", str(ROOT / "Textractor.xcodeproj"),
                       "-scheme", config["scheme"], "-configuration", "Release",
                       "-destination", config["destination"], "-archivePath", str(archive),
                       "-derivedDataPath", str(archive.parent / "DerivedData"), "archive",
                       f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={build}",
                       "ONLY_ACTIVE_ARCH=NO", "SKIP_INSTALL=NO"]
            if args.unsigned:
                command += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]
            else:
                command += ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_STYLE=Automatic",
                            f"DEVELOPMENT_TEAM={team}", *provision_args]
            run(command)
            app, info = verified_archive_app(archive, args.platform)
            if (str(info.get("CFBundleShortVersionString")), str(info.get("CFBundleVersion"))) != (version, build):
                raise ValueError("Built Info.plist did not receive the requested version and build")
            if source_digest(args.platform) != before:
                raise ValueError("Source changed while Xcode was archiving; create a new archive")
            if not args.unsigned:
                require_clean_source()
                verify_signature(app, args.platform, team)
            record = {"schema": 1, "platform": args.platform, "signed": not args.unsigned,
                      "version": version, "build": build, "team_id": team if not args.unsigned else None,
                      "commit": run(["git", "rev-parse", "HEAD"], capture=True),
                      "source_sha256": before, "app_sha256": directory_digest(app), "xcode": xcode_version}
            (archive / PROVENANCE_NAME).write_text(json.dumps(record, indent=2) + "\n")
            print(f"Created {'unsigned CI' if args.unsigned else 'signed candidate'} archive: {archive}")
            print("No App Store upload or review submission was performed.")
            return 0

        app, info = verified_archive_app(archive, args.platform)
        actual_version, actual_build = str(info.get("CFBundleShortVersionString")), str(info.get("CFBundleVersion"))
        if (args.version and args.version != actual_version) or (args.build and args.build != actual_build):
            raise ValueError("Requested version/build does not match the existing archive")
        record = json.loads((archive / PROVENANCE_NAME).read_text())
        validate_provenance(record, platform=args.platform, digest=source_digest(args.platform),
                            app_digest=directory_digest(app), version=actual_version,
                            build=actual_build, team_id=team)
        run(["git", "merge-base", "--is-ancestor", record["commit"], "HEAD"])
        verify_signature(app, args.platform, team)
        check_gate(args.platform, "submission" if args.action == "upload" else "candidate", actual_version, actual_build)
        output = archive.parent / ("Upload" if args.action == "upload" else "Export")
        if output.exists():
            raise ValueError(f"Export destination already exists; retain or move it before retrying: {output}")
        output.mkdir()
        options = output / "ExportOptions.plist"
        with options.open("wb") as stream:
            plistlib.dump(export_options(team, upload=args.action == "upload"), stream)
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
             "-exportOptionsPlist", str(options), "-exportPath", str(output), *provision_args])
        if args.action == "upload":
            print("Xcode upload finished. Check App Store Connect processing; this did not submit for review or publish the app.")
        else:
            print(f"Exported App Store package to {output}. No upload or review submission was performed.")
        return 0
    except (ValueError, OSError, KeyError, json.JSONDecodeError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"Textractor Pro release stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
