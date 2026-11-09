import CoreGraphics

enum Selection {
    static let minimum: CGFloat = 8

    static func between(_ start: CGPoint, _ end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    static func move(_ rect: CGRect, from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX + end.x - start.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + end.y - start.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    enum Handle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        private var horizontal: CGFloat {
            switch self {
            case .topLeft, .left, .bottomLeft: return 0
            case .top, .bottom: return 0.5
            case .topRight, .right, .bottomRight: return 1
            }
        }

        private var vertical: CGFloat {
            switch self {
            case .topLeft, .top, .topRight: return 0
            case .left, .right: return 0.5
            case .bottomLeft, .bottom, .bottomRight: return 1
            }
        }

        func center(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + horizontal * rect.width, y: rect.minY + vertical * rect.height)
        }

        func boundaryPoint(in rect: CGRect, near pointer: CGPoint) -> CGPoint {
            CGPoint(x: horizontal == 0 ? rect.minX : horizontal == 1 ? rect.maxX : pointer.x,
                    y: vertical == 0 ? rect.minY : vertical == 1 ? rect.maxY : pointer.y)
        }

        func resize(_ rect: CGRect, delta: CGPoint, in bounds: CGRect) -> CGRect {
            var left = rect.minX
            var top = rect.minY
            var right = rect.maxX
            var bottom = rect.maxY
            if horizontal == 0 { left = min(max(left + delta.x, bounds.minX), right - Selection.minimum) }
            if horizontal == 1 { right = max(min(right + delta.x, bounds.maxX), left + Selection.minimum) }
            if vertical == 0 { top = min(max(top + delta.y, bounds.minY), bottom - Selection.minimum) }
            if vertical == 1 { bottom = max(min(bottom + delta.y, bounds.maxY), top + Selection.minimum) }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        static func hit(at point: CGPoint, in rect: CGRect, retaining previous: Handle? = nil) -> Handle? {
            if let handle = hit(at: point, in: rect, edgeSlop: 6) { return handle }
            // A small release margin keeps minor movement from alternating cursor shapes.
            guard let previous, hit(at: point, in: rect, edgeSlop: 8) == previous else { return nil }
            return previous
        }

        private static func hit(at point: CGPoint, in rect: CGRect, edgeSlop: CGFloat) -> Handle? {
            let nearestDot = allCases.compactMap { handle -> (Handle, CGFloat)? in
                let center = handle.center(in: rect)
                let distance = hypot(point.x - center.x, point.y - center.y)
                return distance <= edgeSlop + 1 ? (handle, distance) : nil
            }.min { $0.1 < $1.1 }?.0
            if let nearestDot { return nearestDot }

            guard rect.insetBy(dx: -edgeSlop, dy: -edgeSlop).contains(point) else { return nil }
            let left = abs(point.x - rect.minX)
            let right = abs(point.x - rect.maxX)
            let top = abs(point.y - rect.minY)
            let bottom = abs(point.y - rect.maxY)
            let nearHorizontalEdge = min(top, bottom) <= min(edgeSlop, rect.height / 3)
            let nearVerticalEdge = min(left, right) <= min(edgeSlop, rect.width / 3)
            if nearHorizontalEdge && nearVerticalEdge {
                if top <= bottom { return left <= right ? .topLeft : .topRight }
                return left <= right ? .bottomLeft : .bottomRight
            }
            if nearHorizontalEdge { return top <= bottom ? .top : .bottom }
            if nearVerticalEdge { return left <= right ? .left : .right }
            return nil
        }
    }
}
