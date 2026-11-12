import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

enum MarkupTextStyle {
    static func font(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    static func attributes(ink: Ink, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = (ink == .black ? NSColor.white : NSColor.black).withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return [.font: font(size: size), .foregroundColor: ink.color, .shadow: shadow]
    }
}

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
    case ellipse(CGRect, Ink, width: CGFloat = 2.5)
    case rectangle(CGRect, Ink, width: CGFloat = 2.5)
    case arrow(CGPoint, CGPoint, Ink, width: CGFloat = 2.5)
    case curvedArrow(CGPoint, CGPoint, CGPoint, Ink, width: CGFloat = 2.5)
    case pen([CGPoint], Ink, width: CGFloat = 2.5)
    case text(String, CGPoint, Ink, size: CGFloat = 18)
    case mosaic([CGPoint], diameter: CGFloat = 30, style: MosaicStyle = .pixel, color: CoverColor = .fallback)

    static let textFont = NSFont.systemFont(ofSize: 18, weight: .semibold)

    // The middle handle is a point on the visible curve, not its Bézier control point.
    var arrowGeometry: (start: CGPoint, middle: CGPoint, end: CGPoint, ink: Ink, curved: Bool, width: CGFloat)? {
        switch self {
        case .arrow(let start, let end, let ink, let width):
            return (start, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), end, ink, false, width)
        case .curvedArrow(let start, let middle, let end, let ink, let width):
            return (start, middle, end, ink, true, width)
        default: return nil
        }
    }

    static func arrowControl(start: CGPoint, middle: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(x: 2 * middle.x - (start.x + end.x) / 2, y: 2 * middle.y - (start.y + end.y) / 2)
    }

    var resizableBounds: CGRect? {
        switch self {
        case .ellipse(let rect, _, _), .rectangle(let rect, _, _): return rect.standardized
        default: return nil
        }
    }

    func resized(to rect: CGRect) -> Mark {
        switch self {
        case .ellipse(_, let ink, let width): return .ellipse(rect, ink, width: width)
        case .rectangle(_, let ink, let width): return .rectangle(rect, ink, width: width)
        default: return self
        }
    }

    var movableBounds: CGRect? {
        switch self {
        case .ellipse(let rect, _, _), .rectangle(let rect, _, _): return rect.standardized
        case .arrow(let start, let end, _, _): return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        case .curvedArrow(let start, let middle, let end, _, _):
            // A quadratic Bézier lies inside the convex hull of these points.
            let control = Self.arrowControl(start: start, middle: middle, end: end)
            let xs = [start.x, control.x, end.x], ys = [start.y, control.y, end.y]
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        case .pen(let points, _, _):
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0.01, height: 0.01)) { rect, point in
                rect.union(CGRect(x: point.x, y: point.y, width: 0.01, height: 0.01))
            }
        case .text(let value, let origin, _, let fontSize):
            let size = (value as NSString).size(withAttributes: [.font: MarkupTextStyle.font(size: fontSize)])
            return CGRect(origin: origin, size: size)
        case .mosaic: return selectionBounds
        }
    }

    var editableInk: Ink? {
        switch self {
        case .ellipse(_, let ink, _), .rectangle(_, let ink, _), .arrow(_, _, let ink, _),
             .curvedArrow(_, _, _, let ink, _), .pen(_, let ink, _), .text(_, _, let ink, _): return ink
        case .mosaic(_, _, .manual, let color): return .custom(color)
        case .mosaic: return nil
        }
    }

    func withInk(_ ink: Ink) -> Mark? {
        switch self {
        case .ellipse(let rect, _, let width): return .ellipse(rect, ink, width: width)
        case .rectangle(let rect, _, let width): return .rectangle(rect, ink, width: width)
        case .arrow(let a, let b, _, let width): return .arrow(a, b, ink, width: width)
        case .curvedArrow(let a, let m, let b, _, let width): return .curvedArrow(a, m, b, ink, width: width)
        case .pen(let points, _, let width): return .pen(points, ink, width: width)
        case .text(let text, let origin, _, let size): return .text(text, origin, ink, size: size)
        case .mosaic(let points, let diameter, .manual, _):
            let color = ink.color
            return .mosaic(points, diameter: diameter, style: .manual,
                           color: CoverColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent))
        case .mosaic: return nil
        }
    }

    var lineWidth: CGFloat? {
        switch self {
        case .ellipse(_, _, let width), .rectangle(_, _, let width), .arrow(_, _, _, let width),
             .curvedArrow(_, _, _, _, let width), .pen(_, _, let width): return width
        default: return nil
        }
    }

    func withLineWidth(_ width: CGFloat) -> Mark {
        switch self {
        case .ellipse(let rect, let ink, _): return .ellipse(rect, ink, width: width)
        case .rectangle(let rect, let ink, _): return .rectangle(rect, ink, width: width)
        case .arrow(let start, let end, let ink, _): return .arrow(start, end, ink, width: width)
        case .curvedArrow(let start, let middle, let end, let ink, _):
            return .curvedArrow(start, middle, end, ink, width: width)
        case .pen(let points, let ink, _): return .pen(points, ink, width: width)
        default: return self
        }
    }

    var selectionBounds: CGRect? {
        if case .pen(_, _, let width) = self, let bounds = movableBounds {
            return bounds.insetBy(dx: -width / 2, dy: -width / 2)
        }
        if case .mosaic(let points, let diameter, _, _) = self {
            guard let first = points.first else { return nil }
            let bounds = points.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0.01, height: 0.01)) {
                $0.union(CGRect(x: $1.x, y: $1.y, width: 0.01, height: 0.01))
            }
            return bounds.insetBy(dx: -diameter / 2, dy: -diameter / 2)
        }
        return movableBounds
    }

    private static func arrowHead(start: CGPoint, end: CGPoint, control: CGPoint?, width: CGFloat) -> (CGPoint, CGPoint)? {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length >= 2 else { return nil }
        var dx = end.x - (control?.x ?? start.x), dy = end.y - (control?.y ?? start.y)
        if hypot(dx, dy) < 0.001 { dx = end.x - start.x; dy = end.y - start.y }
        let angle = atan2(dy, dx), head = min(max(15, width * 3), length * 0.48)
        return (CGPoint(x: end.x - head * cos(angle - 0.5), y: end.y - head * sin(angle - 0.5)),
                CGPoint(x: end.x - head * cos(angle + 0.5), y: end.y - head * sin(angle + 0.5)))
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        func segment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, radius: CGFloat) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) <= radius
        }
        switch self {
        case .ellipse(let rect, _, let width):
            let r = rect.standardized
            let tolerance = max(tolerance, width / 2)
            func contains(_ ellipse: CGRect) -> Bool {
                guard ellipse.width > 0, ellipse.height > 0 else { return false }
                return hypot((point.x - ellipse.midX) / (ellipse.width / 2),
                             (point.y - ellipse.midY) / (ellipse.height / 2)) <= 1
            }
            return contains(r.insetBy(dx: -tolerance, dy: -tolerance))
                && !contains(r.insetBy(dx: tolerance, dy: tolerance))
        case .rectangle(let rect, _, let width):
            let r = rect.standardized
            let tolerance = max(tolerance, width / 2)
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                && !r.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .arrow(let start, let end, _, let width):
            let radius = max(tolerance, width / 2)
            if segment(point, start, end, radius: radius) { return true }
            guard let head = Self.arrowHead(start: start, end: end, control: nil, width: width) else { return false }
            return segment(point, head.0, end, radius: radius) || segment(point, head.1, end, radius: radius)
        case .curvedArrow(let start, let middle, let end, _, let width):
            let tolerance = max(tolerance, width / 2)
            let control = Self.arrowControl(start: start, middle: middle, end: end)
            if let head = Self.arrowHead(start: start, end: end, control: control, width: width),
               segment(point, head.0, end, radius: tolerance) || segment(point, head.1, end, radius: tolerance) { return true }
            var prior = start
            for i in 1...48 {
                let t = CGFloat(i) / 48, u = 1 - t
                let next = CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
                                   y: u*u*start.y + 2*u*t*control.y + t*t*end.y)
                if segment(point, prior, next, radius: tolerance) { return true }
                prior = next
            }
            return false
        case .pen(let points, _, let width):
            guard let first = points.first else { return false }
            let radius = max(tolerance, width / 2)
            if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= radius }
            return zip(points, points.dropFirst()).contains { segment(point, $0.0, $0.1, radius: radius) }
        case .text: return movableBounds?.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ?? false
        case .mosaic(let points, let diameter, _, _):
            guard let first = points.first else { return false }
            let radius = diameter / 2 + tolerance
            if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= radius }
            return zip(points, points.dropFirst()).contains { segment(point, $0.0, $0.1, radius: radius) }
        }
    }

    func translated(by delta: CGPoint) -> Mark {
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.x, y: p.y + delta.y) }
        switch self {
        case .ellipse(let rect, let ink, let width): return .ellipse(rect.offsetBy(dx: delta.x, dy: delta.y), ink, width: width)
        case .rectangle(let rect, let ink, let width): return .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y), ink, width: width)
        case .arrow(let start, let end, let ink, let width): return .arrow(moved(start), moved(end), ink, width: width)
        case .curvedArrow(let start, let middle, let end, let ink, let width):
            return .curvedArrow(moved(start), moved(middle), moved(end), ink, width: width)
        case .pen(let points, let ink, let width): return .pen(points.map(moved), ink, width: width)
        case .text(let value, let origin, let ink, let size): return .text(value, moved(origin), ink, size: size)
        case .mosaic(let points, let diameter, let style, let color):
            return .mosaic(points.map(moved), diameter: diameter, style: style, color: color)
        }
    }

    func draw(in context: CGContext, background: CaptureImage, isPreview: Bool = false) {
        context.saveGState()
        defer { context.restoreGState() }
        let path = CGMutablePath()
        let ink: Ink
        var strokeWidth: CGFloat = 2.5
        switch self {
        case .ellipse(let rect, let color, let width):
            ink = color
            strokeWidth = width
            path.addEllipse(in: rect)
        case .rectangle(let rect, let color, let width):
            ink = color
            strokeWidth = width
            path.addRect(rect)
        case .arrow(let start, let end, let color, let width):
            ink = color
            strokeWidth = width
            guard let head = Self.arrowHead(start: start, end: end, control: nil, width: width) else { return }
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: head.0)
            path.addLine(to: end)
            path.addLine(to: head.1)
        case .curvedArrow(let start, let middle, let end, let color, let width):
            ink = color
            strokeWidth = width
            let control = Self.arrowControl(start: start, middle: middle, end: end)
            guard let head = Self.arrowHead(start: start, end: end, control: control, width: width) else { return }
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            path.move(to: head.0)
            path.addLine(to: end)
            path.addLine(to: head.1)
        case .pen(let points, let color, let width):
            ink = color
            strokeWidth = width
            guard let start = points.first else { return }
            if points.count == 1 {
                context.setFillColor(ink.color.cgColor)
                context.fillEllipse(in: CGRect(x: start.x - width / 2, y: start.y - width / 2, width: width, height: width))
                return
            }
            path.addLines(between: points)
        case .text(let value, let origin, let color, let fontSize):
            (value as NSString).draw(at: origin, withAttributes: MarkupTextStyle.attributes(ink: color, size: fontSize))
            return
        case .mosaic(let points, let diameter, let style, let color):
            guard let start = points.first else { return }
            if style == .brush {
                background.drawBrush(points, diameter: diameter, in: context, cache: !isPreview)
                return
            }
            if points.count == 1 {
                context.addEllipse(in: CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                              width: diameter, height: diameter))
            } else {
                path.addLines(between: points)
                context.addPath(path.copy(strokingWithWidth: diameter,
                                          lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
            context.clip()
            switch style {
            case .pixel:
                context.interpolationQuality = .none
                background.drawMosaic(in: context)
            case .brush:
                break  // Already drawn using a raster mask.
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
        context.setLineWidth(strokeWidth + 2)
        context.setStrokeColor(ink.outline.withAlphaComponent(0.9).cgColor)
        context.strokePath()
        context.addPath(path)
        context.setLineWidth(strokeWidth)
        context.setStrokeColor(ink.color.cgColor)
        context.strokePath()
    }
}

private final class BrushStroke: NSObject {
    let points: [CGPoint]
    let diameter: CGFloat

    init(points: [CGPoint], diameter: CGFloat) {
        self.points = points
        self.diameter = diameter
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(diameter)
        for point in points {
            hasher.combine(point.x)
            hasher.combine(point.y)
        }
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BrushStroke else { return false }
        return diameter == other.diameter && points == other.points
    }
}

private final class BrushMask {
    let image: CGImage
    let rect: CGRect

    init(image: CGImage, rect: CGRect) {
        self.image = image
        self.rect = rect
    }
}

final class CaptureImage {
    let image: CGImage
    let size: CGSize
    let origin: CGPoint
    var frame: CGRect { CGRect(origin: origin, size: size) }
    private let brushMasks: NSCache<BrushStroke, BrushMask> = {
        let cache = NSCache<BrushStroke, BrushMask>()
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
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

    fileprivate func drawBrush(_ points: [CGPoint], diameter: CGFloat, in context: CGContext, cache: Bool) {
        guard let start = points.first else { return }
        let stroke = BrushStroke(points: points, diameter: diameter)
        let mask: BrushMask
        if cache, let cached = brushMasks.object(forKey: stroke) {
            mask = cached
        } else if let rasterized = rasterizeBrush(stroke, start: start) {
            mask = rasterized
            if cache {
                brushMasks.setObject(mask, forKey: stroke, cost: mask.image.bytesPerRow * mask.image.height)
            }
        } else {
            // Preserve coverage if the bitmap allocation fails.
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            Self.paintBrushCore(points, start: start, diameter: diameter, width: diameter, in: context)
            return
        }

        let flip = CGAffineTransform(translationX: mask.rect.minX, y: mask.rect.maxY).scaledBy(x: 1, y: -1)
        context.concatenate(flip)
        context.clip(to: CGRect(origin: .zero, size: mask.rect.size), mask: mask.image)
        context.concatenate(flip.inverted())
        if let blurred { drawTopDown(blurred, in: context) }
        else {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(mask.rect)
        }
    }

    private func rasterizeBrush(_ stroke: BrushStroke, start: CGPoint) -> BrushMask? {
        let points = stroke.points
        let diameter = stroke.diameter
        let pathBounds = points.dropFirst().reduce(CGRect(origin: start, size: .zero)) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        let pixels = pixelRect(for: pathBounds.insetBy(dx: -diameter, dy: -diameter))
        guard !pixels.isEmpty,
              let mask = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
                                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        mask.translateBy(x: -pixels.minX, y: pixels.maxY)
        mask.scaleBy(x: scaleX, y: -scaleY)
        mask.translateBy(x: -origin.x, y: -origin.y)
        mask.setFillColor(gray: 1, alpha: 1)
        mask.setStrokeColor(gray: 1, alpha: 1)
        Self.paintBrushCore(points, start: start, diameter: diameter, width: diameter * 0.38, in: mask)

        // Paint the strands and dabs separately. A single vector clip with thousands
        // of overlapping edges is much slower for Quartz to draw.
        if points.count > 1 {
            mask.setLineWidth(max(1, diameter * 0.035))
            for strand in 0..<18 {
                let path = CGMutablePath()
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
                        if drawing { path.addLine(to: p) } else { path.move(to: p) }
                    }
                    drawing = visible
                }
                mask.addPath(path)
                mask.strokePath()
            }
        }
        for (index, point) in points.enumerated() {
            for j in 0..<7 {
                let phase = CGFloat(index * 7 + j) * 2.399963
                let radius = diameter * (0.21 + 0.12 * CGFloat((index + j) % 3) / 2)
                let dab = diameter * (0.09 + 0.05 * CGFloat((index + j * 2) % 4) / 3)
                let center = CGPoint(x: point.x + cos(phase) * radius, y: point.y + sin(phase) * radius)
                mask.fillEllipse(in: CGRect(x: center.x - dab, y: center.y - dab, width: dab * 2, height: dab * 2))
            }
        }
        guard let image = mask.makeImage() else { return nil }
        return BrushMask(image: image, rect: selection(for: pixels))
    }

    private static func paintBrushCore(_ points: [CGPoint], start: CGPoint, diameter: CGFloat,
                                       width: CGFloat, in context: CGContext) {
        if points.count == 1 {
            context.fillEllipse(in: CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                           width: diameter, height: diameter))
        } else {
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(width)
            context.addLines(between: points)
            context.strokePath()
        }
    }

    func color(at point: CGPoint) -> CoverColor? {
        let x = Int((point.x - origin.x) * CGFloat(image.width) / size.width)
        let y = Int((point.y - origin.y) * CGFloat(image.height) / size.height)
        return Self.sample(image, x: x, y: y)
    }

    private var scaleX: CGFloat { CGFloat(image.width) / size.width }
    private var scaleY: CGFloat { CGFloat(image.height) / size.height }
    private var pixelBounds: CGRect { CGRect(x: 0, y: 0, width: image.width, height: image.height) }

    func pixelRect(for selection: CGRect) -> CGRect {
        let rect = selection.offsetBy(dx: -origin.x, dy: -origin.y)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
        // Ignore round-off when a backing-pixel-aligned edge is converted to points and back.
        let minX = floor(rect.minX + 1e-7), maxX = ceil(rect.maxX - 1e-7)
        let minY = floor(rect.minY + 1e-7), maxY = ceil(rect.maxY - 1e-7)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            .intersection(pixelBounds)
    }

    private func pixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: ((point.x - origin.x) * scaleX).rounded(),
                y: ((point.y - origin.y) * scaleY).rounded())
    }

    private func selection(for pixels: CGRect) -> CGRect {
        pixels.applying(CGAffineTransform(scaleX: 1 / scaleX, y: 1 / scaleY)).offsetBy(dx: origin.x, dy: origin.y)
    }

    func squareSelection(from start: CGPoint, to end: CGPoint) -> CGRect {
        selection(for: Selection.square(from: pixelPoint(start), to: pixelPoint(end), in: pixelBounds))
    }

    func squareSelection(resizing rect: CGRect, handle: Selection.Handle, delta: CGPoint) -> CGRect {
        let pixelDelta = CGPoint(x: (delta.x * scaleX).rounded(), y: (delta.y * scaleY).rounded())
        let minimum = ceil(Selection.minimum * max(scaleX, scaleY))
        let pixels = handle.resizeSquare(pixelRect(for: rect), delta: pixelDelta, in: pixelBounds, minimum: minimum)
        return selection(for: pixels)
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
        let pixelRect = pixelRect(for: selection)
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

    func render(selection: CGRect, marks: [Mark], preview: Mark? = nil) -> CGImage? {
        let pixels = pixelRect(for: selection)
        guard !pixels.isEmpty, let crop = image.cropping(to: pixels) else { return nil }
        // Unmarked captures can keep the source pixels and colour profile as-is.
        if marks.isEmpty, preview == nil { return crop }
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
        preview?.draw(in: context, background: self, isPreview: true)
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

    static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
