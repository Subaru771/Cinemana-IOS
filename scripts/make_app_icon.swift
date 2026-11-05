import AppKit
import Foundation

// The approved app icon already lives in the asset catalog. Never overwrite
// it with the transparent Cinemana glyph or a compressed legacy placeholder.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let icon = root.appendingPathComponent("CinemanaMobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let iconData = try Data(contentsOf: icon)
guard let pixels = NSBitmapImageRep(data: iconData), pixels.pixelsWide == 1024,
      pixels.pixelsHigh == 1024, !pixels.hasAlpha else {
    fatalError("Approved Home Screen icon missing or incorrectly formatted")
}
let artworkSource = root.appendingPathComponent("Branding/CinemanaIOSIcon-Original.png")
let artworkTarget = root.appendingPathComponent("CinemanaMobile/Assets.xcassets/CinemanaArtwork.imageset/CinemanaArtwork.png")
let artwork = try Data(contentsOf: artworkSource)
guard let sourcePixels = NSBitmapImageRep(data: artwork), sourcePixels.pixelsWide >= 1024,
      sourcePixels.pixelsHigh >= 1024 else {
    fatalError("Original full-resolution transparent glyph missing")
}
try artwork.write(to: artworkTarget, options: .atomic)
print("Approved RGB Home Screen icon retained: 1024×1024; transparent in-app glyph verified")
