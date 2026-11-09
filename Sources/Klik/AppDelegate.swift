import AppKit
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = KlikPreferences()
    private var hotKey: GlobalHotKey?
    private var setup: ShortcutSetup?
    private var captureTask: Task<Void, Never>?
    private var overlay: CapturePanel?
    private var previousForegroundApp: NSRunningApplication?
    private var presentingAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        var shortcutIssue: Error?
        do {
            try enableShortcut(preferences.shortcut)
        } catch {
            shortcutIssue = error
        }
        if preferences.savedShortcut == nil || shortcutIssue != nil {
            showSetup(issue: shortcutIssue)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if overlay == nil, captureTask == nil, !presentingAlert { showSetup() }
        return false
    }

    private func enableShortcut(_ shortcut: CaptureShortcut) throws {
        if hotKey == nil {
            hotKey = try GlobalHotKey { [weak self] in
                guard let self else { return }
                guard self.overlay == nil, self.captureTask == nil, !self.presentingAlert else { return }
                if self.setup == nil, self.preferences.savedShortcut == nil { self.showSetup() }
                if self.setup?.handleRegisteredShortcut(self.preferences.shortcut) == true { return }
                self.beginCapture()
            }
        }
        try hotKey?.register(shortcut)
    }

    @MainActor
    private func showSetup(issue: Error? = nil) {
        if let setup {
            setup.present()
            return
        }
        let controller = ShortcutSetup(
            shortcut: preferences.shortcut, firstRun: preferences.savedShortcut == nil, issue: issue,
            language: preferences.language,
            changeLanguage: { [weak self] language in self?.preferences.language = language },
            startPractice: { [weak self] guide in self?.beginCapture(practice: guide) },
            save: { [weak self] shortcut in
                guard let self else { return }
                try self.enableShortcut(shortcut)
                try self.preferences.save(shortcut)
            },
            didClose: { [weak self] in self?.setup = nil }
        )
        setup = controller
        controller.present()
    }

    func applicationDidResignActive(_ notification: Notification) {
        if captureTask == nil, overlay?.isVisible == true { closeCapture(restoreFocus: false) }
    }

    @MainActor
    private func beginCapture(practice: ShortcutSetup? = nil) {
        guard overlay == nil, captureTask == nil, !presentingAlert else { return }
        let strings = preferences.strings

        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            presentingAlert = true
            if practice != nil { NSApp.activate() }
            let alert = NSAlert()
            alert.messageText = strings(.permissionTitle)
            alert.informativeText = practice == nil
                ? strings(.permissionBody, preferences.shortcut.title(using: strings))
                : strings(.practicePermissionBody)
            alert.addButton(withTitle: strings(.openSystemSettings))
            alert.addButton(withTitle: strings(.cancel))
            if alert.runModal() == .alertFirstButtonReturn,
               let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(settings)
            }
            presentingAlert = false
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            showAlert(strings(.displayUnavailable), strings(.captureRetry))
            return
        }

        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let id = displayID.uint32Value
        practice?.window?.orderOut(nil)
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.captureTask = nil }
            do {
                let image = try await Self.snapshot(displayID: id, pointSize: frame.size, scale: scale)
                guard NSScreen.screens.contains(where: {
                    $0.frame == frame && $0.backingScaleFactor == scale
                        && ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                }) else { throw CaptureError.displayChanged }

                let panel = CapturePanel(frame: frame, image: image, strings: strings, guided: practice != nil) {
                    [weak self, weak practice] outcome in
                    self?.closeCapture(restoreFocus: practice == nil)
                    practice?.returnFromPractice(outcome)
                }
                guard try await self.presentCapture(panel) else {
                    throw CaptureError.overlayFocus
                }
            } catch {
                self.closeCapture(restoreFocus: practice == nil)
                practice?.returnFromPractice(.cancelled)
                self.showAlert(strings(.captureFailed), strings.message(for: error, fallback: .captureRetry))
            }
        }
    }

    @MainActor
    private func presentCapture(_ panel: CapturePanel) async throws -> Bool {
        let foreground = NSWorkspace.shared.frontmostApplication
        previousForegroundApp = foreground?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? nil : foreground
        // App activation and the key-window handoff can complete on different run-loop turns.
        NSApp.activate()
        overlay = panel
        for _ in 0..<24 {
            if ownsForeground, NSApp.isActive, panel.present() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func snapshot(displayID: CGDirectDisplayID, pointSize: CGSize, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayChanged
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int((pointSize.width * scale).rounded())
        config.height = Int((pointSize.height * scale).rounded())
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private var ownsForeground: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    private func closeCapture(restoreFocus: Bool = true) {
        let returnTo = previousForegroundApp
        previousForegroundApp = nil
        overlay?.orderOut(nil)
        overlay = nil
        if restoreFocus, ownsForeground, let returnTo, !returnTo.isTerminated {
            NSApp.yieldActivation(to: returnTo)
            returnTo.activate(from: .current, options: [])
        }
    }

    private func showAlert(_ title: String, _ detail: String) {
        presentingAlert = true
        defer { presentingAlert = false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: preferences.strings(.ok))
        alert.runModal()
    }
}

private enum CaptureError: KlikLocalizedError {
    case displayChanged
    case overlayFocus

    func message(using strings: AppStrings) -> String {
        switch self {
        case .displayChanged: return strings(.displayChanged)
        case .overlayFocus: return strings(.overlayFocus)
        }
    }
}
