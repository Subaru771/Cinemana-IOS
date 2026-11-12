"""Offline regression tests. Synthetic tools cannot prove an iOS installation."""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'install.sh'
DIGEST = 'e334f86e6ceeab2e0d886c07611246533f474bb18838cf13ebc09ed1f0d622b5'


class BootstrapTests(unittest.TestCase):
    def test_shell_syntax(self):
        subprocess.run(['sh', '-n', str(SCRIPT)], check=True)

    def test_pinned_official_release_and_dependencies(self):
        source = SCRIPT.read_text()
        self.assertIn('https://github.com/SideStore/SideStore/releases/download/0.7.0-alpha/SideStore.ipa', source)
        self.assertIn(DIGEST, source)
        self.assertIn('86cfb433e4ecc042dafca357c7ad9d10d25bcb0b', source)
        self.assertIn('--ipa "$IPA"', source)
        self.assertNotIn('curl | sh', source)
        self.assertNotIn('wget | sh', source)
        self.assertNotIn('SIBOOT_PASSWORD=', source)

    def test_help_and_no_network(self):
        r = subprocess.run(['sh', str(SCRIPT), '--help'], capture_output=True, text=True, check=True)
        self.assertIn('NOT automated', r.stdout)

    def test_verify_rejects_wrong_bytes(self):
        with tempfile.TemporaryDirectory() as t:
            f = pathlib.Path(t) / 'fake.ipa'
            f.write_bytes(b'PK\x03\x04not-a-real-ipa')
            r = subprocess.run(['sh', str(SCRIPT), 'verify', str(f)], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('not the pinned official', r.stderr)

    def install_with_mocks(self, mismatch=False, consent='y\n'):
        with tempfile.TemporaryDirectory() as t:
            base = pathlib.Path(t)
            mockbin = base / 'bin'
            mockbin.mkdir()
            home = base / 'home'
            home.mkdir()
            runlog = base / 'upstream-args'

            def put(name, script):
                path = mockbin / name
                path.write_text('#!/bin/sh\n' + script)
                path.chmod(0o755)

            put('uname', 'printf "aarch64\\n"\n')
            wrong = '0' * 64
            put('sha256sum', f"""case "$1" in
  *SideStore*.ipa*)
    printf '%s  %s\\n' '{"0"*64 if mismatch else DIGEST}' "$1" ;;
  *) printf '%064d  %s\\n' 0 "$1" ;;
esac
""")
            put('curl', """out=''
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out="$2"; shift 2;; *) shift;; esac
done
case "$out" in
 *SideStore*.ipa.part) printf 'fake IPA fixture' > "$out";;
 *siboot-install.sh.part) cat > "$out" <<'SCRIPT'
#!/bin/sh
printf '%s\\n' "$*" > "$BOOTSTRAP_RUNLOG"
SCRIPT
 ;;
 *) exit 3;;
esac
""")
            env = os.environ.copy()
            env.update({
                'HOME': str(home),
                'PATH': str(mockbin) + os.pathsep + os.environ['PATH'],
                'BOOTSTRAP_RUNLOG': str(runlog),
            })
            r = subprocess.run(['sh', str(SCRIPT)], input=consent, text=True, env=env, capture_output=True)
            return dict(
                returncode=r.returncode,
                out=r.stdout,
                err=r.stderr,
                args=runlog.read_text() if runlog.exists() else None,
            )

    def test_valid_fixture_passes_correct_custom_ipa_to_upstream(self):
        result = self.install_with_mocks()
        self.assertEqual(result['returncode'], 0, result)
        self.assertIn('--ipa ', result['args'])
        self.assertIn('SideStore-0.7.0-alpha.ipa', result['args'])
        self.assertIn('UNVERIFIED', result['out'])

    def test_checksum_mismatch_refuses_upstream(self):
        result = self.install_with_mocks(mismatch=True)
        self.assertNotEqual(result['returncode'], 0)
        self.assertIsNone(result['args'])
        self.assertIn('checksum mismatch', result['err'])

    def test_decline_prevents_signing(self):
        result = self.install_with_mocks(consent='n\n')
        self.assertEqual(result['returncode'], 0)
        self.assertIsNone(result['args'])
        self.assertIn('Cancelled', result['out'])


if __name__ == '__main__':
    unittest.main()
