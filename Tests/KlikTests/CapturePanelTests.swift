import AppKit
import Carbon
import ImageIO
import XCTest
@testable import Klik

final class CapturePanelTests: XCTestCase {
    func testMagnifierStaysInsideDisplayAtEachCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: 639, y: 1),
                      CGPoint(x: 1, y: 479), CGPoint(x: 639, y: 479)] {
            let frame = MagnifierLayout.frame(near: point, in: bounds)
            XCTAssertTrue(bounds.contains(frame))
            XCTAssertFalse(frame.contains(point))
        }
    }

    @MainActor
    func testMagnifierAppearsOnlyDuringSelectionAndResize() throws {
        _ = NSApplication.shared
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage()) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let magnifier = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "captureMagnifier" })
        XCTAssertTrue(magnifier.isHidden)
        let start = CGPoint(x: 100, y: 400)
        let end = CGPoint(x: 400, y: 100)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
        XCTAssertFalse(magnifier.isHidden)
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
        XCTAssertFalse(magnifier.isHidden)
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        XCTAssertTrue(magnifier.isHidden)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: end, in: panel))
        XCTAssertFalse(magnifier.isHidden)
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 420, y: 80), in: panel))
        XCTAssertFalse(magnifier.isHidden)
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 420, y: 80), in: panel))
        XCTAssertTrue(magnifier.isHidden)
    }

    @MainActor
    func testMagnifierCentersImageAtSelectionPoint() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 480))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 300, y: 0, width: 340, height: 480))
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage())) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let magnifier = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "captureMagnifier" })
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 240), in: panel))
        let bitmap = try XCTUnwrap(magnifier.bitmapImageRepForCachingDisplay(in: magnifier.bounds))
        magnifier.cacheDisplay(in: magnifier.bounds, to: bitmap)
        let y = bitmap.pixelsHigh / 2 - 12
        let left = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2 - 20, y: y)?.usingColorSpace(.deviceRGB))
        let right = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2 + 20, y: y)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(left.redComponent, left.blueComponent)
        XCTAssertGreaterThan(right.blueComponent, right.redComponent)
    }

    @MainActor
    func testScrollCaptureToolbarPassesTheSelectedDisplayRegion() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        var selected: CGRect?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings,
                                 startScrollCapture: { selected = $0 }) { _ in XCTFail("Capture closed") }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        let button = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolScrollCapture) })
        let start = CGPoint(x: 40, y: 400)
        func select(to end: CGPoint) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        }

        try select(to: CGPoint(x: 80, y: 340))
        button.performClick(nil)
        XCTAssertNil(selected)

        let freshStart = CGPoint(x: 30, y: 420)
        let end = CGPoint(x: 340, y: 150)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: freshStart, in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        button.performClick(nil)
        XCTAssertEqual(selected, CGRect(x: 30, y: 60, width: 310, height: 270))
    }

    @MainActor
    func testStitchedPreviewClipsItsSurfaceInsideTransparentShadowMargins() throws {
        _ = NSApplication.shared
        let preview = ScrollCapturePreview(image: try testImage(), axis: .vertical,
                                           screenFrame: CGRect(x: -2_000, y: -2_000, width: 900, height: 720),
                                           strings: AppStrings(), message: nil)
        defer { preview.orderOut(nil) }
        XCTAssertFalse(preview.isOpaque)
        XCTAssertEqual(preview.backgroundColor, .clear)
        XCTAssertFalse(preview.hasShadow)
        let chrome = try XCTUnwrap(preview.contentView)
        let surface = try XCTUnwrap(chrome.subviews.first { $0.identifier?.rawValue == "scrollPreviewSurface" })
        XCTAssertTrue(chrome.bounds.contains(surface.frame))
        XCTAssertGreaterThan(surface.frame.minX, chrome.bounds.minX)
        XCTAssertLessThan(surface.frame.maxX, chrome.bounds.maxX)
        XCTAssertGreaterThan(surface.frame.minY, chrome.bounds.minY)
        XCTAssertLessThan(surface.frame.maxY, chrome.bounds.maxY)
        XCTAssertEqual(chrome.layer?.isOpaque, false)
        XCTAssertNotNil(chrome.layer?.shadowPath)
        XCTAssertEqual(surface.layer?.cornerCurve, .continuous)
        XCTAssertEqual(surface.layer?.masksToBounds, true)
    }

    @MainActor
    func testStitchedPreviewExportsMarksFromSeparateViewports() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let context = try XCTUnwrap(CaptureImage.bitmap(width: 360, height: 1_600))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 360, height: 1_600))
        let preview = ScrollCapturePreview(image: try XCTUnwrap(context.makeImage()), axis: .vertical,
                                           screenFrame: CGRect(x: -2_000, y: -2_000, width: 900, height: 720),
                                           strings: strings, message: nil)
        defer { preview.orderOut(nil) }
        func views(in view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap { views(in: $0) } }
        let children = views(in: try XCTUnwrap(preview.contentView))
        let scroll = try XCTUnwrap(children.compactMap { $0 as? NSScrollView }.first)
        let canvas = try XCTUnwrap(scroll.documentView as? CaptureView)
        let rectangle = try XCTUnwrap(children.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRectangle) })
        let save = try XCTUnwrap(children.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolDownload) })
        rectangle.performClick(nil)
        func mark(y: CGFloat) throws {
            let x = canvas.bounds.midX - 40
            let start = canvas.convert(CGPoint(x: x, y: y), to: nil)
            let end = canvas.convert(CGPoint(x: x + 80, y: y + 60), to: nil)
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: preview))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: preview))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: preview))
        }
        try mark(y: 90)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 700))
        scroll.reflectScrolledClipView(scroll.contentView)
        try mark(y: canvas.visibleRect.minY + 100)
        XCTAssertEqual(canvas.marks.count, 2)

        var saved: CGImage?
        preview.onExport = { destination, image in
            XCTAssertEqual(destination, .downloads)
            saved = image
        }
        save.performClick(nil)
        let result = try XCTUnwrap(saved)
        XCTAssertEqual(result.width, 360)
        XCTAssertEqual(result.height, 1_600)
        let pixels = CaptureImage(image: result, size: CGSize(width: 360, height: 1_600))
        for mark in canvas.marks {
            let rect = try XCTUnwrap(mark.movableBounds)
            let color = try XCTUnwrap(pixels.color(at: CGPoint(x: 180, y: rect.minY - 10)))
            XCTAssertGreaterThan(color.red, color.green + 0.2)
        }
    }

    @MainActor
    func testSelectionBadgeShowsExportPixelsAndTracksShiftImmediately() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let source = try XCTUnwrap(CaptureImage.bitmap(width: 1_280, height: 960)?.makeImage())
        var exported: Data?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480), image: source,
                                 windowTargets: [WindowSnap(id: 1, frame: CGRect(x: 20, y: 20, width: 240, height: 120))],
                                 strings: strings, saveDownload: { exported = $0 }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        func badge(_ id: String) throws -> (NSView, NSTextField) {
            let view = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == id })
            view.layoutSubtreeIfNeeded()
            return (view, try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first))
        }
        let (hint, label) = try badge("captureModeHint")
        XCTAssertEqual(label.stringValue, "Hold space to select a window")
        XCTAssertEqual(label.frame.midX, hint.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(label.frame.midY, hint.bounds.midY, accuracy: 0.5)
        let hintWidth = (label.stringValue as NSString).size(withAttributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)]).width
        XCTAssertGreaterThanOrEqual(label.frame.width, hintWidth + 6)

        let start = CGPoint(x: 100.25, y: 380.25)
        let end = CGPoint(x: 222.75, y: 292.25)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
        let (size, dimensions) = try badge("capturePixelSize")
        XCTAssertFalse(size.isHidden)
        XCTAssertEqual(dimensions.stringValue, "246 x 177")
        func shift(_ modifiers: NSEvent.ModifierFlags) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: end, modifierFlags: modifiers,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_Shift)))
            panel.sendEvent(event)
        }
        try shift(.shift)
        XCTAssertEqual(dimensions.stringValue, "245 x 245")
        try shift([])
        XCTAssertEqual(dimensions.stringValue, "246 x 177")
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel, modifiers: .shift))
        XCTAssertEqual(dimensions.stringValue, "245 x 245")

        let save = try XCTUnwrap(canvas.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolDownload) })
        save.performClick(nil)
        let png = try XCTUnwrap(exported)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 245)
        XCTAssertEqual(image.height, 245)
    }

    @MainActor
    func testEllipseButtonPrecedesRectangleAndShiftDrawsACircle() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        let controls = canvas.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
        let ellipse = try XCTUnwrap(controls.first { $0.toolTip == strings(.toolEllipse) })
        let rectangle = try XCTUnwrap(controls.first { $0.toolTip == strings(.toolRectangle) })
        XCTAssertEqual(ellipse.frame.maxX, rectangle.frame.minX, accuracy: 0.5)

        func drag(_ start: CGPoint, _ end: CGPoint, modifiers: NSEvent.ModifierFlags = []) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel, modifiers: modifiers))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel, modifiers: modifiers))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel, modifiers: modifiers))
        }
        try drag(CGPoint(x: 80, y: 420), CGPoint(x: 550, y: 70))
        ellipse.performClick(nil)
        try drag(CGPoint(x: 130, y: 370), CGPoint(x: 245, y: 330))
        try drag(CGPoint(x: 305, y: 365), CGPoint(x: 410, y: 310), modifiers: .shift)
        XCTAssertEqual(canvas.marks, [
            .ellipse(CGRect(x: 130, y: 110, width: 115, height: 40), .red),
            .ellipse(CGRect(x: 305, y: 115, width: 105, height: 105), .red)
        ])
        XCTAssertTrue(canvas.marks[1].hitTest(CGPoint(x: 357.5, y: 115)))
        XCTAssertFalse(canvas.marks[1].hitTest(CGPoint(x: 357.5, y: 167.5)))
        canvas.undo()
        XCTAssertEqual(canvas.marks.count, 1)
        canvas.redo()
        XCTAssertEqual(canvas.marks.count, 2)
    }

    @MainActor
    func testSelectedRegionCanBeCopiedByDoubleClickOrEnter() throws {
        _ = NSApplication.shared
        let image = try testImage()
        for useEnter in [false, true] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            var outcome: CapturePanel.Outcome?
            let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                     image: image, pasteboard: board) { outcome = $0 }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView)
            let start = CGPoint(x: 100, y: 400)
            let end = CGPoint(x: 400, y: 100)
            let middle = CGPoint(x: 250, y: 250)
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
            if useEnter {
                let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                         timestamp: 0, windowNumber: panel.windowNumber,
                                                         context: nil, characters: "\r",
                                                         charactersIgnoringModifiers: "\r", isARepeat: false,
                                                         keyCode: UInt16(kVK_Return)))
                panel.sendEvent(key)
            } else {
                for count in 1...2 {
                    canvas.mouseDown(with: try mouse(.leftMouseDown, at: middle, in: panel, count: count))
                    canvas.mouseUp(with: try mouse(.leftMouseUp, at: middle, in: panel, count: count))
                }
            }
            XCTAssertEqual(outcome, .exported)
            let png = try XCTUnwrap(board.data(forType: .png))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(result.width, 300)
            XCTAssertEqual(result.height, 300)
        }
    }

    @MainActor
    func testDoubleClickCopiesDisplay() throws {
        _ = NSApplication.shared
        let image = try testImage()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KlikPanelHistory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CaptureHistory(directory: directory)
        var outcome: CapturePanel.Outcome?
        var recorded: Data?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: image, pasteboard: board,
                                 recordCapture: { png in
                                     recorded = png
                                     do { try history.record(png) } catch { XCTFail("History write failed: \(error)") }
                                 }) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let point = CGPoint(x: 300, y: 240)
        for count in 1...2 {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel, count: count))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel, count: count))
        }
        XCTAssertEqual(outcome, .exported)
        XCTAssertNotNil(board.data(forType: .png))
        XCTAssertEqual(recorded, board.data(forType: .png))
        let saved = try XCTUnwrap(history.entries().first)
        XCTAssertEqual(try Data(contentsOf: saved), board.data(forType: .png))
    }

    @MainActor
    func testDoubleClickCopiesWindowBeforeAndAfterCaptureCompletes() async throws {
        _ = NSApplication.shared
        let image = try testImage()
        for delay in [0, 200] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let exported = expectation(description: "Window copied")
            let target = WindowSnap(id: 123, frame: CGRect(x: 400, y: 80, width: 160, height: 160))
            let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                     image: image, windowTargets: [target],
                                     captureWindow: { id in
                                         XCTAssertEqual(id, target.id)
                                         try await Task.sleep(for: .milliseconds(100))
                                         return image
                                     }, pasteboard: board) { outcome in
                XCTAssertEqual(outcome, .exported)
                exported.fulfill()
            }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView)
            let point = CGPoint(x: 450, y: 320)
            panel.sendEvent(try space(.keyDown))
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel))
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel, count: 2))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel, count: 2))
            await fulfillment(of: [exported], timeout: 2)
            XCTAssertNotNil(board.data(forType: .png))
        }
    }

    @MainActor
    func testDoubleClickCopiesMenuFromFrozenScreen() throws {
        _ = NSApplication.shared
        let image = try testImage()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var outcome: CapturePanel.Outcome?
        let menu = WindowSnap(id: 0, frame: CGRect(x: 400, y: 80, width: 160, height: 160), usesDesktopImage: true)
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: image, windowTargets: [menu], pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let point = CGPoint(x: 450, y: 320)
        panel.sendEvent(try space(.keyDown))
        for count in 1...2 {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel, count: count))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel, count: count))
        }
        XCTAssertEqual(outcome, .exported)
        let data = try XCTUnwrap(board.data(forType: .png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(result.width, 160)
        XCTAssertEqual(result.height, 160)
    }

    @MainActor
    func testClickOutsideWindowWhileHoldingSpaceKeepsSelecting() throws {
        _ = NSApplication.shared
        let size = CGSize(width: 640, height: 480)
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let target = WindowSnap(id: 1, frame: CGRect(x: 400, y: 80, width: 160, height: 160))
        let panel = CapturePanel(frame: CGRect(origin: CGPoint(x: -2_000, y: -2_000), size: size),
                                 image: image, windowTargets: [target],
                                 captureWindow: { _ in
                                     XCTFail("The click did not hit the window")
                                     return image
                                 }) { _ in
            XCTFail("The capture should stay open")
        }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        let point = CGPoint(x: 80, y: 240)

        panel.sendEvent(try space(.keyDown))
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel))
        // Releasing Space before the mouse button should still finish a window-mode click.
        panel.sendEvent(try space(.keyUp))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel))
        XCTAssertTrue(toolbar.isHidden)

        canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel))
        XCTAssertFalse(toolbar.isHidden)
    }

    @MainActor
    func testColorPickerAvailableBeforeChoosingMarkupTool() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try testImage(), strings: strings) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 400), in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 500, y: 50), in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 500, y: 50), in: panel))
        let trays = canvas.subviews.compactMap { $0 as? NSVisualEffectView }
        let toolbar = try XCTUnwrap(trays.first)
        let color = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.inkPicker, strings(.inkRed)) })
        XCTAssertFalse(color.isHidden)
        color.performClick(nil)
        let palette = try XCTUnwrap(trays.first { $0 !== toolbar && $0.subviews.count == Ink.allCases.count + 1 })
        XCTAssertFalse(palette.isHidden)
        let blue = try XCTUnwrap(palette.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkBlue) })
        blue.performClick(nil)
        XCTAssertTrue(palette.isHidden)
        XCTAssertEqual(color.toolTip, strings(.inkPicker, strings(.inkBlue)))
        XCTAssertFalse(color.isHidden)
    }

    @MainActor
    func testShiftConstrainedMarkupInCaptureAndOCR() async throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try testImage(), strings: strings,
                                 recognizeText: { _ in "text" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ p: CGPoint, shift: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: p, modifierFlags: shift ? .shift : [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey, _ parent: NSView) throws -> NSButton {
            try XCTUnwrap(parent.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        try button(.toolRectangle, toolbar).performClick(nil)
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 160, y: 340)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 230, y: 310), shift: true))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 230, y: 310), shift: true))
        guard case .rectangle(let square, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing rectangle") }
        XCTAssertEqual(square.width, square.height, accuracy: 0.001)
        try button(.toolRecognizeText, toolbar).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        let image = try XCTUnwrap(overlay.subviews.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(overlay.subviews.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        try button(.toolPen, tools).performClick(nil)
        let a = image.convert(image.displayPoint(for: CGPoint(x: 300, y: 200)), to: nil)
        let b = image.convert(image.displayPoint(for: CGPoint(x: 320, y: 240)), to: nil)
        let c = image.convert(image.displayPoint(for: CGPoint(x: 400, y: 260)), to: nil)
        image.mouseDown(with: try event(.leftMouseDown, a))
        image.mouseDragged(with: try event(.leftMouseDragged, b, shift: true))
        image.mouseUp(with: try event(.leftMouseUp, c, shift: true))
        guard case .pen(let points, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing line") }
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].x, 300, accuracy: 0.01)
        XCTAssertEqual(points[1].x, 400, accuracy: 0.01)
        canvas.recognitionUndo()
        XCTAssertEqual(canvas.marks.count, 1)
        canvas.recognitionRedo()
        XCTAssertEqual(canvas.marks.last, .pen(points, .red))
    }

    func testShiftConstraintsStayInsideSelection() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let squareEnd = MarkConstraint.squareEnd(from: CGPoint(x: 90, y: 30), toward: CGPoint(x: 40, y: 75), in: bounds)
        XCTAssertEqual(squareEnd, CGPoint(x: 40, y: 80))
        let arrow = MarkConstraint.snappedEnd(from: CGPoint(x: 50, y: 40), toward: CGPoint(x: 90, y: 48), in: bounds)
        XCTAssertEqual(arrow.y, 40, accuracy: 0.001)
        let diagonal = MarkConstraint.snappedEnd(from: CGPoint(x: 90, y: 70), toward: CGPoint(x: 100, y: 80), in: bounds)
        XCTAssertEqual(diagonal.x, 100, accuracy: 0.001)
        XCTAssertEqual(diagonal.y, 80, accuracy: 0.001)
    }

    @MainActor
    func testCoverCanBeRecoloredWithoutRedrawing() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try testImage(), strings: strings) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 400), in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 500, y: 50), in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 500, y: 50), in: panel))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        let options = try XCTUnwrap(canvas.subviews.compactMap { $0 as? MosaicOptions }.first)
        try XCTUnwrap(options.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.mosaicSolid) }).performClick(nil)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 250, y: 250), in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 300, y: 250), in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 300, y: 250), in: panel))
        let original = try XCTUnwrap(canvas.marks.last)
        canvas.export(.clipboard)
        XCTAssertNil(outcome, "Pending striped cover must be colored before export")
        XCTAssertTrue(options.isHidden)
        canvas.updatePointer(at: CGPoint(x: 350, y: 200))
        XCTAssertEqual(canvas.pointer, .eyedropper)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 350, y: 200), in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 350, y: 200), in: panel))
        guard case .mosaic(_, _, let style, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing cover") }
        XCTAssertEqual(style, .manual)
        XCTAssertFalse(options.isHidden)
        let eyedropper = try XCTUnwrap(options.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.mosaicPickColor) })
        XCTAssertFalse(eyedropper.isHidden)
        canvas.undo()
        XCTAssertEqual(canvas.marks.last, original)
        canvas.redo()
        guard case .mosaic(_, _, let redoneStyle, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing cover") }
        XCTAssertEqual(redoneStyle, .manual)
    }

    @MainActor
    func testShiftKeepsBothMosaicBrushesStraight() throws {
        _ = NSApplication.shared
        for mode in [MosaicStyle.pixel, .brush] {
            let strings = AppStrings(language: .english)
            let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                     image: try testImage(), strings: strings) { _ in }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
            func event(_ type: NSEvent.EventType, _ p: CGPoint, shift: Bool = false) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: p, modifierFlags: shift ? .shift : [],
                    timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
            canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
            canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
            let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
            let options = try XCTUnwrap(canvas.subviews.compactMap { $0 as? MosaicOptions }.first)
            try XCTUnwrap(options.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(mode.label) }).performClick(nil)
            canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 180, y: 300)))
            canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 220, y: 250), shift: true))
            canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 280, y: 300), shift: true))
            guard case .mosaic(let points, _, let style, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing stroke") }
            XCTAssertEqual(style, mode)
            XCTAssertEqual(points.count, 2)
            XCTAssertEqual(points[0].y, points[1].y, accuracy: 0.001)
        }
    }

    @MainActor
    func testMosaicScrollChangesSizeOnlyOverSelection() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try testImage(), strings: strings) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 400), in: panel))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 500, y: 50), in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 500, y: 50), in: panel))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        canvas.updatePointer(at: CGPoint(x: 300, y: 250))
        let hint = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "mosaicScrollHint" })
        XCTAssertFalse(hint.isHidden)
        XCTAssertNil(hint.hitTest(CGPoint(x: 1, y: 1)))
        XCTAssertGreaterThan(hint.frame.minX, 300)
        XCTAssertTrue(canvas.adjustMosaicSize(delta: 1, precise: false, at: CGPoint(x: 300, y: 250)))
        XCTAssertTrue(hint.isHidden)
        XCTAssertEqual(canvas.mosaicDiameter, 34)
        XCTAssertFalse(canvas.adjustMosaicSize(delta: 1, precise: false, at: CGPoint(x: 5, y: 5)))
        XCTAssertTrue(canvas.adjustMosaicSize(delta: -1000, precise: true, at: CGPoint(x: 300, y: 250)))
        XCTAssertEqual(canvas.mosaicDiameter, 10)
        XCTAssertTrue(canvas.adjustMosaicSize(delta: 1000, precise: true, at: CGPoint(x: 300, y: 250)))
        XCTAssertEqual(canvas.mosaicDiameter, 100)
        let outline = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "mosaicBrushOutline" })
        XCTAssertFalse(outline.isHidden)
        XCTAssertEqual(outline.frame.width, 104, accuracy: 0.01)
    }

    func testScrollHintStopsAfterPracticeOrThreeDisplays() throws {
        let suite = "KlikScrollHintTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = MosaicScrollHintPolicy(defaults: defaults)
        XCTAssertTrue(policy.shouldShow)
        policy.didShow(); policy.didShow(); policy.didShow()
        XCTAssertFalse(MosaicScrollHintPolicy(defaults: defaults).shouldShow)
        defaults.removePersistentDomain(forName: suite)
        let practiced = MosaicScrollHintPolicy(defaults: defaults)
        practiced.didScroll()
        XCTAssertFalse(MosaicScrollHintPolicy(defaults: defaults).shouldShow)
    }

    @MainActor
    func testUndoRedoAndNewMarkClearRedoHistory() throws {
        _ = NSApplication.shared
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey) throws -> NSButton {
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        let undo = try button(.toolUndo)
        let redo = try button(.toolRedo)
        func drag(_ start: CGPoint, _ end: CGPoint) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        }
        try drag(CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 50))
        try button(.toolRectangle).performClick(nil)
        try drag(CGPoint(x: 180, y: 320), CGPoint(x: 260, y: 240))
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        undo.performClick(nil)
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(redo.isEnabled)
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "Z", charactersIgnoringModifiers: "Z", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Z)))
        panel.sendEvent(key)
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        undo.performClick(nil)
        try drag(CGPoint(x: 300, y: 320), CGPoint(x: 380, y: 240))
        XCTAssertFalse(redo.isEnabled)
    }

    @MainActor
    func testMovingAnnotationCanBeUndoneAndRedone() throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings, pasteboard: board) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey) throws -> NSButton {
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        func drag(_ start: CGPoint, _ end: CGPoint) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        }
        func capture() throws -> Data {
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
            panel.sendEvent(key)
            return try XCTUnwrap(board.data(forType: .png))
        }
        try drag(CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 50))
        try button(.toolRectangle).performClick(nil)
        try drag(CGPoint(x: 180, y: 320), CGPoint(x: 260, y: 240))
        let original = try capture()
        try drag(CGPoint(x: 220, y: 280), CGPoint(x: 280, y: 280))
        let moved = try capture()
        XCTAssertNotEqual(original, moved)
        try drag(CGPoint(x: 320, y: 240), CGPoint(x: 360, y: 210))
        let resized = try capture()
        XCTAssertNotEqual(moved, resized)
        try button(.toolUndo).performClick(nil)
        XCTAssertEqual(try capture(), moved)
        try button(.toolUndo).performClick(nil)
        XCTAssertEqual(try capture(), original)
        try button(.toolRedo).performClick(nil)
        XCTAssertEqual(try capture(), moved)
        try button(.toolRedo).performClick(nil)
        XCTAssertEqual(try capture(), resized)
    }

    @MainActor
    func testEscapeDuringCompositionGoesToTextInputInsteadOfCancellingCapture() throws {
        _ = NSApplication.shared
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage()) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let editor = CompositionTestEditor(frame: .zero)
        panel.contentView?.addSubview(editor)
        XCTAssertTrue(panel.makeFirstResponder(editor))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape)))
        panel.sendEvent(escape)
        XCTAssertNil(outcome)
        XCTAssertTrue(editor.receivedEscape)
        editor.composing = false
        panel.sendEvent(escape)
        XCTAssertEqual(outcome, .cancelled)
    }

    @MainActor
    func testEnterFinishesTextBeforeCopyingScreenshot() throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let strings = AppStrings(language: .english)
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings, pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        let text = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolText) })
        func drag(_ start: CGPoint, _ end: CGPoint) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        }
        try drag(CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 50))
        text.performClick(nil)
        let point = CGPoint(x: 220, y: 280)
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == strings(.textPlaceholder) })
        field.stringValue = "Hello"
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
        panel.sendEvent(key)
        XCTAssertNil(outcome)
        XCTAssertNil(board.data(forType: .png))
        XCTAssertNil(field.superview)
        panel.sendEvent(key)
        XCTAssertEqual(outcome, .exported)
        XCTAssertNotNil(board.data(forType: .png))
    }

    @MainActor
    func testArrowEndpointCanBeAdjustedAndUndone() throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: try testImage(), strings: strings, pasteboard: board) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey) throws -> NSButton {
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        func drag(_ start: CGPoint, _ end: CGPoint) throws {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: panel))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: panel))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: panel))
        }
        func capture() throws -> Data {
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
            panel.sendEvent(key)
            return try XCTUnwrap(board.data(forType: .png))
        }
        try drag(CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 50))
        try button(.toolArrow).performClick(nil)
        try drag(CGPoint(x: 180, y: 320), CGPoint(x: 260, y: 240))
        let original = try capture()
        try drag(CGPoint(x: 260, y: 240), CGPoint(x: 350, y: 300))
        let resized = try capture()
        XCTAssertNotEqual(original, resized)
        try button(.toolUndo).performClick(nil)
        XCTAssertEqual(try capture(), original)
        try button(.toolRedo).performClick(nil)
        XCTAssertEqual(try capture(), resized)
    }

    func testAnnotationHitTestingAndTranslation() {
        let box = Mark.rectangle(CGRect(x: 20, y: 20, width: 80, height: 60), .red)
        XCTAssertTrue(box.hitTest(CGPoint(x: 20, y: 50)))
        XCTAssertFalse(box.hitTest(CGPoint(x: 60, y: 50)))
        XCTAssertEqual(box.translated(by: CGPoint(x: 30, y: 10)).movableBounds,
                       CGRect(x: 50, y: 30, width: 80, height: 60))
        let arrow = Mark.arrow(CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 110), .red)
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 53)))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 90, y: 20)))
        let text = Mark.text("Dinner", CGPoint(x: 40, y: 70), .red)
        XCTAssertTrue(text.hitTest(CGPoint(x: 45, y: 75)))
        XCTAssertEqual(text.translated(by: CGPoint(x: 20, y: 30)).movableBounds?.origin,
                       CGPoint(x: 60, y: 100))
        let pen = Mark.pen([CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 20)], .red)
        XCTAssertTrue(pen.hitTest(CGPoint(x: 40, y: 22)))
        XCTAssertEqual(pen.translated(by: CGPoint(x: 10, y: 10)).movableBounds?.minX, 30)
        XCTAssertFalse(Mark.mosaic([CGPoint(x: 50, y: 50)]).hitTest(CGPoint(x: 50, y: 50)))
    }

    private func space(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: " ",
                                      charactersIgnoringModifiers: " ", isARepeat: false,
                                      keyCode: UInt16(kVK_Space)))
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in panel: NSWindow,
                       count: Int = 1, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
                                        windowNumber: panel.windowNumber, context: nil,
                                        eventNumber: 0, clickCount: count, pressure: 1))
    }

    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480,
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}

private final class CompositionTestEditor: NSTextView {
    var composing = true
    var receivedEscape = false
    override func hasMarkedText() -> Bool { composing }
    override func keyDown(with event: NSEvent) { receivedEscape = Int(event.keyCode) == kVK_Escape }
}
