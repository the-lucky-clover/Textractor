import plistlib
from pathlib import Path
import struct
import tempfile
import unittest

from verify_macos_bundle import REQUIRED_RESOURCES, bundle_errors, mach_o_architectures


class MacBundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Textractor Pro.app"
        self.resources = self.app / "Contents/Resources"
        self.executable = self.app / "Contents/MacOS/Textractor"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x0100000C) + bytes(24))
        self.executable.chmod(0o755)
        self.info = {
            "CFBundleIdentifier": "com.textractor.app", "CFBundleName": "Textractor Pro",
            "CFBundleDisplayName": "Textractor Pro", "CFBundleExecutable": "Textractor",
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
            "CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "2000",
        }
        self.write_info()
        for name in REQUIRED_RESOURCES:
            resource = self.resources / name
            resource.parent.mkdir(parents=True, exist_ok=True)
            resource.write_bytes(b"fixture resource")
        manifest = {
            "NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [
                {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]},
                {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]},
            ],
        }
        (self.resources / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(manifest))

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_complete_development_layout_and_universal_requirement(self):
        self.assertEqual(bundle_errors(self.app), [])
        self.assertIn("App Store Mac archive must include both arm64 and x86_64", bundle_errors(self.app, require_universal=True))
        executable = bytearray(8224)
        header = (
            b"\xca\xfe\xba\xbe" + struct.pack(">I", 2)
            + struct.pack(">IIIII", 0x01000007, 3, 4096, 32, 12)
            + struct.pack(">IIIII", 0x0100000C, 0, 8192, 32, 12)
        )
        executable[:len(header)] = header
        executable[4096:4104] = b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x01000007)
        executable[8192:8200] = b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x0100000C)
        self.executable.write_bytes(executable)
        self.assertEqual(bundle_errors(self.app, require_universal=True), [])

    def test_flattened_menu_resources_are_not_accepted(self):
        for filename in ("textractor-menubar@1x.png", "textractor-menubar@2x.png"):
            (self.resources / "MenuBar" / filename).rename(self.resources / filename)
        self.assertTrue(any("MenuBar/" in error for error in bundle_errors(self.app)))

    def test_localizations_and_privacy_must_be_in_main_app_resources(self):
        nested = self.resources / "Textractor_Textractor.bundle"
        nested.mkdir()
        (self.resources / "en.lproj").rename(nested / "en.lproj")
        (self.resources / "PrivacyInfo.xcprivacy").rename(nested / "PrivacyInfo.xcprivacy")
        errors = bundle_errors(self.app)
        self.assertTrue(any("en.lproj" in error for error in errors))
        self.assertTrue(any("PrivacyInfo.xcprivacy" in error for error in errors))

    def test_unexpanded_version_and_wrong_identity_rejected(self):
        self.info["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
        self.info["CFBundleName"] = "Textractor"
        self.write_info()
        errors = bundle_errors(self.app)
        self.assertTrue(any("CFBundleVersion" in error for error in errors))
        self.assertTrue(any("CFBundleName" in error for error in errors))

    def test_resource_cannot_depend_on_build_machine_file(self):
        icon = self.resources / "textractor.icns"
        outside = Path(self.directory.name) / "outside.icns"
        icon.rename(outside)
        icon.symlink_to(outside)
        self.assertTrue(any("external runtime resource: textractor.icns" in error for error in bundle_errors(self.app)))

    def test_executable_permission_and_macho_required(self):
        self.executable.chmod(0o644)
        self.assertTrue(any("executable permission" in error for error in bundle_errors(self.app)))
        self.executable.chmod(0o755)
        self.executable.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.assertTrue(any("Mach-O" in error for error in bundle_errors(self.app)))

    def test_truncated_universal_header_is_rejected(self):
        self.executable.write_bytes(b"\xca\xfe\xba\xbe" + struct.pack(">I", 2))
        with self.assertRaisesRegex(ValueError, "truncated universal"):
            mach_o_architectures(self.executable)

    def test_universal_table_does_not_establish_missing_architecture_slice(self):
        self.executable.write_bytes(
            b"\xca\xfe\xba\xbe" + struct.pack(">I", 1)
            + struct.pack(">IIIII", 0x01000007, 3, 4096, 32, 12)
        )
        with self.assertRaisesRegex(ValueError, "out-of-bounds"):
            mach_o_architectures(self.executable)


if __name__ == "__main__":
    unittest.main()
