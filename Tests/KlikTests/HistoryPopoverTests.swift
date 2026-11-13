import AppKit
import XCTest
@testable import Klik

final class HistoryPopoverTests: XCTestCase {
    @MainActor
    func testHoverRevealsOnlyTheCurrentRowsActionsAndCopiesItsImage() async throws {
        try await withHistoryPopover { popover, history, pasteboard in
            let (first, second) = try historyRows(in: popover)
            let firstCopy = try button("copyHistory:", in: first)
            let firstDelete = try button("deleteHistory:", in: first)
            let secondCopy = try button("copyHistory:", in: second)
            let secondDelete = try button("deleteHistory:", in: second)
            let firstDate = try timestamp(in: first)
            let secondDate = try timestamp(in: second)
            let firstDateText = firstDate.stringValue
            XCTAssertTrue(firstCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(secondCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(firstDate.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(secondDate.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(firstDate.alignment, .right)
            XCTAssertEqual(firstDate.textColor, KlikTheme.historyTimestamp)
            let scroll = try XCTUnwrap(first.enclosingScrollView)
            scroll.mouseMoved(with: try hoverEvent(over: first))
            XCTAssertFalse(firstCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(firstDelete.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(secondCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(firstDate.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(secondDate.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(firstDelete.contentTintColor, KlikTheme.danger)

            scroll.mouseMoved(with: try hoverEvent(over: second))
            XCTAssertTrue(firstCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(secondCopy.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(firstDate.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(firstDate.stringValue, firstDateText)
            XCTAssertTrue(secondDate.isHiddenOrHasHiddenAncestor)
            let content = try XCTUnwrap(popover.contentViewController?.view)
            content.layoutSubtreeIfNeeded()
            let copyFrame = secondCopy.convert(secondCopy.bounds, to: content)
            let deleteFrame = secondDelete.convert(secondDelete.bounds, to: content)
            XCTAssertGreaterThan(copyFrame.width, 0)
            XCTAssertLessThan(copyFrame.maxX, deleteFrame.minX)
            XCTAssertEqual(deleteFrame.maxX, second.convert(second.bounds, to: content).maxX, accuracy: 0.5)
            let dateFrame = secondDate.convert(secondDate.bounds, to: content)
            XCTAssertGreaterThanOrEqual(secondDate.bounds.width, secondDate.intrinsicContentSize.width)
            XCTAssertTrue(deleteFrame.contains(NSPoint(x: dateFrame.maxX, y: dateFrame.midY)))
            let point = NSPoint(x: copyFrame.midX, y: copyFrame.midY)
            XCTAssertTrue(content.hitTest(content.convert(point, to: content.superview)) === secondCopy)
            secondCopy.performClick(nil)
            let entries = try history.entries()
            let expected = try Data(contentsOf: XCTUnwrap(entries.last))
            for _ in 0..<100 where pasteboard.data(forType: .png) == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(pasteboard.data(forType: .png), expected)
            XCTAssertNotNil(pasteboard.data(forType: .tiff))
            XCTAssertEqual(try history.entries(), entries)
        }
    }

    @MainActor
    func testScrollingUpdatesTheHoveredRowUnderAStationaryPointer() async throws {
        try await withHistoryPopover(count: 8) { popover, _, _ in
            let content = try XCTUnwrap(popover.contentViewController?.view)
            let scroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
            XCTAssertTrue(try XCTUnwrap(scroll.window).acceptsMouseMovedEvents)
            let rows = try XCTUnwrap(scroll.documentView).subviews
            XCTAssertEqual(rows.count, 8)
            let event = try hoverEvent(over: rows[1])
            scroll.mouseEntered(with: event)

            @MainActor func visibleActions() throws -> [Int] {
                try rows.indices.filter { index in
                    let copy = try button("copyHistory:", in: rows[index])
                    let delete = try button("deleteHistory:", in: rows[index])
                    let date = try timestamp(in: rows[index])
                    let hovered = !copy.isHiddenOrHasHiddenAncestor
                    XCTAssertEqual(date.isHiddenOrHasHiddenAncestor, hovered)
                    XCTAssertEqual(delete.isHiddenOrHasHiddenAncestor, !hovered)
                    return hovered
                }
            }

            XCTAssertEqual(try visibleActions(), [1])
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 104))
            XCTAssertEqual(try visibleActions(), [3])
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 156))
            XCTAssertEqual(try visibleActions(), [4])
            scroll.mouseExited(with: event)
            XCTAssertEqual(try visibleActions(), [])
        }
    }

    @MainActor
    func testSingleDeleteAndClearUseTextConfirmationAndPreviewMatchesTheList() async throws {
        try await withHistoryPopover { popover, history, _ in
            let strings = KlikPreferences().strings
            let entries = try history.entries()
            let (first, _) = try historyRows(in: popover)
            let listCopy = try button("copyHistory:", in: first)
            let listDelete = try button("deleteHistory:", in: first)
            var content = try XCTUnwrap(popover.contentViewController?.view)
            let clear = try button("clearHistory:", in: content)
            XCTAssertNotEqual(clear.contentTintColor, KlikTheme.danger)
            for control in [clear, try button("openSettings", in: content), try button("terminate:", in: content)] {
                XCTAssertEqual(control.imagePosition, .imageOnly)
                XCTAssertNotNil(control.image)
                XCTAssertFalse(control.toolTip?.isEmpty ?? true)
            }

            try button("showHistoryPreview:", in: first).performClick(nil)
            content = try XCTUnwrap(popover.contentViewController?.view)
            let previewCopy = try button("copyHistory:", in: content)
            let previewDelete = try button("deleteHistory:", in: content)
            XCTAssertEqual(try XCTUnwrap(previewCopy.image?.tiffRepresentation),
                           try XCTUnwrap(listCopy.image?.tiffRepresentation))
            XCTAssertEqual(try XCTUnwrap(previewDelete.image?.tiffRepresentation),
                           try XCTUnwrap(listDelete.image?.tiffRepresentation))
            XCTAssertEqual(previewDelete.contentTintColor, KlikTheme.danger)
            XCTAssertFalse(previewDelete.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(try button("backToHistory", in: content).imagePosition, .imageOnly)
            try button("backToHistory", in: content).performClick(nil)

            let (_, remainingSecond) = try historyRows(in: popover)
            try XCTUnwrap(remainingSecond.enclosingScrollView).mouseMoved(with: try hoverEvent(over: remainingSecond))
            let delete = try button("deleteHistory:", in: remainingSecond)
            delete.performClick(nil)
            XCTAssertEqual(try history.entries(), entries)
            assertConfirmation(delete, strings: strings)
            delete.performClick(nil)
            XCTAssertEqual(try history.entries(), [try XCTUnwrap(entries.first)])

            content = try XCTUnwrap(popover.contentViewController?.view)
            let clearRemaining = try button("clearHistory:", in: content)
            clearRemaining.performClick(nil)
            XCTAssertEqual(try history.entries().count, 1)
            assertConfirmation(clearRemaining, strings: strings)
            clearRemaining.performClick(nil)
            XCTAssertTrue(try history.entries().isEmpty)
            content = try XCTUnwrap(popover.contentViewController?.view)
            XCTAssertFalse(try button("clearHistory:", in: content).isEnabled)
        }
    }

    @MainActor
    private func withHistoryPopover(
        count: Int = 2,
        _ check: (NSPopover, CaptureHistory, NSPasteboard) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CaptureHistory(directory: directory)
        for index in 0..<count {
            let width = 16 + index * 8
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 12, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            try history.record(XCTUnwrap(CaptureImage.png(XCTUnwrap(context.makeImage()))))
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let delegate = AppDelegate(history: history, historyPasteboard: pasteboard)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 100, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = try XCTUnwrap(window.contentView)
        window.orderFront(nil)
        let popover = delegate.showStatusPopover(relativeTo: anchor)
        defer {
            popover.close()
            delegate.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
            window.close()
        }
        XCTAssertTrue(popover.isShown)
        try await check(popover, history, pasteboard)
    }

    @MainActor
    private func historyRows(in popover: NSPopover) throws -> (NSView, NSView) {
        let content = try XCTUnwrap(popover.contentViewController?.view)
        let scroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
        let rows = try XCTUnwrap(scroll.documentView).subviews
        XCTAssertEqual(rows.count, 2)
        return (try XCTUnwrap(rows.first), try XCTUnwrap(rows.last))
    }

    @MainActor
    private func button(_ action: String, in view: NSView) throws -> NSButton {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString(action)
        }, "Missing button for \(action)")
    }

    @MainActor
    private func timestamp(in row: NSView) throws -> NSTextField {
        let preview = try button("showHistoryPreview:", in: row)
        return try XCTUnwrap(preview.subviews.compactMap { $0 as? NSTextField }.first)
    }

    @MainActor
    private func assertConfirmation(_ button: NSButton, strings: AppStrings,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(button.imagePosition, .noImage, file: file, line: line)
        XCTAssertEqual(button.title, strings(.menuHistoryConfirmClear), file: file, line: line)
        XCTAssertEqual(button.contentTintColor, KlikTheme.danger, file: file, line: line)
    }

    @MainActor
    private func hoverEvent(over row: NSView) throws -> NSEvent {
        let point = row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                                         timestamp: 0, windowNumber: row.window?.windowNumber ?? 0, context: nil,
                                         eventNumber: 0, clickCount: 0, pressure: 0))
    }
}
