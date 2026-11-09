import copy
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from check_release_config import CONFIRMATIONS, manifest_errors, metadata_errors, png_has_alpha


class MetadataTests(unittest.TestCase):
    def draft(self):
        return {"status": "draft", "name": "Textractor Pro", "subtitle": "Copy text from your screen",
                "description": "Extract text on your device.", "keywords": "ocr,text,screen",
                "promotional_text": "Capture and review text.", "review_notes": "Open the menu bar app.",
                "screenshot_paths": [], "submission": {}}

    def ready(self):
        data = self.draft()
        data["status"] = "ready"
        data["screenshot_paths"] = ["appstore/macos/screenshots/capture.png"]
        data["submission"] = dict.fromkeys(CONFIRMATIONS, True)
        data["submission"].update({
            "support_url": "https://github.com/the-lucky-clover/Textractor/issues",
            "privacy_policy_url": "https://github.com/the-lucky-clover/Textractor/blob/main/PRIVACY_POLICY.md",
            "review_contact": {"first_name": "Test", "last_name": "Fixture",
                               "email": "review@fixture.invalid", "phone": "+1 916 555 0100"},
        })
        return data

    def test_draft_allows_build_but_cannot_be_submitted(self):
        self.assertEqual(metadata_errors(self.draft()), [])
        self.assertTrue(metadata_errors(self.draft(), submission=True))

    def test_unicode_keywords_enforce_bytes_not_characters(self):
        data = self.draft()
        data["keywords"] = "漢" * 34
        self.assertLess(len(data["keywords"]), 100)
        self.assertTrue(any("UTF-8" in issue for issue in metadata_errors(data)))

    def test_stale_product_name_is_rejected(self):
        data = self.draft()
        data["name"] = "Textractor"
        self.assertTrue(metadata_errors(data))

    def test_complete_metadata_structure_and_missing_declarations(self):
        self.assertEqual(metadata_errors(self.ready(), submission=True), [])
        for key in CONFIRMATIONS:
            data = self.ready()
            data["submission"][key] = False
            with self.subTest(key=key):
                self.assertTrue(metadata_errors(data, submission=True))

    def test_placeholder_support_and_contact_are_rejected(self):
        data = self.ready()
        data["submission"]["support_url"] = "https://example.com/support"
        data["submission"]["review_contact"]["email"] = "pounds.1@example.com"
        errors = metadata_errors(data, submission=True)
        self.assertTrue(any("support_url" in issue for issue in errors))
        self.assertTrue(any("placeholder" in issue for issue in errors))

    def test_absent_or_malformed_review_contact_rejected(self):
        for value in (None, {}, {"email": None}):
            data = self.ready()
            data["submission"]["review_contact"] = value
            with self.subTest(value=value):
                self.assertTrue(metadata_errors(data, submission=True))


class ManifestTests(unittest.TestCase):
    def manifest(self):
        return {
            "NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [],
            "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [
                {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                 "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]},
            ],
        }

    def test_mobile_defaults_and_mac_timestamp_distinction(self):
        self.assertEqual(manifest_errors(self.manifest(), "ios"), [])
        self.assertTrue(any("FileTimestamp" in issue for issue in manifest_errors(self.manifest(), "macos")))

    def test_missing_reason_and_duplicate_categories_rejected(self):
        data = self.manifest()
        data["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = []
        self.assertTrue(manifest_errors(data, "ios"))
        data = self.manifest()
        data["NSPrivacyAccessedAPITypes"] *= 2
        self.assertTrue(any("unique" in issue for issue in manifest_errors(data, "ios")))

    def test_malformed_manifest_is_reported(self):
        for data in ([], {"NSPrivacyAccessedAPITypes": None},
                     {**self.manifest(), "NSPrivacyTracking": True}):
            with self.subTest(data=data):
                self.assertTrue(manifest_errors(data, "ios"))


class IconTests(unittest.TestCase):
    def png(self, color_type, transparent_palette=False):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, color_type, 0, 0, 0))
        if transparent_palette:
            data += chunk(b"tRNS", b"\x00")
        return data + chunk(b"IEND", b"")

    def test_alpha_channels_and_palette_transparency_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            icon = Path(folder) / "icon.png"
            for color_type, transparent in ((6, False), (4, False), (3, True)):
                with self.subTest(color_type=color_type, transparent=transparent):
                    icon.write_bytes(self.png(color_type, transparent))
                    self.assertTrue(png_has_alpha(icon))
            icon.write_bytes(self.png(2))
            self.assertFalse(png_has_alpha(icon))

    def test_truncated_icon_fails_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            icon = Path(folder) / "icon.png"
            icon.write_bytes(self.png(2)[:-5])
            with self.assertRaisesRegex(ValueError, "Truncated"):
                png_has_alpha(icon)


if __name__ == "__main__":
    unittest.main()
