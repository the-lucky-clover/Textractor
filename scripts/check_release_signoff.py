#!/usr/bin/env python3
"""Validate a candidate, or require platform-specific evidence before submission.

Candidate validation is intentionally possible before signing or device testing.
Submission checks never turn a prior development build into a verified store build.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

from check_release_config import check_configuration

ROOT = Path(__file__).resolve().parents[1]
COMMON = ("configuration", "privacy_review", "metadata", "app_store_name", "signing")
PLATFORM_CHECKS = {
    "macos": COMMON + (
        "native_build", "unit_tests", "ui_playtests", "release_archive", "sandbox_launch",
        "ocr_benchmark", "representative_ocr", "continuity_photo", "continuity_multipage",
        "camera_cancel", "voiceover", "multi_display", "screen_recording_permissions",
        "history_migration", "app_store_validation",
    ),
    "ios": COMMON + (
        "ios_build", "ios_unit_tests", "ios_ui_playtests", "release_archive",
        "ios_physical_import", "ios_print_review", "ios_search_quality", "voiceover",
        "archive_recovery", "app_store_validation",
    ),
}
REQUIRED = PLATFORM_CHECKS["macos"]
COMMON_PATHS = (
    "project.yml", "scripts", ".github/workflows", "fastlane", "deploy_appstore.sh",
    "PRIVACY_POLICY.md", "appstore/shared",
)
PLATFORM_PATHS = {
    "macos": COMMON_PATHS + (
        "Sources", "Tests", "Package.swift", "Package.resolved", "build.sh", "install.sh",
        "appstore/macos",
    ),
    "ios": COMMON_PATHS + ("ios", "appstore/ios"),
}


def validate(record, platform="macos", version=None, build=None):
    if not isinstance(record, dict) or record.get("schema_version") != 2:
        raise ValueError("Release blocked; a platform-specific schema_version 2 record is required")
    if platform not in PLATFORM_CHECKS:
        raise ValueError("Unknown release platform")
    platforms = record.get("platforms", {})
    item = platforms.get(platform) if isinstance(platforms, dict) else None
    if not isinstance(item, dict):
        raise ValueError(f"Release blocked; no {platform} signoff record")
    checks = item.get("checks", {})
    if not isinstance(checks, dict):
        raise ValueError("Release blocked; checks must be an object")
    missing = [key for key in PLATFORM_CHECKS[platform] if checks.get(key) != "passed"]
    if item.get("status") != "approved" or missing:
        raise ValueError(f"{platform} release blocked; status={item.get('status')}; missing verification: "
                         + ", ".join(missing))
    commit = item.get("tested_commit")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Release blocked; tested_commit must be a full Git commit SHA")
    evidence = item.get("evidence", {})
    if not isinstance(evidence, dict):
        raise ValueError("Release blocked; evidence must map each check to its references")
    for key in PLATFORM_CHECKS[platform]:
        refs = evidence.get(key)
        if not isinstance(refs, list) or not refs or any(
            not isinstance(ref, str) or not ref.strip() for ref in refs
        ):
            raise ValueError(f"Release blocked; evidence references are required for {key}")
    if not isinstance(item.get("version"), str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", item["version"]):
        raise ValueError("Release blocked; an explicit marketing version is required")
    if not isinstance(item.get("build"), str) or not re.fullmatch(r"[1-9]\d*(?:\.\d+){0,2}", item["build"]):
        raise ValueError("Release blocked; an explicit positive build number is required")
    if version is not None and item["version"] != version:
        raise ValueError("Release blocked; archive marketing version differs from the signoff")
    if build is not None and item["build"] != build:
        raise ValueError("Release blocked; archive build number differs from the signoff")
    return item


def verify_tested_source(root, commit, platform):
    """Reject changed committed, staged, unstaged, and new untracked shipping inputs."""
    def git(*args):
        result = subprocess.run(["git", "-C", str(root), *args], text=True, capture_output=True)
        if result.returncode:
            raise ValueError("Release blocked; Git verification failed: " + result.stderr.strip())
        return result.stdout.strip()

    git("merge-base", "--is-ancestor", commit, "HEAD")
    paths = PLATFORM_PATHS[platform]
    changed = git("diff", "--name-only", commit, "HEAD", "--", *paths)
    dirty = git("status", "--porcelain=v1", "--untracked-files=all", "--", *paths)
    if changed or dirty:
        detail = "\n".join(value for value in (changed, dirty) if value)
        raise ValueError("Release blocked; shipping inputs differ from the tested source:\n" + detail)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=PLATFORM_CHECKS, default="macos")
    parser.add_argument("--stage", choices=("candidate", "submission"), default="submission")
    parser.add_argument("--version", help="Actual archive marketing version (submission)")
    parser.add_argument("--build", help="Actual archive build number (submission)")
    args = parser.parse_args()
    errors = check_configuration(ROOT, args.platform, submission=args.stage == "submission")
    if errors:
        raise SystemExit("Release configuration blocked:\n- " + "\n- ".join(errors))
    if args.stage == "candidate":
        print(f"{args.platform} candidate configuration passed; signing, device testing and submission are not approved.")
        return
    try:
        record = json.loads((ROOT / "qa/release-signoff.json").read_text())
        item = validate(record, args.platform, args.version, args.build)
        verify_tested_source(ROOT, item["tested_commit"], args.platform)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
    print(f"{args.platform} submission evidence accepted for unchanged tested source, "
          f"version {item['version']} ({item['build']}).")


if __name__ == "__main__":
    main()
