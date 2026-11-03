"""Guard fast startup, direct autoplay, and original-resolution splash behavior."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = (root / "CinemanaMobile/CinemanaMobileApp.swift").read_text()
api = (root / "CinemanaMobile/CinemanaAPI.swift").read_text()
brand = (root / "CinemanaMobile/CinemanaBrand.swift").read_text()
assert "if kind == nil && !library.snapshot.recent.isEmpty" not in app
assert "watch = video" in app and "watch = target" in app
assert "PlaybackPlanner.playTarget(for: video" in app
assert "if rows.isEmpty { await refresh() }" in app
assert "milliseconds(560)" in app
assert "addingTimeInterval(2.8)" not in app
assert "if !preferComplete { finish = true }" in api
assert "2_500_000_000" in api
assert "sharpArtworkAvailable" in brand
assert "CinemanaVectorFallbackGlyph" in brand
print("PASS: fast opening, direct autoplay, no Home carousel, crisp artwork guard.")
