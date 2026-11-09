import XCTest
@testable import Klik

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() {
        func payload(_ tag: String) -> Data { Data("{\"tag_name\":\"\(tag)\"}".utf8) }
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.17"), status: 200, currentVersion: "0.1.16"), .available("v0.1.17", nil))
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.10"), status: 200, currentVersion: "0.1.9"), .available("v0.1.10", nil))
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.16"), status: 200, currentVersion: "0.1.16"), .upToDate)
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v0.1.9"), status: 200, currentVersion: "0.1.16"), .upToDate)
        XCTAssertEqual(UpdateChecker.evaluate(data: payload("v1.0"), status: 200, currentVersion: "1.0.0"), .upToDate)
    }

    func testDownloadOnlyUsesTheExpectedReleaseAsset() {
        let url = "https://github.com/TerryZheng233/Klik./releases/download/v0.1.17/Klik-0.1.17-arm64.dmg"
        let payload = """
        {"tag_name":"v0.1.17","assets":[{"name":"Klik-0.1.17-arm64.dmg","browser_download_url":"\(url)","digest":"sha256:0909166ddb44b21e8adab1c0c6cba8fe2744da3775870bd8db9741210ccce1d2"},{"name":"Klik-0.1.17-arm64.dmg.sig","browser_download_url":"\(url).sig"}]}
        """
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(payload.utf8), status: 200, currentVersion: "0.1.16"), .available("v0.1.17", UpdateChecker.Asset(url: URL(string: url)!, sha256: "0909166ddb44b21e8adab1c0c6cba8fe2744da3775870bd8db9741210ccce1d2", signatureURL: URL(string: url + ".sig")!)))
        let unsafe = payload.replacingOccurrences(of: "github.com", with: "example.com")
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(unsafe.utf8), status: 200, currentVersion: "0.1.16"), .available("v0.1.17", nil))
        let noSignature = """
        {"tag_name":"v0.1.17","assets":[{"name":"Klik-0.1.17-arm64.dmg","browser_download_url":"\(url)","digest":"sha256:0909166ddb44b21e8adab1c0c6cba8fe2744da3775870bd8db9741210ccce1d2"}]}
        """
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(noSignature.utf8), status: 200, currentVersion: "0.1.16"), .available("v0.1.17", nil))
        let unsafeSignature = payload.replacingOccurrences(of: "\(url).sig", with: "https://example.com/evil.sig")
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(unsafeSignature.utf8), status: 200, currentVersion: "0.1.16"), .available("v0.1.17", nil))
    }

    func testErrorsAndInvalidVersionAreNotReportedAsUpToDate() {
        XCTAssertEqual(UpdateChecker.evaluate(data: Data(), status: 404, currentVersion: "0.1.16"), .unavailable)
        XCTAssertEqual(UpdateChecker.evaluate(data: Data("{}".utf8), status: 200, currentVersion: "0.1.16"), .unavailable)
        XCTAssertEqual(UpdateChecker.evaluate(data: Data("{\"tag_name\":\"v0.1.17-beta\"}".utf8), status: 200, currentVersion: "0.1.16"), .unavailable)
    }
}
