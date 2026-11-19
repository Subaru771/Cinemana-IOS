"""Guard against publishing a different app or leaking draft releases."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sync', ROOT/'scripts/sync_install_release.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

class ReleaseTests(unittest.TestCase):
    def test_only_published_cinemana_unsigned_ipa(self):
        def release(date, names, draft=False):
            return dict(published_at=date, draft=draft, assets=[dict(name=n, state='uploaded') for n in names])
        releases = [release('2026-11-01', ['Cinemana-iOS-v1-Unsigned.ipa']), release('2026-11-03', ['Cinemana-SideStore.ipa', 'app.apk']), release(None, ['Cinemana-iOS-v3-Unsigned.ipa']), release('2026-11-04', ['Cinemana-iOS-v4-Unsigned.ipa'], True), release('2026-11-02', ['Cinemana-iOS-v2-Unsigned.ipa'])]
        self.assertEqual([a['name'] for r,a in sync.candidates(releases)], ['Cinemana-iOS-v2-Unsigned.ipa','Cinemana-iOS-v1-Unsigned.ipa'])

    def test_updated_latest_asset_precedes_older_numbered_release(self):
        numbered = dict(published_at='2026-11-11T07:00:00Z', draft=False,
                        assets=[dict(name='Cinemana-iOS-v1.0-Unsigned.ipa',
                                     state='uploaded', updated_at='2026-11-11T07:00:00Z')])
        latest = dict(published_at='2026-11-10T01:00:00Z', draft=False,
                      assets=[dict(name='Cinemana-iOS-v1.0-Unsigned.ipa',
                                   state='uploaded', updated_at='2026-11-19T12:00:00Z')])
        self.assertIs(next(sync.candidates([numbered, latest]))[0], latest)

    def test_catalog_and_source_agree(self):
        data = json.loads((ROOT/'landing/release.json').read_text())
        source = json.loads((ROOT/'landing/source.json').read_text())
        version = source['apps'][0]['versions'][0]
        for key in ['version','downloadURL','size','minOSVersion']:
            self.assertEqual(data[key], version[key])
        self.assertEqual(data['signing'], 'unsigned')
        self.assertFalse(data['deviceTested'])
        self.assertRegex(data['sha256'], '^[a-f0-9]{64}$')

    def test_network_url_restricted(self):
        with self.assertRaises(ValueError):
            sync.fetch('https://example.org/fake.ipa')

if __name__ == '__main__':
    unittest.main()
