import CoreGraphics
import XCTest
@testable import Klik

final class WindowCaptureSnapshotTests: XCTestCase {
    func testForegroundImageIsFrozenBeforeFocusChangesAndOtherWindowsRemainCapturable() async throws {
        let active = try image(width: 20)
        let inactive = try image(width: 10)
        var hasFocus = true
        var earlyCalls = 0
        let frozen = await WindowCaptureSnapshot.prepare(ids: [1, 1]) { _ in
            earlyCalls += 1
            return hasFocus ? active : inactive
        }
        hasFocus = false
        let captured = try await frozen.image(for: 1) { inactive }
        XCTAssertEqual(captured.width, 20)
        XCTAssertEqual(earlyCalls, 1)
        let other = try await frozen.image(for: 2) { inactive }
        XCTAssertEqual(other.width, 10)
    }

    func testFailedEarlyCaptureDoesNotSilentlyReturnAnInactiveImage() async throws {
        enum Failure: Error { case unavailable }
        let frozen = await WindowCaptureSnapshot.prepare(ids: [1]) { _ in throw Failure.unavailable }
        var fallbackCalled = false
        do {
            _ = try await frozen.image(for: 1) {
                fallbackCalled = true
                return try self.image(width: 10)
            }
            XCTFail("Expected the original capture failure")
        } catch Failure.unavailable {
            XCTAssertFalse(fallbackCalled)
        }
    }

    private func image(width: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 10,
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
