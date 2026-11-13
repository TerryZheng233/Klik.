import AppKit
import Carbon
import ImageIO
import XCTest
@testable import Klik

final class TextRecognitionTests: XCTestCase {
    @MainActor
    func testMarkupTextEnterCommitsAnnotationWithoutSaving() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        var saved: Data?
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in "recognized" }, saveDownload: { saved = $0 }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        let image = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolText) }).performClick(nil)
        let position = image.convert(image.displayPoint(for: CGPoint(x: 320, y: 180)), to: nil)
        image.mouseDown(with: try mouse(.leftMouseDown, position))
        image.mouseUp(with: try mouse(.leftMouseUp, position))
        let field = try XCTUnwrap(image.subviews.compactMap { $0 as? InlineMarkupTextView }.first)
        let canvasView = try XCTUnwrap(canvas as? CaptureView)
        canvasView.updatePointer(at: field.convert(CGPoint(x: 8, y: 8), to: nil))
        XCTAssertEqual(canvasView.pointer, .text)
        field.string = "discard"
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: UInt16(kVK_Escape)))
        panel.sendEvent(escape)
        XCTAssertFalse(image.isEditingMarkupText)
        XCTAssertTrue(canvasView.marks.isEmpty)
        XCTAssertTrue(canvasView.isRecognizingText)
        image.mouseDown(with: try mouse(.leftMouseDown, position))
        let freshField = try XCTUnwrap(image.subviews.compactMap { $0 as? InlineMarkupTextView }.first)
        freshField.string = "annotation"
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: panel.windowNumber, context: nil, characters: "\r",
                                                   charactersIgnoringModifiers: "\r", isARepeat: false,
                                                   keyCode: UInt16(kVK_Return)))
        panel.sendEvent(enter)
        XCTAssertFalse(image.isEditingMarkupText)
        XCTAssertNil(saved)
        XCTAssertTrue(try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolUndo) }).isEnabled)
    }

    @MainActor
    func testTextSizeBeforeAndAfterInRecognitionView() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in "recognized" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        let image = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolText) }).performClick(nil)
        func at(_ point: CGPoint) -> CGPoint { image.convert(image.displayPoint(for: point), to: nil) }
        let location = at(CGPoint(x: 230, y: 180))
        XCTAssertTrue(canvas.adjustMarkupSize(delta: 20, precise: true, at: location, modifiers: []))
        let preview = try XCTUnwrap(canvas.subviews.compactMap { $0 as? TextSizePreview }.first)
        XCTAssertTrue(preview.isHidden)
        let cursor = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "capturePointer" })
        let textCursor = CaptureView.Pointer.textCursor(for: .red, size: 28 * image.imageScale)
        XCTAssertEqual(cursor.frame.size, textCursor.image.size)
        image.mouseDown(with: try event(.leftMouseDown, location))
        let field = try XCTUnwrap(image.subviews.compactMap { $0 as? InlineMarkupTextView }.first)
        XCTAssertEqual(try XCTUnwrap(field.font).pointSize, 28 * image.imageScale, accuracy: 0.01)
        field.string = "Hello"
        image.commitText()
        guard case .text(_, let origin, _, let original) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("Missing text") }
        XCTAssertEqual(original, 28)
        let select = at(CGPoint(x: origin.x + 5, y: origin.y + 5))
        image.mouseDown(with: try event(.leftMouseDown, select))
        image.mouseUp(with: try event(.leftMouseUp, select))
        XCTAssertTrue(canvas.adjustMarkupSize(delta: 24, precise: true, at: select, modifiers: []))
        guard case .text(_, _, _, let changed) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("Missing text") }
        XCTAssertEqual(changed, 40)
        canvas.recognitionUndo()
        guard case .text(_, _, _, let undone) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("Missing text") }
        XCTAssertEqual(undone, 28)
        image.mouseDown(with: try event(.leftMouseDown, select))
        image.mouseUp(with: try event(.leftMouseUp, select))
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: select, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 2, pressure: 1))
        image.mouseDown(with: doubleClick)
        let reopened = try XCTUnwrap(image.subviews.compactMap { $0 as? InlineMarkupTextView }.first)
        XCTAssertEqual(reopened.string, "Hello")
        XCTAssertEqual(try XCTUnwrap(reopened.font).pointSize, 28 * image.imageScale, accuracy: 0.01)
        reopened.string = "Changed"
        image.commitText()
        XCTAssertEqual(canvas.marks.last, .text("Changed", origin, .red, size: 28))
        canvas.recognitionUndo()
        XCTAssertEqual(canvas.marks.last, .text("Hello", origin, .red, size: 28))
        image.mouseDown(with: try event(.leftMouseDown, select))
        image.mouseUp(with: try event(.leftMouseUp, select))
        let colorButton = try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkPicker, strings(.inkRed)) })
        colorButton.performClick(nil)
        let palette = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrColorPalette" })
        try XCTUnwrap(palette.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkBlue) }).performClick(nil)
        XCTAssertEqual(canvas.marks.last, .text("Hello", origin, .blue, size: 28))
        canvas.recognitionUndo()
        XCTAssertEqual(canvas.marks.last, .text("Hello", origin, .red, size: 28))
        canvas.recognitionRedo()
        XCTAssertEqual(canvas.marks.last, .text("Hello", origin, .blue, size: 28))
        canvas.recognitionUndo()
        XCTAssertEqual(canvas.marks.last, .text("Hello", origin, .red, size: 28))
        let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }.first)
        let editorPoint = editor.convert(CGPoint(x: 10, y: 10), to: nil)
        XCTAssertFalse(canvas.adjustMarkupSize(delta: 20, precise: true, at: editorPoint, modifiers: []))
    }

    @MainActor
    func testBendArrowInRecognitionView() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in "recognized" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey) throws -> NSButton {
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        try button(.toolArrow).performClick(nil)
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 180, y: 320)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 300, y: 320)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 300, y: 320)))
        try button(.toolRecognizeText).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let image = try XCTUnwrap(descendants(overlay).compactMap { $0 as? RecognitionImageView }.first)
        func at(_ point: CGPoint) -> CGPoint { image.convert(image.displayPoint(for: point), to: nil) }
        let select = at(CGPoint(x: 200, y: 160))
        image.mouseDown(with: try event(.leftMouseDown, select))
        image.mouseUp(with: try event(.leftMouseUp, select))
        let middle = at(CGPoint(x: 240, y: 160)), bent = at(CGPoint(x: 240, y: 220))
        image.mouseDown(with: try event(.leftMouseDown, middle))
        image.mouseDragged(with: try event(.leftMouseDragged, bent))
        image.mouseUp(with: try event(.leftMouseUp, bent))
        let geometry = try XCTUnwrap(canvas.marks.first?.arrowGeometry)
        XCTAssertTrue(geometry.curved)
        XCTAssertEqual(geometry.middle.x, 240, accuracy: 0.1)
        XCTAssertEqual(geometry.middle.y, 220, accuracy: 0.1)
        XCTAssertTrue(canvas.adjustMarkupSize(delta: 34, precise: true, at: bent, modifiers: []))
        XCTAssertEqual(canvas.marks.first?.lineWidth, 11)
        canvas.recognitionUndo()
        XCTAssertEqual(canvas.marks.first?.lineWidth, 2.5)
        canvas.recognitionUndo()
        XCTAssertFalse(try XCTUnwrap(canvas.marks.first?.arrowGeometry).curved)
    }

    @MainActor
    func testMovingMosaicRefreshesRecognition() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        var calls = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in calls += 1; return "result \(calls)" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        let image = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "ocrText" })
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            image.convert(image.displayPoint(for: CGPoint(x: x, y: y)), to: nil)
        }
        let start = at(320, 180), end = at(400, 240)
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        image.mouseDragged(with: try mouse(.leftMouseDragged, end))
        image.mouseUp(with: try mouse(.leftMouseUp, end))
        try await Task.sleep(for: .milliseconds(50))
        let original = try XCTUnwrap(canvas.marks.first)
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        image.mouseUp(with: try mouse(.leftMouseUp, start))
        try await Task.sleep(for: .milliseconds(50))
        let copy = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrCopy" })
        let beforeResize = calls
        XCTAssertTrue(canvas.adjustMarkupSize(delta: 10, precise: true, at: start, modifiers: []))
        XCTAssertFalse(copy.isEnabled)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(calls, beforeResize + 1)
        XCTAssertEqual(editor.string, "result \(calls)")
        XCTAssertTrue(copy.isEnabled)
        let beforeMove = calls
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        image.mouseDragged(with: try mouse(.leftMouseDragged, at(340, 200)))
        XCTAssertFalse(copy.isEnabled)
        XCTAssertNotEqual(editor.string, "result \(beforeMove)")
        image.mouseUp(with: try mouse(.leftMouseUp, at(340, 200)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotEqual(canvas.marks.first, original)
        XCTAssertEqual(calls, beforeMove + 1)
        XCTAssertEqual(editor.string, "result \(calls)")
    }

    @MainActor
    func testMosaicClearsOldTextAndRerunsRecognitionAfterDrawingAndUndo() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        var calls = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in calls += 1; return "result \(calls)" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        let image = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "ocrText" })
        let copy = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrCopy" })
        XCTAssertEqual(editor.string, "result 1")
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        let start = image.convert(image.displayPoint(for: CGPoint(x: 320, y: 180)), to: nil)
        let end = image.convert(image.displayPoint(for: CGPoint(x: 400, y: 240)), to: nil)
        canvas.updatePointer(at: start)
        let scrollHint = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "mosaicScrollHint" })
        XCTAssertFalse(scrollHint.isHidden)
        XCTAssertTrue(canvas.adjustMosaicSize(delta: 1, precise: false, at: start))
        XCTAssertTrue(scrollHint.isHidden)
        XCTAssertEqual(canvas.mosaicDiameter, 34)
        let textPoint = editor.convert(CGPoint(x: 20, y: 20), to: nil)
        XCTAssertFalse(canvas.adjustMosaicSize(delta: 1, precise: false, at: textPoint))
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        XCTAssertEqual(editor.string, "")
        XCTAssertFalse(copy.isEnabled)
        image.mouseDragged(with: try mouse(.leftMouseDragged, end))
        image.mouseUp(with: try mouse(.leftMouseUp, end))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(editor.string, "result 2")
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolUndo) }).performClick(nil)
        XCTAssertEqual(editor.string, "")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(editor.string, "result 3")
        editor.string = "My edited result"
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        XCTAssertEqual(editor.string, "My edited result")
        XCTAssertFalse(copy.isEnabled)
        image.mouseDragged(with: try mouse(.leftMouseDragged, end))
        image.mouseUp(with: try mouse(.leftMouseUp, end))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(editor.string, "My edited result")
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(copy.isEnabled)
        let warning = try XCTUnwrap(descendants(overlay).compactMap { $0 as? NSTextField }.first {
            !$0.isHidden && $0.stringValue == strings(.ocrEditedImageChanged)
        })
        XCTAssertEqual(warning.textColor, KlikTheme.danger)
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolUndo) }).performClick(nil)
        XCTAssertEqual(editor.string, "My edited result")
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRedo) }).performClick(nil)
        XCTAssertEqual(editor.string, "My edited result")
    }

    @MainActor
    func testRecognitionPageAllowsMarkupAndUndo() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        var outcome: CapturePanel.Outcome?
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in "recognized" }) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        func button(_ key: UIKey, in view: NSView) throws -> NSButton {
            try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(key) })
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 500, y: 50)))
        try button(.toolRectangle, in: toolbar).performClick(nil)
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 180, y: 320)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 260, y: 240)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 260, y: 240)))
        canvas.updatePointer(at: CGPoint(x: 220, y: 280))
        XCTAssertEqual(canvas.pointer, .canvasPoint)
        try button(.toolRecognizeText, in: toolbar).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        XCTAssertNil(all.first { $0.identifier?.rawValue == "ocrBack" })
        let image = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first)
        let markPoint = image.convert(image.displayPoint(for: CGPoint(x: 220, y: 200)), to: nil)
        canvas.updatePointer(at: markPoint)
        XCTAssertEqual(canvas.pointer, .canvasPoint)
        let tools = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        try button(.toolText, in: tools).performClick(nil)
        canvas.updatePointer(at: markPoint)
        XCTAssertEqual(canvas.pointer, .canvasPoint)
        let blankPoint = image.convert(image.displayPoint(for: CGPoint(x: 380, y: 250)), to: nil)
        canvas.updatePointer(at: blankPoint)
        XCTAssertEqual(canvas.pointer, .canvasPoint)
        let color = try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.inkPicker, strings(.inkRed)) })
        color.performClick(nil)
        let palette = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrColorPalette" })
        XCTAssertFalse(palette.isHidden)
        try XCTUnwrap(palette.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.inkBlue) }).performClick(nil)
        XCTAssertTrue(palette.isHidden)
        XCTAssertEqual(color.toolTip, strings(.inkPicker, strings(.inkBlue)))
        let undo = try button(.toolUndo, in: tools)
        XCTAssertTrue(undo.isEnabled, "The initial mark remains editable")
        try button(.toolArrow, in: tools).performClick(nil)
        let start = image.convert(image.displayPoint(for: CGPoint(x: 320, y: 180)), to: nil)
        let end = image.convert(image.displayPoint(for: CGPoint(x: 400, y: 240)), to: nil)
        image.mouseDown(with: try mouse(.leftMouseDown, start))
        image.mouseDragged(with: try mouse(.leftMouseDragged, end))
        image.mouseUp(with: try mouse(.leftMouseUp, end))
        XCTAssertTrue(undo.isEnabled)
        undo.performClick(nil)
        XCTAssertTrue(undo.isEnabled, "The mark added before OCR should remain after undoing the new mark")
        undo.performClick(nil)
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(try button(.toolRedo, in: tools).isEnabled)
        XCTAssertNil(outcome)
    }

    @MainActor
    func testResultSavesByButtonAndCopiesByEnter() async throws {
        _ = NSApplication.shared
        for mode in ["button", "enter", "editing"] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.clearContents()
            XCTAssertTrue(board.setString("original clipboard", forType: .string))
            var saved: Data?
            var outcome: CapturePanel.Outcome?
            let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                     image: try XCTUnwrap(context.makeImage()),
                                     recognizeText: { _ in "recognized" }, saveDownload: { saved = $0 },
                                     pasteboard: board) { outcome = $0 }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
            func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                 windowNumber: panel.windowNumber, context: nil,
                                                 eventNumber: 1, clickCount: 1, pressure: 1))
            }
            func enter(_ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
                try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: panel.windowNumber, context: nil, characters: "\r",
                                               charactersIgnoringModifiers: "\r", isARepeat: false,
                                               keyCode: UInt16(kVK_Return)))
            }
            canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: 100)))
            canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: 100)))
            let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
                .first { $0.toolTip == AppStrings()(.toolRecognizeText) }).performClick(nil)
            try await Task.sleep(for: .milliseconds(50))
            let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let all = descendants(overlay)
            if mode == "button" {
                // Both the dimmed overlay and its underlying canvas must ignore a new drag.
                overlay.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 10, y: 10)))
                overlay.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 60, y: 40)))
                overlay.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 60, y: 40)))
                canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 10, y: 10)))
                canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 60, y: 40)))
                canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 60, y: 40)))
                try XCTUnwrap(all.compactMap { $0 as? NSButton }
                    .first { $0.identifier?.rawValue == "ocrSaveImage" }).performClick(nil)
            } else if mode == "editing" {
                let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }
                    .first { $0.identifier?.rawValue == "ocrText" })
                XCTAssertTrue(panel.makeFirstResponder(editor))
                panel.sendEvent(try enter())
                XCTAssertNil(saved, "Enter inside the editor must not save")
                XCTAssertNil(outcome)
                XCTAssertTrue(editor.string.contains("\n"), editor.string)
                panel.sendEvent(try enter(.command))
            } else {
                panel.sendEvent(try enter())
            }
            try await waitForCaptureExport(canvas)
            let png = try XCTUnwrap(mode == "button" ? saved : board.data(forType: .png), mode)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 300)
            XCTAssertEqual(image.height, 300)
            XCTAssertEqual(outcome, .exported, "Saving must finish successfully")
            if mode == "button" {
                XCTAssertEqual(board.string(forType: .string), "original clipboard")
            } else {
                XCTAssertNil(saved)
            }
        }
    }

    func testLayoutKeepsLandscapeBelowAndPortraitToRightWithinScreen() {
        for screen in [CGSize(width: 1440, height: 900), CGSize(width: 640, height: 480),
                       CGSize(width: 960, height: 540)] {
            let bounds = CGRect(origin: .zero, size: screen)
            for size in [CGSize(width: 900, height: 350), CGSize(width: 350, height: 900),
                         CGSize(width: 1440, height: 900), CGSize(width: 900, height: 900),
                         CGSize(width: 100, height: 500)] {
                let layout = RecognitionLayout.make(bounds: bounds, imageSize: size)
                XCTAssertTrue(bounds.contains(layout.image), "\(screen) \(size): \(layout.image)")
                XCTAssertTrue(bounds.contains(layout.panel), "\(screen) \(size): \(layout.panel)")
                XCTAssertTrue(bounds.contains(layout.toolbar), "\(screen) \(size): \(layout.toolbar)")
                XCTAssertFalse(layout.image.intersects(layout.panel))
                XCTAssertFalse(layout.image.intersects(layout.toolbar))
                XCTAssertFalse(layout.panel.intersects(layout.toolbar))
                XCTAssertEqual(layout.image.size.width, layout.panel.size.width, accuracy: 0.001)
                XCTAssertEqual(layout.image.size.height, layout.panel.size.height, accuracy: 0.001)
                XCTAssertEqual(layout.image.width / layout.image.height,
                               min(2.4, max(0.6, size.width / size.height)), accuracy: 0.001)
                if size.width >= size.height {
                    XCTAssertGreaterThan(layout.toolbar.minY, layout.image.maxY)
                    XCTAssertGreaterThan(layout.panel.minY, layout.toolbar.maxY)
                } else {
                    XCTAssertGreaterThan(layout.panel.minX, layout.image.maxX)
                    XCTAssertGreaterThan(layout.toolbar.minY, layout.image.maxY)
                }
            }
        }
    }

    func testLayoutDoesNotEnlargeNormalSizedScreenshots() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let landscape = RecognitionLayout.make(bounds: bounds, imageSize: CGSize(width: 500, height: 250))
        XCTAssertEqual(landscape.image.size.width, 500, accuracy: 0.001)
        XCTAssertEqual(landscape.image.size.height, 250, accuracy: 0.001)
        let portrait = RecognitionLayout.make(bounds: bounds, imageSize: CGSize(width: 300, height: 500))
        XCTAssertEqual(portrait.image.size.width, 300, accuracy: 0.001)
        XCTAssertEqual(portrait.image.size.height, 500, accuracy: 0.001)
    }

    @MainActor
    func testRecognizesEnglishAndChineseFromRealImage() throws {
        let image = NSImage(size: NSSize(width: 1000, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 180).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 38),
                                                          .foregroundColor: NSColor.black]
        ("Materials science and engineering" as NSString).draw(at: NSPoint(x: 30, y: 100), withAttributes: attributes)
        ("材料科学与工程" as NSString).draw(at: NSPoint(x: 30, y: 35), withAttributes: attributes)
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let result = try TextRecognition.recognize(cgImage)
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Materials"), result)
        XCTAssertTrue(result.contains("材料"), result)
    }

    @MainActor
    func testSelectionRecognitionPreservesClipboardAndCopiesEditedText() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.setString("existing clipboard", forType: .string))
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let source = try XCTUnwrap(context.makeImage())
        var receivedSize: CGSize?
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480), image: source,
                                 recognizeText: { image in
                                     receivedSize = CGSize(width: image.width, height: image.height)
                                     return "Recognized text"
                                 }, pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: 100)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: 100)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        let button = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == AppStrings()(.toolRecognizeText) })
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(receivedSize, CGSize(width: 300, height: 300))
        XCTAssertEqual(board.string(forType: .string), "existing clipboard")
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        let imageCard = try XCTUnwrap(all.compactMap { $0 as? RecognitionImageView }.first { $0.identifier?.rawValue == "ocrImageCard" })
        let resultPanel = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrPanel" })
        XCTAssertGreaterThan(resultPanel.frame.minY, imageCard.frame.maxY)
        XCTAssertEqual(imageCard.frame.size, resultPanel.frame.size)
        XCTAssertEqual(imageCard.layer?.cornerRadius, resultPanel.layer?.cornerRadius)
        let save = try XCTUnwrap(all.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "ocrSaveImage" })
        let markupToolbar = try XCTUnwrap(all.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        XCTAssertTrue(save.superview === markupToolbar)
        for id in ["ocrCancel", "ocrConfirm"] {
            let action = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
            XCTAssertTrue(action.superview === markupToolbar)
            XCTAssertNotNil(action.image)
            XCTAssertTrue(markupToolbar.bounds.contains(action.frame))
        }
        XCTAssertFalse(markupToolbar.frame.intersects(imageCard.frame))
        XCTAssertFalse(markupToolbar.frame.intersects(resultPanel.frame))
        XCTAssertNotNil(save.image)
        XCTAssertNotNil(save.toolTip)
        for id in ["ocrCopy"] {
            let action = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
            XCTAssertTrue(action.superview === resultPanel)
            XCTAssertNotNil(action.image)
            XCTAssertNotNil(action.toolTip)
        }
        let savePoint = save.convert(CGPoint(x: save.bounds.midX, y: save.bounds.midY), to: canvas)
        XCTAssertTrue(overlay.hitTest(savePoint) === save)
        let editorScroll = try XCTUnwrap(all.compactMap { $0 as? NSScrollView }
            .first { $0.identifier?.rawValue == "ocrEditorScroll" })
        XCTAssertEqual(resultPanel.bounds.height - editorScroll.frame.maxY, 42, accuracy: 0.01)
        let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "ocrText" })
        XCTAssertEqual(editor.string, "Recognized text")
        let pointer = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "capturePointer" })
        let buttonPoint = canvas.convert(CGPoint(x: resultPanel.frame.maxX - 60, y: resultPanel.frame.maxY - 22), to: nil)
        canvas.updatePointer(at: buttonPoint, force: true)
        XCTAssertFalse(pointer.isHidden)
        XCTAssertGreaterThan(try XCTUnwrap(canvas.subviews.firstIndex(of: pointer)),
                             try XCTUnwrap(canvas.subviews.firstIndex(of: overlay)))
        let textPoint = editor.convert(CGPoint(x: 20, y: 20), to: nil)
        canvas.updatePointer(at: textPoint)
        XCTAssertFalse(pointer.isHidden)
        editor.string = "Edited result"
        let copy = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrCopy" })
        copy.performClick(nil)
        XCTAssertEqual(board.string(forType: .string), "Edited result")
        XCTAssertNil(outcome)
        XCTAssertNotNil(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
    }

    @MainActor
    func testEscapeCancelsRecognitionAndPreservesClipboard() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.setString("unchanged", forType: .string))
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()),
                                 recognizeText: { _ in "hello" }, pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: 100)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: 100)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == AppStrings()(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                                    keyCode: UInt16(kVK_Escape)))
        panel.sendEvent(escape)
        XCTAssertEqual(board.string(forType: .string), "unchanged")
        XCTAssertEqual(outcome, .cancelled)
    }
    @MainActor
    func testRecognitionToolbarCancelAndConfirm() async throws {
        _ = NSApplication.shared
        for actionID in ["ocrCancel", "ocrConfirm"] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.clearContents()
            XCTAssertTrue(board.setString("unchanged", forType: .string))
            var outcome: CapturePanel.Outcome?
            let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                     image: try XCTUnwrap(context.makeImage()),
                                     recognizeText: { _ in "hello" }, pasteboard: board) { outcome = $0 }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView)
            func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: 100)))
            canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: 100)))
            let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
            try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
                .first { $0.toolTip == AppStrings()(.toolRecognizeText) }).performClick(nil)
            let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
            let tools = try XCTUnwrap(overlay.subviews.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
            let button = try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == actionID })
            button.performClick(nil)
            if actionID == "ocrCancel" {
                XCTAssertEqual(outcome, .cancelled)
                XCTAssertEqual(board.string(forType: .string), "unchanged")
            } else {
                try await waitForCaptureExport(canvas)
                XCTAssertEqual(outcome, .exported)
                XCTAssertNotNil(board.data(forType: .png))
            }
        }
    }

    @MainActor
    func testFailedSaveKeepsOCRAndCanCopyImage() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var outcome: CapturePanel.Outcome?
        let strings = AppStrings(language: .english)
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in "hello" },
                                 saveDownload: { _ in throw CocoaError(.fileWriteNoPermission) },
                                 pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: 100)))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: 100)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(overlay)
        try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrSaveImage" }).performClick(nil)
        try await waitForCaptureExport(canvas)
        XCTAssertNil(outcome)
        XCTAssertNotNil(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        XCTAssertTrue(all.compactMap { $0 as? NSTextField }.contains { $0.stringValue == strings(.downloadError) && !$0.isHidden })
        try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrConfirm" }).performClick(nil)
        try await waitForCaptureExport(canvas)
        XCTAssertEqual(outcome, .exported)
        XCTAssertNotNil(board.data(forType: .png))
    }

    @MainActor
    func testSaveConfirmationDoesNotCaptureMouseOrFocus() async throws {
        _ = NSApplication.shared
        let before = Set(NSApp.windows.map(\.windowNumber))
        SaveConfirmation.show(at: CGRect(x: -2000, y: -2000, width: 33, height: 30))
        let popup = try XCTUnwrap(NSApp.windows.first { !before.contains($0.windowNumber) && $0 is NSPanel } as? NSPanel)
        XCTAssertTrue(popup.ignoresMouseEvents)
        XCTAssertTrue(popup.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(popup.isKeyWindow)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertFalse(popup.isVisible)
    }

    @MainActor
    func testMosaicModesCarryIntoOCRAndRefreshRecognizedText() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        var calls = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in calls += 1; return "result" }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ p: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        let options = try XCTUnwrap(canvas.subviews.compactMap { $0 as? MosaicOptions }.first)
        XCTAssertFalse(options.isHidden)
        try XCTUnwrap(options.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.mosaicBrush) }).performClick(nil)
        XCTAssertTrue(options.isHidden)
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        let image = try XCTUnwrap(overlay.subviews.compactMap { $0 as? RecognitionImageView }.first)
        let tools = try XCTUnwrap(overlay.subviews.first { $0.identifier?.rawValue == "ocrMarkupToolbar" })
        try XCTUnwrap(tools.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        let ocrOptions = try XCTUnwrap(overlay.subviews.compactMap { $0 as? MosaicOptions }.first)
        XCTAssertFalse(ocrOptions.isHidden)
        try XCTUnwrap(ocrOptions.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.mosaicSolid) }).performClick(nil)
        let p = image.convert(image.displayPoint(for: CGPoint(x: 320, y: 180)), to: nil)
        image.mouseDown(with: try event(.leftMouseDown, p))
        image.mouseUp(with: try event(.leftMouseUp, p))
        guard case .mosaic(_, _, let style, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing cover") }
        XCTAssertEqual(style, .solid)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(ocrOptions.isHidden)
        let sample = image.convert(image.displayPoint(for: CGPoint(x: 420, y: 280)), to: nil)
        image.mouseDown(with: try event(.leftMouseDown, sample))
        image.mouseUp(with: try event(.leftMouseUp, sample))
        guard case .mosaic(_, _, let changedStyle, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing recolored stroke") }
        XCTAssertEqual(changedStyle, .manual)
        XCTAssertFalse(ocrOptions.isHidden)
        let eyedropper = try XCTUnwrap(ocrOptions.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.mosaicPickColor) })
        XCTAssertFalse(eyedropper.isHidden)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(calls, 3)
        canvas.recognitionUndo()
        guard case .mosaic(_, _, let restoredStyle, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing original stroke") }
        XCTAssertEqual(restoredStyle, .solid)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(calls, 4)
    }

    @MainActor
    func testPickingFromEarlierCoverUsesVisibleColorInBothViews() async throws {
        _ = NSApplication.shared
        for useOCR in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 320, y: 0, width: 320, height: 480))
            let strings = AppStrings(language: .english)
            let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                     image: try XCTUnwrap(context.makeImage()), strings: strings,
                                     recognizeText: { _ in "result" }) { _ in }
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
            if useOCR {
                try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
                try await Task.sleep(for: .milliseconds(50))
            }
            let overlay = canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" }
            let image = overlay?.subviews.compactMap { $0 as? RecognitionImageView }.first
            let bar = useOCR ? try XCTUnwrap(overlay?.subviews.first { $0.identifier?.rawValue == "ocrMarkupToolbar" }) : toolbar
            try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
            let options = try XCTUnwrap((useOCR ? overlay?.subviews : canvas.subviews)?.compactMap { $0 as? MosaicOptions }.first)
            try XCTUnwrap(options.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.mosaicSolid) }).performClick(nil)
            func mapped(_ p: CGPoint) -> CGPoint { image?.convert(image!.displayPoint(for: p), to: nil) ?? canvas.convert(p, to: nil) }
            let target: NSView = image ?? canvas
            func draw(_ start: CGPoint, _ middle: CGPoint, _ end: CGPoint) throws {
                target.mouseDown(with: try event(.leftMouseDown, mapped(start)))
                target.mouseDragged(with: try event(.leftMouseDragged, mapped(middle), shift: true))
                target.mouseUp(with: try event(.leftMouseUp, mapped(end), shift: true))
            }
            func sample(_ p: CGPoint) throws {
                canvas.updatePointer(at: mapped(p))
                let preview = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "eyedropperPreview" })
                XCTAssertFalse(preview.isHidden)
                XCTAssertNil(preview.hitTest(.zero))
                let previewColor = try XCTUnwrap(preview.layer?.backgroundColor).components!
                target.mouseDown(with: try event(.leftMouseDown, mapped(p)))
                target.mouseUp(with: try event(.leftMouseUp, mapped(p)))
                guard case .mosaic(_, _, .manual, let picked) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("Missing picked color") }
                XCTAssertEqual(previewColor[0], picked.red, accuracy: 0.01)
                XCTAssertEqual(previewColor[1], picked.green, accuracy: 0.01)
                XCTAssertEqual(previewColor[2], picked.blue, accuracy: 0.01)
                XCTAssertTrue(preview.isHidden)
            }
            try draw(CGPoint(x: 150, y: 200), CGPoint(x: 170, y: 220), CGPoint(x: 200, y: 200))
            guard case .mosaic(let points, _, .solid, _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing first stroke") }
            XCTAssertEqual(points.count, 2, "Shift makes a straight mosaic stroke")
            try sample(CGPoint(x: 420, y: 200))
            guard case .mosaic(_, _, .manual, let first) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing first color") }
            XCTAssertGreaterThan(first.red, 0.9)
            try draw(CGPoint(x: 180, y: 200), CGPoint(x: 200, y: 220), CGPoint(x: 220, y: 200))
            try sample(CGPoint(x: 190, y: 200))
            guard case .mosaic(_, _, .manual, let second) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("missing second color") }
            XCTAssertEqual(second.red, first.red, accuracy: 0.02)
            XCTAssertEqual(second.green, first.green, accuracy: 0.02)
            XCTAssertEqual(second.blue, first.blue, accuracy: 0.02)
        }
    }

    @MainActor
    func testMarkupEyedropperWorksInCaptureAndOCR() async throws {
        _ = NSApplication.shared
        for useOCR in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            let strings = AppStrings(language: .english)
            let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                     image: try XCTUnwrap(context.makeImage()), strings: strings,
                                     recognizeText: { _ in "result" }) { _ in }
            defer { panel.orderOut(nil) }
            let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
            func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
            canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
            canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
            let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
            if useOCR {
                try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
                try await Task.sleep(for: .milliseconds(50))
            }
            let overlay = canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" }
            let image = overlay?.subviews.compactMap { $0 as? RecognitionImageView }.first
            let bar = useOCR ? try XCTUnwrap(overlay?.subviews.first { $0.identifier?.rawValue == "ocrMarkupToolbar" }) : toolbar
            try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkPicker, strings(.inkRed)) }).performClick(nil)
            let container = useOCR ? try XCTUnwrap(overlay) : canvas
            let picker = try XCTUnwrap(container.subviews.flatMap { $0.subviews }.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkSample) })
            picker.performClick(nil)
            let penButton = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolPen) })
            penButton.performClick(nil)
            let pointForCheck = image?.convert(image!.displayPoint(for: CGPoint(x: 300, y: 180)), to: nil) ?? canvas.convert(CGPoint(x: 300, y: 180), to: nil)
            canvas.updatePointer(at: pointForCheck)
            XCTAssertNotEqual(canvas.pointer, .eyedropper)
            try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.inkPicker, strings(.inkRed)) }).performClick(nil)
            picker.performClick(nil)
            func mapped(_ p: CGPoint) -> CGPoint { image?.convert(image!.displayPoint(for: p), to: nil) ?? canvas.convert(p, to: nil) }
            let target: NSView = image ?? canvas
            let sample = mapped(CGPoint(x: 300, y: 180))
            canvas.updatePointer(at: sample)
            let preview = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "eyedropperPreview" })
            XCTAssertFalse(preview.isHidden)
            let cursorPoint = canvas.convert(sample, from: nil)
            XCTAssertGreaterThan(preview.frame.minX, cursorPoint.x)
            XCTAssertLessThan(preview.frame.maxY, cursorPoint.y)
            let color = try XCTUnwrap(preview.layer?.backgroundColor).components!
            XCTAssertEqual(color[0], 0.2, accuracy: 0.02)
            XCTAssertEqual(color[1], 0.5, accuracy: 0.02)
            XCTAssertEqual(color[2], 0.8, accuracy: 0.02)
            target.mouseDown(with: try event(.leftMouseDown, sample))
            XCTAssertTrue(preview.isHidden)
            target.mouseUp(with: try event(.leftMouseUp, sample))
            let start = mapped(CGPoint(x: 200, y: 200)), end = mapped(CGPoint(x: 230, y: 200))
            target.mouseDown(with: try event(.leftMouseDown, start))
            target.mouseDragged(with: try event(.leftMouseDragged, end))
            target.mouseUp(with: try event(.leftMouseUp, end))
            guard case .pen(_, .custom(let picked), _) = try XCTUnwrap(canvas.marks.last) else { return XCTFail("Expected a custom-colored pen stroke") }
            XCTAssertEqual(picked.red, 0.2, accuracy: 0.02)
            XCTAssertEqual(picked.green, 0.5, accuracy: 0.02)
            XCTAssertEqual(picked.blue, 0.8, accuracy: 0.02)
        }
    }

    @MainActor
    func testRefreshRecognitionConfirmsEditsAndPreservesThemOnFailure() async throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let strings = AppStrings(language: .english)
        var calls = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: try XCTUnwrap(context.makeImage()), strings: strings,
                                 recognizeText: { _ in
                                     calls += 1
                                     if calls == 3 { throw CocoaError(.fileReadUnknown) }
                                     return "result \(calls)"
                                 }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(overlay)
        let editor = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "ocrText" })
        let refresh = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrRefresh" })
        XCTAssertEqual(editor.string, "result 1")
        refresh.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(panel.attachedSheet)
        XCTAssertEqual(editor.string, "result 2")
        editor.string = "My changes"
        refresh.performClick(nil)
        XCTAssertNil(panel.attachedSheet)
        let confirmation = try XCTUnwrap(descendants(overlay).first { $0.identifier?.rawValue == "ocrRefreshConfirmation" })
        XCTAssertFalse(confirmation.isHidden)
        XCTAssertTrue(descendants(confirmation).compactMap { $0 as? NSTextField }.contains { $0.stringValue == strings(.ocrReplaceTitle) })
        let cancel = try XCTUnwrap(descendants(confirmation).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrRefreshCancel" })
        let replace = try XCTUnwrap(descendants(confirmation).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrRefreshReplace" })
        XCTAssertLessThanOrEqual(confirmation.frame.width, 196)
        XCTAssertEqual(confirmation.frame.height, 64)
        XCTAssertEqual(cancel.frame.midY, replace.frame.midY, accuracy: 0.01)
        XCTAssertLessThanOrEqual(cancel.frame.maxX, replace.frame.minX)
        XCTAssertTrue(confirmation.bounds.contains(cancel.frame))
        XCTAssertTrue(confirmation.bounds.contains(replace.frame))
        let cancelPoint = cancel.convert(CGPoint(x: cancel.bounds.midX, y: cancel.bounds.midY), to: nil)
        XCTAssertTrue(canvas.hitTest(cancelPoint) === cancel)
        cancel.performClick(nil)
        XCTAssertTrue(confirmation.isHidden)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(editor.string, "My changes")
        refresh.performClick(nil)
        XCTAssertFalse(confirmation.isHidden)
        let replacePoint = replace.convert(CGPoint(x: replace.bounds.midX, y: replace.bounds.midY), to: nil)
        XCTAssertTrue(canvas.hitTest(replacePoint) === replace)
        replace.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(editor.string, "My changes")
        XCTAssertTrue(editor.isEditable)
        XCTAssertTrue(refresh.isEnabled)
        refresh.performClick(nil)
        replace.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(editor.string, "result 4")
    }

    @MainActor
    func testEditedOCRRemainsUsableAfterChangingMosaicDuringRefresh() async throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(CaptureImage.bitmap(width: 640, height: 480)?.makeImage())
        let strings = AppStrings(language: .english)
        var calls = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: image, strings: strings,
                                 recognizeText: { _ in
                                     calls += 1
                                     if calls == 2 { try await Task.sleep(for: .seconds(2)) }
                                     return "Recognized text"
                                 }) { _ in }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 400)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 500, y: 50)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 500, y: 50)))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0 is NSVisualEffectView })
        try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolRecognizeText) }).performClick(nil)
        let overlay = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "ocrOverlay" })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(overlay)
        let editor = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "ocrText" })
        let refresh = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrRefresh" })
        let replace = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrRefreshReplace" })
        let copy = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "ocrCopy" })
        for _ in 0..<100 where !refresh.isEnabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(editor.string, "Recognized text")
        editor.string = "My edits"
        refresh.performClick(nil)
        replace.performClick(nil)
        for _ in 0..<100 where calls < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(editor.isEditable)
        XCTAssertFalse(refresh.isEnabled)

        try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.toolTip == strings(.toolMosaic) }).performClick(nil)
        let imageView = try XCTUnwrap(views.compactMap { $0 as? RecognitionImageView }.first)
        let start = imageView.convert(imageView.displayPoint(for: CGPoint(x: 200, y: 130)), to: nil)
        let end = imageView.convert(imageView.displayPoint(for: CGPoint(x: 280, y: 170)), to: nil)
        imageView.mouseDown(with: try event(.leftMouseDown, start))
        imageView.mouseDragged(with: try event(.leftMouseDragged, end))
        imageView.mouseUp(with: try event(.leftMouseUp, end))
        XCTAssertEqual(canvas.marks.count, 1)
        await Task.yield()
        XCTAssertEqual(editor.string, "My edits")
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(editor.isEditable, "Editing should be restored when the old recognition is cancelled")
        XCTAssertTrue(refresh.isEnabled, "The replacement action should be available again")
        editor.string = "Edited again"
        refresh.performClick(nil)
        replace.performClick(nil)
        for _ in 0..<100 where !refresh.isEnabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(editor.string, "Recognized text")
    }

}
