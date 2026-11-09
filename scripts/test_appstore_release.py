"""Regression checks for release identity, credentials and archive provenance."""
import argparse
import contextlib
import copy
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import appstore_release as release


class AppStoreReleaseTests(unittest.TestCase):
    def test_signed_archive_requires_matching_team_and_identifier(self):
        valid = "Executable=/tmp/Textractor Pro.app/Contents/MacOS/Textractor\nIdentifier=com.textractor.app\nAuthority=Apple Development: Test Fixture\nTeamIdentifier=A123456789\n"
        release.validate_signature_identity(valid, "macos", "A123456789")
        for invalid in (
            valid.replace("A123456789", "B987654321"),
            valid.replace("Identifier=com.textractor.app", "Identifier=other.app"),
            valid.replace("Authority=Apple Development: Test Fixture", "Signature=adhoc"),
            valid.replace("Authority=Apple Development: Test Fixture\n", ""),
            "",
        ):
            with self.subTest(details=invalid), self.assertRaises(ValueError):
                release.validate_signature_identity(invalid, "macos", "A123456789")

    def test_export_is_local_and_preserves_reviewed_build(self):
        local = release.export_options("A123456789", upload=False)
        self.assertEqual(local["destination"], "export")
        self.assertEqual(local["method"], "app-store-connect")
        self.assertFalse(local["manageAppVersionAndBuildNumber"])
        self.assertEqual(release.export_options("A123456789", upload=True)["destination"], "upload")
        with self.assertRaises(ValueError):
            release.export_options("", upload=False)

    def test_api_credentials_must_be_complete(self):
        self.assertEqual(release.authentication_args({}), [])
        for env in ({"ASC_API_KEY_ID": "key"}, {"ASC_API_ISSUER_ID": "issuer"},
                    {"ASC_API_KEY_PATH": "/missing", "ASC_API_KEY_ID": "key", "ASC_API_ISSUER_ID": "issuer"}):
            with self.assertRaises(ValueError):
                release.authentication_args(env)

    def test_key_path_with_spaces_is_one_argument(self):
        with tempfile.TemporaryDirectory(prefix="release test ") as temp:
            key = Path(temp) / "private key.p8"
            key.write_text("test fixture; not a credential")
            arguments = release.authentication_args({"ASC_API_KEY_PATH": str(key),
                                                     "ASC_API_KEY_ID": "key", "ASC_API_ISSUER_ID": "issuer"})
            self.assertEqual(arguments[1], str(key.resolve()))
            self.assertEqual(len(arguments), 6)

    def test_unsigned_upload_fails_before_any_external_command(self):
        with patch.object(release, "run") as command, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(release.main(["--unsigned", "--action", "upload"]), 1)
        command.assert_not_called()

    def test_release_versions_reject_options_and_zero_build(self):
        for value in ("2; touch bad", "--help", "2.0 beta", "2", "2.0.0.0"):
            with self.assertRaises(argparse.ArgumentTypeError):
                release.marketing_version(value)
        for value in ("0", "01", "2000;exit", "1.2.3.4"):
            with self.assertRaises(argparse.ArgumentTypeError):
                release.build_number(value)
        self.assertEqual(release.marketing_version("1.0"), "1.0")
        self.assertEqual(release.build_number("2000"), "2000")

    def test_each_provenance_field_is_required_and_exact(self):
        arguments = {"platform": "macos", "digest": "source", "app_digest": "app",
                     "version": "2.0.0", "build": "2000", "team_id": "A123456789"}
        record = {"schema": 1, "platform": "macos", "signed": True, "source_sha256": "source",
                  "app_sha256": "app", "version": "2.0.0", "build": "2000", "team_id": "A123456789"}
        release.validate_provenance(record, **arguments)
        for field in record:
            wrong = copy.deepcopy(record)
            wrong[field] = False if field == "signed" else "different"
            with self.subTest(field=field), self.assertRaises(ValueError):
                release.validate_provenance(wrong, **arguments)
        with self.assertRaises(ValueError):
            release.validate_provenance({}, **arguments)

    def test_bundle_digest_detects_content_rename_and_link_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            file = app / "binary"
            file.write_bytes(b"original")
            before = release.directory_digest(app)
            file.write_bytes(b"edited")
            self.assertNotEqual(before, release.directory_digest(app))
            file.write_bytes(b"original")
            self.assertEqual(before, release.directory_digest(app))
            file.rename(app / "renamed")
            self.assertNotEqual(before, release.directory_digest(app))
            link = app / "link"
            link.symlink_to("renamed")
            with_link = release.directory_digest(app)
            link.unlink()
            link.symlink_to("elsewhere")
            self.assertNotEqual(with_link, release.directory_digest(app))

    def test_archive_identity_and_resource_root_manifest(self):
        with tempfile.TemporaryDirectory(prefix="archive test ") as temp:
            archive = Path(temp)
            app = archive / "Products/Applications/Textractor Pro.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            path = app / "Contents/Info.plist"
            info = {"CFBundleIdentifier": "com.textractor.app", "CFBundleDisplayName": "Textractor Pro",
                    "CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "2001"}
            path.write_bytes(plistlib.dumps(info))
            with self.assertRaises(FileNotFoundError):
                release.app_info(app, "macos")
            (resources / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
            self.assertEqual(release.archive_app(archive), app)
            self.assertEqual(release.app_info(app, "macos")["CFBundleVersion"], "2001")
            info["CFBundleIdentifier"] = "wrong.app"
            path.write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError):
                release.app_info(app, "macos")

    def test_submission_gate_receives_actual_archive_version(self):
        with patch.object(release, "run") as command:
            release.check_gate("ios", "submission", "1.3", "41")
        args = command.call_args.args[0]
        self.assertEqual(args[-4:], ["--version", "1.3", "--build", "41"])
        self.assertIn("submission", args)


if __name__ == "__main__":
    unittest.main()
