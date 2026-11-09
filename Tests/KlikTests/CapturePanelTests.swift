import AppKit
import Carbon
import ImageIO
import XCTest
@testable import Klik

final class CapturePanelTests: XCTestCase {
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
        var outcome: CapturePanel.Outcome?
        let panel = CapturePanel(frame: CGRect(x: -2_000, y: -2_000, width: 640, height: 480),
                                 image: image, pasteboard: board) { outcome = $0 }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView)
        let point = CGPoint(x: 300, y: 240)
        for count in 1...2 {
            canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: panel, count: count))
            canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, in: panel, count: count))
        }
        XCTAssertEqual(outcome, .exported)
        XCTAssertNotNil(board.data(forType: .png))
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

    private func space(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: " ",
                                      charactersIgnoringModifiers: " ", isARepeat: false,
                                      keyCode: UInt16(kVK_Space)))
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in panel: NSWindow,
                       count: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
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
