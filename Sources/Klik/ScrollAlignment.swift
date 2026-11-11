import CoreGraphics

struct ScrollAlignment {
    struct Frame {
        fileprivate let height: Int
        fileprivate let rows: [SIMD16<UInt8>]

        init?(_ image: CGImage, axis: ScrollAxis) {
            let width = ScrollAlignment.bands * 16
            let height = axis.length(of: image)
            let margin = max(1, axis.crossLength(of: image) / 30)
            let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let cropBounds = axis == .vertical ? imageBounds.insetBy(dx: CGFloat(margin), dy: 0)
                                              : imageBounds.insetBy(dx: 0, dy: CGFloat(margin))
            guard let crop = image.cropping(to: cropBounds),
                  let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let pixels = bitmap.data else { return nil }
            bitmap.interpolationQuality = .medium
            if axis == .horizontal {
                // Map the leading edge of the screenshot to the first sampled row.
                bitmap.translateBy(x: 0, y: CGFloat(height))
                bitmap.rotate(by: -.pi / 2)
                bitmap.draw(crop, in: CGRect(x: 0, y: 0, width: height, height: width))
            } else {
                bitmap.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            }

            self.height = height
            var samples: [SIMD16<UInt8>] = []
            samples.reserveCapacity(height * ScrollAlignment.bands)
            for row in 0..<height {
                let above = max(0, row - 1) * bitmap.bytesPerRow
                let center = row * bitmap.bytesPerRow
                let below = min(height - 1, row + 1) * bitmap.bytesPerRow
                for x in stride(from: 0, to: width, by: 16) {
                    let a = pixels.loadUnaligned(fromByteOffset: above + x, as: SIMD16<UInt8>.self)
                    let b = pixels.loadUnaligned(fromByteOffset: center + x, as: SIMD16<UInt8>.self)
                    let c = pixels.loadUnaligned(fromByteOffset: below + x, as: SIMD16<UInt8>.self)
                    let sum = SIMD16<UInt16>(truncatingIfNeeded: a) &+ SIMD16<UInt16>(truncatingIfNeeded: c)
                        &+ (SIMD16<UInt16>(truncatingIfNeeded: b) &* 2)
                    samples.append(SIMD16<UInt8>(truncatingIfNeeded: sum &>> 2))
                }
            }
            rows = samples
        }

        fileprivate subscript(_ row: Int, _ band: Int) -> SIMD16<UInt8> {
            rows[row * ScrollAlignment.bands + band]
        }
    }

    enum Match {
        case stationary
        case unaligned
        case aligned(Registration)
    }

    struct Registration {
        let offset: Int
        let seam: Int
        let score: Int
    }

    private struct Patch {
        let row: Int
        let band: Int
        let section: Int
        let contrast: Int
    }

    private struct Hit {
        let patch: Patch
        let shift: Int
    }

    private static let bands = 6
    private static let sampleOffsets = [-9, -6, -3, 0, 3, 6, 9]
    private static let radius = 9

    static func match(_ previous: Frame, _ current: Frame) -> Match {
        if previous.rows == current.rows { return .stationary }
        let height = current.height
        let maximumShift = height - max(44, height / 5)
        guard previous.height == height, maximumShift > 0 else { return .unaligned }

        let patches = patches(in: current)
        var hits: [Hit] = []
        var stationary = 0
        for patch in patches {
            let samePosition = cost(previous, current, patch, shift: 0)
            if samePosition <= max(30, patch.contrast / 14) {
                stationary += 1
            } else if let shift = bestShift(previous, current, patch, maximumShift: maximumShift) {
                hits.append(Hit(patch: patch, shift: shift))
            }
        }

        // Independent vertical sections must agree. Nearby integer shifts can
        // describe the same subpixel motion; a distant runner-up is ambiguous.
        let candidates = Set(hits.map(\.shift)).map { shift in
            let agreeing = hits.filter { abs($0.shift - shift) <= 1 }
            let sections = Set(agreeing.map { $0.patch.section }).count
            return (shift: shift, hits: agreeing, score: 3 * sections + agreeing.count, sections: sections)
        }
        let ordered = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return abs($0.shift) < abs($1.shift)
        }
        guard let best = ordered.first, best.sections >= 2 else {
            return stationary >= max(2, (patches.count * 4 + 4) / 5) ? .stationary : .unaligned
        }
        if let alternative = ordered.first(where: { abs($0.shift - best.shift) > 3 }),
           best.score < alternative.score + max(3, alternative.score / 5) { return .unaligned }

