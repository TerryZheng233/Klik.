import CoreGraphics
import Foundation

enum WindowSnap {
    static func visibleFrames(on displayID: CGDirectDisplayID, canvasSize: CGSize) -> [CGRect] {
        let display = CGDisplayBounds(displayID)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return localFrame(frame, display: display, canvasSize: canvasSize)
        }
    }

    static func localFrame(_ frame: CGRect, display: CGRect, canvasSize: CGSize) -> CGRect? {
        guard !display.isEmpty else { return nil }
        let visible = frame.intersection(display)
        guard !visible.isEmpty else { return nil }

        // Quartz bounds and the flipped canvas both run from top to bottom.
        let xScale = canvasSize.width / display.width
        let yScale = canvasSize.height / display.height
        let local = CGRect(x: (visible.minX - display.minX) * xScale,
                           y: (visible.minY - display.minY) * yScale,
                           width: visible.width * xScale, height: visible.height * yScale)
        return local.width >= Selection.minimum && local.height >= Selection.minimum ? local : nil
    }

    static func target(at point: CGPoint, in frontToBack: [CGRect]) -> CGRect? {
        frontToBack.first { $0.contains(point) }
    }
}
