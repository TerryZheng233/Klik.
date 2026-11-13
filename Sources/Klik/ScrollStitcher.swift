import CoreGraphics

enum ScrollVerticalEdge: CaseIterable {
    case top, bottom
}

enum ScrollAxis: CaseIterable {
    case vertical, horizontal

    func length(of image: CGImage) -> Int { self == .vertical ? image.height : image.width }
    func crossLength(of image: CGImage) -> Int { self == .vertical ? image.width : image.height }

    func crop(_ image: CGImage, from start: Int, to end: Int) -> CGImage? {
        let rect = self == .vertical
            ? CGRect(x: 0, y: start, width: image.width, height: end - start)
            : CGRect(x: start, y: 0, width: end - start, height: image.height)
        return image.cropping(to: rect)
    }
}

struct ScrollStitcher {
    enum Update: Equatable {
        case waiting, extended, unaligned, limit
    }

    private struct Frame {
        let origin: Int
        let samples: ScrollAlignment.Frame
    }

    private struct Strip {
        let origin: Int
        let end: Int
        let image: CGImage
    }

    private struct PendingEdge {
        let image: CGImage
        let frame: Frame
        let seam: Int
    }

    private static let maximumPixels = 40_000_000
    static let maximumLength = 30_000

    private var firstImage: CGImage?
    private var startingSamples: [ScrollAxis: ScrollAlignment.Frame] = [:]
    private var tracking: Frame?
    private var leading: Frame?
    private var trailing: Frame?
    private var strips: [Strip] = []
    private var viewportLength = 0
    private var pending: PendingEdge?
    private(set) var axis: ScrollAxis?
    var scrollOrigin: Int? { pending?.frame.origin ?? tracking?.origin }
    func isAtEdge(_ edge: ScrollVerticalEdge) -> Bool {
        guard axis == .vertical, let tracking, let boundary = edge == .top ? leading : trailing else { return false }
        return tracking.origin == boundary.origin
    }
    var length: Int {
        guard let first = strips.first, let last = strips.last else { return firstImage?.height ?? 0 }
        return last.end - first.origin
    }

    mutating func append(_ image: CGImage, final: Bool = false) -> Update {
        if let axis, let tracking {
            if final, pending != nil { return commitPending(before: image, axis: axis, final: true) }
            guard let first = strips.first, let last = strips.last,
                  axis.length(of: image) == viewportLength,
                  axis.crossLength(of: image) == axis.crossLength(of: first.image),
                  let samples = ScrollAlignment.Frame(image, axis: axis) else { return .unaligned }

            let registration: ScrollAlignment.Registration
            let origin: Int
            switch ScrollAlignment.match(tracking.samples, samples) {
            case .stationary: return pending == nil ? .waiting : commitPending(axis: axis)
            case .unaligned: return pending == nil ? .unaligned : commitPending(axis: axis)
            case .aligned(let match):
                registration = match
                origin = tracking.origin + match.offset
            }
            if let pending,
               (pending.frame.origin < first.origin && origin > pending.frame.origin
                || pending.frame.origin + viewportLength > last.end && origin < pending.frame.origin) {
                // Keep the furthest position even when the next scroll reverses.
                return commitPending(before: image, axis: axis, final: final)
            }

            let frameEnd = origin + viewportLength
            if origin >= first.origin, frameEnd <= last.end {
                self.tracking = Frame(origin: origin, samples: samples)
                return .waiting
            }

            let towardLeadingEdge = origin < first.origin
            let edge = towardLeadingEdge ? leading : trailing
            // After retracing captured content, match against the existing
            // frontier to keep small frame-to-frame errors from accumulating.
            var candidate = Frame(origin: origin, samples: samples)
            var seam = origin + registration.seam
            if let edge, edge.origin != tracking.origin {
                switch ScrollAlignment.match(edge.samples, samples) {
                case .stationary:
                    if abs(origin - edge.origin) <= 4 {
                        self.tracking = edge
                        return .waiting
                    }
                case .aligned(let refined):
                    let refinedOrigin = edge.origin + refined.offset
                    if abs(refinedOrigin - origin) <= 8 {
                        candidate = Frame(origin: refinedOrigin, samples: samples)
                        seam = refinedOrigin + refined.seam
                    }
                case .unaligned: break
                }
            }
            return extend(with: image, frame: candidate, seam: seam, axis: axis, final: final)
        }
        return chooseAxis(with: image, final: final)
    }

