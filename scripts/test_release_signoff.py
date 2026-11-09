import copy
import subprocess
import tempfile
import unittest
from pathlib import Path

from check_release_signoff import PLATFORM_CHECKS, validate, verify_tested_source


def approved_record(platform="macos"):
    return {
        "schema_version": 2,
        "platforms": {
            platform: {
                "status": "approved",
                "version": "2.0.0" if platform == "macos" else "1.0",
                "build": "2000" if platform == "macos" else "1",
                "tested_commit": "a" * 40,
                "checks": dict.fromkeys(PLATFORM_CHECKS[platform], "passed"),
                "evidence": {key: ["qa/device-run.txt"] for key in PLATFORM_CHECKS[platform]},
            }
        },
    }


class ReleaseGateTests(unittest.TestCase):
    def test_pending_and_old_unscoped_record_are_not_signoff(self):
        for record in ({"status": "approved"}, {"schema_version": 2, "platforms": {}}):
            with self.subTest(record=record), self.assertRaises(ValueError):
                validate(record)

    def test_each_check_and_its_evidence_are_mandatory(self):
        for platform, required in PLATFORM_CHECKS.items():
            for key in required:
                with self.subTest(platform=platform, check=key):
                    record = approved_record(platform)
                    record["platforms"][platform]["checks"][key] = "pending-device"
                    with self.assertRaises(ValueError):
                        validate(record, platform)
                    record = approved_record(platform)
                    del record["platforms"][platform]["evidence"][key]
                    with self.assertRaises(ValueError):
                        validate(record, platform)

    def test_other_platform_does_not_block_approved_platform(self):
        record = approved_record()
        record["platforms"]["ios"] = {"status": "blocked", "checks": {}}
        validate(record, "macos")
        with self.assertRaises(ValueError):
            validate(record, "ios")

    def test_references_must_be_real_nonempty_lists(self):
        for refs in ([], "", [" "], [None], "qa/file.txt"):
            record = approved_record()
            record["platforms"]["macos"]["evidence"]["signing"] = refs
            with self.subTest(refs=refs), self.assertRaises(ValueError):
                validate(record)

    def test_actual_archive_versions_must_match(self):
        validate(approved_record(), version="2.0.0", build="2000")
        for version, build in (("2.1", "2000"), ("2.0.0", "2001")):
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                validate(approved_record(), version=version, build=build)

    def test_full_commit_and_explicit_versions_required(self):
        for key, value in (("tested_commit", "main"), ("tested_commit", "abcdef"),
                           ("version", None), ("version", "v2.0"), ("build", 2000), ("build", "0")):
            record = approved_record()
            record["platforms"]["macos"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate(record)

    def test_complete_mobile_record(self):
        validate(approved_record("ios"), "ios", version="1.0", build="1")


class SourceEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@invalid.test")
        self.git("config", "user.name", "Release gate fixture")
        self.write("Sources/Probe.swift", "let value = 1\n")
        self.write("ios/Probe.swift", "let value = 1\n")
        self.write("fastlane/Fastfile", "fixture\n")
        self.write("appstore/macos/en-US.json", "{}\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.commit = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True).stdout

    def write(self, path, value):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def test_clean_tested_source_is_accepted(self):
        verify_tested_source(self.root, self.commit, "macos")

    def test_unstaged_staged_and_committed_changes_rejected(self):
        self.write("Sources/Probe.swift", "let value = 2\n")
        with self.assertRaisesRegex(ValueError, "differ"):
            verify_tested_source(self.root, self.commit, "macos")
        self.git("add", ".")
        with self.assertRaisesRegex(ValueError, "differ"):
            verify_tested_source(self.root, self.commit, "macos")
        self.git("commit", "-qm", "changed")
        with self.assertRaisesRegex(ValueError, "differ"):
            verify_tested_source(self.root, self.commit, "macos")

    def test_new_untracked_source_rejected(self):
        self.write("Sources/New.swift", "let new = true\n")
        with self.assertRaisesRegex(ValueError, "New.swift"):
            verify_tested_source(self.root, self.commit, "macos")

    def test_pipeline_and_listing_changes_rejected(self):
        for path in ("fastlane/Fastfile", "appstore/macos/en-US.json"):
            with self.subTest(path=path):
                old = (self.root / path).read_text()
                self.write(path, "changed\n")
                with self.assertRaises(ValueError):
                    verify_tested_source(self.root, self.commit, "macos")
                self.write(path, old)

    def test_platform_specific_source_is_scoped(self):
        self.write("ios/Probe.swift", "let value = 2\n")
        verify_tested_source(self.root, self.commit, "macos")
        with self.assertRaises(ValueError):
            verify_tested_source(self.root, self.commit, "ios")

    def test_signoff_and_validation_docs_can_record_evidence(self):
        self.write("qa/release-signoff.json", "{}\n")
        self.write("qa/VALIDATION.md", "Recorded evidence\n")
        verify_tested_source(self.root, self.commit, "macos")

    def test_nonexistent_commit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Git verification failed"):
            verify_tested_source(self.root, "0" * 40, "macos")


if __name__ == "__main__":
    unittest.main()
