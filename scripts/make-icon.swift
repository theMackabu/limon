import AppKit

let canvas: CGFloat = 1024
let rectSize: CGFloat = 824
let cornerRadius: CGFloat = rectSize * 0.225

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let rect = NSRect(x: (canvas - rectSize) / 2, y: (canvas - rectSize) / 2,
                  width: rectSize, height: rectSize)
NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.78, alpha: 1.0).setFill()
NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

let emoji = NSAttributedString(string: "🍋", attributes: [
    .font: NSFont.systemFont(ofSize: 560),
])
let glyph = emoji.size()
emoji.draw(at: NSPoint(x: (canvas - glyph.width) / 2,
                       y: (canvas - glyph.height) / 2))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let master = NSBitmapImageRep(data: tiff) else {
    fatalError("could not render icon")
}

let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
                                   pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try! rep.representation(using: .png, properties: [:])!.write(to: file)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

try? FileManager.default.removeItem(at: iconset)
print("Wrote AppIcon.icns")
