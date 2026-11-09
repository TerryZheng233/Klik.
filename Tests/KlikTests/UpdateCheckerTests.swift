import XCTest
@testable import Klik

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() {
        func payload(_ tag: String) -> Data { Data("{\"tag_name\":\"\(tag)\"}".utf8) }
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.17"), status: 200, currentVersion: "0.1.16"), .available("v0.1.17"))
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.10"), status: 200, currentVersion: "0.1.9"), .available("v0.1.10"))
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.16"), status: 200, currentVersion: "0.1.16"), .upToDate)
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.9"), status: 200, currentVersion: "0.1.16"), .upToDate)
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v1.0"), status: 200, currentVersion: "1.0.0"), .upToDate)
    }

    func testErrorsAndInvalidVersionAreNotReportedAsUpToDate() {
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(), status: 404, currentVersion: "0.1.16"), .unavailable)
        XCTAssertEqual(UpdateChecker.evaluate(data: Data("{}".utf8), status: 200, currentVersion: "0.1.16"), .unavailable)
        XCTAssertEqual(UpdateChecker.evaluate(data: Data("{\"tag_name\":\"v0.1.17-beta\"}".utf8), status: 200, currentVersion: "0.1.16"), .unavailable)
    }
}
