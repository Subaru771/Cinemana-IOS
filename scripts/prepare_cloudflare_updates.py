#!/usr/bin/env python3
"""Prepare a same-origin Cloudflare Pages OTA feed from the freshly built IPA.

The public iPhone app never contacts GitHub. The Pages project hosts both
latest.json and the real IPA, so neither app checks nor downloads redirect.
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


def prepare(ipa: Path, output: Path) -> dict:
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
    metadata = {
        "version": version,
        "build": build,
        "minOSVersion": minimum,
        "ipa": name,
        "size": destination.stat().st_size,
        "sha256": digest.hexdigest(),
    }
    (output / "latest.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.ipa, args.output), indent=2))
