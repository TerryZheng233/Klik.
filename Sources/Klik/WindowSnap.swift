import CoreGraphics
import Foundation

struct WindowSnap: Equatable {
    let id: CGWindowID
    let frame: CGRect

    static func candidates(on displayID: CGDirectDisplayID, canvasSize: CGSize,
                           available: Set<CGWindowID>) -> [WindowSnap] {
        let display = CGDisplayBounds(displayID)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID, available.contains(id),
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let local = localFrame(frame, display: display, canvasSize: canvasSize)
            else { return nil }
            return WindowSnap(id: id, frame: local)
        }
    }

    static func localFrame(_ frame: CGRect, display: CGRect, canvasSize: CGSize) -> CGRect? {
        guard !display.isEmpty else { return nil }
        // Quartz bounds and the flipped canvas both run from top to bottom.
        let xScale = canvasSize.width / display.width
        let yScale = canvasSize.height / display.height
        let local = CGRect(x: (frame.minX - display.minX) * xScale,
                           y: (frame.minY - display.minY) * yScale,
                           width: frame.width * xScale, height: frame.height * yScale)
        let visible = local.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !visible.isEmpty, visible.width >= Selection.minimum, visible.height >= Selection.minimum else { return nil }
        return local
    }

    static func target(at point: CGPoint, in frontToBack: [WindowSnap]) -> WindowSnap? {
        frontToBack.first { $0.frame.contains(point) }
    }

    func previewFrame(in bounds: CGRect) -> CGRect {
        let scale = min(1, bounds.width / frame.width, bounds.height / frame.height)
        let width = frame.width * scale
        let height = frame.height * scale
        let x = max(bounds.minX, min(frame.minX, bounds.maxX - width))
        let y = max(bounds.minY, min(frame.minY, bounds.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
