import AppKit
import Foundation

// Reproducible original Cinemana iOS artwork.
// A full-resolution Branding/CinemanaIOSIcon.jpg takes precedence;
// otherwise use the bundled JPEG representation of the same user-provided art.
// Never draw a generic filmstrip approximation.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let highResolution = root.appendingPathComponent("Branding/CinemanaIOSIcon.jpg")
let embedded = root.appendingPathComponent("Branding/CinemanaIOSIcon.b64")

let sourceData: Data
if FileManager.default.fileExists(atPath: highResolution.path) {
    sourceData = try Data(contentsOf: highResolution)
} else {
    let encoded = try String(contentsOf: embedded, encoding: .utf8)
    guard let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fatalError("Bundled Cinemana logo is not valid base64")
    }
    sourceData = decoded
}
guard let original = NSImage(data: sourceData) else {
    fatalError("Cinemana logo does not contain a readable image")
}

let assetRoot = root.appendingPathComponent("CinemanaMobile/Assets.xcassets")
let imageDirectory = assetRoot.appendingPathComponent("CinemanaArtwork.imageset")
try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
try sourceData.write(to: imageDirectory.appendingPathComponent("CinemanaArtwork.jpg"), options: .atomic)
let manifest = """
{
  "images": [{ "filename": "CinemanaArtwork.jpg", "idiom": "universal" }],
  "info": { "author": "xcode", "version": 1 }
}
"""
try manifest.write(to: imageDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let pixels = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 3,
    hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
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
try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
try png.write(to: iconDir.appendingPathComponent("AppIcon.png"), options: .atomic)
print("Generated Cinemana iOS original-artwork assets; app icon: \(png.count) bytes")
