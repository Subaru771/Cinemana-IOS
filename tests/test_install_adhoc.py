import datetime as dt
import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import stat
import urllib.parse
import zipfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "scripts/build_adhoc_ota.py"
spec = importlib.util.spec_from_file_location("build_adhoc_ota", SOURCE)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def openssl(*args):
    subprocess.run(["openssl", *map(str, args)], check=True, capture_output=True)


class AdHocBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.tmp.name)
        openssl("req", "-x509", "-newkey", "rsa:2048", "-keyout", cls.base / "key.pem",
                "-out", cls.base / "cert.pem", "-nodes", "-days", "1",
                "-subj", "/CN=Test-only-provisioning-profile")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def create_ipa(self, bundle=app.EXPECTED_BUNDLE, adhoc=True, expired=False, sig=True):
        profile = {
            "Entitlements": {"application-identifier":"TESTTEAM01."+bundle, "get-task-allow":False, "com.apple.developer.team-identifier":"TESTTEAM01"},
            "ProvisionedDevices": ["TEST-UDID-PLACEHOLDER"] if adhoc else [],
            "ExpirationDate":dt.datetime(2020 if expired else 2099, 1, 1),
            "Name": "Synthetic test profile", "TeamIdentifier":["TESTTEAM01"], "DeveloperCertificates":[b"fixture-cert"],
        }
        payload = self.root / "profile.plist"
        payload.write_bytes(plistlib.dumps(profile))
        encoded = self.root / "profile.mobileprovision"
        openssl("cms", "-sign", "-binary", "-nodetach", "-in", payload,
                "-signer", self.base / "cert.pem", "-inkey", self.base / "key.pem",
                "-outform", "DER", "-out", encoded)
        ipa = self.root / "sample.ipa"
        info = {"CFBundleIdentifier":bundle,"CFBundlePackageType":"APPL",
                "CFBundleExecutable":"Cinemana", "CFBundleShortVersionString":"2.1.1", "CFBundleVersion":"30", "MinimumOSVersion":"16.0"}
        with zipfile.ZipFile(ipa, "w") as zipf:
            zipf.writestr("Payload/Cinemana.app/Info.plist",plistlib.dumps(info))
            zipf.writestr("Payload/Cinemana.app/embedded.mobileprovision",encoded.read_bytes())
            zipf.writestr("Payload/Cinemana.app/Cinemana",b"fake executable")
            if sig:
                zipf.writestr("Payload/Cinemana.app/_CodeSignature/CodeResources",b"synthetic-signature-not-real")
        return ipa

    def test_preview_never_publishes_ipa_manifest_or_enabled_link(self):
        ipa=self.create_ipa()
        result=app.build(ipa, self.root / "out", "https://install.example.test/closed-beta/")
        output=self.root / "out"
        self.assertFalse((output/'manifest.plist').exists())
        self.assertFalse((output/'Cinemana.ipa').exists())
        self.assertIsNone(result['install'])
        self.assertFalse(result['metadata']['signatureChecked'])
        page=(output/'index.html').read_text()
        self.assertIn('PREVIEW ONLY',page)
        self.assertIn('aria-disabled="true"',page)
        self.assertNotIn('itms-services://',page)
        self.assertNotIn('TEST-UDID', (output/'release.json').read_text())

    def test_publish_rejects_synthetic_signatures_without_native_verifier(self):
        ipa=self.create_ipa()
        with patch.object(app.sys, 'platform', 'linux'), self.assertRaisesRegex(app.PackageError, 'requires macOS'):
            app.build(ipa,self.root/'out','https://example.test/',preview=False)
        self.assertFalse((self.root/'out').exists())

    def test_manifest_metadata_and_escaping(self):
        info=app.inspect_ipa(self.create_ipa())
        manifest=plistlib.loads(app.make_manifest('https://example.test/app.ipa?a=1&b=2',info))
        self.assertEqual(manifest['items'][0]['metadata']['bundle-version'],'30')
        self.assertEqual(manifest['items'][0]['assets'][0]['url'],'https://example.test/app.ipa?a=1&b=2')

    def test_cms_trust_rejects_self_signed_profile(self):
        ipa=self.create_ipa()
        with zipfile.ZipFile(ipa) as z:
            blob=z.read('Payload/Cinemana.app/embedded.mobileprovision')
        # Even explicitly trusting the fixture root cannot impersonate Apple's profile-signing authority.
        with self.assertRaisesRegex(app.PackageError, "CMS signer"):
            app.decode_profile(blob,self.base/'cert.pem')

    def test_publish_writes_assets_only_after_verifier_passes(self):
        # Tests plumbing only: this fixture can never pass the real native verifier.
        ipa=self.create_ipa()
        with patch.object(app,'verify_native') as verify:
            result=app.build(ipa,self.root/'out','https://example.test/private/',preview=False)
        verify.assert_called_once()
        manifest=plistlib.loads((self.root/'out/manifest.plist').read_bytes())
        self.assertEqual(manifest['items'][0]['metadata']['bundle-version'],'30')
        self.assertTrue((self.root/'out/Cinemana.ipa').is_file())
        self.assertEqual(urllib.parse.parse_qs(urllib.parse.urlsplit(result['install']).query)['url'],['https://example.test/private/manifest.plist'])

    def test_unsigned_rejected(self):
        ipa = self.root / "unsigned.ipa"
        with zipfile.ZipFile(ipa,"w") as z:
            z.writestr("Payload/Cinemana.app/Info.plist",plistlib.dumps({"CFBundleIdentifier": app.EXPECTED_BUNDLE}))
        with self.assertRaisesRegex(app.PackageError,"Missing embedded"):
            app.inspect_ipa(ipa)

    def test_app_store_profile_rejected(self):
        with self.assertRaisesRegex(app.PackageError,"registered device list"):
            app.inspect_ipa(self.create_ipa(adhoc=False))

    def test_wrong_bundle_rejected(self):
        with self.assertRaisesRegex(app.PackageError,"Unexpected bundle"):
            app.inspect_ipa(self.create_ipa(bundle="com.other.app"))

    def test_expired_profile_rejected(self):
        with self.assertRaisesRegex(app.PackageError,"expired"):
            app.inspect_ipa(self.create_ipa(expired=True))

    def test_missing_signature_resources_rejected(self):
        with self.assertRaisesRegex(app.PackageError,"Missing app code signature"):
            app.inspect_ipa(self.create_ipa(sig=False))

    def test_http_link_rejected(self):
        with self.assertRaisesRegex(app.PackageError,"HTTPS"):
            app.build(self.root/"missing.ipa",self.root/"out","http://example.test/foo/")

    def test_protect_existing_output(self):
        ipa=self.create_ipa()
        out=self.root/"out"
        out.mkdir()
        (out/"human-data.txt").write_text("do not overwrite")
        with self.assertRaisesRegex(app.PackageError,"new directory"):
            app.build(ipa,out,"https://example.test/foo/")
        self.assertEqual((out/"human-data.txt").read_text(),"do not overwrite")

    def test_unsafe_urls(self):
        for url in ['https://localhost/', 'https://127.0.0.1/', 'https://192.168.1.1/', 'https://[::1]/', 'https://host.local/', 'https://example.test/%2e%2e/', 'https://example.test/?token=secret', 'https://user:pass@example.test/', 'https://example.test/#fragment']:
            with self.subTest(url=url), self.assertRaises(app.PackageError): app.public_base(url)

    def test_adversarial_archive(self):
        original=self.create_ipa().read_bytes()
        for filename in ['../outside', '/absolute', 'Payload/Cinemana.app/Info.plist', 'Payload/Cinemana.app/PlugIns/Extra.appex/file']:
            ipa=self.root/'bad.ipa';ipa.write_bytes(original)
            with zipfile.ZipFile(ipa,'a') as z: z.writestr(filename,b'x')
            with self.subTest(filename=filename), self.assertRaises(app.PackageError): app.inspect_ipa(ipa)
        ipa.write_bytes(original)
        with zipfile.ZipFile(ipa,'a') as z:
            entry=zipfile.ZipInfo('Payload/Cinemana.app/link');entry.create_system=3;entry.external_attr=(stat.S_IFLNK|0o777)<<16
            z.writestr(entry,'../../outside')
        with self.assertRaises(app.PackageError): app.inspect_ipa(ipa)

    def test_resource_limits_and_output_symlink(self):
        ipa=self.create_ipa()
        with patch.object(app,'MAX_EXPANDED',1), self.assertRaises(app.PackageError): app.inspect_ipa(ipa)
        link=self.root/'link'; link.symlink_to(self.root/'other')
        with self.assertRaises(app.PackageError): app.build(ipa,link,'https://example.test/')

    def test_entitlement_subset(self):
        self.assertTrue(app.permitted({'keychain-access-groups':['TEAM.app']},{'keychain-access-groups':['TEAM.*']}))
        self.assertFalse(app.permitted({'get-task-allow':True},{'get-task-allow':False}))
        self.assertFalse(app.permitted({'unknown':True},{}))


    def test_native_preflight_rejects_signer_and_entitlement_mismatches(self):
        ipa=self.create_ipa()
        with zipfile.ZipFile(ipa) as z:
            profile=app.decode_profile(z.read('Payload/Cinemana.app/embedded.mobileprovision'))
        ca=self.root/'public-roots.pem';ca.write_text('test-only placeholder')
        for mismatch in ('certificate','entitlements','codesign'):
            def fake_command(command):
                if '--verify' in command:
                    self.assertIn('anchor apple generic',command[command.index('-R')+1])
                    if mismatch=='codesign':raise app.PackageError('Invalid native signature')
                if '--extract-certificates' in command:
                    prefix=command[command.index('--extract-certificates')+1]
                    Path(prefix+'0').write_bytes(b'wrong-cert' if mismatch=='certificate' else b'fixture-cert')
                if '--entitlements' in command:
                    ent=dict(profile['Entitlements']);ent['unauthorized-capability']=True
                    return plistlib.dumps(ent)
                return b''
            with self.subTest(mismatch=mismatch), patch.object(app.sys,'platform','darwin'), patch.object(app,'decode_profile',return_value=profile), patch.object(app,'checked',side_effect=fake_command), self.assertRaises(app.PackageError):
                app.verify_native(ipa,ca)


if __name__=="__main__":
    unittest.main()
