import AppKit
import CoreVideo
import XCTest
@testable import Klik

final class OptimizationTests: XCTestCase {
    func testScrollFrameCopyReusesIdenticalPixelsButOwnsChangedBuffers() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 24, kCVPixelFormatType_32BGRA,
                                            nil, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        func fill(_ byte: UInt8) {
            CVPixelBufferLockBaseAddress(frame, [])
            memset(CVPixelBufferGetBaseAddress(frame), Int32(byte),
                   CVPixelBufferGetBytesPerRow(frame) * CVPixelBufferGetHeight(frame))
            CVPixelBufferUnlockBaseAddress(frame, [])
        }
        fill(17)
        let cache = ScrollFrameCopyCache()
        let first = try XCTUnwrap(cache.image(from: frame))
        let duplicate = try XCTUnwrap(cache.image(from: frame))
        XCTAssertTrue(first === duplicate)
        let original = try XCTUnwrap(first.dataProvider?.data) as Data
        fill(42)
        let changed = try XCTUnwrap(cache.image(from: frame))
        XCTAssertFalse(first === changed)
        XCTAssertEqual(try XCTUnwrap(first.dataProvider?.data) as Data, original)
        XCTAssertNotEqual(try XCTUnwrap(changed.dataProvider?.data) as Data, original)
    }


    func testHistoryThumbnailReflectsFileReplacementAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CaptureHistory(directory: directory)
        func png(_ width: Int) throws -> Data {
            let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: 20))
            return try XCTUnwrap(CaptureImage.png(XCTUnwrap(context.makeImage())))
        }
        try history.record(png(20))
        let url = try XCTUnwrap(history.entries().first)
        let first = try XCTUnwrap(history.thumbnail(url))
        XCTAssertEqual(first.size.width, first.size.height)
        XCTAssertEqual(history.thumbnail(url)?.size, first.size)
        try png(40).write(to: url, options: .atomic)
        let updated = try XCTUnwrap(history.thumbnail(url))
        XCTAssertEqual(updated.size.width, updated.size.height * 2)
        try history.remove(url)
        XCTAssertNil(history.thumbnail(url))
    }

    func testOCRWorkerSerializesConcurrentRequests() async throws {
        let bitmap = try XCTUnwrap(CaptureImage.bitmap(width: 20, height: 20))
        let image = try XCTUnwrap(bitmap.makeImage())
        let counter = RecognitionCounter()
        let worker = TextRecognitionWorker { _ in
            counter.begin()
            Thread.sleep(forTimeInterval: 0.04)
            counter.end()
            return "result"
        }
        async let first = worker.recognize(image)
        async let second = worker.recognize(image)
        let values = try await [first, second]
        XCTAssertEqual(values, ["result", "result"])
        XCTAssertEqual(counter.maximum, 1)
    }

    @MainActor
    func testExportRejectsDuplicatesAndCancellationDoesNotCopy() async throws {
        _ = NSApplication.shared
        let bitmap = try XCTUnwrap(CaptureImage.bitmap(width: 640, height: 480))
        let image = try XCTUnwrap(bitmap.makeImage())
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("previous", forType: .string)
        var outcomes: [CapturePanel.Outcome] = []
        var records = 0
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: image, pasteboard: board, recordCapture: { _ in records += 1 }) {
            outcomes.append($0)
        }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let start = CGPoint(x: 40, y: 400), end = CGPoint(x: 400, y: 80)
        canvas.mouseDown(with: try event(.leftMouseDown, start))
        canvas.mouseDragged(with: try event(.leftMouseDragged, end))
        canvas.mouseUp(with: try event(.leftMouseUp, end))
        canvas.export(.clipboard)
        canvas.export(.clipboard)
        try await waitForCaptureExport(canvas)
        XCTAssertEqual(outcomes, [.exported])
        XCTAssertEqual(records, 1)
        XCTAssertNotNil(board.data(forType: .png))

        board.clearContents()
        board.setString("previous", forType: .string)
        outcomes.removeAll()
        canvas.export(.clipboard)
        canvas.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(outcomes, [.cancelled])
        XCTAssertEqual(records, 1)
        XCTAssertEqual(board.string(forType: .string), "previous")
    }
}

private final class RecognitionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peak = 0
    func begin() { lock.lock(); active += 1; peak = max(peak, active); lock.unlock() }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    var maximum: Int { lock.lock(); defer { lock.unlock() }; return peak }
}