    private mutating func chooseAxis(with image: CGImage, final: Bool) -> Update {
        guard let initial = firstImage else {
            for axis in ScrollAxis.allCases { startingSamples[axis] = ScrollAlignment.Frame(image, axis: axis) }
            guard startingSamples.count == ScrollAxis.allCases.count else { return .unaligned }
            firstImage = image
            return .waiting
        }
        guard image.width == initial.width, image.height == initial.height else { return .unaligned }
        var candidates: [(ScrollAxis, ScrollAlignment.Frame, ScrollAlignment.Registration)] = []
        var stationary = false
        for axis in ScrollAxis.allCases {
            guard let start = startingSamples[axis], let current = ScrollAlignment.Frame(image, axis: axis) else { continue }
            switch ScrollAlignment.match(start, current) {
            case .stationary: stationary = true
            case .unaligned: break
            case .aligned(let match):
                if final || abs(match.offset) >= 2 { candidates.append((axis, current, match)) }
                else { stationary = true }
            }
        }
        candidates.sort { $0.2.score > $1.2.score }
        guard let (axis, samples, match) = candidates.first else { return stationary ? .waiting : .unaligned }
        if candidates.count > 1, match.score < candidates[1].2.score + max(3, candidates[1].2.score / 5) {
            return .unaligned
        }
        guard let start = startingSamples[axis] else { return .unaligned }
        viewportLength = axis.length(of: initial)
        self.axis = axis
        let initialFrame = Frame(origin: 0, samples: start)
        tracking = initialFrame
        leading = initialFrame
        trailing = initialFrame
        strips = [Strip(origin: 0, end: viewportLength, image: initial)]
        firstImage = nil
        startingSamples.removeAll()
        return extend(with: image, frame: Frame(origin: match.offset, samples: samples),
                      seam: match.offset + match.seam, axis: axis, final: true)
    }

    private mutating func commitPending(before image: CGImage? = nil, axis: ScrollAxis,
                                        final: Bool = false) -> Update {
        guard let pending else { return .waiting }
        self.pending = nil
        let saved = extend(with: pending.image, frame: pending.frame, seam: pending.seam, axis: axis, final: true)
        guard saved == .extended, let image else { return saved }
        let update = append(image, final: final)
        return update == .waiting ? .extended : update
    }

