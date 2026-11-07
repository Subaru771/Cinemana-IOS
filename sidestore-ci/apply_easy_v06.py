#!/usr/bin/env python3
"""Apply tested v0.6 guided setup screen to the full v0.5 SideStore build."""
from pathlib import Path
import base64, hashlib, lzma, sys
root = Path(sys.argv[1])
base = Path(__file__).resolve().parent
encoded = "".join((base / "easy-setup-v06.xz.b64").read_text(encoding="ascii").split())
payload = lzma.decompress(base64.b64decode(encoded, validate=True))
expected = "f57de342a99cb4f83e9ba8ff57976a036e1a09b766d17cac4ec6c579ac30a167"
actual = hashlib.sha256(payload).hexdigest()
if actual != expected:
    raise RuntimeError("Cinemana guided setup integrity mismatch: " + actual)
view = payload.decode("utf-8")
if view.count("// CINEMANA_EASY_SETUP_V06") != 1:
    raise RuntimeError("v0.6 asset is missing its marker")
file = root / "AltStore/Settings/SettingsViewController.swift"
src = file.read_text(encoding="utf-8")
old = "rootView: CinemanaAssistantView()"
new = "rootView: CinemanaEasySetupView()"
if src.count("// CINEMANA_ASSISTANT_VIEW_V05") != 1 or src.count(old) != 1:
    raise RuntimeError("Full v0.5 onboarding not found uniquely; refusing modification")
if "// CINEMANA_EASY_SETUP_V06" in src:
    raise RuntimeError("v0.6 already exists, duplicate injection refused")
src = src.replace(old, new, 1).rstrip() + "\n\n" + view.strip() + "\n"
file.write_text(src, encoding="utf-8")
print("Cinemana v0.6 Guided Setup SwiftUI injected. SHA-256 verified.")
