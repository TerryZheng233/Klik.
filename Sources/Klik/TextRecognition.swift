import CoreGraphics
import Vision

enum TextRecognition {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["en-US", "zh-Hans"].filter { supported.contains($0) }
        request.automaticallyDetectsLanguage = true
        // Scientific names, symbols and identifiers should not be silently corrected.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

/// Keeps Vision requests serial, so obsolete large recognitions cannot accumulate.
actor TextRecognitionWorker {
    static let shared = TextRecognitionWorker()
    private var previous: Task<Void, Never>?
    private let perform: @Sendable (CGImage) throws -> String

    init(perform: @escaping @Sendable (CGImage) throws -> String = { try TextRecognition.recognize($0) }) {
        self.perform = perform
    }

    func recognize(_ image: CGImage) async throws -> String {
        let predecessor = previous
        let perform = perform
        let operation = Task.detached(priority: .userInitiated) {
            await predecessor?.value
            try Task.checkCancellation()
            return try perform(image)
        }
        previous = Task.detached { _ = try? await operation.value }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
}
