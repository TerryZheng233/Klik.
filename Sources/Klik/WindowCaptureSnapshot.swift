import CoreGraphics

// A failed early capture stays a failure: silently recapturing after activation
// would produce an image with the wrong focus state.
struct WindowCaptureSnapshot {
    private let images: [CGWindowID: Result<CGImage, Error>]

    static func prepare(ids: [CGWindowID], capture: (CGWindowID) async throws -> CGImage) async -> Self {
        var images: [CGWindowID: Result<CGImage, Error>] = [:]
        for id in ids where images[id] == nil {
            do { images[id] = .success(try await capture(id)) }
            catch { images[id] = .failure(error) }
        }
        return Self(images: images)
    }

    func image(for id: CGWindowID, otherwise capture: () async throws -> CGImage) async throws -> CGImage {
        if let saved = images[id] { return try saved.get() }
        return try await capture()
    }
}
