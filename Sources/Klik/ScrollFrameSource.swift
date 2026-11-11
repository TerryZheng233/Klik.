import AppKit
import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScrollFrameSource {
    let frames: AsyncThrowingStream<CGImage, Error>
    private let receiver: Receiver
    private let stream: SCStream

    static func make(displayID: CGDirectDisplayID, screenFrame: CGRect, scale: CGFloat,
                     selection: CGRect, excluding windowIDs: Set<CGWindowID>) async throws -> ScrollFrameSource {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              NSScreen.screens.contains(where: {
                  $0.frame == screenFrame && $0.backingScaleFactor == scale
                      && ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
              }) else { throw Failure.display }

        let ownPID = NSRunningApplication.current.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter: SCContentFilter
        if ownApps.isEmpty {
            let ownWindows = content.windows.filter {
                windowIDs.contains($0.windowID) || $0.owningApplication?.processID == ownPID
            }
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        } else {
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        }

        let pixelRect = selection.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = pixelRect.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        configuration.width = Int(pixelRect.width)
        configuration.height = Int(pixelRect.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 4
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        return try ScrollFrameSource(filter: filter, configuration: configuration)
    }

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration) throws {
        let (frames, continuation) = AsyncThrowingStream<CGImage, Error>.makeStream(bufferingPolicy: .bufferingNewest(2))
        self.frames = frames
        receiver = Receiver(continuation: continuation, width: configuration.width, height: configuration.height)
        stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "klik.scroll-frames", qos: .userInitiated))
    }

    func start() async throws { try await stream.startCapture() }

    func finishFrames() { receiver.continuation.finish() }

    func stop() async {
        finishFrames()
        try? await stream.stopCapture()
    }

    private enum Failure: Error { case display, frame }

    private final class Receiver: NSObject, SCStreamOutput, SCStreamDelegate {
        let continuation: AsyncThrowingStream<CGImage, Error>.Continuation
        private let width: Int
        private let height: Int
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        init(continuation: AsyncThrowingStream<CGImage, Error>.Continuation, width: Int, height: Int) {
            self.continuation = continuation
            self.width = width
            self.height = height
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            continuation.finish(throwing: error)
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, sampleBuffer.isValid,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  status == SCFrameStatus.complete.rawValue,
                  let buffer = sampleBuffer.imageBuffer else { return }

            guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
                  let image = copyImage(from: buffer) else {
                continuation.finish(throwing: Failure.frame)
                return
            }
            continuation.yield(image)
        }

        private func copyImage(from buffer: CVPixelBuffer) -> CGImage? {
            guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            // Copy before releasing the sample. The capture stream reuses its IOSurfaces.
            guard let address = CVPixelBufferGetBaseAddress(buffer),
                  let data = CFDataCreate(nil, address.assumingMemoryBound(to: UInt8.self), stride * height),
                  let provider = CGDataProvider(data: data) else { return nil }
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            )
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: stride, space: colorSpace, bitmapInfo: bitmapInfo,
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
