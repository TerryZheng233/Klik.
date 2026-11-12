import AppKit
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences = KlikPreferences()
    private let mosaicScrollHintPolicy = MosaicScrollHintPolicy(defaults: .standard)
    private let history: CaptureHistory
    private var historyIssue = false
    private weak var pendingHistoryClear: ForestButton?
    private var previewURL: URL?
    private var historyThumbnailTask: Task<Void, Never>?
    private var historyCopyTask: Task<Void, Never>?
    private var historyPreviewTask: Task<Void, Never>?
    private var statusItem: NSStatusItem?
    private let statusPopover = NSPopover()
    private var popoverMouseMonitors: [Any] = []
    private var hotKey: GlobalHotKey?
    private var setup: ShortcutSetup?
    private var captureTask: Task<Void, Never>?
    private var overlay: CapturePanel?
    private var scrollCapture: ScrollCaptureSession?
    private var screenPanels: [CapturePanel] = []
    private var mouseMonitors: [Any] = []
    private var previousForegroundApp: NSRunningApplication?
    private var presentingAlert = false

    init(history: CaptureHistory = CaptureHistory()) {
        self.history = history
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        history.limit = preferences.historyLimit
        do { try history.enforceLimit() } catch { historyIssue = true }
        installStatusItem()
        var shortcutIssue: Error?
        do {
            try enableShortcut(preferences.shortcut)
        } catch {
            shortcutIssue = error
        }
        if preferences.savedShortcut == nil || shortcutIssue != nil {
            showSetup(issue: shortcutIssue)
        }
        UpdateStartup.confirmAfterStartup()
    }

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            let text = "k." as NSString
            let font = NSFont.systemFont(ofSize: 15, weight: .bold)
            let size = text.size(withAttributes: [.font: font])
            text.draw(at: NSPoint(x: (19 - size.width) / 2, y: (18 - size.height) / 2),
                      withAttributes: [.font: font, .foregroundColor: NSColor.black])
            return true
        }
        icon.isTemplate = true
        icon.accessibilityDescription = "Klik."
        item.button?.image = icon
        item.button?.toolTip = "Klik."
        item.button?.target = self
        item.button?.action = #selector(toggleStatusPopover)
        statusPopover.behavior = .transient
        statusPopover.delegate = self
        statusPopover.animates = false
        statusItem = item
    }

    @MainActor @objc private func toggleStatusPopover() {
        if statusPopover.isShown {
            statusPopover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        showStatusPopover(relativeTo: button)
    }

    @MainActor
    @discardableResult
    func showStatusPopover(relativeTo anchor: NSView) -> NSPopover {
        refreshStatusPopover()
        statusPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        if statusPopover.isShown { watchForOutsideClicks() }
        return statusPopover
    }

    @MainActor
    private func watchForOutsideClicks() {
        stopWatchingForOutsideClicks()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { [weak self] _ in
            DispatchQueue.main.async { self?.statusPopover.performClose(nil) }
        }) { popoverMouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            guard let self, self.statusPopover.isShown else { return event }
            let popoverWindow = self.statusPopover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.statusPopover.performClose(nil)
            }
            return event
        }) { popoverMouseMonitors.append(monitor) }
    }

    @MainActor
    private func stopWatchingForOutsideClicks() {
        popoverMouseMonitors.forEach { NSEvent.removeMonitor($0) }
        popoverMouseMonitors.removeAll()
    }

    func popoverDidClose(_ notification: Notification) {
        pendingHistoryClear = nil
        historyThumbnailTask?.cancel()
        historyCopyTask?.cancel()
        historyCopyTask = nil
        historyPreviewTask?.cancel()
        stopWatchingForOutsideClicks()
    }

    @MainActor
    private func refreshStatusPopover() {
        historyThumbnailTask?.cancel()
        historyCopyTask?.cancel()
        historyCopyTask = nil
        historyPreviewTask?.cancel()
        pendingHistoryClear = nil
        let strings = preferences.strings
        let entries: [URL]
        do {
            entries = Array(try history.entries().prefix(preferences.historyLimit == 0 ? 50 : preferences.historyLimit))
        } catch {
            entries = []
            historyIssue = true
        }

        previewURL = nil
        let visibleRows = min(max(entries.count, 1), 5)
        let listHeight = CGFloat(visibleRows * 52)
        let inset: CGFloat = 16
        let buttonHeight = KlikTheme.controlHeight
        let width: CGFloat = 300
        let height = listHeight + 98
        let content = StatusPopoverView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.isSurface = true
        let title = NSTextField(labelWithString: strings(historyIssue ? .historyErrorTitle : .menuHistory))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = KlikTheme.ink
        title.frame = NSRect(x: inset, y: 16, width: width - 116, height: 20)
        if historyIssue { title.toolTip = strings(.historyErrorBody) }
        content.addSubview(title)

        let clear = ForestButton(title: strings(.menuHistoryClear), target: self, action: #selector(clearHistory(_:)))
        clear.isEnabled = !entries.isEmpty
        clear.frame = CGRect(x: width - inset - 76, y: 11, width: 76, height: buttonHeight)
        content.addSubview(clear)

        let scroll = NSScrollView(frame: NSRect(x: inset, y: 46, width: width - 2 * inset, height: listHeight))
        scroll.hasVerticalScroller = entries.count > visibleRows
        scroll.drawsBackground = false
        let list = StatusPopoverView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                                                  height: max(listHeight, CGFloat(entries.count * 52))))
        if entries.isEmpty {
            let message = NSTextField(labelWithString: strings(historyIssue ? .historyErrorTitle : .menuHistoryEmpty))
            message.textColor = KlikTheme.mutedInk
            message.frame = NSRect(x: 0, y: 11, width: scroll.contentSize.width, height: 22)
            list.addSubview(message)
        }
        var rows: [(URL, HistoryButton)] = []
        for (index, url) in entries.enumerated() {
            let item = HistoryButton(frame: NSRect(x: 0, y: CGFloat(index * 52), width: list.bounds.width, height: 50),
                                     url: url, image: nil,
                                     label: HistoryDateFormatter.label(for: url, strings: strings))
            item.target = self
            item.action = #selector(showHistoryPreview(_:))
            list.addSubview(item)
            rows.append((url, item))
        }
        let history = history
        historyThumbnailTask = Task { @MainActor [weak content] in
            for (url, item) in rows {
                let thumbnail = await Task.detached(priority: .utility) { history.thumbnail(url) }.value
                guard !Task.isCancelled, content != nil, item.superview === list else { return }
                item.setThumbnail(thumbnail)
            }
        }
        scroll.documentView = list
        content.addSubview(scroll)

        let settings = ForestButton(title: strings(.menuSettings), target: self, action: #selector(openSettings))
        let buttonWidth = (width - 2 * inset - 8) / 2
        settings.frame = NSRect(x: inset, y: listHeight + 56, width: buttonWidth, height: buttonHeight)
        content.addSubview(settings)
        let quit = ForestButton(title: strings(.menuQuit), target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = NSRect(x: inset + buttonWidth + 8, y: listHeight + 56, width: buttonWidth, height: buttonHeight)
        content.addSubview(quit)
        let controller = NSViewController()
        controller.view = content
        statusPopover.contentViewController = controller
        statusPopover.contentSize = content.frame.size
    }

    @MainActor @objc private func openSettings() {
        statusPopover.performClose(nil)
        if let setup {
            setup.showSettings()
        } else {
            showSetup()
            setup?.showSettings()
        }
    }

    @MainActor @objc private func showHistoryPreview(_ sender: HistoryButton) {
        historyThumbnailTask?.cancel()
        historyPreviewTask?.cancel()
        previewURL = sender.url
        let strings = preferences.strings
        let content = StatusPopoverView(frame: NSRect(x: 0, y: 0, width: 360, height: 330))
        content.isSurface = true
        let back = ForestButton(title: "‹  " + strings(.back), target: self, action: #selector(backToHistory))
        back.frame = CGRect(x: 16, y: 10, width: 76, height: KlikTheme.controlHeight)
        content.addSubview(back)
        let title = NSTextField(labelWithString: strings(.historyPreview))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = KlikTheme.ink
        title.alignment = .center
        title.frame = NSRect(x: 115, y: 15, width: 130, height: 20)
        content.addSubview(title)
        let imageView = PassiveImageView(frame: NSRect(x: 16, y: 44, width: 328, height: 220))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.styleHistoryImage(radius: KlikTheme.badgeRadius)
        content.addSubview(imageView)
        let date = NSTextField(labelWithString: HistoryDateFormatter.label(for: sender.url, strings: strings))
        date.textColor = KlikTheme.mutedInk
        date.font = .systemFont(ofSize: 12)
        date.frame = NSRect(x: 18, y: 280, width: 140, height: 22)
        content.addSubview(date)
        let delete = ForestButton(title: strings(.historyDelete), target: self, action: #selector(deleteHistory(_:)))
        delete.frame = CGRect(x: 166, y: 275, width: 72, height: 30)
        delete.identifier = NSUserInterfaceItemIdentifier("historyDelete")
        content.addSubview(delete)
        let copy = ForestButton(title: strings(.historyCopy), target: self, action: #selector(copyHistory))
        copy.isPrimary = true
        copy.frame = NSRect(x: 246, y: 275, width: 98, height: 30)
        content.addSubview(copy)
        let controller = NSViewController()
        controller.view = content
        statusPopover.contentViewController = controller
        statusPopover.contentSize = content.frame.size
        let history = history
        let url = sender.url
        historyPreviewTask = Task { @MainActor [weak self, weak content, weak imageView] in
            let image = await Task.detached(priority: .userInitiated) { history.preview(url) }.value
            guard let self, !Task.isCancelled, self.previewURL == url,
                  let content, self.statusPopover.contentViewController?.view === content,
                  let imageView else { return }
            guard let image else {
                self.showAlert(self.preferences.strings(.historyErrorTitle), self.preferences.strings(.historyErrorBody))
                return
            }
            imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    @MainActor @objc private func backToHistory() { refreshStatusPopover() }

    @MainActor @objc private func copyHistory() {
        guard let url = previewURL, historyCopyTask == nil else { return }
        let history = history
        historyCopyTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try history.clipboardData(url) }
            }.value
            guard let self, !Task.isCancelled, self.previewURL == url else { return }
            self.historyCopyTask = nil
            switch result {
            case .success(let (png, tiff)):
                if ClipboardImage.write(png: png, tiff: tiff, to: .general) {
                    self.statusPopover.performClose(nil)
                } else {
                    self.showAlert(self.preferences.strings(.historyErrorTitle), self.preferences.strings(.historyErrorBody))
                }
            case .failure:
                self.showAlert(self.preferences.strings(.historyErrorTitle), self.preferences.strings(.historyErrorBody))
            }
        }
    }

    @MainActor @objc private func deleteHistory(_ sender: ForestButton) {
        guard statusPopover.isShown, let url = previewURL,
              sender.superview === statusPopover.contentViewController?.view else { return }
        if pendingHistoryClear !== sender {
            pendingHistoryClear = sender
            sender.title = preferences.strings(.menuHistoryConfirmClear)
            sender.toolTip = preferences.strings(.historyDeleteConfirmHint)
            sender.setAccessibilityHelp(sender.toolTip)
            sender.isDestructive = true
            return
        }
        do {
            try history.remove(url)
            historyIssue = false
        } catch {
            historyIssue = true
        }
        refreshStatusPopover()
    }

    @MainActor @objc private func clearHistory(_ sender: ForestButton) {
        guard statusPopover.isShown, sender.isEnabled,
              let content = statusPopover.contentViewController?.view, sender.superview === content else { return }
        if pendingHistoryClear !== sender {
            pendingHistoryClear = sender
            let strings = preferences.strings
            let hint = strings(.menuHistoryConfirmClearHint)
            sender.title = strings(.menuHistoryConfirmClear)
            sender.toolTip = hint
            sender.setAccessibilityHelp(hint)
            sender.isDestructive = true
            return
        }
        do {
            try history.clear()
            historyIssue = false
        } catch {
            historyIssue = true
        }
        refreshStatusPopover()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if overlay == nil, captureTask == nil, !presentingAlert { showSetup() }
        return false
    }

    private func enableShortcut(_ shortcut: CaptureShortcut) throws {
        if hotKey == nil {
            hotKey = try GlobalHotKey { [weak self] in
                self?.requestCaptureFromShortcut()
            }
        }
        try hotKey?.register(shortcut)
    }

    @MainActor
    private func requestCaptureFromShortcut() {
        DispatchQueue.main.async { [weak self] in self?.handleCaptureShortcut() }
    }

    @MainActor
    private func handleCaptureShortcut() {
        guard overlay == nil, scrollCapture == nil, captureTask == nil, !presentingAlert else { return }
        if setup == nil, preferences.savedShortcut == nil { showSetup() }
        if setup?.handleRegisteredShortcut(preferences.shortcut) == true { return }
        beginCapture()
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
            historyLimit: preferences.historyLimit,
            changeHistoryLimit: { [weak self] limit in
                guard let self else { return }
                self.history.limit = limit
                do {
                    try self.history.enforceLimit()
                    self.preferences.historyLimit = limit
                    self.historyIssue = false
                } catch {
                    self.history.limit = self.preferences.historyLimit
                    self.historyIssue = true
                    throw error
                }
            },
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

    @MainActor
    func applicationDidResignActive(_ notification: Notification) {
        if captureTask == nil, overlay?.isVisible == true { closeCapture(restoreFocus: false) }
    }

    @MainActor
    private func beginCapture(practice: ShortcutSetup? = nil) {
        guard overlay == nil, scrollCapture == nil, captureTask == nil, !presentingAlert else { return }
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
            KlikTheme.styleAlert(alert)
            if alert.runModal() == .alertFirstButtonReturn,
               let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(settings)
            }
            presentingAlert = false
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else {
            showAlert(strings(.displayUnavailable), strings(.captureRetry))
            return
        }

        let openPopoverFrame = statusPopover.isShown ? statusPopover.contentViewController?.view.window?.frame : nil
        let foregroundAtStart = NSWorkspace.shared.frontmostApplication
        let guideWindow = practice?.window
        let guideWindowID = guideWindow.flatMap { CGWindowID(exactly: $0.windowNumber) }
        // Practice stays on its original screen; ordinary capture can switch displays.
        let screens = practice == nil ? NSScreen.screens : [screen]
        let displays = screens.compactMap { screen -> (frame: CGRect, scale: CGFloat, id: CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen.frame, screen.backingScaleFactor, number.uint32Value)
        }
        guard displays.count == screens.count else {
            showAlert(strings(.displayUnavailable), strings(.captureRetry))
            return
        }
        captureTask = Task { @MainActor [weak self, practice] in
            guard let self else { return }
            defer { self.captureTask = nil }
            do {
                // Take every snapshot before showing any overlays, so no display captures
                // another display's selection UI. Keep the open menu visible until then.
                var panels: [CapturePanel] = []
                for display in displays {
                    let snapshot = try await Self.snapshot(displayID: display.id, pointSize: display.frame.size,
                                                           scale: display.scale, excluding: guideWindowID)
                    guard NSScreen.screens.contains(where: {
                        $0.frame == display.frame && $0.backingScaleFactor == display.scale
                            && ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
                    }) else { throw CaptureError.displayChanged }
                    let windows = snapshot.windows
                    var targets = snapshot.targets
                    // Capture the foreground app's windows while it still has focus.
                    // Capturing after the overlay activates would render inactive selections.
                    let foregroundIDs = targets.compactMap { target -> CGWindowID? in
                        guard let window = windows[target.id],
                              window.owningApplication?.processID == foregroundAtStart?.processIdentifier,
                              foregroundAtStart?.processIdentifier != NSRunningApplication.current.processIdentifier
                        else { return nil }
                        return target.id
                    }
                    let frozenWindows = await WindowCaptureSnapshot.prepare(ids: foregroundIDs) { id in
                        guard let window = windows[id] else { throw CaptureError.displayChanged }
                        return try await Self.snapshot(window: window)
                    }
                    if let popover = openPopoverFrame {
                        let visible = popover.intersection(display.frame)
                        if !visible.isNull && !visible.isEmpty {
                            let local = CGRect(x: visible.minX - display.frame.minX,
                                               y: display.frame.maxY - visible.maxY,
                                               width: visible.width, height: visible.height)
                            targets.insert(WindowSnap(id: 0, frame: local, usesDesktopImage: true), at: 0)
                        }
                    }
                    let scrollAction: ((CGRect) -> Void)? = practice == nil ? { [weak self] selection in
                        self?.beginScrollCapture(selection: selection, displayID: display.id,
                                                 frame: display.frame, scale: display.scale, strings: strings)
                    } : nil
                    let panel = CapturePanel(frame: display.frame, image: snapshot.image, windowTargets: targets,
                                             strings: strings, guided: practice != nil,
                                             scrollHintPolicy: self.mosaicScrollHintPolicy,
                                             captureWindow: { id in
                                                 try await frozenWindows.image(for: id) {
                                                     guard let window = windows[id] else { throw CaptureError.displayChanged }
                                                     return try await Self.snapshot(window: window)
                                                 }
                                             }, startScrollCapture: scrollAction,
                                             recordCapture: { [weak self] png in await self?.recordCapture(png) }) {
                        [weak self, weak practice] outcome in
                        self?.closeCapture(restoreFocus: practice == nil)
                        practice?.returnFromPractice(outcome)
                    }
                    panels.append(panel)
                }
                // A screenshot can take long enough for the user to change apps.
                // Respect that choice instead of activating an obsolete capture.
                if practice == nil, !CaptureFocus.mayPresent(
                    startingPID: foregroundAtStart?.processIdentifier,
                    currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    ownPID: NSRunningApplication.current.processIdentifier) {
                    return
                }
                if self.statusPopover.isShown { self.statusPopover.performClose(nil) }
                self.screenPanels = panels
                let initial = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                    ?? panels.first(where: { $0.frame == screen.frame })
                guard let panel = initial, try await self.presentCapture(panel, returningTo: foregroundAtStart) else {
                    throw CaptureError.overlayFocus
                }
                self.watchMouseForScreenChanges()
                if self.overlay === panel { guideWindow?.orderOut(nil) }
            } catch {
                self.closeCapture(restoreFocus: practice == nil)
                practice?.returnFromPractice(.cancelled)
                self.showAlert(strings(.captureFailed), strings.message(for: error, fallback: .captureRetry))
            }
        }
    }

    @MainActor
    private func presentCapture(_ panel: CapturePanel, returningTo foreground: NSRunningApplication?) async throws -> Bool {
        previousForegroundApp = foreground?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? nil : foreground
        // App activation and the key-window handoff can complete on different run-loop turns.
        overlay = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate()
        // The shortcut is an explicit request for keyboard input. Menu-bar
        // interactions can leave another app active, preventing a normal activation.
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<24 {
            if panel.present() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @MainActor
    private func watchMouseForScreenChanges() {
        guard screenPanels.count > 1 else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.switchScreenIfNeeded()
            return event
        }) { mouseMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            DispatchQueue.main.async { self?.switchScreenIfNeeded() }
        }) { mouseMonitors.append(global) }
    }

    @MainActor
    private func switchScreenIfNeeded() {
        guard NSEvent.pressedMouseButtons == 0, let current = overlay, !current.isRecognizingText,
              let next = screenPanels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
              next !== current else { return }
        current.orderOut(nil)
        overlay = next
        next.alphaValue = 0
        _ = next.present()
    }

    private static func snapshot(displayID: CGDirectDisplayID, pointSize: CGSize,
                                 scale: CGFloat, excluding windowID: CGWindowID?) async throws
        -> (image: CGImage, windows: [CGWindowID: SCWindow], targets: [WindowSnap]) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayChanged
        }
        let excludedWindows = content.windows.filter { $0.windowID == windowID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.width = Int((pointSize.width * scale).rounded())
        config.height = Int((pointSize.height * scale).rounded())
        config.showsCursor = false
        var windows: [CGWindowID: SCWindow] = [:]
        for window in content.windows where window.windowID != windowID {
            windows[window.windowID] = window
        }
        let targets = WindowSnap.candidates(on: displayID, canvasSize: pointSize, available: Set(windows.keys))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, windows, targets)
    }

    private static func snapshot(window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = filter.contentRect.size
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    @MainActor
    private func beginScrollCapture(selection: CGRect, displayID: CGDirectDisplayID, frame: CGRect,
                                    scale: CGFloat, strings: AppStrings) {
        guard overlay != nil, scrollCapture == nil else { return }
        guard let screen = NSScreen.screens.first(where: {
            $0.frame == frame && $0.backingScaleFactor == scale
                && ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            closeCapture()
            showAlert(strings(.captureFailed), strings(.displayChanged))
            return
        }

        let session = ScrollCaptureSession(selection: selection, screenFrame: frame, visibleFrame: screen.visibleFrame,
                                           strings: strings, record: { [weak self] in await self?.recordCapture($0) },
                                           finish: { [weak self] in self?.closeCapture() })
        scrollCapture = session
        hideCapturePanels()
        restoreCaptureFocus(to: previousForegroundApp)
        session.start { windowIDs in
            try await ScrollFrameSource.make(displayID: displayID, screenFrame: frame,
                                             scale: scale, selection: selection, excluding: windowIDs)
        }
    }

    @MainActor
    private func recordCapture(_ png: Data) async {
        let history = history
        let failed = await Task.detached(priority: .utility) {
            do { try history.record(png); return false }
            catch { return true }
        }.value
        historyIssue = failed
    }

    private var ownsForeground: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    @MainActor
    private func closeCapture(restoreFocus: Bool = true) {
        let returnTo = previousForegroundApp
        previousForegroundApp = nil
        hideCapturePanels()
        scrollCapture?.close()
        scrollCapture = nil
        if restoreFocus { restoreCaptureFocus(to: returnTo) }
    }

    private func hideCapturePanels() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        overlay?.orderOut(nil)
        overlay = nil
        screenPanels.removeAll()
    }

    private func restoreCaptureFocus(to app: NSRunningApplication?) {
        guard ownsForeground, let app, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    @MainActor
    private func showAlert(_ title: String, _ detail: String) {
        presentingAlert = true
        defer { presentingAlert = false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: preferences.strings(.ok))
        KlikTheme.styleAlert(alert)
        alert.runModal()
    }
}

enum CaptureFocus {
    static func mayPresent(startingPID: pid_t?, currentPID: pid_t?, ownPID: pid_t) -> Bool {
        guard let start = startingPID, let current = currentPID else { return true }
        return current == start || (current == ownPID && start != ownPID)
    }
}

private final class StatusPopoverView: NSView {
    var isSurface = false
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isSurface {
            KlikTheme.window.setFill()
            dirtyRect.fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class HistoryButton: HoverButton {
    let url: URL
    private let thumbnail = PassiveImageView(frame: NSRect(x: 6, y: 5, width: 52, height: 40))

    func setThumbnail(_ image: NSImage?) { thumbnail.image = image }

    init(frame: NSRect, url: URL, image: NSImage?, label: String) {
        self.url = url
        super.init(frame: frame)
        isBordered = false
        title = ""
        setAccessibilityLabel(label)
        thumbnail.image = image
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.styleHistoryImage(radius: KlikTheme.controlRadius)
        addSubview(thumbnail)
        let text = PassiveTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 13)
        text.textColor = KlikTheme.ink
        text.frame = NSRect(x: 70, y: 16, width: frame.width - 76, height: 18)
        addSubview(text)
    }

    required init?(coder: NSCoder) { nil }
}

private final class PassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func styleHistoryImage(radius: CGFloat) {
        wantsLayer = true
        KlikTheme.round(layer, radius: radius)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = KlikTheme.inset.cgColor
        }
    }
}

private final class PassiveTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
