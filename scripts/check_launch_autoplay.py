"""Regression check: tapping a poster opens details, but Play autostarts video."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = (root / 'CinemanaMobile/CinemanaMobileApp.swift').read_text()
api = (root / 'CinemanaMobile/CinemanaAPI.swift').read_text()
brand = (root / 'CinemanaMobile/CinemanaBrand.swift').read_text()
player = (root / 'CinemanaMobile/CinemaPlayerFullscreen.swift').read_text()
assert 'if kind == nil && !library.snapshot.recent.isEmpty' not in app
assert 'if rows.isEmpty { await refresh() }' in app
assert 'milliseconds(560)' in app
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
assert 'Button { watch = ep }' in app
assert '.fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0, playlist: episodes) }' in app
assert '.task(id: current.id) { await startPlayback() }' in player
assert 'await session.load(video: current, library: library, prefetched: prefetched)' in player
assert 'showsPlayerSettings' in player and '.popover(isPresented: $showsPlayerSettings)' in player
assert 'playing && !isScrubbing && !showsPlayerSettings' in player
assert 'PlayerOrientation.restoreAfterPlayer()' in player
support = (root / 'CinemanaMobile/PlayerSupport.swift').read_text()
assert 'supportedMask = mask' in support and 'requestGeometryUpdate' in support
assert 'supportedInterfaceOrientationsFor window: UIWindow?' in app
assert 'case .readyToPlay:' in app
assert 'next.play()' in app
assert 'Queue playback immediately' in app
print('PASS: stable details-first navigation, parallel metadata, and reliable AVPlayer autostart')
