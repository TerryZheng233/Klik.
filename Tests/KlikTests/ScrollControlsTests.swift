import AppKit
import XCTest
@testable import Klik

final class ScrollControlsTests: XCTestCase {
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
        let buttons = views.compactMap { $0 as? NSButton }
        let done = try XCTUnwrap(buttons.first { $0.title == AppStrings(language: .english)(.done) })
        XCTAssertFalse(done.isEnabled, "Done must stay disabled until a scroll is stitched")
        let cancel = try XCTUnwrap(buttons.first { $0.title == AppStrings(language: .english)(.cancel) })
        XCTAssertTrue(cancel.isEnabled)
        cancel.performClick(nil)
        XCTAssertTrue(finished)
    }
}
