import Foundation
import XCTest
@testable import Klik

final class UpdateInstallerTests: XCTestCase {
    func testStartupMarkerCannotEscapeApplicationDirectory() {
        let app = URL(fileURLWithPath: "/Applications/Klik.app")
        let token = UpdateStartup.prefix + UUID().uuidString
        XCTAssertEqual(UpdateStartup.markerURL(arguments: ["Klik", UpdateStartup.argument, token], app: app)?.path,
                       "/Applications/" + token)
        XCTAssertNil(UpdateStartup.markerURL(arguments: ["Klik", UpdateStartup.argument, "../../other"], app: app))
        XCTAssertNil(UpdateStartup.markerURL(arguments: ["Klik", UpdateStartup.argument], app: app))
    }

    func testBackupIsRemovedOnlyAfterStartupConfirmation() throws {
        try exerciseHelper(mode: .ready)
    }

    func testEarlyCrashRestoresPreviousApp() throws {
        try exerciseHelper(mode: .crash)
    }

    func testSlowUnconfirmedLaunchKeepsBackup() throws {
        try exerciseHelper(mode: .slow)
    }

    private enum LaunchMode { case ready, crash, slow }

    private func exerciseHelper(mode: LaunchMode) throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("klik-helper-test-\(UUID())")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Klik.app")
        let staged = directory.appendingPathComponent("staged.app")
        let backup = directory.appendingPathComponent("backup.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try "old".write(to: app.appendingPathComponent("kind"), atomically: true, encoding: .utf8)
        try "new".write(to: staged.appendingPathComponent("kind"), atomically: true, encoding: .utf8)
        let opener = directory.appendingPathComponent("open-test")
        let script: String
        switch mode {
        case .ready:
            script = #"""
            #!/bin/sh
            if [ "$2" = -W ]; then touch "${3%/*}/$6"; sleep 2; fi
            exit 0
            """#
        case .crash:
            script = #"""
            #!/bin/sh
            if [ "$2" = -W ]; then exit 1; fi
            exit 0
            """#
        case .slow:
            script = #"""
            #!/bin/sh
            if [ "$2" = -W ]; then sleep 2; fi
            exit 0
            """#
        }
        try script.write(to: opener, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: opener.path)
        let token = UpdateStartup.prefix + UUID().uuidString
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", UpdateInstaller.helperScript, "test", "99999999", app.path, staged.path, backup.path, opener.path, token, mode == .slow ? "3" : "30"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("kind"), encoding: .utf8), mode == .crash ? "old" : "new")
        XCTAssertEqual(process.terminationStatus, mode == .ready ? 0 : 1)
        XCTAssertEqual(fm.fileExists(atPath: backup.path), mode == .slow)
    }
}
