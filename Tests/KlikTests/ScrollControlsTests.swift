import AppKit
import Carbon
import XCTest
@testable import Klik

final class ScrollControlsTests: XCTestCase {
    @MainActor
    func testCommandScrollZoomsAtPointerWithoutChangingExportPixels() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        for axis in ScrollAxis.allCases {
            let width = axis == .vertical ? 900 : 1600
            let height = axis == .vertical ? 1600 : 600
            let image = try XCTUnwrap(CaptureImage.bitmap(width: width, height: height)?.makeImage())
            let preview = ScrollCapturePreview(image: image, axis: axis,
                screenFrame: CGRect(x: -3000, y: -3000, width: 900, height: 720),
                strings: AppStrings(language: .english), message: nil)
            defer { preview.orderOut(nil) }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let root = try XCTUnwrap(preview.contentView)
            let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
            let clip = scroll.contentView
            let canvas = try XCTUnwrap(scroll.documentView as? CaptureView)
            let anchor = CGPoint(x: clip.bounds.midX, y: clip.bounds.midY)
            let windowPoint = clip.convert(anchor, to: nil)
            func wheel(_ steps: Int32, flags: CGEventFlags = .maskCommand) throws {
                let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                    wheel1: steps, wheel2: 0, wheel3: 0))
                let global = preview.convertPoint(toScreen: windowPoint)
                event.location = CGPoint(x: global.x, y: screen.frame.maxY - global.y)
                event.flags = flags
                preview.sendEvent(try XCTUnwrap(NSEvent(cgEvent: event)))
            }

            try wheel(2, flags: [])
            XCTAssertEqual(scroll.magnification, 1)
            try wheel(2, flags: .maskAlternate)
            XCTAssertEqual(scroll.magnification, 1)
            let before = canvas.convert(windowPoint, from: nil)
            try wheel(2)
            XCTAssertGreaterThan(scroll.magnification, 1)
            let after = canvas.convert(windowPoint, from: nil)
            XCTAssertEqual(after.x, before.x, accuracy: 1)
            XCTAssertEqual(after.y, before.y, accuracy: 1)

            var exported: CGImage?
            preview.onExport = { _, image in exported = image }
            canvas.export(.clipboard)
            let output = try XCTUnwrap(exported)
            XCTAssertEqual(output.width, width)
            XCTAssertEqual(output.height, height)

            try wheel(-2)
            XCTAssertEqual(scroll.magnification, 1, accuracy: 0.01)
            try wheel(-20)
            XCTAssertEqual(scroll.magnification, scroll.minMagnification)
            for _ in 0..<3 { try wheel(20) }
            XCTAssertEqual(scroll.magnification, scroll.maxMagnification)
        }
    }

    @MainActor
    func testPreviewShowsSizeGestureHint() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        for language in [InterfaceLanguage.english, .simplifiedChinese] {
            let preview = ScrollCapturePreview(image: image, axis: .vertical,
                screenFrame: CGRect(x: -3000, y: -3000, width: 1440, height: 900),
                strings: AppStrings(language: language), message: nil)
            defer { preview.orderOut(nil) }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let label = try XCTUnwrap(descendants(try XCTUnwrap(preview.contentView)).compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == "scrollPreviewSizeHint" })
            XCTAssertFalse(label.isHidden)
            XCTAssertGreaterThanOrEqual(label.frame.width, label.intrinsicContentSize.width)
        }
    }
    @MainActor
    func testEscapeHotKeyIsReleasedWhenScrollingEnds() throws {
        _ = NSApplication.shared
        let screen = CGRect(x: -3000, y: -3000, width: 1000, height: 800)
        let session = ScrollCaptureSession(selection: CGRect(x: 200, y: 200, width: 550, height: 365),
                                           screenFrame: screen, visibleFrame: screen,
                                           strings: AppStrings(language: .english),
                                           record: { _ in }, finish: {})
        session.start { _ in throw CocoaError(.userCancelled) }
        let escape = CaptureShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0, keyLabel: "Esc")
        let other = try GlobalHotKey(action: {})
        XCTAssertThrowsError(try other.register(escape))
        session.close()
        XCTAssertNoThrow(try other.register(escape))
    }

    @MainActor
    func testScrollControlsAppearInsideVisibleScreenAndCancel() async throws {
        _ = NSApplication.shared
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let screen = CGRect(x: -3000, y: -3000, width: 1000, height: 800)
        let visible = screen.insetBy(dx: 0, dy: 20)
        var finished = false
        let session = ScrollCaptureSession(selection: CGRect(x: 200, y: 200, width: 550, height: 365),
                                           screenFrame: screen, visibleFrame: visible, strings: AppStrings(language: .english),
                                           record: { _ in }, finish: { finished = true })
        defer { session.close() }
        session.start { _ in throw CocoaError(.userCancelled) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let panel = try XCTUnwrap(NSApp.windows.first { window in
            !existing.contains(window.windowNumber) && window.contentView.map { root in
                descendants(root).contains { $0.identifier?.rawValue == "scrollControlSurface" }
            } == true
        })
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(visible.contains(panel.frame))
        let views = descendants(try XCTUnwrap(panel.contentView))
        let surface = try XCTUnwrap(views.first { $0.identifier?.rawValue == "scrollControlSurface" })
        let status = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(status.alignment, .center)
        XCTAssertEqual(status.frame.midY, surface.bounds.midY, accuracy: 0.5)
        XCTAssertLessThanOrEqual(surface.frame.height, 48)
        let buttons = views.compactMap { $0 as? NSButton }
        let done = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier() == "scrollDone" })
        XCTAssertNotNil(done.image)
        XCTAssertFalse(done.isEnabled, "Done must stay disabled until a scroll is stitched")
        let cancel = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier() == "scrollCancel" })
        XCTAssertNotNil(cancel.image)
        XCTAssertTrue(cancel.isEnabled)
        cancel.performClick(nil)
        XCTAssertTrue(finished)
    }
}
