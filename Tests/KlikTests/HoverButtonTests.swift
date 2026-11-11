import AppKit
import XCTest
@testable import Klik

final class HoverButtonTests: XCTestCase {
    @MainActor
    func testHoverPreservesSelectionAndIgnoresDisabledControls() throws {
        _ = NSApplication.shared
        let button = HoverButton(frame: CGRect(x: 0, y: 0, width: 33, height: 30))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                                                     timestamp: 0, windowNumber: 0, context: nil,
                                                     eventNumber: 0, clickCount: 0, pressure: 0))
        button.mouseEntered(with: event)
        XCTAssertGreaterThan(try XCTUnwrap(button.layer).shadowOpacity, 0)
        XCTAssertEqual(button.layer?.cornerCurve, .continuous)
        button.toolSelected = true
        XCTAssertEqual(button.layer?.backgroundColor, KlikTheme.buttonSelected.cgColor)
        button.mouseExited(with: event)
        XCTAssertEqual(button.layer?.shadowOpacity, 0)
        XCTAssertEqual(button.layer?.backgroundColor, KlikTheme.buttonSelected.cgColor)
        button.toolSelected = false
        button.isEnabled = false
        button.mouseEntered(with: event)
        XCTAssertEqual(button.layer?.shadowOpacity, 0)
    }
}
