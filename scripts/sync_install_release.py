#!/usr/bin/env python3
"""Publish metadata only for a downloadable, checksummed Cinemana app release.
Never publish Actions artifacts, draft releases, signing keys or SideStore builds.
"""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import re
import urllib.request
import zipfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
REPO = 'Subaru771/Cinemana-IOS'

MAX_DOWNLOAD = 200_000_000
MAX_EXPANDED = 500_000_000

def release_url(url):
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or parsed.netloc != 'github.com' or
        not parsed.path.startswith('/'+REPO+'/releases/download/') or
        parsed.query or parsed.fragment):
        raise ValueError('Unexpected release URL')
    return url

def fetch(url, limit=MAX_DOWNLOAD):
    if not url.startswith('https://api.github.com/repos/'+REPO+'/releases?'):
        release_url(url)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Cinemana-release-validator'}), timeout=60) as response:
        raw = response.read(limit + 1)
    if len(raw) > limit:
        raise ValueError('Download exceeds size limit')
    return raw

def validate_ipa(raw):
    """Packaging checks only. Neither a plist nor a checksum proves Apple signing."""
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(entries) > 20000 or len(set(names)) != len(names):
            raise ValueError('Duplicate or excessive ZIP entries')
        if sum(entry.file_size for entry in entries) > MAX_EXPANDED:
            raise ValueError('Expanded IPA exceeds size limit')
        for entry in entries:
            parts = entry.filename.split('/')
            if entry.filename.startswith('/') or '\\' in entry.filename or '..' in parts or entry.flag_bits & 1:
                raise ValueError('Unsafe or encrypted ZIP entry')
        infos = [entry for entry in entries if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', entry.filename)]
        if len(infos) != 1 or infos[0].file_size > 1_000_000:
            raise ValueError('Expected one bounded main app plist')
        if archive.testzip() is not None:
            raise ValueError('Corrupt IPA')
        info = plistlib.loads(archive.read(infos[0]))
        if info.get('CFBundleIdentifier') != 'app.cinemana.mobile.ios':
            raise ValueError('Wrong application')
        if any(n.endswith('embedded.mobileprovision') for n in names):
            raise ValueError('Expected an unprovisioned build; this is not a signing validator')
        for key in ('CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion'):
            if not isinstance(info.get(key), str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', info[key]):
                raise ValueError('Missing or invalid version metadata')
        executable = info.get('CFBundleExecutable')
        if not isinstance(executable, str) or not executable or '/' in executable or '\\' in executable or executable in ('.', '..'):
            raise ValueError('Invalid executable name')
        if infos[0].filename.rsplit('/', 1)[0]+'/'+executable not in names:
            raise ValueError('Missing app executable')
        return info

def candidates(releases):
    for release in sorted((r for r in releases if not r.get('draft') and r.get('published_at')), key=lambda r:r['published_at'], reverse=True):
        for asset in release['assets']:
            if re.fullmatch(r'Cinemana-iOS-.+-Unsigned\.ipa', asset['name']) and asset.get('state') == 'uploaded':
                yield release, asset

def main():
    releases = []
    for page in range(1, 11):
        batch = json.loads(fetch(f'https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}'))
        releases.extend(batch)
        if len(batch) < 100:
            break
    release, asset = next(candidates(releases))
    # Fail closed if the newest candidate is broken; do not silently advertise an old build.
    raw = fetch(asset['browser_download_url'])
    if len(raw) != asset['size']:
        raise ValueError('Asset size mismatch')
    digest = hashlib.sha256(raw).hexdigest()
    checksum = next(a for a in release['assets'] if a['name'] == 'SHA256SUMS.txt')
    lines = fetch(checksum['browser_download_url'], limit=1_000_000).decode().splitlines()
    if not any(re.fullmatch(digest + r'\s+\*?(?:dist/)?' + re.escape(asset['name']), line) for line in lines):
        raise ValueError('Checksum mismatch')
    info = validate_ipa(raw)
    data = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'], minOSVersion=info['MinimumOSVersion'], date=release['published_at'][:10], downloadURL=asset['browser_download_url'], releaseURL=release['html_url'], size=len(raw), sha256=digest, signing='unsigned', deviceTested=False)
    (ROOT/'landing/release.json').write_text(json.dumps(data, indent=2)+'\n')
    source = dict(name='Cinemana iOS beta', identifier='app.cinemana.beta.source', apps=[dict(name='Cinemana iOS', bundleIdentifier=info['CFBundleIdentifier'], developerName='Cinemana iOS contributors', localizedDescription='Unsigned development beta. Requires signing. Installation and playback have not been verified on a real iPhone.', iconURL='https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/landing/install-icon.png', versions=[dict(version=data['version'], date=release['published_at'], downloadURL=data['downloadURL'], size=data['size'], minOSVersion=data['minOSVersion'], localizedDescription='Development beta; requires signing. See installation page for device test status.')])], news=[])
    (ROOT/'landing/source.json').write_text(json.dumps(source, indent=2)+'\n')
    print(f"Validated Cinemana {data['version']} ({data['build']}), {len(raw)} bytes, SHA-256 {digest}")

if __name__ == '__main__':
    main()
