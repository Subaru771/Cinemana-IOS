"""Offline orchestration tests. No upstream executable or Apple service is run."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
class AutomationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.folder=Path(self.tmp.name);self.bin=self.folder/'bin';self.bin.mkdir()
        self.home=self.folder/'home with spaces';self.home.mkdir()
        self.trace=self.folder/'trace'
        self.env=dict(os.environ,HOME=str(self.home),PATH=str(self.bin)+os.pathsep+os.environ['PATH'],TEST_TRACE=str(self.trace),SIBOOT_PASSWORD='never-forward-this',SIBOOT_APPLE_ID='never-forward-this')
        self.stub('uname','printf aarch64')
        self.stub('ifconfig','printf "inet 192.0.2.1\\n"')
        self.stub('curl','while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; cp "$TEST_DOWNLOAD" "$1"; exit; fi; shift; done; exit 1')
    def stub(self,name,body):
        p=self.bin/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o700)
    def script(self,stage='minis',bad_download=False):
        source=ROOT/'installer-ios'/('minis-bootstrap.sh' if stage=='minis' else 'rootshell-pair.sh')
        payload=self.folder/'fixture'
        payload.write_text('#!/bin/sh\n'+'[ -z "${SIBOOT_PASSWORD:-}${SIBOOT_APPLE_ID:-}" ] || exit 90\n'*(stage=='minis')+'printf "%s\\n" "${1:-install}" >> "$TEST_TRACE"\n[ "${1:-install}" != "${TEST_FAIL_STAGE:-none}" ]\n')
        sha=hashlib.sha256(payload.read_bytes()).hexdigest()
        script=self.folder/'launcher.sh'
        # Replace only the integrity pin in the test copy. Production has no bypass.
        script.write_text(re.sub(r'^SHA=[a-f0-9]{64}$','SHA='+sha,source.read_text(),flags=re.M))
        download=self.folder/'download';download.write_bytes(b'corrupt' if bad_download else payload.read_bytes())
        self.env['TEST_DOWNLOAD']=str(download)
        return script
    def run_script(self,script,*args):
        return subprocess.run(['sh',str(script),*args],env=self.env,capture_output=True,text=True)
    def stages(self):return self.trace.read_text().splitlines() if self.trace.exists() else []
    def test_install_order_and_reuse(self):
        script=self.script();r=self.run_script(script);self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.stages(),['check','connect','install'])
        self.stub('curl','exit 99')
        self.assertEqual(self.run_script(script).returncode,0)
    def test_diagnostic_never_requests_signing(self):
        r=self.run_script(self.script(),'--diagnose');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.stages(),['check','connect'])
    def test_failure_stops_before_sign_in(self):
        for stage,expected in [('check',['check']),('connect',['check','connect'])]:
            with self.subTest(stage=stage):
                self.trace.unlink(missing_ok=True);self.env['TEST_FAIL_STAGE']=stage
                self.assertNotEqual(self.run_script(self.script()).returncode,0)
                self.assertEqual(self.stages(),expected)
    def test_bad_download_never_executes(self):
        for stage in ['root','minis']:
            with self.subTest(stage=stage):
                r=self.run_script(self.script(stage,bad_download=True));self.assertNotEqual(r.returncode,0)
                self.assertEqual(self.stages(),[])
    def test_pairing_preparation_runs_program(self):
        r=self.run_script(self.script('root'));self.assertEqual(r.returncode,0,r.stderr)
        self.assertTrue((self.home/'.cinemana-pair/ifconfig.txt').is_file())
        self.assertEqual(self.stages(),['install'])
    def test_symlink_directory_refused(self):
        for stage,dirname in [('root','.cinemana-pair'),('minis','.cinemana-minis')]:
            with self.subTest(stage=stage):
                (self.home/dirname).symlink_to(self.folder/'unrelated')
                self.assertNotEqual(self.run_script(self.script(stage)).returncode,0)
                self.assertEqual(self.stages(),[])
    def test_architecture_guard(self):
        self.stub('uname','printf x86_64')
        self.assertNotEqual(self.run_script(self.script()).returncode,0)
        self.assertEqual(self.stages(),[])
    def test_help_syntax_and_invalid_arguments(self):
        for filename in ['rootshell-pair.sh','minis-bootstrap.sh']:
            script=ROOT/'installer-ios'/filename
            subprocess.run(['sh','-n',str(script)],check=True)
            self.assertEqual(self.run_script(script,'--help').returncode,0)
            self.assertNotEqual(self.run_script(script,'--password','secret').returncode,0)
if __name__=='__main__':unittest.main()
