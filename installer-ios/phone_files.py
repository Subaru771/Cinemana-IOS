#!/usr/bin/env python3
"""Select/validate a Cinemana Installer IPA or Actions ZIP without unsafe extraction."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import sys
import tempfile
import zipfile

BUNDLE = "com.subaru771.cinemanainstaller"
MAX_IPA = 200_000_000


def validate_ipa(path: Path) -> None:
    if not 0 < path.stat().st_size <= MAX_IPA:
        raise ValueError("IPA is empty or too large")
    with zipfile.ZipFile(path) as archive:
        entries = [i for i in archive.infolist()
                   if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", i.filename)]
        if len(entries) != 1 or entries[0].file_size > 1_000_000:
            raise ValueError("IPA must contain one app Info.plist")
        info = plistlib.loads(archive.read(entries[0]))
        if info.get("CFBundleIdentifier") != BUNDLE:
            raise ValueError("This is not the Cinemana Installer IPA")


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def verify_checksum(path: Path, text: str) -> None:
    expected = text.split()[0] if text.split() else ""
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected) or digest(path) != expected.lower():
        raise ValueError("IPA SHA-256 mismatch; download the artifact again")


def prepare(source: Path, state: Path) -> Path:
    """Only publish a validated complete file; never extract arbitrary ZIP paths."""
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = state / "Cinemana-Installer-Unsigned.ipa"
    if source.resolve() == destination.resolve():
        validate_ipa(source)
        return destination
    fd, name = tempfile.mkstemp(prefix="ipa-", suffix=".part", dir=state)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as output:
            if source.suffix.lower() == ".ipa":
                if source.stat().st_size > MAX_IPA:
                    raise ValueError("IPA too large")
                with source.open("rb") as input_file:
                    shutil.copyfileobj(input_file, output)
            else:
                with zipfile.ZipFile(source) as archive:
                    matches = [i for i in archive.infolist() if i.filename.lower().endswith(".ipa")]
                    if len(matches) != 1 or matches[0].file_size > MAX_IPA:
                        raise ValueError("Choose an artifact ZIP containing exactly one installer IPA")
                    with archive.open(matches[0]) as input_file:
                        shutil.copyfileobj(input_file, output)
        validate_ipa(temporary)
        if source.suffix.lower() == ".ipa":
            checksum = source.with_name(source.name + ".sha256")
            if checksum.exists():
                verify_checksum(temporary, checksum.read_text())
        else:
            with zipfile.ZipFile(source) as archive:
                checksum_name = matches[0].filename + ".sha256"
                checksums = [i for i in archive.infolist() if i.filename == checksum_name]
                if checksums:
                    if checksums[0].file_size > 4096:
                        raise ValueError("Checksum file too large")
                    verify_checksum(temporary, archive.read(checksums[0]).decode())
        os.replace(temporary, destination)
        return destination
    finally:
        temporary.unlink(missing_ok=True)


def candidates(folder: Path) -> list[Path]:
    files = []
    for root, dirs, names in os.walk(folder, followlinks=False):
        if len(Path(root).relative_to(folder).parts) >= 2:
            dirs[:] = []
        for name in names:
            path = Path(root) / name
            if path.suffix.lower() == ".ipa" or (path.suffix.lower() == ".zip" and "installer" in name.lower()):
                files.append(path)
            if len(files) >= 50:
                return sorted(files)
    return sorted(files)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        raise ValueError("Usage: phone_files.py INPUT_FILE_OR_FOLDER STATE_FOLDER")
    source, state = map(Path, argv)
    choices = candidates(source) if source.is_dir() else [source]
    if not choices:
        raise ValueError("No IPA or installer artifact ZIP found in that folder. Choose Downloads or pass the file path.")
    if len(choices) > 1:
        print("Choose your installer file (the downloaded Actions ZIP works too):")
        for n, path in enumerate(choices, 1):
            print(f"  {n}. {path.name}")
        raw = input("File number: ").strip()
        if not raw.isdigit() or not 1 <= int(raw) <= len(choices):
            raise ValueError("No file selected")
        source = choices[int(raw) - 1]
    else:
        source = choices[0]
    result = prepare(source, state)
    print("Installer ready:", result)
    print("SHA-256:", digest(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print("Setup stopped:", error, file=sys.stderr)
        raise SystemExit(1)
