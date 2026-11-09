import AppKit

/// A newly installed build acknowledges a successful launch to the updater.
enum UpdateStartup {
    static let argument = "--klik-update-confirm"
    static let prefix = ".Klik-update-ready-"

    static func markerURL(arguments: [String], app: URL) -> URL? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        let token = arguments[index + 1]
        guard token.hasPrefix(prefix), UUID(uuidString: String(token.dropFirst(prefix.count))) != nil else { return nil }
        return app.deletingLastPathComponent().appendingPathComponent(token)
    }

    @MainActor
    static func confirmAfterStartup() {
        guard let marker = markerURL(arguments: ProcessInfo.processInfo.arguments, app: Bundle.main.bundleURL) else { return }
        // Wait for initialization and the event loop, rather than confirming at process launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            try? Data("ready\n".utf8).write(to: marker, options: [.withoutOverwriting])
        }
    }
}