        // Re-evaluate the integer neighbors using all agreeing patches rather
        // than rounding each patch's estimate independently.
        let measurements = (best.shift - 1...best.shift + 1).compactMap { shift -> (Int, Double)? in
            guard shift != 0, abs(shift) <= maximumShift,
                  best.hits.allSatisfy({
                      let row = $0.patch.row + shift
                      return row >= radius && row < height - radius
                  }) else { return nil }
            let error = best.hits.reduce(0.0) { sum, hit in
                sum + Double(cost(previous, current, hit.patch, shift: shift)) / Double(hit.patch.contrast)
            }
            return (shift, error)
        }
        let shift = measurements.min { $0.1 < $1.1 }?.0 ?? best.shift
        guard let seam = seam(previous, current, shift: shift, hits: best.hits) else { return .unaligned }
        return .aligned(Registration(offset: shift, seam: seam, score: best.score))
    }

    private static func patches(in frame: Frame) -> [Patch] {
        let margin = max(radius, frame.height / 28)
        let sections = min(16, max(5, (frame.height - 2 * margin) / 22))
        guard frame.height - 2 * margin >= sections else { return [] }
        var patches: [Patch] = []
        for section in 0..<sections {
            let start = margin + (frame.height - 2 * margin) * section / sections
            let end = margin + (frame.height - 2 * margin) * (section + 1) / sections
            var strongest: [Patch] = []
            for band in 0..<bands {
                var patch = Patch(row: start, band: band, section: section, contrast: 0)
                for row in stride(from: start, to: end, by: max(1, (end - start) / 8)) {
                    var energy = 0
                    for sample in sampleOffsets.dropLast() {
                        energy += distance(frame[row + sample, band], frame[row + sample + 3, band])
                    }
                    if energy > patch.contrast { patch = Patch(row: row, band: band, section: section, contrast: energy) }
                }
                if patch.contrast >= 125 { strongest.append(patch) }
            }
            patches.append(contentsOf: strongest.sorted { $0.contrast > $1.contrast }.prefix(3))
        }
        return patches
    }

    private static func bestShift(_ previous: Frame, _ current: Frame, _ patch: Patch,
                                  maximumShift: Int) -> Int? {
        let lower = max(-maximumShift, radius - patch.row)
        let upper = min(maximumShift, previous.height - radius - 1 - patch.row)
        let ceiling = max(115, patch.contrast * 2 / 5)
        var costs: [Int] = []
        costs.reserveCapacity(upper - lower + 1)
        var best = ceiling + 1
        var position = 0
        for shift in lower...upper {
            let error = cost(previous, current, patch, shift: shift, cutoff: ceiling)
            costs.append(error)
            if error < best {
                best = error
                position = shift
            }
        }
        guard position != 0, best <= ceiling else { return nil }
        let minimumGap = max(21, patch.contrast / 15)
        for (index, error) in costs.enumerated()
        where abs(index + lower - position) > 2 && error < best + minimumGap {
            return nil
        }
        return position
    }

    private static func seam(_ previous: Frame, _ current: Frame, shift: Int, hits: [Hit]) -> Int? {
        let centers = hits.map { $0.patch.row }
        guard let first = centers.min(), let last = centers.max(),
              last - first >= max(8, min(36, current.height / 22)) else { return nil }
        // Stay between patches that moved with the content, clear of fixed bars.
        let lower = max(radius + max(0, -shift), first)
        let upper = min(current.height - max(0, shift) - radius - 1, last)
        guard lower <= upper else { return nil }
        let middle = (lower + upper) / 2
        let reach = max(2, (upper - lower) / 3)
        let participating = Set(hits.map { $0.patch.band })
        var best = (row: middle, error: Int.max)
        for row in max(lower, middle - reach)...min(upper, middle + reach) {
            var error = abs(row - middle)
            for band in participating {
                error += 3 * distance(previous[row + shift, band], current[row, band])
                error += distance(current[row - 1, band], current[row + 1, band])
            }
            if error < best.error { best = (row, error) }
        }
        return best.row
    }

    @inline(__always)
    private static func cost(_ previous: Frame, _ current: Frame, _ patch: Patch,
                             shift: Int, cutoff: Int = .max) -> Int {
        var total = 0
        for sample in sampleOffsets {
            let row = patch.row + sample
            total += distance(previous[row + shift, patch.band], current[row, patch.band])
            if total > cutoff { return total }
        }
        return total
    }

    @inline(__always)
    private static func distance(_ a: SIMD16<UInt8>, _ b: SIMD16<UInt8>) -> Int {
        let higher = a.replacing(with: b, where: a .< b)
        let lower = a.replacing(with: b, where: a .> b)
        return Int(SIMD16<UInt16>(truncatingIfNeeded: higher &- lower).wrappedSum())
    }
}
