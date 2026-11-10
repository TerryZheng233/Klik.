import Foundation

struct ScreenshotLocation {
    private let defaults: UserDefaults
    private let bookmarkKey = "screenshotSaveLocationBookmark"
    private let pathKey = "screenshotSaveLocationPath"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isCustom: Bool { defaults.data(forKey: bookmarkKey) != nil }
    var lastKnownPath: String? { defaults.string(forKey: pathKey) }

    func select(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileReadInvalidFileName) }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.path, forKey: pathKey)
    }

    func reset() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
    }

    func resolve() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            return try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try select(url) }
        return url
    }
}
