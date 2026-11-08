from pathlib import Path
p=Path(__file__).resolve().parents[1]
app=(p/'CinemanaMobile/CinemanaMobileApp.swift').read_text()
player=(p/'CinemanaMobile/CinemaPlayerFullscreen.swift').read_text()
plan=(p/'CinemanaMobile/SceneSkipPlanner.swift').read_text()
filtering=(p/'CinemanaMobile/MatureContentFilter.swift').read_text()
assert 'Toggle("Skip timed mature scenes"' in app and 'Toggle("Skip timed mature scenes"' in player
assert 'Use community intro timings' in player
assert 'CommunitySkipTimes.skipDestination' in player
assert 'current + 90' not in plan and 'target.estimated' not in player
assert 'Scene timings unavailable' not in player
assert 'chapterMenu' not in player and 'Menu("Skip markers")' not in player
assert 'SceneSkipPlanner.introDestination' in player and 'Skip Intro' in player
assert 'SceneSkipPlanner.active(' in player and 'seek(to: scene.end)' in player
assert 'static func visibleRows' in filtering and '{ rows }' in filtering
assert 'matureScenes' in plan and 'introEnd' in plan
assert 'PersonalSceneMarkers.save' in player and 'Button("Undo Skip")' in player
print('PASS: no fake 90-second jump, verifiable intro markers and accurately labeled scene-marker limitations')
