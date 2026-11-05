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
print('PASS: only direct play and season download controls; no checklist selection')
