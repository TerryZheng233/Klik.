import AppKit
import Carbon
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var captureTask: Task<Void, Never>?
    private var overlay: CapturePanel?
    private var previousForegroundApp: NSRunningApplication?
    private var presentingAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            hotKey = try GlobalHotKey { [weak self] in self?.beginCapture() }
        } catch {
            showAlert("无法注册 ⌥A", "请检查其他截图工具或全局快捷键是否占用了 ⌥A，然后重新打开 Klik。\n系统状态码：\(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if overlay?.isVisible == true { closeCapture(restoreFocus: false) }
    }

    @MainActor
    private func beginCapture() {
        guard overlay == nil, captureTask == nil, !presentingAlert else { return }

        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            presentingAlert = true
            let alert = NSAlert()
            alert.messageText = "允许 Klik 截取屏幕"
            alert.informativeText = "在系统设置的「隐私与安全性 → 屏幕与系统音频录制」中开启 Klik。若系统提示重新打开，请照做，再按 ⌥A。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
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
            showAlert("无法识别显示器", "请重新按 ⌥A。")
            return
        }

        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let id = displayID.uint32Value
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.captureTask = nil }
            do {
                let image = try await Self.snapshot(displayID: id, pointSize: frame.size, scale: scale)
                guard NSScreen.screens.contains(where: {
                    $0.frame == frame && $0.backingScaleFactor == scale
                        && ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                }) else { throw CaptureError.displayChanged }

                let panel = CapturePanel(frame: frame, image: image) { [weak self] in
                    self?.closeCapture()
                }
                guard try await self.presentCapture(panel) else {
                    throw CaptureError.overlayFocus
                }
            } catch {
                self.closeCapture()
                self.showAlert("截图未完成", error.localizedDescription)
            }
        }
    }

    @MainActor
    private func presentCapture(_ panel: CapturePanel) async throws -> Bool {
        let foreground = NSWorkspace.shared.frontmostApplication
        previousForegroundApp = foreground?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? nil : foreground
        // A key panel alone does not own the system pointer while another app is foreground.
        NSApp.activate()
        for _ in 0..<20 {
            if ownsForeground { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        overlay = panel
        return panel.present()
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
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private enum CaptureError: LocalizedError {
    case displayChanged
    case overlayFocus

    var errorDescription: String? {
        switch self {
        case .displayChanged: return "显示器状态已变化，请重新按 ⌥A。"
        case .overlayFocus: return "截图浮层未获得键盘焦点，请重新按 ⌥A。"
        }
    }
}

private final class GlobalHotKey {
    private var handler: EventHandlerRef?
    private var key: EventHotKeyRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) throws {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x54534E50, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        guard status == noErr else { throw HotKeyError(status: status) }
        let id = EventHotKeyID(signature: 0x54534E50, id: 1)
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(optionKey), id,
                                              GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &key)
        guard registration == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            throw HotKeyError(status: registration)
        }
    }

    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}

private struct HotKeyError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { String(status) }
}
