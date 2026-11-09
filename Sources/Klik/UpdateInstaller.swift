import CryptoKit
import Foundation

/// Downloads and prepares a verified release before handing the swap to a small
/// helper. The running app stays untouched until it has exited.
enum UpdateInstaller {
    struct Prepared {
        let app: URL
        let staged: URL
        let backup: URL
    }

    static func prepare(_ asset: UpdateChecker.Asset, version: String, app: URL) async throws -> Prepared {
        let fm = FileManager.default
        let parent = app.deletingLastPathComponent()
        guard app.pathExtension == "app", fm.isWritableFile(atPath: parent.path) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var request = URLRequest(url: asset.url, timeoutInterval: 90)
        request.setValue("Klik-Updater", forHTTPHeaderField: "User-Agent")
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? fm.removeItem(at: download) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == asset.sha256 else { throw URLError(.cannotDecodeContentData) }

        let temporary = fm.temporaryDirectory.appendingPathComponent("klik-update-\(UUID().uuidString)", isDirectory: true)
        let mount = temporary.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, download.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let candidate = mount.appendingPathComponent("Klik.app", isDirectory: true)
        guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.trimmingCharacters(in: CharacterSet(charactersIn: "v")) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try run("/usr/bin/codesign", ["--verify", "--strict", candidate.path])
        let suffix = UUID().uuidString
        let staged = parent.appendingPathComponent(".Klik-update-\(suffix).app")
        let backup = parent.appendingPathComponent(".Klik-backup-\(suffix).app")
        do {
            try fm.copyItem(at: candidate, to: staged)
            try run("/usr/bin/codesign", ["--verify", "--strict", staged.path])
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return Prepared(app: app, staged: staged, backup: backup)
    }

    static func installAfterExit(_ prepared: Prepared) throws {
        // Paths are arguments rather than interpolated shell text. Keep the old
        // app until the replacement has been placed and Launch Services accepts it.
        let script = #"""
        pid="$1"; app="$2"; staged="$3"; backup="$4"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        if ! /bin/mv "$app" "$backup"; then /bin/rm -rf "$staged"; /usr/bin/open -n "$app"; exit 1; fi
        if ! /bin/mv "$staged" "$app"; then /bin/mv "$backup" "$app"; /usr/bin/open -n "$app"; exit 1; fi
        if /usr/bin/open -n "$app"; then
          /bin/rm -rf "$backup"
        else
          /bin/mv "$app" "$staged"
          /bin/mv "$backup" "$app"
          /usr/bin/open -n "$app"
          /bin/rm -rf "$staged"
        fi
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "klik-updater", String(ProcessInfo.processInfo.processIdentifier), prepared.app.path, prepared.staged.path, prepared.backup.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
    }
}
