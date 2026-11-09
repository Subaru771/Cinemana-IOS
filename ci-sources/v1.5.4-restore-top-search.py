from pathlib import Path
import sys

root = Path(sys.argv[1])
home = root / "app/src/main/java/app/cinemanatv/ui/Home.kt"
text = home.read_text()
old = """    Row(
        Modifier.fillMaxWidth().background(C.Bg)
            .padding(horizontal = 28.dp, vertical = 12.dp),
"""
new = """    Row(
        Modifier.fillMaxWidth().background(C.Bg)
            // Top navigation: Up opens Search, without changing D-pad behavior in Settings.
            .onPreviewKeyEvent { event ->
                if (event.key == Key.DirectionUp && selected != 3) {
                    if (event.type == KeyEventType.KeyDown) onUpAtTop()
                    true
                } else false
            }
            .padding(horizontal = 28.dp, vertical = 12.dp),
"""
assert text.count(old) == 1, "Unexpected top-bar layout"
home.write_text(text.replace(old, new, 1))
grad = root / "app/build.gradle.kts"
text = grad.read_text()
assert "versionCode = 48" in text and 'versionName = "1.5.3"' in text, "Unexpected build version"
grad.write_text(text.replace("versionCode = 48", "versionCode = 49")
                    .replace('versionName = "1.5.3"', 'versionName = "1.5.4"'))
assert "right = firstRightFocus" in (root / "app/src/main/java/app/cinemanatv/ui/Settings.kt").read_text()
assert "PlayerSheet.SCENES" not in (root / "app/src/main/java/app/cinemanatv/ui/Player.kt").read_text()
print("Restored top search, retained v1.5.3 Settings, build 49")
