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

ROOT = Path(__file__).resolve().parents[1]
REPO = 'Subaru771/Cinemana-IOS'

def fetch(url):
    if not url.startswith(('https://api.github.com/repos/'+REPO+'/', 'https://github.com/'+REPO+'/releases/')):
        raise ValueError('Unexpected release URL')
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Cinemana-release-validator'}), timeout=60) as response:
        return response.read()

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
    assert len(raw) == asset['size'], 'Asset size mismatch'
    digest = hashlib.sha256(raw).hexdigest()
    checksum = next(a for a in release['assets'] if a['name'] == 'SHA256SUMS.txt')
    lines = fetch(checksum['browser_download_url']).decode().splitlines()
    assert any(re.fullmatch(digest + r'\s+\*?(?:dist/)?' + re.escape(asset['name']), line) for line in lines), 'Checksum mismatch'
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        assert archive.testzip() is None, 'Corrupt IPA'
        infos = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        assert len(infos) == 1, 'Expected one main app'
        info = plistlib.loads(archive.read(infos[0]))
        assert info['CFBundleIdentifier'] == 'app.cinemana.mobile.ios', 'Wrong application'
        assert not any(n.endswith('embedded.mobileprovision') for n in archive.namelist()), 'Expected unsigned development build'
    data = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'], minOSVersion=info['MinimumOSVersion'], date=release['published_at'][:10], downloadURL=asset['browser_download_url'], releaseURL=release['html_url'], size=len(raw), sha256=digest, signing='unsigned', deviceTested=False)
    (ROOT/'landing/release.json').write_text(json.dumps(data, indent=2)+'\n')
    source = dict(name='Cinemana iOS beta', identifier='app.cinemana.beta.source', apps=[dict(name='Cinemana iOS', bundleIdentifier=info['CFBundleIdentifier'], developerName='Cinemana iOS contributors', localizedDescription='Unsigned development beta. Requires signing. Installation and playback have not been verified on a real iPhone.', iconURL='https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/landing/install-icon.png', versions=[dict(version=data['version'], date=release['published_at'], downloadURL=data['downloadURL'], size=data['size'], minOSVersion=data['minOSVersion'], localizedDescription='Development beta; requires signing. See installation page for device test status.')])], news=[])
    (ROOT/'landing/source.json').write_text(json.dumps(source, indent=2)+'\n')
    print(f"Validated Cinemana {data['version']} ({data['build']}), {len(raw)} bytes, SHA-256 {digest}")

if __name__ == '__main__':
    main()
