from pathlib import Path
root=Path(__file__).resolve().parents[1]
detail=(root/'CinemanaMobile/CinemanaMobileApp.swift').read_text()
browser=(root/'CinemanaMobile/SeriesEpisodeBrowser.swift').read_text()
collections=(root/'CinemanaMobile/LibraryCollectionsView.swift').read_text()
assert 'SeriesEpisodeBrowser(' in detail
assert 'EpisodeBatchDownloadView' not in detail + browser + collections
assert 'Select episodes' not in detail + browser + collections
assert 'Choose episodes' not in detail + browser + collections
assert 'onPlay(episode)' in browser and 'DownloadQualityMenu(videos: currentSeason' in browser
assert 'EpisodeDownloadControl(video: episode)' in browser
assert 'DownloadAction(video: episode)' not in browser, 'Full-width download row must never expand episode cards'
assert '.frame(width: 40, height: 40)' in browser, 'Episode download control must be a small fixed-size icon'
api=(root/'CinemanaMobile/CinemanaAPI.swift').read_text()
assert 'identity != seriesID' not in api.split('static func decodeEpisodes',1)[1].split('static func episodePayloadSummary',1)[0], 'Episode 1 can reuse the catalog series ID'
print('PASS: only direct play and season download controls; no checklist selection')
