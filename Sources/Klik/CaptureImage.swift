import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Ink: CaseIterable {
    case red, orange, yellow, green, blue, purple, white, black

    var label: UIKey {
        switch self {
        case .red: return .inkRed
        case .orange: return .inkOrange
        case .yellow: return .inkYellow
        case .green: return .inkGreen
        case .blue: return .inkBlue
        case .purple: return .inkPurple
        case .white: return .inkWhite
        case .black: return .inkBlack
        }
    }

    var color: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .red: rgb = (0.98, 0.25, 0.25)
        case .orange: rgb = (1, 0.51, 0.17)
        case .yellow: rgb = (1, 0.82, 0.20)
        case .green: rgb = (0.25, 0.76, 0.38)
        case .blue: rgb = (0.18, 0.57, 1)
        case .purple: rgb = (0.65, 0.40, 0.98)
        case .white: rgb = (1, 1, 1)
        case .black: rgb = (0.08, 0.09, 0.09)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    var outline: NSColor { self == .white || self == .yellow ? .black : .white }
}

enum Mark {
    case rectangle(CGRect, Ink)
    case arrow(CGPoint, CGPoint, Ink)
    case pen([CGPoint], Ink)
    case text(String, CGPoint, Ink)
    case mosaic([CGPoint])

    static let textFont = NSFont.systemFont(ofSize: 18, weight: .semibold)

    func draw(in context: CGContext, background: CaptureImage) {
        context.saveGState()
        defer { context.restoreGState() }
        let path = CGMutablePath()
        let ink: Ink
        switch self {
        case .rectangle(let rect, let color):
            ink = color
            path.addRect(rect)
        case .arrow(let start, let end, let color):
            ink = color
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length >= 2 else { return }
            let angle = atan2(dy, dx)
            let head = min(15, length * 0.48)
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: CGPoint(x: end.x - head * cos(angle - 0.5), y: end.y - head * sin(angle - 0.5)))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x - head * cos(angle + 0.5), y: end.y - head * sin(angle + 0.5)))
        case .pen(let points, let color):
            ink = color
            guard let start = points.first else { return }
            if points.count == 1 {
                context.setFillColor(ink.color.cgColor)
                context.fillEllipse(in: CGRect(x: start.x - 1.5, y: start.y - 1.5, width: 3, height: 3))
                return
            }
            path.addLines(between: points)
        case .text(let value, let origin, let color):
            let shadow = NSShadow()
            shadow.shadowColor = (color == .black ? NSColor.white : NSColor.black).withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            (value as NSString).draw(at: origin, withAttributes: [
                .font: Self.textFont, .foregroundColor: color.color, .shadow: shadow
            ])
            return
        case .mosaic(let points):
            guard let start = points.first else { return }
            let diameter: CGFloat = 30
            if points.count == 1 {
                let dot = CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                 width: diameter, height: diameter)
                context.addEllipse(in: dot)
            } else {
                path.addLines(between: points)
                context.addPath(path.copy(strokingWithWidth: diameter, lineCap: .round,
                                          lineJoin: .round, miterLimit: 1))
            }
            context.clip()
            context.interpolationQuality = .none
            background.drawMosaic(in: context)
            return
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.setLineWidth(4.5)
        context.setStrokeColor(ink.outline.withAlphaComponent(0.9).cgColor)
        context.strokePath()
        context.addPath(path)
        context.setLineWidth(2.5)
        context.setStrokeColor(ink.color.cgColor)
        context.strokePath()
    }
}

final class CaptureImage {
    let image: CGImage
    let size: CGSize
    private let pixelated: CGImage?

    init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
        // One sample per roughly 14 points. Upscaling with nearest neighbour gives visible blocks.
        let reduced = Self.bitmap(width: max(1, Int(size.width / 14)), height: max(1, Int(size.height / 14)))
        reduced?.interpolationQuality = .high
        if let reduced {
            reduced.draw(image, in: CGRect(x: 0, y: 0, width: reduced.width, height: reduced.height))
        }
        pixelated = reduced?.makeImage()
    }

    func draw(in context: CGContext) {
        drawTopDown(image, in: context)
    }

    func drawMosaic(in context: CGContext) {
        if let pixelated {
            drawTopDown(pixelated, in: context)
        } else {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func drawTopDown(_ image: CGImage, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    func render(selection: CGRect, marks: [Mark]) -> CGImage? {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let pixelBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixels = selection.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .integral.intersection(pixelBounds)
        guard !pixels.isEmpty, let crop = image.cropping(to: pixels),
              let context = Self.bitmap(width: crop.width, height: crop.height) else { return nil }

        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        context.translateBy(x: 0, y: CGFloat(crop.height))
        context.scaleBy(x: scaleX, y: -scaleY)
        context.translateBy(x: -pixels.minX / scaleX, y: -pixels.minY / scaleY)
        context.clip(to: selection)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for mark in marks {
            mark.draw(in: context, background: self)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(encoder, image, nil)
        return CGImageDestinationFinalize(encoder) ? data as Data : nil
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
