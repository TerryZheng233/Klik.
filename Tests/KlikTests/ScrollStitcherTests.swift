import AppKit
import CoreGraphics
import CoreText
import XCTest
@testable import Klik

final class ScrollStitcherTests: XCTestCase {
    private let width = 180
    private let viewportHeight = 240

    func testBottomCompletionRequiresMatchingFrontierAndAppendsOnlySelectedRows() throws {
        let document = try page(height: 900)
        let expanded = try crop(document, y: 71, height: viewportHeight + 110)
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 0, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.append(try crop(document, y: 71, height: viewportHeight)), .extended)
        XCTAssertEqual(stitcher.availableRows(at: .bottom, from: expanded), 110)
        XCTAssertEqual(stitcher.extendEdge(.bottom, from: try crop(document, y: 83, height: viewportHeight + 110), extraRows: 85), .unaligned)
        XCTAssertEqual(stitcher.append(try crop(document, y: 20, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.extendEdge(.bottom, from: expanded, extraRows: 85), .unaligned)
        XCTAssertEqual(stitcher.append(try crop(document, y: 71, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.extendEdge(.bottom, from: expanded, extraRows: 85), .extended)
        let expected = try crop(document, y: 0, height: viewportHeight + 71 + 85)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())), CaptureImage.png(expected))
    }

