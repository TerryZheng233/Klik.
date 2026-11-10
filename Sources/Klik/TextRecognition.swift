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
