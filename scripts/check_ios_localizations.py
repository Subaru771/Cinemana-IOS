"""Fail CI if a fixed SwiftUI label lacks an Arabic translation."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
mobile = root / "CinemanaMobile"
ar = (mobile / "ar.lproj/Localizable.strings").read_text(encoding="utf-8")
translations = dict(re.findall(r'^"([^"]+)"\s*=\s*"([^"]*)";', ar, flags=re.M))
assert len(translations) >= 260, "Arabic catalog unexpectedly incomplete"
components = (r"Text|Button|Label|Toggle|Section|Picker|Link|ProgressView|"
              r"LabeledContent|TextField|Menu|navigationTitle|accessibilityLabel|"
              r"confirmationDialog|alert|EmptyStateView")
pattern = re.compile(r"\b(?:" + components + r")\s*\(\s*\"((?:\\.|[^\"\\])*)\"")
missing = []
for path in mobile.glob("*.swift"):
    content = path.read_text(encoding="utf-8")
    for match in pattern.finditer(content):
        key = match.group(1)
        if r"\(" in key or not re.search("[A-Za-z]", key) or key == "C":
            continue
        if key not in translations or not re.search(r"[\u0600-\u06ff]", translations[key]):
            missing.append(f"{path.name}: {key}")
assert not missing, "Untranslated visible iOS strings:\n" + "\n".join(sorted(set(missing)))
app = (mobile / "CinemanaMobileApp.swift").read_text(encoding="utf-8")
assert ".environment(\\.locale, selectedLocale)" in app
assert "CinemanaReleaseMonitor" in app and "showTelegramPrompt" in app
assert "CinemanaLocale.genre" in app and "CinemanaLocale.episode" in app
print(f"PASS: {len(translations)} Arabic keys, no missing fixed UI labels")