    private mutating func extend(with image: CGImage, frame: Frame, seam: Int,
                                 axis: ScrollAxis, final: Bool) -> Update {
        guard let first = strips.first, let last = strips.last else { return .unaligned }
        let end = frame.origin + viewportLength
        let leadingAdvance = first.origin - frame.origin
        let trailingAdvance = end - last.end
        let advance = max(leadingAdvance, trailingAdvance)
        if advance <= 0 {
            tracking = frame
            return .waiting
        }
        guard seam >= first.origin, seam <= last.end, seam > frame.origin, seam < end else { return .unaligned }
        // Batch very small steps while keeping their full extent for a reversal or Done.
        if !final, advance < max(8, min(48, viewportLength / 24)) {
            pending = PendingEdge(image: image, frame: frame, seam: seam)
            return .waiting
        }

        let newLength = length + advance
        guard newLength <= Self.maximumLength, newLength <= Self.maximumPixels / axis.crossLength(of: image) else {
            return .limit
        }

        if leadingAdvance > 0 {
            guard let index = strips.firstIndex(where: { seam < $0.end }),
                  let segment = Self.copy(axis.crop(image, from: 0, to: seam - frame.origin)) else { return .limit }
            let prefix = Strip(origin: frame.origin, end: seam, image: segment)
            let boundary = strips[index]
            if seam == boundary.origin {
                strips.replaceSubrange(0..<index, with: [prefix])
            } else {
                guard let remainder = Self.copy(axis.crop(boundary.image, from: seam - boundary.origin,
                                                          to: boundary.end - boundary.origin)) else { return .limit }
                strips.replaceSubrange(0...index, with: [prefix, Strip(origin: seam, end: boundary.end, image: remainder)])
            }
            leading = frame
        } else {
            guard let index = strips.lastIndex(where: { $0.origin < seam }),
                  let segment = Self.copy(axis.crop(image, from: seam - frame.origin, to: viewportLength)) else { return .limit }
            let suffix = Strip(origin: seam, end: end, image: segment)
            let boundary = strips[index]
            if seam == boundary.end {
                strips.replaceSubrange((index + 1)..<strips.count, with: [suffix])
            } else {
                guard let remainder = Self.copy(axis.crop(boundary.image, from: 0, to: seam - boundary.origin)) else { return .limit }
                strips.replaceSubrange(index..<strips.count, with: [Strip(origin: boundary.origin, end: seam, image: remainder), suffix])
            }
            trailing = frame
        }
        tracking = frame
        pending = nil
        return .extended
    }

    func availableRows(at edge: ScrollVerticalEdge, from image: CGImage) -> Int {
        let extraRows = image.height - viewportLength
        let overlapStart = edge == .top ? extraRows : 0
        guard isAtEdge(edge), let boundary = edge == .top ? leading : trailing,
              image.width == strips.first?.image.width, extraRows > 0,
              let overlap = ScrollAxis.vertical.crop(image, from: overlapStart, to: overlapStart + viewportLength),
              let samples = ScrollAlignment.Frame(overlap, axis: .vertical) else { return 0 }
        if case .stationary = ScrollAlignment.match(boundary.samples, samples) { return extraRows }
        return 0
    }

    mutating func extendEdge(_ edge: ScrollVerticalEdge, from image: CGImage, extraRows: Int) -> Update {
        guard extraRows > 0 else { return .waiting }
        guard let first = strips.first, let last = strips.last,
              extraRows <= availableRows(at: edge, from: image) else { return .unaligned }
        let newLength = length + extraRows
        guard newLength <= Self.maximumLength, newLength <= Self.maximumPixels / image.width else { return .limit }
        let start = edge == .top ? image.height - viewportLength - extraRows : viewportLength
        guard let segment = Self.copy(ScrollAxis.vertical.crop(image, from: start, to: start + extraRows)) else { return .limit }
        switch edge {
        case .top:
            strips.insert(Strip(origin: first.origin - extraRows, end: first.origin, image: segment), at: 0)
        case .bottom:
            strips.append(Strip(origin: last.end, end: last.end + extraRows, image: segment))
        }
        return .extended
    }

    func render() -> CGImage? {
        guard let axis, let first = strips.first else { return firstImage }
        if strips.count == 1 { return first.image }
        let cross = axis.crossLength(of: first.image)
        let width = axis == .vertical ? cross : length
        let height = axis == .vertical ? length : cross
        guard let bitmap = CaptureImage.bitmap(width: width, height: height) else { return nil }
        for strip in strips {
            let x = axis == .horizontal ? strip.origin - first.origin : 0
            let y = axis == .vertical ? height - (strip.end - first.origin) : 0
            bitmap.draw(strip.image, in: CGRect(x: x, y: y, width: strip.image.width, height: strip.image.height))
        }
        return bitmap.makeImage()
    }

    private static func copy(_ image: CGImage?) -> CGImage? {
        // A crop can retain a whole stream frame. Copy only the pixels we keep.
        guard let image, let context = CaptureImage.bitmap(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
