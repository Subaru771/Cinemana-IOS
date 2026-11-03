"""Verify that old download choices cannot reappear in the iOS UI."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "CinemanaMobile"
menu = (root / "DownloadQualityMenu.swift").read_text()
settings = (root / "CinemanaMobileApp.swift").read_text()
downloads = (root / "DownloadsView.swift").read_text()
assert "ForEach([480, 720, 1080, 2160]" in menu
for term in ("Best available", "Use preferred quality", "Wi-Fi only", "wifiOnly", "center.enqueue(videos)"):
    assert term not in menu, f"Unexpected menu item: {term}"
assert 'Picker("Preferred download quality"' not in settings
assert 'Toggle("Download on Wi-Fi only"' not in settings
assert 'Toggle(isOn: $wifiOnly)' not in downloads
assert 'Label("Wi-Fi only"' not in downloads
print("PASS: only 480p/720p/1080p/2160p appear in download UI.")