    func testTopCompletionPrependsOnlySelectedRowsInOrder() throws {
        let document = try page(height: 900)
        let expanded = try crop(document, y: 0, height: viewportHeight + 100)
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 171, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.append(try crop(document, y: 100, height: viewportHeight)), .extended)
        XCTAssertEqual(stitcher.availableRows(at: .top, from: expanded), 100)
        let misaligned = try crop(document, y: 8, height: viewportHeight + 100)
        XCTAssertEqual(stitcher.extendEdge(.top, from: misaligned, extraRows: 65), .unaligned)
        XCTAssertEqual(stitcher.extendEdge(.top, from: expanded, extraRows: 65), .extended)
        let expected = try crop(document, y: 35, height: viewportHeight + 71 + 65)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())), CaptureImage.png(expected))
    }

    func testStitchesAtOriginalResolutionWithAnExactFinalOffset() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        for (offset, expected): (Int, ScrollStitcher.Update) in [
            (0, .waiting), (0, .waiting), (71, .extended), (211, .extended),
            (260, .extended), (266, .waiting)
        ] {
            XCTAssertEqual(stitcher.append(try crop(document, y: offset, height: viewportHeight)), expected,
                           "offset \(offset)")
        }
        XCTAssertEqual(stitcher.append(try crop(document, y: 266, height: viewportHeight), final: true), .extended)
        let image = try XCTUnwrap(stitcher.render())
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, 506)
        XCTAssertEqual(CaptureImage.png(image), CaptureImage.png(try crop(document, y: 0, height: 506)))
    }

    func testFixedHeaderAndFooterAppearOnlyOnce() throws {
        let document = try page(height: 520)
        let top = 29
        let bottom = 34
        let bodyHeight = viewportHeight - top - bottom
        func framed(_ body: CGImage) throws -> CGImage {
            let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: top + body.height + bottom))
            context.setFillColor(red: 0.04, green: 0.32, blue: 0.68, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: context.height))
            context.setFillColor(red: 0.94, green: 0.23, blue: 0.08, alpha: 1)
            context.fill(CGRect(x: 0, y: bottom + body.height, width: width, height: top))
            context.draw(body, in: CGRect(x: 0, y: bottom, width: width, height: body.height))
            return try XCTUnwrap(context.makeImage())
        }
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try framed(crop(document, y: 0, height: bodyHeight))), .waiting)
        for offset in [83, 159, 201] {
            XCTAssertEqual(stitcher.append(try framed(crop(document, y: offset, height: bodyHeight))), .extended)
        }
        let expected = try framed(crop(document, y: 0, height: bodyHeight + 201))
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())), CaptureImage.png(expected))
    }

    func testJumpAndReverseDoNotChangeTheImageAndScrollingCanRecover() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        func frame(_ offset: Int) throws -> CGImage { try crop(document, y: offset, height: viewportHeight) }
        XCTAssertEqual(stitcher.append(try frame(0)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(65)), .extended)
        XCTAssertEqual(stitcher.append(try frame(12)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(390)), .unaligned)
        XCTAssertEqual(stitcher.length, viewportHeight + 65)
        XCTAssertEqual(stitcher.append(try frame(65)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(128)), .extended)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 0, height: viewportHeight + 128)))
    }

    func testPeriodicContentWithSeveralPossibleOffsetsIsRejected() throws {
        let document = try page(height: 500, repeatingEvery: 40)
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 0, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.append(try crop(document, y: 53, height: viewportHeight)), .unaligned)
        XCTAssertEqual(stitcher.length, viewportHeight)
    }

    func testTextInOneColumnMatchesAcrossBlankMargins() throws {
        let height = 850
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (index, name) in ["Almond", "Bamboo", "Chestnut", "Dogwood", "Elm", "Fir", "Ginkgo", "Holly",
                              "Ivy", "Juniper", "Kauri", "Larch", "Maple", "Nutmeg", "Oak", "Pine",
                              "Quince", "Redwood", "Spruce", "Tamarind", "Umbrella", "Willow", "Yew"].enumerated() {
            let attributed = NSAttributedString(string: "\(index + 1). \(name)",
                                                 attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 17, y: height - 23 - index * 33)
            CTLineDraw(line, context)
        }
        let document = try XCTUnwrap(context.makeImage())
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 0, height: viewportHeight)), .waiting)
        for offset in [64, 171, 322, 455] {
            XCTAssertEqual(stitcher.append(try crop(document, y: offset, height: viewportHeight)), .extended,
                           "offset \(offset)")
        }
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 0, height: viewportHeight + 455)))
    }

    func testBrightnessChangeAndAnimatedPatchStillAlign() throws {
        let document = try page(height: 600)
        let original = try crop(document, y: 0, height: viewportHeight)
        let shifted = try crop(document, y: 86, height: viewportHeight)
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: viewportHeight))
        let bounds = CGRect(x: 0, y: 0, width: width, height: viewportHeight)
        context.draw(shifted, in: bounds)
        context.setFillColor(gray: 1, alpha: 0.025)
        context.fill(bounds)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 100, y: 82, width: 52, height: 72))
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(original), .waiting)
        XCTAssertEqual(stitcher.append(try XCTUnwrap(context.makeImage())), .extended)
        XCTAssertEqual(stitcher.length, viewportHeight + 86)
    }

    func testExtendsBothEndsOfOneVerticalImage() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (240, .waiting), (340, .extended), (428, .extended), (350, .waiting), (230, .extended),
            (188, .extended), (80, .extended), (219, .waiting), (344, .waiting), (460, .extended)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try crop(document, y: position, height: viewportHeight)), expected,
                           "position \(position)")
        }
        XCTAssertEqual(stitcher.axis, .vertical)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 80, height: viewportHeight + 380)))
    }

    func testReversingKeepsSmallExtensionsAtBothEnds() throws {
        let document = try page(height: 700)
        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (120, .waiting), (180, .extended), (185, .waiting), (171, .extended),
            (110, .extended), (105, .waiting), (128, .extended)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try crop(document, y: position, height: viewportHeight)), expected,
                           "position \(position)")
        }
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 105, height: viewportHeight + 80)))
    }

    func testLocksHorizontalAxisAndExtendsInBothDirections() throws {
        let portrait = try page(height: 900)
        let context = try XCTUnwrap(CaptureImage.bitmap(width: portrait.height, height: portrait.width))
        context.translateBy(x: CGFloat(context.width), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(portrait, in: CGRect(x: 0, y: 0, width: portrait.width, height: portrait.height))
        let document = try XCTUnwrap(context.makeImage())
        func frame(_ offset: Int, width: Int = 240) throws -> CGImage {
            try XCTUnwrap(document.cropping(to: CGRect(x: offset, y: 0, width: width, height: document.height)))
        }

        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (300, .waiting), (245, .extended), (111, .extended), (230, .waiting), (350, .extended),
            (477, .extended), (370, .waiting), (257, .waiting)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try frame(position)), expected, "position \(position)")
        }
        XCTAssertEqual(stitcher.axis, .horizontal)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try frame(111, width: 477 - 111 + 240)))
    }

    @MainActor
    func testScrollSessionEnablesDoneAndOpensFullSizePreview() async throws {
        try await checkScrollSessionPreview(extending: nil)
    }

    @MainActor
    func testScrollSessionCanMoveBottomSelectionAndConfirmWithEnter() async throws {
        try await checkScrollSessionPreview(extending: .bottom, confirmWithEnter: true)
    }

    @MainActor
    func testScrollSessionCanConfirmWithCheckOnMovingSelectionEdge() async throws {
        try await checkScrollSessionPreview(extending: .bottom)
    }

    @MainActor
    func testScrollSessionCanExtendUpAndConfirmOnTopEdge() async throws {
        try await checkScrollSessionPreview(extending: .top)
    }

    @MainActor
    func testInterruptedScrollKeepsAlreadyMatchedPendingRows() async throws {
        _ = NSApplication.shared
        let document = try page(height: 900)
        let first = try crop(document, y: 0, height: viewportHeight)
        let second = try crop(document, y: 71, height: viewportHeight)
        let pending = try crop(document, y: 77, height: viewportHeight)
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(first), .waiting)
        XCTAssertEqual(stitcher.append(second), .extended)
        XCTAssertEqual(stitcher.append(pending), .waiting)
        XCTAssertEqual(stitcher.append(pending, final: true), .extended)
        let expected = try XCTUnwrap(stitcher.render()).height
        XCTAssertEqual(expected, viewportHeight + 77)

        let source = FixtureScrollSource([first, second])
        let strings = AppStrings(language: .english)
        let screen = CGRect(x: -3000, y: -3000, width: 1000, height: 800)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let session = ScrollCaptureSession(
            selection: CGRect(x: 100, y: 100, width: width, height: viewportHeight),
            screenFrame: screen, visibleFrame: screen, strings: strings,
            record: { _ in XCTFail("Preview should not write history") }, finish: {})
        defer { session.close() }
        func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views(in: $0) } }
        func visibleViews() -> [NSView] {
            NSApp.windows.filter { $0.isVisible && !existing.contains($0.windowNumber) }
                .compactMap(\.contentView).flatMap { views(in: $0) }
        }

        session.start { _ in source }
        let done = try XCTUnwrap(visibleViews().compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "scrollDone" })
        for _ in 0..<200 where !done.isEnabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(done.isEnabled)
        source.send(pending)
        source.fail()
        for _ in 0..<200 where !visibleViews().compactMap({ $0 as? NSTextField })
            .contains(where: { $0.stringValue == strings(.scrollSourceFailed) }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(visibleViews().compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == strings(.scrollSourceFailed) })
        done.performClick(nil)
        for _ in 0..<200 where !visibleViews().contains(where: { $0.identifier?.rawValue == "scrollPreviewSurface" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let preview = try XCTUnwrap(visibleViews().first { $0.identifier?.rawValue == "scrollPreviewSurface" })
        let window = try XCTUnwrap(preview.window as? ScrollCapturePreview)
        var exported: CGImage?
        window.onExport = { _, image in exported = image }
        let save = try XCTUnwrap(views(in: preview).compactMap { $0 as? NSButton }
            .first { $0.toolTip == strings(.toolDownload) })
        save.performClick(nil)
        let image = try XCTUnwrap(exported)
        XCTAssertEqual(image.height, expected)
        XCTAssertEqual(CaptureImage.png(image), CaptureImage.png(try crop(document, y: 0, height: expected)))
    }

    @MainActor
    private func checkScrollSessionPreview(extending edge: ScrollVerticalEdge?, confirmWithEnter: Bool = false) async throws {
        _ = NSApplication.shared
        let document = try page(height: 900)
        let upward = edge == .top
        let direction = upward ? 1 : -1
        let selectionTop: CGFloat = upward ? 140 : 100
        let edgeOrigin = upward ? 100 : 71
        let first = try crop(document, y: edgeOrigin + direction * 71, height: viewportHeight)
        let second = try crop(document, y: edgeOrigin, height: viewportHeight)
        let expanded = try crop(document, y: upward ? 0 : edgeOrigin, height: viewportHeight + 100)
        let source = FixtureScrollSource([first, second], extensionFrame: expanded)
        let strings = AppStrings(language: .english)
        let screen = CGRect(x: -3000, y: -3000, width: 1000, height: 800)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let session = ScrollCaptureSession(
            selection: CGRect(x: 100, y: selectionTop, width: CGFloat(width), height: CGFloat(viewportHeight)),
            screenFrame: screen, visibleFrame: screen, strings: strings,
            record: { _ in XCTFail("Preview should not write history") },
            finish: { XCTFail("Completing capture should open a preview") }
        )
        defer { session.close() }

        func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func visibleSurface(_ identifier: String) -> NSView? {
            NSApp.windows.lazy.filter { $0.isVisible && !existing.contains($0.windowNumber) }
                .compactMap(\.contentView).flatMap { views(in: $0) }
                .first { $0.identifier?.rawValue == identifier }
        }
        func wait<T>(for value: () -> T?) async throws -> T {
            let deadline = ContinuousClock.now + .seconds(3)
            while ContinuousClock.now < deadline {
                if let result = value() { return result }
                try await Task.sleep(for: .milliseconds(20))
            }
            return try XCTUnwrap(value(), "Timed out waiting for scroll capture state")
        }

        session.start { _ in source }
        let controls = try XCTUnwrap(visibleSurface("scrollControlSurface"))
        let done = try XCTUnwrap(views(in: controls).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "scrollDone" })
        let status = try XCTUnwrap(views(in: controls).compactMap { $0 as? NSTextField }.first)
        XCTAssertFalse(done.isEnabled)
        _ = try await wait { done.isEnabled ? true : nil }
        if let edge {
            func extendButton() -> NSButton? {
                NSApp.windows.lazy.filter { $0.isVisible && !existing.contains($0.windowNumber) }
                    .compactMap(\.contentView).flatMap { views(in: $0) }
                    .compactMap { $0 as? NSButton }
                    .first { $0.accessibilityIdentifier() == "scrollExtend" }
            }
            let insideSelection = CGPoint(x: screen.minX + 150, y: screen.maxY - selectionTop - 50)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertNil(extendButton(), "A pause alone must not show completion")
            let progressFrame = try XCTUnwrap(controls.window?.frame)
            let doneFrame = done.frame
            session.observeVerticalScroll(CGFloat(direction * 20), at: insideSelection)
            let bottom = try await wait(for: extendButton)
            let pulseKey = "klik.extendAttention"
            let pulseStart = bottom.layer?.animation(forKey: pulseKey)?.beginTime
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                XCTAssertNil(pulseStart)
            } else {
                XCTAssertNotNil(pulseStart)
            }
            XCTAssertEqual(bottom.title, "Extend")
            let reached = edge == .top ? UIKey.scrollTopReached : .scrollBottomReached
            XCTAssertEqual(bottom.accessibilityLabel(), strings(edge == .top ? .scrollTopStart : .scrollBottomStart))
            XCTAssertEqual(status.stringValue, strings(reached))
            XCTAssertEqual(controls.window?.frame, progressFrame)
            XCTAssertEqual(done.frame, doneFrame)
            XCTAssertEqual(done.toolTip, strings(.done))
            let doneIcon = try XCTUnwrap(done.image)
            let extendFrame = try XCTUnwrap(bottom.window?.frame)
            XCTAssertEqual(extendFrame.midX, screen.minX + 100 + CGFloat(width) / 2, accuracy: 0.5)
            XCTAssertEqual(extendFrame.midY, screen.maxY - selectionTop - (upward ? 0 : CGFloat(viewportHeight)))
            let bitmap = try XCTUnwrap(bottom.bitmapImageRepForCachingDisplay(in: bottom.bounds))
            bottom.cacheDisplay(in: bottom.bounds, to: bitmap)
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)).alphaComponent, 0.1)
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)).alphaComponent, 0.9)
            session.observeVerticalScroll(CGFloat(-direction * 2), at: insideSelection)
            source.send(try crop(document, y: edgeOrigin + direction * 10, height: viewportHeight))
            try await Task.sleep(for: .milliseconds(220))
            XCTAssertTrue(extendButton() === bottom, "A small bounce at the end keeps Extend visible")
            let awayFromEdge = try crop(document, y: edgeOrigin + direction * 26, height: viewportHeight)
            source.send(awayFromEdge)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(extendButton() === bottom, "A brief excursion does not hide Extend")
            source.send(second)
            try await Task.sleep(for: .milliseconds(220))
            XCTAssertTrue(extendButton() === bottom, "Returning to the edge cancels hiding")
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(status.stringValue, strings(reached))
            XCTAssertEqual(bottom.window?.frame, extendFrame)
            if let activePulse = bottom.layer?.animation(forKey: pulseKey) {
                XCTAssertEqual(activePulse.beginTime, pulseStart, "Further scrolling must not restart the pulse")
            }
            source.send(awayFromEdge)
            _ = try await wait { extendButton() == nil ? true : nil }
            XCTAssertEqual(status.stringValue, strings(.scrollProgress, viewportHeight + 71))
            source.send(second)
            try await Task.sleep(for: .milliseconds(150))
            session.observeVerticalScroll(CGFloat(direction * 20), at: insideSelection)
            _ = try await wait(for: extendButton)
            bottom.performClick(nil)
            let selection = try await wait { visibleSurface("scrollExtensionSelection") }
            XCTAssertTrue(extendButton() === bottom)
            XCTAssertNil(bottom.layer?.animation(forKey: pulseKey))
            XCTAssertTrue(bottom.title.isEmpty)
            XCTAssertEqual(bottom.accessibilityLabel(), strings(.scrollBottomApply))
            XCTAssertEqual(status.stringValue, strings(.scrollBottomInstructions))
            XCTAssertEqual(controls.window?.frame, progressFrame)
            XCTAssertEqual(done.frame, doneFrame)
            XCTAssertEqual(done.toolTip, strings(.scrollBottomApply))
            XCTAssertTrue(done.image === doneIcon)
            XCTAssertEqual(source.capturedEdge, edge)
            let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                              wheel1: Int32(direction * 100), wheel2: 0, wheel3: 0))
            selection.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
            XCTAssertEqual(controls.window?.frame, progressFrame)
            XCTAssertEqual(try XCTUnwrap(bottom.window?.frame.midY), extendFrame.midY + CGFloat(direction * 100),
                           accuracy: 0.5)
            if confirmWithEnter {
                let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: selection.window?.windowNumber ?? 0, context: nil,
                    characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                selection.window?.sendEvent(enter)
            } else {
                bottom.performClick(nil)
            }
        } else {
            done.performClick(nil)
        }
        let preview = try await wait { visibleSurface("scrollPreviewSurface") }
        XCTAssertNil(visibleSurface("scrollControlSurface"))
        XCTAssertTrue(views(in: preview).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == strings(.scrollDimensions, width, viewportHeight + 71 + (edge == nil ? 0 : 100)) })
    }

    private func crop(_ document: CGImage, y: Int, height: Int) throws -> CGImage {
        try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: y, width: width, height: height)))
    }

    private func page(height: Int, repeatingEvery period: Int? = nil) throws -> CGImage {
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: height))
        for y in 0..<height {
            let row = y % (period ?? height)
            for column in 0..<9 {
                var hash = UInt64(row * 9 + column) &+ 0x9e3779b97f4a7c15
                hash = (hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9
                hash = (hash ^ (hash >> 27)) &* 0x94d049bb133111eb
                let red = CGFloat(hash & 255) / 255
                let green = CGFloat((hash >> 8) & 255) / 255
                let blue = CGFloat((hash >> 16) & 255) / 255
                context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                context.fill(CGRect(x: column * 20, y: height - y - 1, width: 20, height: 1))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
}


@MainActor
private final class FixtureScrollSource: ScrollCaptureFrameSource {
    let frames: AsyncThrowingStream<CGImage, Error>
    private let continuation: AsyncThrowingStream<CGImage, Error>.Continuation
    private let images: [CGImage]
    private let extensionFrame: CGImage?
    private(set) var capturedEdge: ScrollVerticalEdge?

    init(_ images: [CGImage], extensionFrame: CGImage? = nil) {
        (frames, continuation) = AsyncThrowingStream<CGImage, Error>.makeStream()
        self.images = images
        self.extensionFrame = extensionFrame
    }

    func captureEdge(_ edge: ScrollVerticalEdge, through displayY: CGFloat) async throws -> CGImage? {
        capturedEdge = edge
        return extensionFrame
    }

    func start() async throws {
        for image in images { continuation.yield(image) }
    }

    func send(_ image: CGImage) { continuation.yield(image) }
    func fail() { continuation.finish(throwing: CocoaError(.fileReadUnknown)) }

    func finishFrames() { continuation.finish() }
    func stop() async { finishFrames() }
}
