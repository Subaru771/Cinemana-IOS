import AppKit
import Foundation

// Deterministic 1024px Cinemana app icon. Generated at build time on the macOS runner.
let canvas = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                              xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.060, alpha: 1).setFill()
background.fill()

let shield = NSBezierPath(roundedRect: NSRect(x: 160, y: 190, width: 704, height: 644),
                          xRadius: 170, yRadius: 170)
NSColor(calibratedRed: 0.55, green: 0.96, blue: 0.69, alpha: 1).setFill()
shield.fill()
let play = NSBezierPath()
play.move(to: NSPoint(x: 405, y: 363))
play.line(to: NSPoint(x: 405, y: 660))
play.line(to: NSPoint(x: 651, y: 512))
play.close()
NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.060, alpha: 1).setFill()
play.fill()
NSGraphicsContext.restoreGraphicsState()

let dir = URL(fileURLWithPath: "CinemanaMobile/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}
try png.write(to: dir.appendingPathComponent("AppIcon.png"), options: .atomic)
print("Created branded AppIcon.png: \(png.count) bytes")
