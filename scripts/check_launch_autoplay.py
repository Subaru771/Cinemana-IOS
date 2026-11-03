"""Regression guard: poster -> details -> explicit Play -> player autostarts."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = (root / "CinemanaMobile/CinemanaMobileApp.swift").read_text()
api = (root / "CinemanaMobile/CinemanaAPI.swift").read_text()
brand = (root / "CinemanaMobile/CinemanaBrand.swift").read_text()
player = (root / "CinemanaMobile/CinemaPlayerFullscreen.swift").read_text()

assert "if kind == nil && !library.snapshot.recent.isEmpty" not in app
assert "if rows.isEmpty { await refresh() }" in app
assert "milliseconds(560)" in app
assert "addingTimeInterval(2.8)" not in app
assert "if !preferComplete { finish = true }" in api
assert "2_500_000_000" in api
assert "sharpArtworkAvailable" in brand
assert "CinemanaVectorFallbackGlyph" in brand

# All poster navigation stays in the details page, not a direct player.
assert ".navigationDestination(for: Video.self) { MovieDetailView(video: $0) }" in app
detail = app.split("struct MovieDetailView: View {", 1)[1].split(
    "struct SearchCatalogView: View {", 1)[0]
task_body = detail.split(".task(id: video.id) {", 1)[1].split(
    "\n        }\n", 1)[0]
assert "watch =" not in task_body, "Poster selection must not begin playback"
assert "await reloadEpisodes()" in task_body
assert "await loadSupplementaryDetails()" in task_body
assert "if let target = playTarget { watch = target }" in detail
assert "Button { watch = ep }" in detail
assert ".fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0, playlist: episodes) }" in detail

# The player automatically loads the selected video, and AVPlayer starts when ready.
assert ".task(id: current.id) { await startPlayback() }" in player
assert "await session.load(video: current, library: library)" in player
assert "case .readyToPlay:" in app
assert "next.play()" in app
print("PASS: details-first navigation and autoplay after Play, no Home carousel, fast splash.")
