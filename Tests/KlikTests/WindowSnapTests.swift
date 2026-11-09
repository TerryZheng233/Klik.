import CoreGraphics
import XCTest
@testable import Klik

final class WindowSnapTests: XCTestCase {
    func testTopmostWindowWinsWhereFramesOverlap() {
        let front = CGRect(x: 130, y: 80, width: 220, height: 160)
        let back = CGRect(x: 30, y: 30, width: 260, height: 280)
        let frames = [front, back]
        XCTAssertEqual(WindowSnap.target(at: CGPoint(x: 200, y: 180), in: frames), front)
        XCTAssertEqual(WindowSnap.target(at: CGPoint(x: 100, y: 180), in: frames), back)
        XCTAssertNil(WindowSnap.target(at: CGPoint(x: 500, y: 200), in: frames))
    }

    func testClipsAndProjectsWindowToTheCurrentDisplay() {
        let display = CGRect(x: -1920, y: -320, width: 1920, height: 1080)
        let spanningWindow = CGRect(x: -600, y: -400, width: 800, height: 480)
        let canvas = CGSize(width: 960, height: 540)
        XCTAssertEqual(WindowSnap.localFrame(spanningWindow, display: display, canvasSize: canvas),
                       CGRect(x: 660, y: 0, width: 300, height: 200))
        XCTAssertNil(WindowSnap.localFrame(CGRect(x: 20, y: 0, width: 500, height: 400),
                                           display: display, canvasSize: canvas))
    }
}
