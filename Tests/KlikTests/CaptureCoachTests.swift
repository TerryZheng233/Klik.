import CoreGraphics
import XCTest
@testable import Klik

final class CaptureCoachTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)

    func testCoachGoesOutsideTheSelectionWhenThereIsRoom() throws {
        let selection = CGRect(x: 380, y: 80, width: 300, height: 260)
        let toolbar = CGRect(x: 320, y: 349, width: 360, height: 40)
        let palette = CGRect(x: 400, y: 395, width: 226, height: 35)
        let coach = try XCTUnwrap(CaptureCoach.placement(toolbar: toolbar, palette: palette,
                                                         selection: selection, in: screen))
        XCTAssertGreaterThan(coach.minY, palette.maxY)
        XCTAssertTrue(screen.contains(coach))
    }

    func testCoachCanMoveAboveTheToolbarNearTheBottomEdge() throws {
        let selection = CGRect(x: 400, y: 340, width: 400, height: 190)
        let toolbar = CGRect(x: 436, y: 539, width: 360, height: 40)
        let coach = try XCTUnwrap(CaptureCoach.placement(toolbar: toolbar, palette: nil,
                                                         selection: selection, in: screen))
        XCTAssertLessThan(coach.maxY, toolbar.minY)
        XCTAssertTrue(screen.contains(coach))
    }
}