extension OptimizationTests {
    func testDownloadStagesUntilCommitAndCleansUpOnCancel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "KlikDownloadTest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let location = ScreenshotLocation(defaults: defaults)
        try location.select(directory)
        let bytes = Data([1, 2, 3, 4])
        var staged: CaptureDownload.Pending? = try CaptureDownload.prepare(bytes, location: location)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)[0].hasSuffix(".tmp"))
        staged = nil
        XCTAssertNil(staged)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let committed = try CaptureDownload.prepare(bytes, location: location)
        try committed.commit()
        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(filenames.count, 1)
        XCTAssertTrue(try XCTUnwrap(filenames.first).hasSuffix(".png"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(XCTUnwrap(filenames.first))), bytes)
    }
}

extension OptimizationTests {
    func testLargeCaptureProducesFullResolutionClipboardFormatsOffMainThread() async throws {
        let bitmap = try XCTUnwrap(CaptureImage.bitmap(width: 4096, height: 3072))
        let colors = [NSColor(calibratedRed: 0.03, green: 0.15, blue: 0.8, alpha: 1).cgColor,
                      NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.12, alpha: 1).cgColor] as CFArray
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                                locations: [0, 1]))
        bitmap.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 4096, y: 3072), options: [])
        let image = try XCTUnwrap(bitmap.makeImage())
        let (result, wasMain) = try await Task.detached(priority: .userInitiated) {
            (try PreparedCaptureExport.make(image: image, destination: .clipboard), currentlyOnMainThread())
        }.value
        XCTAssertFalse(wasMain)
        for data in [result.png, try XCTUnwrap(result.tiff)] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 4096)
            XCTAssertEqual(decoded.height, 3072)
        }
    }
}

extension OptimizationTests {
    @MainActor
    func testExportWaitsForHistoryWithoutAllowingLateCancellation() async throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(CaptureImage.bitmap(width: 640, height: 480)?.makeImage())
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var recording = false
        var outcomes: [CapturePanel.Outcome] = []
        let panel = CapturePanel(frame: CGRect(x: -2000, y: -2000, width: 640, height: 480),
                                 image: image, pasteboard: board, recordCapture: { _ in
            recording = true
            try? await Task.sleep(for: .milliseconds(200))
        }) { outcomes.append($0) }
        defer { panel.orderOut(nil) }
        let canvas = try XCTUnwrap(panel.contentView as? CaptureView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let start = CGPoint(x: 40, y: 400), end = CGPoint(x: 400, y: 80)
        canvas.mouseDown(with: try event(.leftMouseDown, start))
        canvas.mouseDragged(with: try event(.leftMouseDragged, end))
        canvas.mouseUp(with: try event(.leftMouseUp, end))
        canvas.export(.clipboard)
        for _ in 0..<200 where !recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recording)
        XCTAssertTrue(canvas.isExporting)
        canvas.cancel()
        XCTAssertTrue(outcomes.isEmpty)
        try await waitForCaptureExport(canvas)
        XCTAssertEqual(outcomes, [.exported])
    }

    func testHistoryPreviewScalesLargeImageWithoutChangingOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try XCTUnwrap(CaptureImage.bitmap(width: 2400, height: 1600))
        let png = try XCTUnwrap(CaptureImage.png(XCTUnwrap(bitmap.makeImage())))
        let history = CaptureHistory(directory: directory)
        try history.record(png)
        let url = try XCTUnwrap(history.entries().first)
        let preview = try XCTUnwrap(history.preview(url, maxPixelSize: 400))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 400)
        XCTAssertEqual(try Data(contentsOf: url), png)
    }
}

private func currentlyOnMainThread() -> Bool { Thread.isMainThread }

extension OptimizationTests {
    func testClearingHistoryWhileImageWritesDoesNotRestoreIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = expectation(description: "write started")
        let allowWrite = DispatchSemaphore(value: 0)
        let history = CaptureHistory(directory: directory, writeData: { data, url in
            started.fulfill()
            guard allowWrite.wait(timeout: .now() + 3) == .success else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url, options: .atomic)
        })
        let record = Task.detached { try history.record(Data(repeating: 3, count: 1024)) }
        await fulfillment(of: [started], timeout: 2)
        try history.clear()
        allowWrite.signal()
        try await record.value
        XCTAssertTrue(try history.entries().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
