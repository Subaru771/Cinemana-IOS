#!/usr/bin/env python3
"""Prepare a same-origin Cloudflare Pages OTA feed from the freshly built IPA.

The public iPhone app never contacts GitHub. The Pages project hosts both
updates.json (preserving TV metadata) and a same-origin IPA.
This script validates packaging, not Apple code signing or device playback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import zipfile
from pathlib import Path

# Cloudflare Pages accepts files up to 25 MiB per asset.
MAX_PAGES_ASSET = 25 * 1024 * 1024
EXPECTED_BUNDLE = "app.cinemana.mobile.ios"
UPDATE_HOST = "https://cinemana-updates-e8l.pages.dev"


def prepare(ipa: Path, output: Path, existing_manifest: Path) -> dict:
    if not ipa.is_file() or not 100_000 < ipa.stat().st_size <= MAX_PAGES_ASSET:
        raise ValueError("Missing IPA or IPA exceeds the Cloudflare Pages per-file limit")
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        info_paths = [name for name in names
                      if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(info_paths) != 1:
            raise ValueError("Expected one iOS application Info.plist")
        info_item = archive.getinfo(info_paths[0])
        if info_item.file_size > 1_000_000:
            raise ValueError("Info.plist exceeds limit")
        info = plistlib.loads(archive.read(info_paths[0]))
        executable = info.get("CFBundleExecutable")
        if (not isinstance(executable, str)
                or not re.fullmatch(r"[A-Za-z0-9._-]+", executable)
                or f"{info_paths[0].rsplit('/', 1)[0]}/{executable}" not in names):
            raise ValueError("Missing or invalid app executable")
        if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE:
            raise ValueError("Not the Cinemana iOS app")
        if archive.testzip() is not None:
            raise ValueError("Corrupted IPA archive")

    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    minimum = info.get("MinimumOSVersion")
    if (not isinstance(version, str) or
            not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", version) or
            not isinstance(build, str) or
            not re.fullmatch(r"[0-9]{1,12}", build) or
            not isinstance(minimum, str) or
            not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum)):
        raise ValueError("Invalid bundle version, build or minimum iOS")
    name = f"Cinemana-iOS-v{version}-b{build}-Unsigned.ipa"
    output.mkdir(parents=True, exist_ok=True)
    destination = output / name
    shutil.copyfile(ipa, destination)

    digest = hashlib.sha256()
    with destination.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    existing = json.loads(existing_manifest.read_text(encoding="utf-8"))
    if (not isinstance(existing, dict) or existing.get("schema") != 1
            or not isinstance(existing.get("tv"), dict)
            or not isinstance(existing.get("ios"), dict)):
        raise ValueError("Expected the existing combined TV/iOS schema-1 manifest")
    ios = existing["ios"].copy()
    ios.update({
        "enabled": False,
        "version": version,
        "build": int(build),
        "minOSVersion": minimum,
        "downloadUrl": f"{UPDATE_HOST}/{name}",
        "size": destination.stat().st_size,
        "sha256": digest.hexdigest(),
    })
    existing["ios"] = ios
    (output / "updates.json").write_text(
        json.dumps(existing, indent=2) + "\n", encoding="utf-8")
    return existing


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("existing_manifest", type=Path, help="Existing combined updates.json")
    args = parser.parse_args()
    print(json.dumps(prepare(args.ipa, args.output, args.existing_manifest), indent=2))
