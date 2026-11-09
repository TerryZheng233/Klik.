import AppKit
import ImageIO
import XCTest
@testable import Klik

final class CaptureTests: XCTestCase {
    func testRetinaCropUsesTopLeftCoordinatesAndNativePixels() throws {
        let source = try makeImage(width: 160, height: 120) { context in
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 60, width: 80, height: 60))
        }
        let background = CaptureImage(image: source, size: CGSize(width: 80, height: 60))
        let selection = CGRect(x: 10, y: 5, width: 20, height: 18)
        let result = try XCTUnwrap(background.render(selection: selection, marks: []))
        XCTAssertEqual(result.width, 40)
        XCTAssertEqual(result.height, 36)
        XCTAssertEqual(try rgba(result, x: 10, y: 10), try rgba(source, x: 30, y: 20))
        XCTAssertGreaterThan(try rgba(result, x: 10, y: 10)[1], 230)
        let png = try XCTUnwrap(CaptureImage.png(result))
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(decoded) as String?, "public.png")
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(decoded, 0, nil)?.width, 40)
    }

    func testMarksUseScreenCoordinatesInsideRetinaCrop() throws {
        let source = try makeImage(width: 240, height: 160) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        }
        let background = CaptureImage(image: source, size: CGSize(width: 120, height: 80))
        let result = try XCTUnwrap(background.render(
            selection: CGRect(x: 20, y: 10, width: 80, height: 60),
            marks: [
                .rectangle(CGRect(x: 30, y: 20, width: 22, height: 15), .red),
                .arrow(CGPoint(x: 60, y: 24), CGPoint(x: 85, y: 24), .red),
                .pen([CGPoint(x: 25, y: 60), CGPoint(x: 45, y: 60)], .blue),
                .text("Hi", CGPoint(x: 55, y: 42), .red)
            ]
        ))
        try assertRed(result, x: 30, y: 20)
        try assertRed(result, x: 100, y: 28)
        let pen = try rgba(result, x: 30, y: 100)
        XCTAssertGreaterThan(pen[2], 220)
        XCTAssertLessThan(pen[0], 100)
        var redTextPixels = 0
        for y in 64..<104 {
            for x in 70..<120 {
                let pixel = try rgba(result, x: x, y: y)
                if pixel[0] > 120 && Int(pixel[0]) > Int(pixel[1]) + 50 { redTextPixels += 1 }
            }
        }
        XCTAssertGreaterThan(redTextPixels, 50)
        XCTAssertEqual(try rgba(result, x: 6, y: 20), [0, 0, 0, 255])
    }

    func testUnmarkedCropPreservesSourceColorSpace() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let source = try XCTUnwrap(context.makeImage())
        let background = CaptureImage(image: source, size: CGSize(width: 16, height: 12))
        let crop = try XCTUnwrap(background.render(
            selection: CGRect(x: 2, y: 3, width: 10, height: 8), marks: []
        ))
        XCTAssertEqual(crop.width, 20)
        XCTAssertEqual(crop.height, 16)
        XCTAssertEqual(crop.colorSpace?.name, colorSpace.name)
        let png = try XCTUnwrap(CaptureImage.png(crop))
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(exported.colorSpace?.name, colorSpace.name)
    }

    func testWindowExportUsesNativePixelsAndMarksAtItsPreviewPosition() throws {
        let source = try makeImage(width: 200, height: 140) { context in
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 140))
        }
        let preview = CGRect(x: 280, y: 190, width: 100, height: 70)
        let window = CaptureImage(image: source, size: preview.size, origin: preview.origin)
        let result = try XCTUnwrap(window.render(
            selection: preview,
            marks: [.pen([CGPoint(x: 300, y: 215), CGPoint(x: 320, y: 215)], .red)]
        ))
        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 140)
        XCTAssertEqual(try rgba(result, x: 180, y: 115), try rgba(source, x: 180, y: 115))
        try assertRed(result, x: 60, y: 50)
    }

    func testMosaicFollowsBrushInsteadOfItsBoundingBox() throws {
        let source = try makeImage(width: 224, height: 224) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            for x in stride(from: 0, to: 224, by: 2) {
                context.fill(CGRect(x: x, y: 0, width: 1, height: 224))
            }
        }
        let background = CaptureImage(image: source, size: CGSize(width: 112, height: 112))
        let result = try XCTUnwrap(background.render(
            selection: CGRect(x: 0, y: 0, width: 112, height: 112),
            marks: [.mosaic([CGPoint(x: 20, y: 20), CGPoint(x: 85, y: 20), CGPoint(x: 85, y: 85)])]
        ))
        XCTAssertEqual(try rgba(result, x: 90, y: 40), try rgba(result, x: 91, y: 40))
        XCTAssertEqual(try rgba(result, x: 170, y: 124), try rgba(result, x: 171, y: 124))
        XCTAssertNotEqual(try rgba(result, x: 90, y: 124), try rgba(result, x: 91, y: 124))
    }

    func testAllEightHandlesResizeFromTheirEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let selection = CGRect(x: 30, y: 30, width: 40, height: 40)
        let results = [
            CGRect(x: 40, y: 42, width: 30, height: 28),
            CGRect(x: 30, y: 42, width: 40, height: 28),
            CGRect(x: 30, y: 42, width: 50, height: 28),
            CGRect(x: 40, y: 30, width: 30, height: 40),
            CGRect(x: 30, y: 30, width: 50, height: 40),
            CGRect(x: 40, y: 30, width: 30, height: 52),
            CGRect(x: 30, y: 30, width: 40, height: 52),
            CGRect(x: 30, y: 30, width: 50, height: 52)
        ]
        for (handle, expected) in zip(Selection.Handle.allCases, results) {
            XCTAssertEqual(Selection.Handle.hit(at: handle.center(in: selection), in: selection), handle)
            XCTAssertEqual(handle.resize(selection, delta: CGPoint(x: 10, y: 12), in: bounds), expected)
        }
        XCTAssertEqual(Selection.Handle.hit(at: CGPoint(x: 40, y: 28), in: selection), .top)
        XCTAssertEqual(Selection.Handle.hit(at: CGPoint(x: 69, y: 61), in: selection), .right)
        XCTAssertEqual(Selection.Handle.hit(at: CGPoint(x: 41, y: 71), in: selection), .bottom)
        XCTAssertEqual(Selection.Handle.hit(at: CGPoint(x: 28, y: 40), in: selection), .left)
        XCTAssertNil(Selection.Handle.hit(at: CGPoint(x: 40, y: 40), in: selection))
        XCTAssertEqual(Selection.Handle.topLeft.resize(selection, delta: CGPoint(x: 100, y: -100), in: bounds),
                       CGRect(x: 62, y: 0, width: 8, height: 70))
        XCTAssertEqual(Selection.move(selection, from: .zero, to: CGPoint(x: 120, y: -120), in: bounds),
                       CGRect(x: 60, y: 0, width: 40, height: 40))
    }

    func testMagnifierSamplesTheActualResizeBoundary() {
        let rect = CGRect(x: 30, y: 40, width: 100, height: 80)
        let offsetPointer = CGPoint(x: 126, y: 76)
        XCTAssertEqual(Selection.Handle.right.boundaryPoint(in: rect, near: offsetPointer),
                       CGPoint(x: 130, y: 76))
        XCTAssertEqual(Selection.Handle.topLeft.boundaryPoint(in: rect, near: offsetPointer),
                       CGPoint(x: 30, y: 40))
        XCTAssertEqual(Selection.Handle.bottom.boundaryPoint(in: rect, near: offsetPointer),
                       CGPoint(x: 126, y: 120))
    }

    func testResizeHoverStaysStableNearTheEdgeBoundary() {
        let selection = CGRect(x: 30, y: 30, width: 40, height: 40)
        let justOutside = CGPoint(x: 40, y: 23)
        XCTAssertNil(Selection.Handle.hit(at: justOutside, in: selection))
        XCTAssertEqual(Selection.Handle.hit(at: justOutside, in: selection, retaining: .top), .top)
        XCTAssertNil(Selection.Handle.hit(at: justOutside, in: selection, retaining: .left))
        XCTAssertNil(Selection.Handle.hit(at: CGPoint(x: 40, y: 21), in: selection, retaining: .top))
    }

    private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try bitmap(width: width, height: height)
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func bitmap(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let context = try bitmap(width: 1, height: 1)
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: 4))
    }

    private func assertRed(_ image: CGImage, x: Int, y: Int, line: UInt = #line) throws {
        let pixel = try rgba(image, x: x, y: y)
        XCTAssertGreaterThan(pixel[0], 200, line: line)
        XCTAssertLessThan(pixel[1], 125, line: line)
    }
}
