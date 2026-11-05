"""Asset/quality-menu checks; Python standard library only for macOS CI."""
from pathlib import Path
from struct import unpack

root = Path(__file__).resolve().parents[1]

def png_dimensions(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", path
    return unpack(">II", header[16:24])

master = root / "Branding/CinemanaIOSIcon-Original.png"
icon = root / "CinemanaMobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
artwork = root / "CinemanaMobile/Assets.xcassets/CinemanaArtwork.imageset/CinemanaArtwork.png"
assert min(png_dimensions(master)) >= 1024, png_dimensions(master)
assert png_dimensions(icon) == (1024, 1024), png_dimensions(icon)
# PNG IHDR byte 25 is the color type: 2=RGB, 6=RGBA.
# App Store icons must not include an alpha channel.
assert icon.read_bytes()[25] == 2, "App icon must be opaque RGB (no alpha channel)"
assert png_dimensions(artwork) == png_dimensions(master)
assert artwork.read_bytes() == master.read_bytes()
# In-app artwork and wordmark are transparent, so no embedded rounded tile
# appears against the dark red navigation header or black splash.
assert master.read_bytes()[25] == 6, "Master emblem needs transparency for borderless UI"
wordmark = root / "CinemanaMobile/Assets.xcassets/CinemanaWordmark.imageset/CinemanaWordmark.png"
w, h = png_dimensions(wordmark)
assert w >= 1000 and h >= 100, (w, h)
assert wordmark.read_bytes()[25] == 6, "Wordmark should have a transparent background"
project = (root / "project.yml").read_text()
brand = (root / "CinemanaMobile/CinemanaBrand.swift").read_text()
header = (root / "CinemanaMobile/CinemaPlayerFullscreen.swift").read_text()
assert 'CFBundleDisplayName: Cinemana iOS' in project
assert 'Image("CinemanaSplash")' in brand
splash = root / "CinemanaMobile/Assets.xcassets/CinemanaSplash.imageset/CinemanaSplash-3x.png"
assert png_dimensions(splash) == (2823, 5016), "Approved splash must be a Retina-size PNG"
assert 'Text("iOS")' in header
assert 'RoundedRectangle(cornerRadius: side' not in brand, "Do not add an inner icon tile"
menu = (root / "CinemanaMobile/DownloadQualityMenu.swift").read_text()
assert "ForEach([480, 720, 1080, 2160]" in menu
for removed in ["Best available", "Use preferred quality", "Wi-Fi only", "wifiOnly", "center.enqueue(videos) "]:
    assert removed not in menu, removed
print("Full-resolution icon and four-option download menu validated.")

# The approved v1.6.13 iOS icon is RGB, opaque and exactly 1024px.
assert "CFBundleShortVersionString: '2.0.4'" in project
assert splash.stat().st_size > 500_000, "Full-resolution approved startup asset missing"
assert icon.stat().st_size > 500_000, "Full-resolution approved Home Screen icon missing"
manifest = root / "Branding/v1.6.13-assets-manifest.json"
assert manifest.is_file(), "Expected approved-asset manifest"

# Verify that the icon generator cannot silently overwrite the approved image.
# Pin the exact approved icon bytes shipped in the current repository; never
# let a generator overwrite it with the older transparent Cinemana C glyph.
from hashlib import sha256
assert sha256(icon.read_bytes()).hexdigest() == "b6ca1864af05c8e7cce125c9d3dd1c9d67bf87592fcd9c532d3a2d8fadd51562"
assert "Never overwrite" in (root / "scripts/make_app_icon.swift").read_text()
print("Approved iOS icon and 3x startup artwork verified")
