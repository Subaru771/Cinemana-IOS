import AppKit
import Foundation

// Generate the Cinemana iOS red filmstrip application icon.
// An exact approved brand image can replace the generated fallback by placing
// Branding/CinemanaIOSIcon.jpg in the repository. No network fetch is required.
let canvas = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to allocate the Cinemana icon canvas")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGraphicsContext.current?.imageInterpolation = .high
let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let source = URL(fileURLWithPath: "Branding/CinemanaIOSIcon.jpg")
if FileManager.default.fileExists(atPath: source.path),
   let imported = NSImage(contentsOf: source) {
    imported.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
} else {
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.0, blue: 0.015, alpha: 1),
        NSColor(calibratedRed: 0.015, green: 0.006, blue: 0.012, alpha: 1),
        NSColor(calibratedRed: 0.23, green: 0.002, blue: 0.032, alpha: 1)
    ])!
    background.draw(in: bounds, angle: -50)

    let upper = NSBezierPath()
    upper.move(to: NSPoint(x: 0, y: 840))
    upper.curve(to: NSPoint(x: 600, y: 1065),
                controlPoint1: NSPoint(x: 230, y: 1095),
                controlPoint2: NSPoint(x: 330, y: 1085))
    upper.line(to: NSPoint(x: 0, y: 1024))
    upper.close()
    NSColor(calibratedRed: 0.73, green: 0.0, blue: 0.025, alpha: 0.78).setFill()
    upper.fill()
    let lower = NSBezierPath()
    lower.move(to: NSPoint(x: 350, y: -45))
    lower.curve(to: NSPoint(x: 1024, y: 210),
                controlPoint1: NSPoint(x: 680, y: 160),
                controlPoint2: NSPoint(x: 840, y: 60))
    lower.line(to: NSPoint(x: 1024, y: 0))
    lower.close()
    NSColor(calibratedRed: 0.80, green: 0.01, blue: 0.04, alpha: 0.60).setFill()
    lower.fill()

    let left: CGFloat = 130
    let top: CGFloat = 115
    let width: CGFloat = 760
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: left + x * width, y: 1024 - top - y * width)
    }
    let ribbon = NSBezierPath()
    ribbon.move(to: point(0.83, 0.16))
    ribbon.curve(to: point(0.34, 0.10),
                 controlPoint1: point(0.66, 0.07), controlPoint2: point(0.46, 0.02))
    ribbon.curve(to: point(0.10, 0.40),
                 controlPoint1: point(0.18, 0.14), controlPoint2: point(0.10, 0.27))
    ribbon.line(to: point(0.10, 0.60))
    ribbon.curve(to: point(0.36, 0.90),
                 controlPoint1: point(0.10, 0.77), controlPoint2: point(0.20, 0.86))
    ribbon.curve(to: point(0.83, 0.82),
                 controlPoint1: point(0.51, 0.97), controlPoint2: point(0.70, 0.90))
    ribbon.line(to: point(0.80, 0.66))
    ribbon.curve(to: point(0.44, 0.72),
                 controlPoint1: point(0.63, 0.78), controlPoint2: point(0.53, 0.79))
    ribbon.curve(to: point(0.33, 0.58),
                 controlPoint1: point(0.37, 0.69), controlPoint2: point(0.32, 0.62))
    ribbon.line(to: point(0.33, 0.43))
    ribbon.curve(to: point(0.43, 0.28),
                 controlPoint1: point(0.33, 0.36), controlPoint2: point(0.37, 0.30))
    ribbon.curve(to: point(0.80, 0.32),
                 controlPoint1: point(0.53, 0.22), controlPoint2: point(0.65, 0.27))
    ribbon.close()
    let ruby = NSGradient(colors: [
        NSColor(calibratedRed: 0.65, green: 0.00, blue: 0.03, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.28, blue: 0.31, alpha: 1),
        NSColor(calibratedRed: 0.97, green: 0.04, blue: 0.09, alpha: 1)
    ])!
    ruby.draw(in: ribbon, angle: 110)
    NSColor.white.withAlphaComponent(0.32).setStroke()
    ribbon.lineWidth = 8
    ribbon.stroke()

    // Film perforations. Their tapered placement follows the two ribbon arcs.
    let slots: [(CGFloat, CGFloat)] = [
        (0.21, 0.30), (0.28, 0.20), (0.39, 0.16), (0.52, 0.15),
        (0.20, 0.70), (0.30, 0.82), (0.43, 0.85), (0.56, 0.85)
    ]
    NSColor(calibratedRed: 0.08, green: 0.003, blue: 0.010, alpha: 1).setFill()
    for (x, y) in slots {
        let center = point(x, y)
        let slot = NSBezierPath(roundedRect:
            NSRect(x: center.x - 15, y: center.y - 21, width: 30, height: 42),
            xRadius: 7, yRadius: 7)
        slot.fill()
    }

    let play = NSBezierPath()
    play.move(to: point(0.47, 0.36))
    play.line(to: point(0.47, 0.64))
    play.line(to: point(0.74, 0.50))
    play.close()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.56, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.02, blue: 0.09, alpha: 1)
    ])!.draw(in: play, angle: -65)

    let badge = NSBezierPath(roundedRect: NSRect(x: 401, y: 50, width: 222, height: 78),
                             xRadius: 39, yRadius: 39)
    NSColor(calibratedRed: 0.45, green: 0.0, blue: 0.02, alpha: 1).setFill()
    badge.fill()
    NSColor(calibratedRed: 0.98, green: 0.10, blue: 0.18, alpha: 1).setStroke()
    badge.lineWidth = 4
    badge.stroke()
    let style: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 55, weight: .semibold),
        .foregroundColor: NSColor.white
    ]
    let title = "iOS" as NSString
    let titleSize = title.size(withAttributes: style)
    title.draw(at: NSPoint(x: 512 - titleSize.width / 2,
                           y: 91 - titleSize.height / 2), withAttributes: style)
}
NSGraphicsContext.restoreGraphicsState()

let dir = URL(fileURLWithPath: "CinemanaMobile/Assets.xcassets/AppIcon.appiconset",
              isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode Cinemana iOS icon")
}
try png.write(to: dir.appendingPathComponent("AppIcon.png"), options: .atomic)
print("Cinemana iOS icon generated (red filmstrip): \(png.count) bytes")
