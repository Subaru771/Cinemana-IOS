from pathlib import Path
p=Path(__file__).resolve().parents[1]
app=(p/'CinemanaMobile/CinemanaMobileApp.swift').read_text()
player=(p/'CinemanaMobile/CinemaPlayerFullscreen.swift').read_text()
plan=(p/'CinemanaMobile/SceneSkipPlanner.swift').read_text()
filtering=(p/'CinemanaMobile/MatureContentFilter.swift').read_text()
assert 'Toggle("Skip marked mature scenes"' in app and 'Toggle("Skip marked mature scenes"' in player
assert 'chapterMenu' not in player and 'Menu("Skip markers")' not in player
assert 'SceneSkipPlanner.introDestination' in player and 'Button("Skip Intro")' in player
assert 'SceneSkipPlanner.active(' in player and 'seek(to: scene.end)' in player
assert 'static func visibleRows' in filtering and '{ rows }' in filtering
assert 'matureScenes' in plan and 'introEnd' in plan
print('PASS: series titles visible, mature skipping based on time-coded scenes, single-tap intro skip')
