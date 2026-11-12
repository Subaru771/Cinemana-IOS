"""Fail-closed tests for the optional source-only SideStore handoff patch."""
import importlib.util
import pathlib
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'patch_siboot.py'
spec = importlib.util.spec_from_file_location('patch_siboot', SOURCE)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

class SourcePatchTests(unittest.TestCase):
    def fixture(self, root, main=patch.MAIN_OLD, seed='pub async fn hand_over(\n'):
        path = pathlib.Path(root) / 'minis/src'
        path.mkdir(parents=True, exist_ok=True)
        (path/'main.rs').write_text('fn fake() {\n' + main + '}\n')
        (path/'seed.rs').write_text(seed + '\nasync fn write_verified(\n')
        return path

    def test_patch_adds_target_without_removing_original(self):
        with tempfile.TemporaryDirectory() as d:
            p=self.fixture(d)
            patch.patch_source(pathlib.Path(d))
            self.assertIn('signed.name == "SideStore"', (p/'main.rs').read_text())
            self.assertIn('seed::hand_over(&mut connection', (p/'main.rs').read_text())
            s=(p/'seed.rs').read_text()
            self.assertIn('/Documents/PairingFile_RemoteRP.plist', s)
            self.assertIn('/Documents/ALTPairingFile.mobiledevicepairing', s)
            self.assertIn('"isPairingReset"', s)
            self.assertIn('"activePairingProtocol"', s)
            self.assertIn('write_verified(&mut afc', s)

    def test_rejects_unexpected_upstream_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            p=self.fixture(d,main='unrelated')
            old_seed=(p/'seed.rs').read_text()
            with self.assertRaises(ValueError):patch.patch_source(pathlib.Path(d))
            self.assertEqual(old_seed,(p/'seed.rs').read_text())

    def test_rejects_second_application_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            p=self.fixture(d)
            patch.patch_source(pathlib.Path(d))
            with self.assertRaises(ValueError):patch.patch_source(pathlib.Path(d))

if __name__=='__main__':unittest.main()