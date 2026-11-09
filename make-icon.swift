import AppKit
import CoreText

enum IconError: Error { case cannotEncode }

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let wordmark = NSMutableAttributedString(string: "k.", attributes: [
    .font: NSFont.systemFont(ofSize: 586, weight: .bold),
    .foregroundColor: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.94, alpha: 1),
    .kern: -10
])
wordmark.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.75, green: 0.96, blue: 0.36, alpha: 1),
                      range: NSRange(location: 1, length: 1))
let glyphs = CTLineCreateWithAttributedString(wordmark)
let inkBounds = CTLineGetBoundsWithOptions(glyphs, .useGlyphPathBounds)

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw IconError.cannotEncode }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    context.clear(canvas)
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = CGRect(x: 98, y: 98, width: 828, height: 828)
    let edge = NSBezierPath(roundedRect: tile, xRadius: 198, yRadius: 198)
    let top = NSColor(srgbRed: 0.17, green: 0.18, blue: 0.18, alpha: 1)
    let bottom = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.09, alpha: 1)
    NSGradient(starting: bottom, ending: top)?.draw(in: edge, angle: 90)
    NSColor(white: 1, alpha: 0.15).setStroke()
    edge.lineWidth = 4
    edge.stroke()

    context.textMatrix = .identity
    context.textPosition = CGPoint(x: tile.midX - inkBounds.midX, y: tile.midY - inkBounds.midY)
    CTLineDraw(glyphs, context)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw IconError.cannotEncode }
    return png
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(size)x\(size)\(suffix).png"
        try renderIcon(pixels: size * scale).write(to: iconset.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 2 {
    try renderIcon(pixels: 256).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
}
