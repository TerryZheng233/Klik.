import CoreGraphics
import XCTest
@testable import Klik

final class WindowSnapTests: XCTestCase {
    func testTopmostWindowWinsWhereFramesOverlap() {
        let front = WindowSnap(id: 1, frame: CGRect(x: 130, y: 80, width: 220, height: 160))
        let back = WindowSnap(id: 2, frame: CGRect(x: 30, y: 30, width: 260, height: 280))
        let frames = [front, back]
        XCTAssertEqual(WindowSnap.target(at: CGPoint(x: 200, y: 180), in: frames), front)
        XCTAssertEqual(WindowSnap.target(at: CGPoint(x: 100, y: 180), in: frames), back)
        XCTAssertNil(WindowSnap.target(at: CGPoint(x: 500, y: 200), in: frames))
    }

    func testProjectsFullWindowAndFitsItIntoTheCurrentDisplayForPreview() throws {
        let display = CGRect(x: -1920, y: -320, width: 1920, height: 1080)
        let spanningWindow = CGRect(x: -600, y: -400, width: 800, height: 480)
        let canvas = CGSize(width: 960, height: 540)
        let fullFrame = try XCTUnwrap(WindowSnap.localFrame(spanningWindow, display: display, canvasSize: canvas))
        XCTAssertEqual(fullFrame, CGRect(x: 660, y: -40, width: 400, height: 240))
        let target = WindowSnap(id: 1, frame: fullFrame)
        XCTAssertEqual(target.previewFrame(in: CGRect(origin: .zero, size: canvas)),
                       CGRect(x: 560, y: 0, width: 400, height: 240))
        XCTAssertNil(WindowSnap.localFrame(CGRect(x: 20, y: 0, width: 500, height: 400),
                                           display: display, canvasSize: canvas))
    }
}
