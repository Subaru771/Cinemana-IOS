import AppKit
import Foundation

// Prefer the user's original full-resolution Cinemana art. Never mistake
// enlarging a small JPEG for restoring missing image detail.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterPNG = root.appendingPathComponent("Branding/CinemanaIOSIcon-Original.png")
let masterJPG = root.appendingPathComponent("Branding/CinemanaIOSIcon.jpg")
let legacy = root.appendingPathComponent("Branding/CinemanaIOSIcon.b64")
let fm = FileManager.default

let sourceData: Data
let assetFilename: String
if fm.fileExists(atPath: masterPNG.path) {
    sourceData = try Data(contentsOf: masterPNG)
    assetFilename = "CinemanaArtwork.png"
} else if fm.fileExists(atPath: masterJPG.path) {
    sourceData = try Data(contentsOf: masterJPG)
    assetFilename = "CinemanaArtwork.jpg"
} else {
    // Legacy developer fallback only. Public builds should include masterPNG.
    let content = try String(contentsOf: legacy, encoding: .utf8)
    guard let data = Data(base64Encoded: content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fatalError("The old branding fallback could not be decoded")
    }
    sourceData = data
    assetFilename = "CinemanaArtwork.jpg"
}
guard let original = NSImage(data: sourceData),
      let originalPixels = NSBitmapImageRep(data: sourceData) else {
    fatalError("Cinemana icon artwork is unreadable")
}
let fullSize = originalPixels.pixelsWide >= 1024 && originalPixels.pixelsHigh >= 1024
if !fullSize {
    print("::warning::High-resolution Cinemana icon is missing from GitHub. This unsigned development build still uses a compressed placeholder. Upload Branding/CinemanaIOSIcon-Original.png (1024px+) to fix the app icon.")
}
let assetRoot = root.appendingPathComponent("CinemanaMobile/Assets.xcassets")
let artworkDir = assetRoot.appendingPathComponent("CinemanaArtwork.imageset")
try fm.createDirectory(at: artworkDir, withIntermediateDirectories: true)
try sourceData.write(to: artworkDir.appendingPathComponent(assetFilename), options: .atomic)
let manifest = """
{
  "images": [{ "filename": "\(assetFilename)", "idiom": "universal" }],
  "info": { "author": "xcode", "version": 1 }
}
"""
try manifest.write(to: artworkDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let pixels = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Failed to create App Store icon canvas")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
original.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
              from: .zero, operation: .sourceOver, fraction: 1)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode Cinemana iOS icon")
}
let iconDir = assetRoot.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
try png.write(to: iconDir.appendingPathComponent("AppIcon.png"), options: .atomic)
print("Generated Cinemana iOS icon at 1024x1024 from \(originalPixels.pixelsWide)x\(originalPixels.pixelsHigh) input.")
