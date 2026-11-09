import AppKit
import XCTest
@testable import Klik

final class CaptureHistoryTests: XCTestCase {
    func testHistoryPersistsRespectsLimitAndClearsOnlyItsOwnFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KlikHistoryTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CaptureHistory(directory: directory)
        for index in 0..<12 {
            try history.record(Data([UInt8(index)]))
        }
        let reloaded = CaptureHistory(directory: directory)
        var entries = try reloaded.entries()
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(entries.first)), Data([11]))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(entries.last)), Data([2]))

        reloaded.limit = 5
        try reloaded.enforceLimit()
        entries = try reloaded.entries()
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(entries.last)), Data([7]))

        let unrelated = directory.appendingPathComponent("other.txt")
        try Data("keep".utf8).write(to: unrelated)
        try reloaded.clear()
        XCTAssertTrue(try reloaded.entries().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testHistoryDatesUseTodayYesterdayAndOlderDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        func url(daysAgo: Int) -> URL {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            return URL(fileURLWithPath: "capture-\(Int64(date.timeIntervalSince1970 * 1_000_000))-id.png")
        }
        for (language, today, yesterday) in [(InterfaceLanguage.english, "Today", "Yesterday"),
                                             (.simplifiedChinese, "今天", "昨天")] {
            let strings = AppStrings(language: language)
            XCTAssertTrue(HistoryDateFormatter.label(for: url(daysAgo: 0), strings: strings, now: now, calendar: calendar).hasPrefix(today))
            XCTAssertTrue(HistoryDateFormatter.label(for: url(daysAgo: 1), strings: strings, now: now, calendar: calendar).hasPrefix(yesterday))
            let older = HistoryDateFormatter.label(for: url(daysAgo: 2), strings: strings, now: now, calendar: calendar)
            XCTAssertFalse(older.hasPrefix(today))
            XCTAssertFalse(older.hasPrefix(yesterday))
        }
    }

    func testHistoryCopiesImageToIndependentPasteboard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KlikHistoryTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 12, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(CaptureImage.png(image))
        let history = CaptureHistory(directory: directory)
        try history.record(png)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try history.copy(XCTUnwrap(history.entries().first), to: board)
        XCTAssertEqual(board.data(forType: .png), png)
        XCTAssertNotNil(board.data(forType: .tiff))
    }
}
