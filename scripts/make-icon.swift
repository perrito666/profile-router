// Original routing glyph on a teal tile, following ClipChum's native icon-generation approach.
// Run with `bash scripts/build-icon.sh`; no image libraries or external artwork are required.
import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 214, yRadius: 214)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.42, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.62, alpha: 1),
                    NSColor(calibratedRed: 0.035, green: 0.25, blue: 0.37, alpha: 1)])!
    .draw(in: tile, angle: -70)
NSColor.white.withAlphaComponent(0.15).setStroke()
tile.lineWidth = 3
tile.stroke()

let branches = NSBezierPath()
branches.lineWidth = 62
branches.lineCapStyle = .round
branches.lineJoinStyle = .round
branches.move(to: NSPoint(x: 512, y: 286))
branches.line(to: NSPoint(x: 512, y: 438))
branches.curve(to: NSPoint(x: 340, y: 622), controlPoint1: NSPoint(x: 512, y: 546), controlPoint2: NSPoint(x: 340, y: 530))
branches.line(to: NSPoint(x: 340, y: 684))
branches.move(to: NSPoint(x: 512, y: 438))
branches.curve(to: NSPoint(x: 684, y: 622), controlPoint1: NSPoint(x: 512, y: 546), controlPoint2: NSPoint(x: 684, y: 530))
branches.line(to: NSPoint(x: 684, y: 684))
NSColor.white.setStroke()
branches.stroke()

let ink = NSColor(calibratedRed: 0.04, green: 0.30, blue: 0.40, alpha: 1)
func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)).fill()
}
for (x, tint) in [(CGFloat(340), NSColor(calibratedRed: 0.63, green: 0.94, blue: 0.98, alpha: 1)),
                  (CGFloat(684), NSColor(calibratedRed: 1, green: 0.79, blue: 0.56, alpha: 1))] {
    circle(x, 724, 90, .white)
    circle(x, 724, 72, tint)
    circle(x, 744, 22, ink)
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: x-37, y: 682, width: 74, height: 38), xRadius: 19, yRadius: 19).fill()
}
circle(512, 286, 49, .white)
circle(512, 286, 21, ink)

NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
