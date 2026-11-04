"""Regression check: posters open details; playback starts from Play/Episode only."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = (root / "CinemanaMobile/CinemanaMobileApp.swift").read_text()
api = (root / "CinemanaMobile/CinemanaAPI.swift").read_text()
brand = (root / "CinemanaMobile/CinemanaBrand.swift").read_text()
player = (root / "CinemanaMobile/CinemaPlayerFullscreen.swift").read_text()
assert 'if rows.isEmpty { await refresh() }' in app
assert 'milliseconds(560)' in app
assert '2_500_000_000' in api
assert 'sharpArtworkAvailable' in brand
assert 'CinemanaVectorFallbackGlyph' in brand
assert '.navigationDestination(for: Video.self) { MovieDetailView(video: $0) }' in app
start = app.index('        .task(id: video.id) {')
end = app.index('    @MainActor\n    private func reloadEpisodes()', start)
assert 'watch =' not in app[start:end], 'Poster tap must not start playback'
assert 'await withTaskGroup(of: DetailLoadResult.self)' in app[start:end]
assert 'group.addTask { .episodes(await CinemanaAPI.shared.episodes(video.id)) }' in app[start:end]
assert 'value.id == video.id' in app[start:end]
assert 'return PlaybackPlanner.playTarget(for: video, episodes: episodes, recent: library.snapshot.recent)' in app
assert 'next.play()' in app
assert 'if let target = playTarget { watch = target }' in app
assert 'Button { watch = ep }' in app
assert '.fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0, playlist: episodes) }' in app
assert '.task(id: current.id) { await startPlayback() }' in player
assert 'await session.load(video: current, library: library)' in player
assert 'case .readyToPlay:' in app
print('PASS: details-first, concurrent metadata, autoplay, and 2.0 regression checks')
