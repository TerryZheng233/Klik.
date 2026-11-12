import AppKit
import XCTest
@testable import Klik

@MainActor
func waitForCaptureExport(_ view: NSView) async throws {
    let canvas = try XCTUnwrap(view as? CaptureView)
    for _ in 0..<500 {
        if !canvas.isExporting { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Export did not finish")
}
