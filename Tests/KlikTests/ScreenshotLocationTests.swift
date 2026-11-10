import Foundation
import XCTest
@testable import Klik

final class ScreenshotLocationTests: XCTestCase {
    func testSelectedFolderPersistsSavesAndResets() throws {
        let suite = "KlikLocationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let location = ScreenshotLocation(defaults: defaults)
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        XCTAssertEqual(try location.resolve().standardizedFileURL, downloads.standardizedFileURL)
        try location.select(temp)
        let persisted = ScreenshotLocation(defaults: defaults)
        XCTAssertEqual(try persisted.resolve().resolvingSymlinksInPath(), temp.resolvingSymlinksInPath())
        let content = Data([1, 2, 3])
        try CaptureDownload.save(content, location: persisted)
        let files = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: files[0]), content)
        try FileManager.default.removeItem(at: temp)
        XCTAssertThrowsError(try CaptureDownload.save(content, location: persisted))
        persisted.reset()
        XCTAssertEqual(try persisted.resolve().standardizedFileURL, downloads.standardizedFileURL)
    }
}
