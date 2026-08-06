import AppKit

let width: CGFloat = 640
let height: CGFloat = 400
let scale = 2

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(width) * scale,
                           pixelsHigh: Int(height) * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.cgContext.interpolationQuality = .high

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [
    NSColor(calibratedRed: 0.965, green: 0.941, blue: 0.855, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.992, blue: 0.965, alpha: 1),
])!.draw(in: canvas, angle: 285)

let warmth = NSGradient(
    colors: [
        NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 0.20),
        NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 0.06),
        NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 0.0),
    ],
    atLocations: [0.0, 0.4, 0.8],
    colorSpace: .deviceRGB
)!
warmth.draw(in: canvas, angle: 305)

let title = NSAttributedString(string: "Limón", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.10, alpha: 1),
])
title.draw(at: NSPoint(x: (width - title.size().width) / 2, y: height - 76))

let subtitle = NSAttributedString(string: "Drag the app onto Applications to install", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.27, alpha: 1),
])
subtitle.draw(at: NSPoint(x: (width - subtitle.size().width) / 2, y: height - 102))

let arrowY = height - 205
NSColor(calibratedRed: 0.72, green: 0.56, blue: 0.10, alpha: 0.9).setStroke()

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 252, y: arrowY))
shaft.line(to: NSPoint(x: 386, y: arrowY))
shaft.lineWidth = 2
shaft.lineCapStyle = .round
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 376, y: arrowY + 7))
head.line(to: NSPoint(x: 387, y: arrowY))
head.line(to: NSPoint(x: 376, y: arrowY - 7))
head.lineWidth = 2
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

let hint = NSAttributedString(string: "Requires macOS 26 or later", attributes: [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.45, blue: 0.38, alpha: 1),
])
hint.draw(at: NSPoint(x: (width - hint.size().width) / 2, y: 30))

NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
