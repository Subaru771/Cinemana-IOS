"""Regression check: tapping a poster opens details, but Play autostarts video."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = (root / 'CinemanaMobile/CinemanaMobileApp.swift').read_text()
api = (root / 'CinemanaMobile/CinemanaAPI.swift').read_text()
brand = (root / 'CinemanaMobile/CinemanaBrand.swift').read_text()
player = (root / 'CinemanaMobile/CinemaPlayerFullscreen.swift').read_text()
assert 'if kind == nil && !library.snapshot.recent.isEmpty' not in app
assert 'if rows.isEmpty, let cached = await CatalogCache.shared.readEntry(kind: kind)' in app
assert 'await refresh()' in app
assert 'milliseconds(300)' in app
assert 'addingTimeInterval(2.8)' not in app
assert 'if !preferComplete { finish = true }' in api
assert '2_500_000_000' in api
assert 'sharpArtworkAvailable' in brand
assert 'CinemanaVectorFallbackGlyph' in brand
assert 'MovieDetailView(video: selected, seriesContext: kind == 2' in app, 'Series tab must set series context'
start = app.index('        .task(id: video.id) {')
end = app.index('    @MainActor\n    private func reloadEpisodes()', start)
assert 'watch =' not in app[start:end], 'Poster should open details without playback'
assert 'await withTaskGroup(of: DetailLoadResult.self)' in app[start:end], 'Metadata and episodes should load concurrently'
assert 'episodesDetailed(video.id)' in app[start:end], 'Series must attempt episode metadata while loading detail'
assert 'value.id == video.id' in app[start:end], 'Reject unrelated metadata'
assert 'PlaybackPlanner.playTarget(for: video,' in app, 'Stable movie target must not depend on asynchronous detail metadata'
assert 'next.play()\n                        next.seek' in app, 'Resume seek must not block autoplay on failure'
assert 'if let target = playTarget { watch = target }' in app
assert 'SeriesEpisodeBrowser(' in app
assert 'onPlay(episode)' in (root / 'CinemanaMobile/SeriesEpisodeBrowser.swift').read_text()
assert '.fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0, playlist: episodes) }' in app
assert 'await startPlayback()' in player and 'await loadSkipMarkers()' in player
assert 'await session.load(video: current, library: library)' in player
assert 'case .readyToPlay:' in app
assert 'next.play()' in app
print('PASS: stable details-first navigation, parallel metadata, and reliable AVPlayer autostart')
