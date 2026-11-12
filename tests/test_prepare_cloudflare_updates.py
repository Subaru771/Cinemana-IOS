"""Offline tests for the GitHub-free Cloudflare update bundle."""
import importlib.util
import json
import os
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_cloudflare_updates", ROOT / "scripts/prepare_cloudflare_updates.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def ipa_fixture(path, *, build="28", bundle="app.cinemana.mobile.ios", executable=True):
    info = {
        "CFBundleIdentifier": bundle,
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": build,
        "MinimumOSVersion": "16.0",
        "CFBundleExecutable": "CinemanaMobile",
    }
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/CinemanaMobile.app/Info.plist", plistlib.dumps(info))
        if executable:
            archive.writestr("Payload/CinemanaMobile.app/CinemanaMobile", os.urandom(120_000))


class UpdateBundleTests(unittest.TestCase):
    def existing(self, root):
        path = root / "existing.json"
        path.write_text(json.dumps({"schema": 1, "tv": {"enabled": True, "version": "1.2", "versionCode": 120}, "ios": {"enabled": False, "version": "1.0", "build": 27, "notes": {"en": "old"}}}))
        return path

    def test_build28_is_published_without_github_url(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa = root / "input.ipa"
            ipa_fixture(ipa)
            result = module.prepare(ipa, root / "website", self.existing(root))
            ios = result["ios"]
            self.assertEqual(result["tv"], {"enabled": True, "version": "1.2", "versionCode": 120})
            self.assertFalse(ios["enabled"])
            self.assertEqual(ios["notes"], {"en": "old"})
            self.assertEqual(ios["build"], 28)
            self.assertEqual(ios["version"], "1.0")
            self.assertEqual(ios["minOSVersion"], "16.0")
            self.assertTrue(ios["downloadUrl"].endswith("/Cinemana-iOS-v1.0-b28-Unsigned.ipa"))
            self.assertEqual(ios["size"], (root / "website" / "Cinemana-iOS-v1.0-b28-Unsigned.ipa").stat().st_size)
            self.assertNotIn("github", (root / "website" / "updates.json").read_text().lower())

    def test_invalid_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_fixture(root / "x.ipa", bundle="com.other.app")
            with self.assertRaises(ValueError):
                module.prepare(root / "x.ipa", root / "out", self.existing(root))

    def test_missing_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_fixture(root / "x.ipa", executable=False)
            with self.assertRaises(ValueError):
                module.prepare(root / "x.ipa", root / "out", self.existing(root))

    def test_invalid_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_fixture(root / "x.ipa", build="28-beta")
            with self.assertRaises(ValueError):
                module.prepare(root / "x.ipa", root / "out", self.existing(root))


if __name__ == "__main__":
    unittest.main()
