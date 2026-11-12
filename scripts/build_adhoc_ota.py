#!/usr/bin/env python3
"""Build an Apple Ad Hoc OTA install site from a previously signed iOS IPA.

Preview is the safe default. Publishing requires macOS offline signature checks.
No Apple credentials are handled here. This is a packaging utility, not a signer.
The package must have been signed with a valid Ad Hoc profile including testers.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import os
import stat
import ipaddress
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
from pathlib import Path

EXPECTED_BUNDLE = "app.cinemana.mobile.ios"
MAX_IPA_BYTES = 200_000_000
MAX_EXPANDED = 500_000_000


class PackageError(ValueError):
    pass


def decode_profile(blob: bytes, ca_file: Path | None = None) -> dict:
    if not shutil.which("openssl"):
        raise PackageError("OpenSSL must be installed to inspect the embedded provisioning profile")
    with tempfile.TemporaryDirectory(prefix="cinemana-profile-") as tmp:
        src, dst = Path(tmp)/"profile.mobileprovision", Path(tmp)/"profile.plist"
        src.write_bytes(blob)
        command = ["openssl", "cms", "-verify", "-inform", "DER", "-in", str(src),
                   "-out", str(dst)]
        if ca_file is None:
            command += ["-noverify"]  # Metadata inspection only; never used for publishing.
        else:
            command += ["-CAfile", str(ca_file), "-no-CApath", "-no-CAstore", "-purpose", "any", "-signer", str(Path(tmp)/"cms-signer.pem")]
        p = subprocess.run(command, capture_output=True, text=True, timeout=20, check=False)
        if p.returncode != 0:
            raise PackageError("Embedded provisioning profile cannot be decoded as a CMS-signed plist")
        if ca_file is not None:
            subject = subprocess.run(['openssl', 'x509', '-in', str(Path(tmp)/'cms-signer.pem'), '-noout', '-subject', '-nameopt', 'sep_multiline'], capture_output=True, text=True, timeout=20, check=False)
            names = [line.strip().partition('=')[2].strip() for line in subject.stdout.splitlines() if line.strip().startswith('CN=') or line.strip().startswith('CN =')]
            if subject.returncode or names != ['Apple iPhone OS Provisioning Profile Signing']:
                raise PackageError('CMS signer is not the supported Apple provisioning-profile signing authority')
        try:
            result = plistlib.loads(dst.read_bytes())
        except (ValueError, TypeError, plistlib.InvalidFileException) as e:
            raise PackageError("Decoded provisioning profile is not valid plist") from e
        if not isinstance(result, dict):
            raise PackageError("Unexpected profile format")
        return result


def inspect_ipa(path: Path) -> dict:
    if not path.is_file():
        raise PackageError("IPA path is not a file")
    length = path.stat().st_size
    if not 0 < length < MAX_IPA_BYTES:
        raise PackageError("IPA size is outside safe limits")
    try:
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if len(entries) > 20000 or len(set(names)) != len(names):
                raise PackageError("Duplicate or excessive ZIP entries")
            if sum(entry.file_size for entry in entries) > MAX_EXPANDED:
                raise PackageError("Expanded archive exceeds limit")
            for entry in entries:
                parts = entry.filename.rstrip('/').split('/')
                mode = entry.external_attr >> 16
                if (entry.filename.startswith('/') or '\\' in entry.filename or
                    any(part in ('.', '..', '') for part in parts) or entry.flag_bits & 1 or
                    stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))):
                    raise PackageError("Unsafe, encrypted or special ZIP entry")
                if '.appex/' in entry.filename or '.app/' in entry.filename.split('.app/', 1)[-1]:
                    raise PackageError("Nested apps/extensions are not supported by this tool")
            if archive.testzip() is not None:
                raise PackageError("Corrupt IPA")
            infos = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
            if len(infos) != 1:
                raise PackageError("Expected exactly one iPhone app bundle in the IPA")
            root = infos[0].rsplit("/", 1)[0] + "/"
            if root + "embedded.mobileprovision" not in names:
                raise PackageError("Missing embedded.mobileprovision: unsigned/App Store IPAs are not OTA Ad Hoc builds")
            if root + "_CodeSignature/CodeResources" not in names:
                raise PackageError("Missing app code signature resources")
            if archive.getinfo(infos[0]).file_size > 2_000_000 or archive.getinfo(root + "embedded.mobileprovision").file_size > 2_000_000:
                raise PackageError("Unexpectedly large app metadata")
            info = plistlib.loads(archive.read(infos[0]))
            profile = decode_profile(archive.read(root + "embedded.mobileprovision"))
    except (zipfile.BadZipFile, zipfile.LargeZipFile, plistlib.InvalidFileException) as e:
        raise PackageError("Not a valid IPA archive") from e
    if not isinstance(info, dict):
        raise PackageError("App plist must be a dictionary")
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or not executable or '/' in executable or '\\' in executable or executable in ('.', '..') or root + executable not in names:
        raise PackageError("Missing or invalid app executable")
    for key in ('CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion'):
        if not isinstance(info.get(key), str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', info[key]):
            raise PackageError("Invalid numeric version metadata")
    if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE:
        raise PackageError("Unexpected bundle identifier; refusing to distribute a different app")
    if info.get("CFBundlePackageType") != "APPL":
        raise PackageError("Not an iOS application")
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not isinstance(build, str) or not version or not build:
        raise PackageError("Missing app version/build")
    devices = profile.get("ProvisionedDevices")
    if not isinstance(devices, list) or not devices or not all(isinstance(x, str) for x in devices):
        raise PackageError("No registered device list: this is not an Ad Hoc provisioning profile")
    team = profile.get('TeamIdentifier')
    ent = profile.get('Entitlements') or {}
    if (not isinstance(team, list) or len(team) != 1 or not isinstance(team[0], str) or
        not re.fullmatch(r'[A-Z0-9]{10}', team[0]) or not isinstance(ent, dict) or
        ent.get('com.apple.developer.team-identifier') != team[0]):
        raise PackageError("Invalid or mismatched team metadata")
    if ent.get('application-identifier') != team[0] + '.' + EXPECTED_BUNDLE:
        raise PackageError("Profile must explicitly cover this team and bundle")
    if not isinstance(profile.get('DeveloperCertificates'), list) or not profile['DeveloperCertificates'] or not all(isinstance(c, bytes) for c in profile['DeveloperCertificates']):
        raise PackageError("Profile has no signing certificates")
    if profile.get("ProvisionsAllDevices"):
        raise PackageError("Enterprise distribution is intentionally unsupported")
    ent = profile.get("Entitlements") or {}
    if not isinstance(ent, dict) or ent.get("get-task-allow") is not False:
        raise PackageError("Expected a distribution provisioning profile, not a development profile")
    app_id = ent.get("application-identifier") or ent.get("com.apple.application-identifier")
    if not isinstance(app_id, str) or not app_id.endswith("." + EXPECTED_BUNDLE):
        raise PackageError("Provisioning profile does not cover the Cinemana bundle identifier")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime):
        raise PackageError("Provisioning profile has no valid expiration date")
    now = dt.datetime.now(dt.timezone.utc)
    if expiry.replace(tzinfo=dt.timezone.utc) <= now:
        raise PackageError("Provisioning profile has already expired")
    with path.open("rb") as stream:
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"bundle": EXPECTED_BUNDLE, "version": version, "build": build,
            "minimumIOS": str(info.get("MinimumOSVersion", "unknown")),
            "deviceCount": len(devices), "expiry": expiry.replace(tzinfo=dt.timezone.utc).isoformat(),
            "size": length, "sha256": sha}


def make_manifest(ipa_url: str, info: dict) -> bytes:
    payload = {"items": [{"assets": [{"kind": "software-package", "url": ipa_url}],
                          "metadata": {"bundle-identifier": info["bundle"],
                                       "bundle-version": info["build"],
                                       "kind": "software", "title": "Cinemana"}}]}
    return plistlib.dumps(payload, sort_keys=False)


PAGE = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark"><meta name="theme-color" content="#13090b">
<meta name="robots" content="noindex,nofollow"><title>Cinemana · Private iPhone Beta</title>
<style>
:root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 70% -10%,#572029 0%,#13090b 55%);color:#f8edf0;min-height:100svh}
main{max-width:520px;margin:auto;padding:clamp(34px,8vw,80px) 24px 44px}
.brand{font-size:13px;font-weight:850;letter-spacing:.25em;color:#f48c9c}.mark{width:70px;height:70px;display:grid;place-items:center;border-radius:19px;background:#e3324d;color:white;font-size:31px;box-shadow:0 12px 35px #0009;margin:32px 0}
h1{font-size:clamp(36px,9vw,54px);line-height:1.05;letter-spacing:-.055em;margin:0 0 18px}h1 span{color:#fa8395}.lead{color:#c7adb2;line-height:1.65;font-size:17px}
.meta{font-size:13px;color:#c7adb2;margin:28px 0}.cta{background:#ec3754;color:white;padding:17px 20px;text-decoration:none;display:block;text-align:center;border-radius:15px;font-weight:800;font-size:17px}
.cta:focus-visible{outline:3px solid white;outline-offset:4px}.notice{border:1px solid #8a4652;background:#3d1c26;padding:16px;border-radius:14px;line-height:1.6;margin:25px 0;font-size:14px}
ol{padding-left:25px;line-height:1.9;color:#dcc6cb}li+li{margin-top:8px}a{color:#ff9caf}footer{font-size:12px;color:#a58e95;border-top:1px solid #63313c;margin-top:36px;padding-top:20px;line-height:1.65}
[lang=ar]{direction:rtl;text-align:right}html[lang=ar] ol{padding-right:25px;padding-left:0}.lang{float:right;color:#f6bbc5;background:none;border:1px solid #68404a;border-radius:8px;padding:8px 12px;cursor:pointer}
</style></head><body><main>
<button class="lang" id="lang" type="button" aria-label="Change language">العربية</button>
<div class="brand">CINEMANA · BETA</div><div class="mark" aria-hidden="true">▶</div>
<h1 id="heading">Your cinema.<br><span>Direct to iPhone.</span></h1>
<p class="lead" id="intro">Private Ad Hoc delivery for registered testers only; installation on a physical iPhone remains unverified. No PC, pairing file or SideStore on your phone.</p>
<div class="meta" id="metadata"></div>
<div class="notice" id="restriction">Only pre-registered iPhones can install this build. If your iPhone hasn't been approved by the developer, installation will fail.</div>
<a class="cta" id="install" href="__INSTALL_LINK__">Install Cinemana</a>
<ol id="steps"><li>Open this page in Safari on your registered iPhone.</li><li>Tap Install Cinemana and approve the iOS installation prompt.</li><li>Enable Developer Mode if prompted, then launch Cinemana.</li></ol>
<footer><p id="privacy">Private testing only. This page collects no passwords, Apple IDs, identifiers or analytics. The developer must register your device separately. Builds expire when their Apple signature/profile expires and can be revoked.</p><p id="linknote">No app-signing service is operated by this website. You must have rights to distribute the app and access its content.</p></footer>
<script type="application/json" id="release">__RELEASE_JSON__</script>
<script>
const meta=JSON.parse(document.getElementById('release').textContent);
const data={en:{heading:'Your cinema.<br><span>Direct to iPhone.</span>',intro:'Private Ad Hoc delivery for registered testers only; installation on a physical iPhone remains unverified. No PC, pairing file or SideStore on your phone.',restriction:'Only pre-registered iPhones can install this build. If your iPhone has not been approved by the developer, installation will fail.',install:'Install Cinemana',steps:['Open this page in Safari on your registered iPhone.','Tap Install Cinemana and approve the iOS installation prompt.','Enable Developer Mode if prompted, then launch Cinemana.'],privacy:'Private testing only. This page collects no passwords, Apple IDs, identifiers or analytics. The developer must register your device separately. Builds expire when their Apple signature/profile expires and can be revoked.',linknote:'No app-signing service is operated by this website. You must have rights to distribute the app and access its content.'},ar:{heading:'سينمانا.<br><span>مباشرة على الآيفون.</span>',intro:'توزيع Ad Hoc خاص للأجهزة المسجلة؛ لم يُختبر التثبيت على iPhone حقيقي بدون كمبيوتر أو ملفات اقتران أو SideStore.',restriction:'التثبيت متاح فقط لأجهزة الآيفون المسجّلة مسبقاً لدى المطور. الأجهزة غير المسجّلة لن تتمكن من تثبيت التطبيق.',install:'تثبيت سينمانا',steps:['افتح هذه الصفحة في Safari على الآيفون المسجّل.','اضغط تثبيت سينمانا ووافق على رسالة التثبيت.','فعّل وضع المطور إذا طُلب منك، ثم افتح سينمانا.'],privacy:'نسخة اختبار خاصة. الصفحة لا تجمع كلمات مرور أو حسابات Apple أو معرفات أو إحصائيات. تسجيل الجهاز يتم بشكل منفصل لدى المطور. قد تنتهي صلاحية النسخة أو يتم إلغاء الشهادة.',linknote:'هذا الموقع لا يوقّع التطبيقات. يلزم امتلاك التصاريح المناسبة لتوزيع التطبيق ومحتواه.'}};
const publishing=__PUBLISH__;let lang='en';const $=id=>document.getElementById(id);
function render(){const t=data[lang];document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';$('lang').textContent=lang==='ar'?'English':'العربية';$('heading').innerHTML=t.heading;for(const key of ['intro','restriction','install','privacy','linknote'])$(key).textContent=t[key];$('steps').replaceChildren(...t.steps.map(s=>{const li=document.createElement('li');li.textContent=s;return li;}));$('metadata').textContent=`v${meta.version} · Build ${meta.build} · iOS ${meta.minimumIOS}+ · ${Math.round(meta.size/1000000)} MB · ${meta.expiry}`;if(!publishing || Date.parse(meta.expiry)<=Date.now()){ $('install').removeAttribute('href');$('install').setAttribute('aria-disabled','true');$('install').textContent=lang==='ar'?'التثبيت غير متاح':'Installation unavailable';}}
$('lang').addEventListener('click',()=>{lang=lang==='en'?'ar':'en';render();});render();
if(!/iPad|iPhone|iPod/.test(navigator.userAgent)){$('install').addEventListener('click',e=>{e.preventDefault();alert('Open this link in Safari on a registered iPhone.');});}
</script></main></body></html>'''


def checked(command):
    result = subprocess.run(command, capture_output=True, timeout=60, check=False)
    if result.returncode:
        raise PackageError("Native signature/profile verification failed; inspect locally with Apple tools")
    return result.stdout


def permitted(actual, allowed):
    if type(actual) is not type(allowed):
        return False
    if isinstance(actual, str):
        return actual == allowed or (allowed.endswith('*') and actual.startswith(allowed[:-1]))
    if isinstance(actual, list):
        return all(any(permitted(item, candidate) for candidate in allowed) for item in actual)
    if isinstance(actual, dict):
        return all(key in allowed and permitted(value, allowed[key]) for key, value in actual.items())
    return actual == allowed


def verify_native(ipa: Path, ca_file: Path | None):
    """Offline checks; revocation, recipient eligibility and installation are still device gates."""
    if sys.platform != 'darwin' or not ca_file or not ca_file.is_file():
        raise PackageError("Publishing requires macOS codesign and an official Apple public root PEM bundle (--apple-roots); use --preview elsewhere")
    with tempfile.TemporaryDirectory(prefix='cinemana-verify-') as tmp:
        folder = Path(tmp)
        # inspect_ipa has rejected traversal, symlinks, duplicate and oversized entries.
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(folder)
        app = next((folder/'Payload').glob('*.app'))
        profile = decode_profile((app/'embedded.mobileprovision').read_bytes(), ca_file)
        team = profile['TeamIdentifier'][0]
        requirement = 'anchor apple generic and identifier "' + EXPECTED_BUNDLE + '" and certificate leaf[subject.OU] = "' + team + '"'
        checked(['/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, str(app)])
        cert_prefix = folder/'signer'
        checked(['/usr/bin/codesign', '-d', '--extract-certificates', str(cert_prefix), str(app)])
        leaf = Path(str(cert_prefix)+'0')
        if not leaf.is_file() or leaf.read_bytes() not in profile['DeveloperCertificates']:
            raise PackageError("App signer does not match profile certificates")
        checked(['openssl', 'x509', '-inform', 'DER', '-in', str(leaf), '-checkend', '0', '-noout'])
        raw = checked(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)])
        try:
            ent = plistlib.loads(raw)
        except (ValueError, plistlib.InvalidFileException):
            raise PackageError("Cannot inspect signed app entitlements") from None
        expected = profile['Entitlements']
        if (not isinstance(ent, dict) or ent.get('application-identifier') != expected['application-identifier'] or
            ent.get('com.apple.developer.team-identifier') != team or ent.get('get-task-allow', False) is not False or
            not permitted(ent, expected)):
            raise PackageError("Signed entitlements exceed profile permissions")


def public_base(public_url):
    parsed = urllib.parse.urlsplit(public_url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or
        parsed.query or parsed.fragment or parsed.port not in (None, 443) or
        not public_url.endswith('/') or any(ord(c) < 33 for c in public_url) or
        '%' in parsed.netloc or '\\' in public_url):
        raise PackageError("Provide a public HTTPS directory URL without credentials/query/fragment")
    host = parsed.hostname.lower().rstrip('.')
    if host == 'localhost' or host.endswith(('.localhost', '.local')):
        raise PackageError("Local hosts cannot deliver OTA to testers")
    try:
        if not ipaddress.ip_address(host).is_global:
            raise PackageError("Private IPs cannot deliver OTA to testers")
    except ValueError as error:
        if isinstance(error, PackageError):
            raise
    decoded = urllib.parse.unquote(parsed.path)
    if '%' in decoded or any(part in ('.', '..') for part in decoded.split('/')) or any(ord(c) < 32 for c in decoded) or '\\' in decoded:
        raise PackageError("Unsafe URL path")
    return public_url


def build(ipa: Path, out: Path, public_url: str, *, preview=True, apple_roots=None) -> dict:
    public_base(public_url)
    if out.exists() or out.is_symlink() or any(parent.is_symlink() for parent in out.parents):
        raise PackageError("Output must be a new directory without symlink parents; overwriting is unsupported")
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cinemana-input-') as tmp:
        snapshot = Path(tmp)/'input.ipa'
        if not ipa.is_file() or not 0 < ipa.stat().st_size < MAX_IPA_BYTES:
            raise PackageError("IPA size is outside safe limits")
        # Snapshot first so validation/hash/copy refer to exactly the same bytes.
        with ipa.open('rb') as source, snapshot.open('wb') as target:
            remaining = MAX_IPA_BYTES
            while chunk := source.read(min(1024*1024, remaining + 1)):
                remaining -= len(chunk)
                if remaining <= 0:
                    raise PackageError("IPA exceeds size limit")
                target.write(chunk)
        info = inspect_ipa(snapshot)
        if not preview:
            verify_native(snapshot, apple_roots)
        manifest_url = urllib.parse.urljoin(public_url, 'manifest.plist')
        ota_link = 'itms-services://?' + urllib.parse.urlencode({'action': 'download-manifest', 'url': manifest_url})
        public = dict(info, signatureChecked=not preview, deviceTested=False)
        with tempfile.TemporaryDirectory(prefix='.cinemana-site-', dir=out.parent) as stage:
            staging = Path(stage)/'site'
            staging.mkdir()
            if not preview:
                shutil.copyfile(snapshot, staging/'Cinemana.ipa')
                (staging/'manifest.plist').write_bytes(make_manifest(urllib.parse.urljoin(public_url, 'Cinemana.ipa'), info))
            (staging/'release.json').write_text(json.dumps(public, indent=2)+'\n', encoding='utf-8')
            display = {key: info[key] for key in ('version','build','minimumIOS','size','expiry')}
            page = PAGE.replace('__INSTALL_LINK__', html.escape(ota_link, quote=True) if not preview else '#')
            page = page.replace('__PUBLISH__', 'false' if preview else 'true')
            page = page.replace('__RELEASE_JSON__', json.dumps(display).replace('<', '\\u003c'))
            if preview:
                page = page.replace('id="install"', 'id="install" aria-disabled="true" tabindex="-1"')
                page = page.replace('<div class="meta"', '<div class="notice">PREVIEW ONLY · معاينة فقط — no IPA or install manifest is published.</div><div class="meta"')
                page = page.replace('href="#"', 'href="#" onclick="return false"')
            (staging/'index.html').write_text(page, encoding='utf-8')
            if out.exists() or out.is_symlink():
                raise PackageError("Output appeared during build; refusing replacement")
            os.rename(staging, out)
    return {'url': public_url, 'install': None if preview else ota_link, 'metadata': public}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ipa", type=Path, required=True, help="Existing, signed Ad Hoc Cinemana IPA")
    ap.add_argument("--base-url", required=True, help="Final HTTPS directory URL, ending in /")
    ap.add_argument("--out", type=Path, required=True, help="Output static folder")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument('--preview', action='store_true', help='Default: disabled design preview, no IPA or manifest')
    mode.add_argument('--publish', action='store_true', help='macOS: verify signatures and package private Ad Hoc delivery')
    ap.add_argument('--apple-roots', type=Path, help='Official Apple public root certificates in PEM format; never a private key')
    args = ap.parse_args()
    try:
        result = build(args.ipa, args.out, args.base_url, preview=not args.publish, apple_roots=args.apple_roots)
    except (ValueError, TypeError, KeyError, OSError, plistlib.InvalidFileException, subprocess.TimeoutExpired) as e:
        print(f"Unable to prepare native beta: {e}", file=sys.stderr)
        return 1
    print("Prepared preview." if not args.publish else "Prepared private Ad Hoc package after offline checks. Revocation and real-device installation remain unverified.")
    print("Registered devices:",result["metadata"]["deviceCount"])
    print("Open from registered iPhone:", result["url"])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
