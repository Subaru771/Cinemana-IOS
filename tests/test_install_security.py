"""Adversarial packaging and signing metadata regression tests (no Apple secrets)."""
from datetime import datetime, timedelta, timezone
import importlib.util
import io
from pathlib import Path
import plistlib
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT/path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
sync = module('sync_security', 'scripts/sync_install_release.py')
profiles = module('profiles', 'scripts/check_appstore_profile.py')

class PackagingTests(unittest.TestCase):
    def ipa(self, changes=None, extras=None, executable=True):
        info = dict(CFBundleIdentifier='app.cinemana.mobile.ios', CFBundleShortVersionString='2.1.1', CFBundleVersion='30', MinimumOSVersion='16.0', CFBundleExecutable='Cinemana')
        info.update(changes or {})
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as z:
            z.writestr('Payload/Cinemana.app/Info.plist', plistlib.dumps(info))
            if executable:
                z.writestr('Payload/Cinemana.app/Cinemana', b'fixture only, not a signed binary')
            for name, value in (extras or {}).items():
                z.writestr(name, value)
        return data.getvalue()
    def test_packaging_is_not_signing_proof(self):
        self.assertEqual(sync.validate_ipa(self.ipa())['CFBundleVersion'], '30')
    def test_reject_invalid_packages(self):
        cases = [self.ipa({'CFBundleIdentifier':'another.app'}), self.ipa({'MinimumOSVersion':'bad'}), self.ipa({'CFBundleExecutable':'../x'}), self.ipa(executable=False), self.ipa(extras={'../bad':b'x'}), self.ipa(extras={'Payload/Cinemana.app/embedded.mobileprovision':b'fake'}), self.ipa(extras={'Payload/Second.app/Info.plist':b'x'})]
        for raw in cases:
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                sync.validate_ipa(raw)
    def test_resource_limits(self):
        old = sync.MAX_EXPANDED
        try:
            sync.MAX_EXPANDED = 1
            with self.assertRaises(ValueError):
                sync.validate_ipa(self.ipa())
        finally:
            sync.MAX_EXPANDED = old
    def test_url_boundaries(self):
        for url in ['http://github.com/Subaru771/Cinemana-IOS/releases/download/v/a.ipa', 'https://github.com.evil/a', 'https://github.com/Subaru771/Cinemana-IOS/releases/download/v/a.ipa?token=x', 'https://github.com/other/repo/releases/download/v/a.ipa']:
            with self.subTest(url=url), self.assertRaises(ValueError): sync.release_url(url)

class ProfileTests(unittest.TestCase):
    def profile(self):
        return dict(ExpirationDate=datetime.now(timezone.utc)+timedelta(days=1), TeamIdentifier=['TEAM'], UUID='id', Name='App Store', DeveloperCertificates=[b'fixture'], Entitlements={'application-identifier':'TEAM.app.cinemana.mobile.ios','com.apple.developer.team-identifier':'TEAM','get-task-allow':False,'beta-reports-active':True})
    def test_correct_metadata(self):
        profiles.validate(self.profile(), 'TEAM')
    def test_reject_wrong_distribution_expired_and_team(self):
        for change in [dict(ExpirationDate=datetime(2000,1,1)),dict(ProvisionedDevices=['fixture']),dict(ProvisionsAllDevices=True),dict(TeamIdentifier=['OTHER']),dict(Name='injected\nFIELD=value'),dict(DeveloperCertificates=[])]:
            p=self.profile();p.update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): profiles.validate(p,'TEAM')
        for key,value in [('application-identifier','TEAM.*'),('get-task-allow',True),('beta-reports-active',False)]:
            p=self.profile();p['Entitlements'][key]=value
            with self.subTest(key=key), self.assertRaises(ValueError): profiles.validate(p,'TEAM')
