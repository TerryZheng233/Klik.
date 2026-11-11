import CoreGraphics
import CoreText
import XCTest
@testable import Klik

final class ScrollStitcherTests: XCTestCase {
    private let width = 180
    private let viewportHeight = 240

    func testStitchesAtOriginalResolutionWithAnExactFinalOffset() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        for (offset, expected): (Int, ScrollStitcher.Update) in [
            (0, .waiting), (0, .waiting), (71, .extended), (211, .extended),
            (260, .extended), (266, .waiting)
        ] {
            XCTAssertEqual(stitcher.append(try crop(document, y: offset, height: viewportHeight)), expected,
                           "offset \(offset)")
        }
        XCTAssertEqual(stitcher.append(try crop(document, y: 266, height: viewportHeight), final: true), .extended)
        let image = try XCTUnwrap(stitcher.render())
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, 506)
        XCTAssertEqual(CaptureImage.png(image), CaptureImage.png(try crop(document, y: 0, height: 506)))
    }

    func testFixedHeaderAndFooterAppearOnlyOnce() throws {
        let document = try page(height: 520)
        let top = 29
        let bottom = 34
        let bodyHeight = viewportHeight - top - bottom
        func framed(_ body: CGImage) throws -> CGImage {
            let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: top + body.height + bottom))
            context.setFillColor(red: 0.04, green: 0.32, blue: 0.68, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: context.height))
            context.setFillColor(red: 0.94, green: 0.23, blue: 0.08, alpha: 1)
            context.fill(CGRect(x: 0, y: bottom + body.height, width: width, height: top))
            context.draw(body, in: CGRect(x: 0, y: bottom, width: width, height: body.height))
            return try XCTUnwrap(context.makeImage())
        }
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try framed(crop(document, y: 0, height: bodyHeight))), .waiting)
        for offset in [83, 159, 201] {
            XCTAssertEqual(stitcher.append(try framed(crop(document, y: offset, height: bodyHeight))), .extended)
        }
        let expected = try framed(crop(document, y: 0, height: bodyHeight + 201))
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())), CaptureImage.png(expected))
    }

    func testJumpAndReverseDoNotChangeTheImageAndScrollingCanRecover() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        func frame(_ offset: Int) throws -> CGImage { try crop(document, y: offset, height: viewportHeight) }
        XCTAssertEqual(stitcher.append(try frame(0)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(65)), .extended)
        XCTAssertEqual(stitcher.append(try frame(12)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(390)), .unaligned)
        XCTAssertEqual(stitcher.length, viewportHeight + 65)
        XCTAssertEqual(stitcher.append(try frame(65)), .waiting)
        XCTAssertEqual(stitcher.append(try frame(128)), .extended)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 0, height: viewportHeight + 128)))
    }

    func testPeriodicContentWithSeveralPossibleOffsetsIsRejected() throws {
        let document = try page(height: 500, repeatingEvery: 40)
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 0, height: viewportHeight)), .waiting)
        XCTAssertEqual(stitcher.append(try crop(document, y: 53, height: viewportHeight)), .unaligned)
        XCTAssertEqual(stitcher.length, viewportHeight)
    }

    func testTextInOneColumnMatchesAcrossBlankMargins() throws {
        let height = 850
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (index, name) in ["Almond", "Bamboo", "Chestnut", "Dogwood", "Elm", "Fir", "Ginkgo", "Holly",
                              "Ivy", "Juniper", "Kauri", "Larch", "Maple", "Nutmeg", "Oak", "Pine",
                              "Quince", "Redwood", "Spruce", "Tamarind", "Umbrella", "Willow", "Yew"].enumerated() {
            let attributed = NSAttributedString(string: "\(index + 1). \(name)",
                                                 attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 17, y: height - 23 - index * 33)
            CTLineDraw(line, context)
        }
        let document = try XCTUnwrap(context.makeImage())
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(try crop(document, y: 0, height: viewportHeight)), .waiting)
        for offset in [64, 171, 322, 455] {
            XCTAssertEqual(stitcher.append(try crop(document, y: offset, height: viewportHeight)), .extended,
                           "offset \(offset)")
        }
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 0, height: viewportHeight + 455)))
    }

    func testBrightnessChangeAndAnimatedPatchStillAlign() throws {
        let document = try page(height: 600)
        let original = try crop(document, y: 0, height: viewportHeight)
        let shifted = try crop(document, y: 86, height: viewportHeight)
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: viewportHeight))
        let bounds = CGRect(x: 0, y: 0, width: width, height: viewportHeight)
        context.draw(shifted, in: bounds)
        context.setFillColor(gray: 1, alpha: 0.025)
        context.fill(bounds)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 100, y: 82, width: 52, height: 72))
        var stitcher = ScrollStitcher()
        XCTAssertEqual(stitcher.append(original), .waiting)
        XCTAssertEqual(stitcher.append(try XCTUnwrap(context.makeImage())), .extended)
        XCTAssertEqual(stitcher.length, viewportHeight + 86)
    }

    func testExtendsBothEndsOfOneVerticalImage() throws {
        let document = try page(height: 900)
        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (240, .waiting), (340, .extended), (428, .extended), (350, .waiting), (230, .extended),
            (188, .extended), (80, .extended), (219, .waiting), (344, .waiting), (460, .extended)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try crop(document, y: position, height: viewportHeight)), expected,
                           "position \(position)")
        }
        XCTAssertEqual(stitcher.axis, .vertical)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 80, height: viewportHeight + 380)))
    }

    func testReversingKeepsSmallExtensionsAtBothEnds() throws {
        let document = try page(height: 700)
        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (120, .waiting), (180, .extended), (185, .waiting), (171, .extended),
            (110, .extended), (105, .waiting), (128, .extended)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try crop(document, y: position, height: viewportHeight)), expected,
                           "position \(position)")
        }
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try crop(document, y: 105, height: viewportHeight + 80)))
    }

    func testLocksHorizontalAxisAndExtendsInBothDirections() throws {
        let portrait = try page(height: 900)
        let context = try XCTUnwrap(CaptureImage.bitmap(width: portrait.height, height: portrait.width))
        context.translateBy(x: CGFloat(context.width), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(portrait, in: CGRect(x: 0, y: 0, width: portrait.width, height: portrait.height))
        let document = try XCTUnwrap(context.makeImage())
        func frame(_ offset: Int, width: Int = 240) throws -> CGImage {
            try XCTUnwrap(document.cropping(to: CGRect(x: offset, y: 0, width: width, height: document.height)))
        }

        var stitcher = ScrollStitcher()
        let positions: [(Int, ScrollStitcher.Update)] = [
            (300, .waiting), (245, .extended), (111, .extended), (230, .waiting), (350, .extended),
            (477, .extended), (370, .waiting), (257, .waiting)
        ]
        for (position, expected) in positions {
            XCTAssertEqual(stitcher.append(try frame(position)), expected, "position \(position)")
        }
        XCTAssertEqual(stitcher.axis, .horizontal)
        XCTAssertEqual(CaptureImage.png(try XCTUnwrap(stitcher.render())),
                       CaptureImage.png(try frame(111, width: 477 - 111 + 240)))
    }

    private func crop(_ document: CGImage, y: Int, height: Int) throws -> CGImage {
        try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: y, width: width, height: height)))
    }

    private func page(height: Int, repeatingEvery period: Int? = nil) throws -> CGImage {
        let context = try XCTUnwrap(CaptureImage.bitmap(width: width, height: height))
        for y in 0..<height {
            let row = y % (period ?? height)
            for column in 0..<9 {
                var hash = UInt64(row * 9 + column) &+ 0x9e3779b97f4a7c15
                hash = (hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9
                hash = (hash ^ (hash >> 27)) &* 0x94d049bb133111eb
                let red = CGFloat(hash & 255) / 255
                let green = CGFloat((hash >> 8) & 255) / 255
                let blue = CGFloat((hash >> 16) & 255) / 255
                context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                context.fill(CGRect(x: column * 20, y: height - y - 1, width: 20, height: 1))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
}
