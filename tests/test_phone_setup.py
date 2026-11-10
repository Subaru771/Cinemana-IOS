import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("phone_files", ROOT / "installer-ios/phone_files.py")
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)


def ipa_bytes(bundle=files.BUNDLE, extra_app=False):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as archive:
        archive.writestr("Payload/Installer.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": bundle}))
        if extra_app:
            archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": bundle}))
    return data.getvalue()


class PhoneSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "private state"

    def input(self, name="Installer with spaces.ipa", data=None):
        source = self.root / name
        source.write_bytes(ipa_bytes() if data is None else data)
        return source

    def artifact(self, checksum=None, extra=False, entry="Cinemana-Installer-Unsigned.ipa"):
        source = self.root / "Cinemana-Installer-UNSIGNED.zip"
        data = ipa_bytes()
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr(entry, data)
            if checksum is not False:
                text = checksum or hashlib.sha256(data).hexdigest() + "  /private/runner/Installer.ipa\n"
                archive.writestr(entry + ".sha256", text)
            if extra:
                archive.writestr("another.ipa", data)
        return source

    def test_renamed_ipa_is_detected_by_bundle_not_filename(self):
        result = files.prepare(self.input(), self.state)
        files.validate_ipa(result)
        self.assertEqual("Cinemana-Installer-Unsigned.ipa", result.name)

    def test_actions_zip_is_extracted_and_checksum_verified(self):
        result = files.prepare(self.artifact(), self.state)
        self.assertEqual(ipa_bytes(), result.read_bytes())

    def test_wrong_app_cannot_replace_prepared_installer(self):
        good = files.prepare(self.input(), self.state)
        original = good.read_bytes()
        with self.assertRaisesRegex(ValueError, "not the Cinemana Installer"):
            files.prepare(self.input("Cinemana.ipa", ipa_bytes("com.subaru771.cinemana")), self.state)
        self.assertEqual(original, good.read_bytes())
        self.assertEqual([], list(self.state.glob("*.part")))

    def test_bad_checksum_cannot_replace_valid_cached_file(self):
        good = files.prepare(self.input(), self.state)
        original = good.read_bytes()
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            files.prepare(self.artifact(checksum="0" * 64), self.state)
        self.assertEqual(original, good.read_bytes())

    def test_raw_ipa_companion_checksum_is_checked(self):
        source = self.input()
        source.with_name(source.name + ".sha256").write_text("bad checksum")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            files.prepare(source, self.state)
        self.assertFalse((self.state / "Cinemana-Installer-Unsigned.ipa").exists())

    def test_reuse_validated_ipa_without_copying_onto_itself(self):
        result = files.prepare(self.input(), self.state)
        self.assertEqual(result, files.prepare(result, self.state))

    def test_ambiguous_artifact_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            files.prepare(self.artifact(extra=True), self.state)

    def test_zip_entry_paths_are_never_extracted(self):
        files.prepare(self.artifact(entry="../../outside.ipa"), self.state)
        self.assertFalse((self.root / "outside.ipa").exists())
        self.assertTrue((self.state / "Cinemana-Installer-Unsigned.ipa").is_file())

    def test_multiple_apps_inside_ipa_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "one app"):
            files.prepare(self.input(data=ipa_bytes(extra_app=True)), self.state)

    def test_oversized_ipa_is_rejected_before_copy(self):
        with patch.object(files, "MAX_IPA", 10):
            with self.assertRaisesRegex(ValueError, "large"):
                files.prepare(self.input(), self.state)

    def test_invalid_archive_does_not_leave_partial_state(self):
        with self.assertRaises(zipfile.BadZipFile):
            files.prepare(self.input(data=b"not a zip"), self.state)
        self.assertEqual([], list(self.state.glob("*.part")))

    def test_discovery_is_bounded_and_does_not_recurse_into_symlinks(self):
        self.input()
        (self.root / "Cinemana-Installer-UNSIGNED.zip").write_bytes(b"zip")
        deep = self.root / "a" / "b" / "c"
        deep.mkdir(parents=True)
        (deep / "too-deep.ipa").write_bytes(b"ipa")
        (self.root / "linked").symlink_to(deep, target_is_directory=True)
        self.assertEqual(2, len(files.candidates(self.root)))

    def test_noninteractive_help_and_shell_syntax(self):
        script = ROOT / "installer-ios/phone-bootstrap.sh"
        subprocess.run(["sh", "-n", str(script)], check=True)
        result = subprocess.run(["sh", str(script), "--help"], check=True, capture_output=True, text=True)
        self.assertIn("--prepare-only", result.stdout)

    def test_companion_integrity_pin_matches_deployed_source(self):
        script = (ROOT / "installer-ios/phone-bootstrap.sh").read_text()
        expected = re.search(r"^FILES_SHA=([0-9a-f]{64})$", script, re.M).group(1)
        self.assertEqual(expected, hashlib.sha256((ROOT / "installer-ios/phone_files.py").read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
