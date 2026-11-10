"""Ensure quality menus only list resolutions actually returned by the video provider."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / "CinemanaMobile"
menu = (root / "DownloadQualityMenu.swift").read_text()
settings = (root / "CinemanaMobileApp.swift").read_text()
downloads = (root / "DownloadsView.swift").read_text()
assert "ForEach(qualities, id:" in menu
assert "try await CinemanaAPI.shared.streams(video.id, preferComplete: true)" in menu
assert "resolutions.sorted(by: >)" in menu
assert "ForEach([480, 720, 1080, 2160]" not in menu
assert "Use preferred quality" not in menu
assert 'Picker("Preferred download quality"' not in settings
assert 'Toggle("Download on Wi-Fi only"' not in settings
assert 'Toggle(isOn: $wifiOnly)' not in downloads
print("PASS: displayed download qualities originate from actual provider streams")
