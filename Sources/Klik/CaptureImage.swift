import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

enum Ink: CaseIterable, Hashable {
    case red, orange, yellow, green, blue, purple, white, black
    case custom(CoverColor)

    static let allCases: [Ink] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

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
        case .custom: return .inkCustom
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
        case .custom(let color): rgb = (color.red, color.green, color.blue)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    var outline: NSColor {
        let c = color
        return (0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent) > 0.7 ? .black : .white
    }
}

struct CoverColor: Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    var cgColor: CGColor { CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])! }
    static let fallback = CoverColor(red: 0, green: 0, blue: 0)
}

enum Mark: Equatable {
    case rectangle(CGRect, Ink)
    case arrow(CGPoint, CGPoint, Ink)
    case pen([CGPoint], Ink)
    case text(String, CGPoint, Ink)
    case mosaic([CGPoint], diameter: CGFloat = 30, style: MosaicStyle = .pixel, color: CoverColor = .fallback)

    static let textFont = NSFont.systemFont(ofSize: 18, weight: .semibold)

    // Mosaic strokes stay fixed so a misplaced drag cannot reveal covered content.
    var movableBounds: CGRect? {
        switch self {
        case .rectangle(let rect, _): return rect.standardized
        case .arrow(let start, let end, _): return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        case .pen(let points, _):
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0.01, height: 0.01)) { rect, point in
                rect.union(CGRect(x: point.x, y: point.y, width: 0.01, height: 0.01))
            }
        case .text(let value, let origin, _):
            let size = (value as NSString).size(withAttributes: [.font: Self.textFont])
            return CGRect(origin: origin, size: size)
        case .mosaic: return nil
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        func segment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) <= tolerance
        }
        switch self {
        case .rectangle(let rect, _):
            let r = rect.standardized
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                && !r.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .arrow(let start, let end, _): return segment(point, start, end)
        case .pen(let points, _):
            guard let first = points.first else { return false }
            if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= tolerance }
            return zip(points, points.dropFirst()).contains { segment(point, $0.0, $0.1) }
        case .text: return movableBounds?.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ?? false
        case .mosaic: return false
        }
    }

    func translated(by delta: CGPoint) -> Mark {
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.x, y: p.y + delta.y) }
        switch self {
        case .rectangle(let rect, let ink): return .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y), ink)
        case .arrow(let start, let end, let ink): return .arrow(moved(start), moved(end), ink)
        case .pen(let points, let ink): return .pen(points.map(moved), ink)
        case .text(let value, let origin, let ink): return .text(value, moved(origin), ink)
        case .mosaic: return self
        }
    }

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
        case .mosaic(let points, let diameter, let style, let color):
            guard let start = points.first else { return }
            if points.count == 1 {
                context.addEllipse(in: CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                              width: diameter, height: diameter))
            } else {
                path.addLines(between: points)
                context.addPath(path.copy(strokingWithWidth: style == .brush ? diameter * 0.38 : diameter,
                                          lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
            if style == .brush {
                // Offset, broken strands give the edge a soft bristle texture.
                if points.count > 1 {
                    for strand in 0..<18 {
                        let strandPath = CGMutablePath()
                        var drawing = false
                        let offset = (CGFloat(strand) / 17 - 0.5) * diameter * 0.8
                        for (index, point) in points.enumerated() {
                            let neighbor = points[min(index + 1, points.count - 1)]
                            let prior = points[max(index - 1, 0)]
                            let dx = neighbor.x - prior.x, dy = neighbor.y - prior.y
                            let length = max(1, hypot(dx, dy))
                            let wobble = sin(CGFloat(index) * 0.24 + CGFloat(strand) * 1.7) * diameter * 0.025
                            let p = CGPoint(x: point.x - dy / length * (offset + wobble),
                                            y: point.y + dx / length * (offset + wobble))
                            let visible = (index + strand * 3) % 13 < 10
                            if visible {
                                if drawing { strandPath.addLine(to: p) } else { strandPath.move(to: p) }
                                drawing = true
                            } else { drawing = false }
                        }
                        context.addPath(strandPath.copy(strokingWithWidth: max(1, diameter * 0.035),
                                                        lineCap: .round, lineJoin: .round, miterLimit: 1))
                    }
                }
                // Small irregular dabs give the soft smear a feathered, brush-like edge.
                for (index, point) in points.enumerated() {
                    for j in 0..<7 {
                        let phase = CGFloat(index * 7 + j) * 2.399963
                        let r = diameter * (0.21 + 0.12 * CGFloat((index + j) % 3) / 2)
                        let dab = diameter * (0.09 + 0.05 * CGFloat((index + j * 2) % 4) / 3)
                        let center = CGPoint(x: point.x + cos(phase) * r, y: point.y + sin(phase) * r)
                        context.addEllipse(in: CGRect(x: center.x - dab, y: center.y - dab,
                                                      width: dab * 2, height: dab * 2))
                    }
                }
            }
            context.clip()
            switch style {
            case .pixel:
                context.interpolationQuality = .none
                background.drawMosaic(in: context)
            case .brush:
                background.drawBlurred(in: context)
            case .manual:
                context.setFillColor(color.cgColor)
                context.fill(background.frame)
            case .solid:
                // Pending color selection: an opaque, unmistakable diagonal pattern.
                context.setFillColor(NSColor.white.cgColor)
                context.fill(background.frame)
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(6)
                let frame = background.frame
                var x = frame.minX - frame.height
                while x <= frame.maxX + frame.height {
                    context.move(to: CGPoint(x: x, y: frame.minY))
                    context.addLine(to: CGPoint(x: x + frame.height, y: frame.maxY))
                    x += 14
                }
                context.strokePath()
            }
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
    let origin: CGPoint
    var frame: CGRect { CGRect(origin: origin, size: size) }
    private var sampleCache: (selection: CGRect, marks: [Mark], image: CGImage)?
    func clearSampleCache() { sampleCache = nil }
    private lazy var blurred: CGImage? = {
        let source = CIImage(cgImage: image)
        let scale = CGFloat(image.width) / max(1, size.width)
        let filtered = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10 * scale])
        return CIContext(options: nil).createCGImage(filtered, from: source.extent)
    }()
    private lazy var pixelated: CGImage? = {
        // One sample per roughly 14 points. Upscaling with nearest neighbour gives visible blocks.
        guard let reduced = Self.bitmap(width: max(1, Int(size.width / 14)),
                                        height: max(1, Int(size.height / 14))) else { return nil }
        reduced.interpolationQuality = .high
        reduced.draw(image, in: CGRect(x: 0, y: 0, width: reduced.width, height: reduced.height))
        return reduced.makeImage()
    }()

    init(image: CGImage, size: CGSize, origin: CGPoint = .zero) {
        self.image = image
        self.size = size
        self.origin = origin
    }

    func draw(in context: CGContext) {
        drawTopDown(image, in: context)
    }

    func drawMosaic(in context: CGContext) {
        if let pixelated {
            drawTopDown(pixelated, in: context)
        } else {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(frame)
        }
    }

    func drawBlurred(in context: CGContext) {
        if let blurred { drawTopDown(blurred, in: context) }
        else { context.setFillColor(NSColor.black.cgColor); context.fill(frame) }
    }

    func color(at point: CGPoint) -> CoverColor? {
        let x = Int((point.x - origin.x) * CGFloat(image.width) / size.width)
        let y = Int((point.y - origin.y) * CGFloat(image.height) / size.height)
        return Self.sample(image, x: x, y: y)
    }

    // Sample what is actually visible in the selection, including completed annotations.
    func visibleColor(at point: CGPoint, selection: CGRect, marks: [Mark]) -> CoverColor? {
        guard selection.contains(point) else { return color(at: point) }
        let rendered: CGImage
        if let cache = sampleCache, cache.selection == selection, cache.marks == marks {
            rendered = cache.image
        } else {
            guard let image = render(selection: selection, marks: marks) else { return nil }
            sampleCache = (selection, marks, image)
            rendered = image
        }
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let pixelRect = selection.offsetBy(dx: -origin.x, dy: -origin.y)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY)).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let x = Int(floor((point.x - origin.x) * scaleX - pixelRect.minX))
        let y = Int(floor((point.y - origin.y) * scaleY - pixelRect.minY))
        return Self.sample(rendered, x: x, y: y)
    }

    // Convert the source pixel once into the same sRGB space used for marked exports.
    private static func sample(_ image: CGImage, x: Int, y: Int) -> CoverColor? {
        guard x >= 0, x < image.width, y >= 0, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = bitmap(width: 1, height: 1) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self), data[3] > 0 else { return nil }
        let alpha = CGFloat(data[3])
        return CoverColor(red: min(1, CGFloat(data[0]) / alpha),
                          green: min(1, CGFloat(data[1]) / alpha),
                          blue: min(1, CGFloat(data[2]) / alpha))
    }

    private func drawTopDown(_ image: CGImage, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    func render(selection: CGRect, marks: [Mark]) -> CGImage? {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let pixelBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixels = selection.offsetBy(dx: -origin.x, dy: -origin.y)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .integral.intersection(pixelBounds)
        guard !pixels.isEmpty, let crop = image.cropping(to: pixels) else { return nil }
        // Unmarked captures can keep the source pixels and colour profile as-is.
        if marks.isEmpty { return crop }
        guard let context = Self.bitmap(width: crop.width, height: crop.height) else { return nil }

        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        context.translateBy(x: 0, y: CGFloat(crop.height))
        context.scaleBy(x: scaleX, y: -scaleY)
        context.translateBy(x: -origin.x - pixels.minX / scaleX, y: -origin.y - pixels.minY / scaleY)
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
