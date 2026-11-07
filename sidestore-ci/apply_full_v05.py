#!/usr/bin/env python3
"""Inject the complete v0.5 UI assets into a separately cloned SideStore tree.

The original source archive is transmitted losslessly, verified by SHA256, and
extracted only by fixed names. No credentials or pairing files are accessed.
"""
from pathlib import Path
import base64, hashlib, io, tarfile, sys

base = Path(__file__).resolve().parent
source = Path(sys.argv[1])
parts = [base / f"full-assets.b64.part{i}" for i in range(3)]
payload = base64.b64decode("".join(p.read_text(encoding="ascii") for p in parts), validate=True)
actual = hashlib.sha256(payload).hexdigest()
expected = "04c9bae2d6e88ef014121bc531556f0ffa2d4b0d6ade346f54e77a7fb0c3fec6"
if actual != expected:
    raise RuntimeError(f"Full UI source integrity mismatch: {actual}")

with tarfile.open(fileobj=io.BytesIO(payload), mode="r:xz") as archive:
    names = {"CinemanaAssistantView.swift", "CinemanaRecoveryRules.swift"}
    if set(archive.getnames()) != names:
        raise RuntimeError(f"Unexpected file names in source archive: {archive.getnames()}")
    files = {name: archive.extractfile(name).read().decode("utf-8") for name in names}

candidate = (base / "CinemanaAssistantView.swift").read_text(encoding="utf-8").strip()
settings_file = source / "AltStore/Settings/SettingsViewController.swift"
settings = settings_file.read_text(encoding="utf-8")
if not settings.rstrip().endswith(candidate):
    raise RuntimeError("Expected previously-applied candidate at end of Settings; refusing to overwrite")
settings = (settings.rstrip()[:-len(candidate)].rstrip()
    + "\n\n" + files["CinemanaRecoveryRules.swift"].strip()
    + "\n\n" + files["CinemanaAssistantView.swift"].strip() + "\n")
settings_file.write_text(settings, encoding="utf-8")
print("Full Cinemana SideStore v0.5 native setup UI applied and SHA256 verified.")
