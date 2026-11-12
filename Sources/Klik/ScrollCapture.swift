import AppKit

private actor ScrollImageBuilder {
    private var stitcher = ScrollStitcher()
    private var latest: CGImage?

    func append(_ image: CGImage) -> (ScrollStitcher.Update, Int, ScrollAxis?) {
        latest = image
        let update = stitcher.append(image)
        return (update, stitcher.length, stitcher.axis)
    }

    func commitLatest() -> ScrollStitcher.Update {
        guard let latest else { return .waiting }
        return stitcher.append(latest, final: true)
    }

    func render() -> (CGImage, ScrollAxis)? {
        guard let image = stitcher.render(), let axis = stitcher.axis else { return nil }
        stitcher = ScrollStitcher()
        latest = nil
        return (image, axis)
    }
}

@MainActor
final class ScrollCaptureSession: NSObject {
    private let strings: AppStrings
    private let screenFrame: CGRect
    private let builder = ScrollImageBuilder()
    private let controls: NSPanel
    private let outline: NSPanel
    private let status = NSTextField(wrappingLabelWithString: "")
    private let done = ScrollControlButton()
    private let record: (Data) async -> Void
    private let finish: () -> Void
    private var task: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var source: (any ScrollCaptureFrameSource)?
    private var preview: ScrollCapturePreview?
    private var hasExtension = false
    private var finishing = false
    private var exportCommitted = false
    private var stoppedMessage: UIKey?
    private var unalignedSince: ContinuousClock.Instant?

    init(selection: CGRect, screenFrame: CGRect, visibleFrame: CGRect, strings: AppStrings,
         record: @escaping (Data) async -> Void, finish: @escaping () -> Void) {
        self.strings = strings
        self.screenFrame = screenFrame
        self.record = record
        self.finish = finish

        let screenSelection = CGRect(x: screenFrame.minX + selection.minX, y: screenFrame.maxY - selection.maxY,
                                     width: selection.width, height: selection.height)
        let shadowInset = KlikTheme.panelShadowInset
        let size = CGSize(width: min(440, visibleFrame.width - 2 * shadowInset), height: 76)
        let controlsFrame = Self.controlsFrame(size: size, selection: screenSelection, visible: visibleFrame)
        controls = ScrollPassivePanel(contentRect: controlsFrame.insetBy(dx: -shadowInset, dy: -shadowInset),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        outline = ScrollPassivePanel(contentRect: screenSelection.insetBy(dx: -2, dy: -2), styleMask: .borderless,
                                     backing: .buffered, defer: false)
        super.init()

        for panel in [outline, controls] {
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        }
        outline.level = .floating
        outline.isOpaque = false
        outline.backgroundColor = .clear
        outline.ignoresMouseEvents = true
        outline.contentView = ScrollOutlineView()
        controls.level = .statusBar
        let tray = KlikTheme.installPanelSurface(in: controls, radius: KlikTheme.cornerRadius,
                                                 identifier: "scrollControlSurface")

        let title = NSTextField(labelWithString: strings(.toolScrollCapture))
        title.textColor = KlikTheme.ink
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = CGRect(x: 16, y: 48, width: size.width - 32, height: 17)
        tray.addSubview(title)
        status.font = .systemFont(ofSize: 11)
        status.textColor = KlikTheme.mutedInk
        status.maximumNumberOfLines = 3
        status.frame = CGRect(x: 16, y: 6, width: size.width - 184, height: 40)
        tray.addSubview(status)

        let cancel = ScrollControlButton(title: strings(.cancel), target: self, action: #selector(cancelCapture))
        cancel.frame = CGRect(x: size.width - 164, y: 12, width: 70, height: KlikTheme.controlHeight)
        tray.addSubview(cancel)
        done.title = strings(.done)
        done.target = self
        done.action = #selector(complete)
        done.isPrimary = true
        done.isEnabled = false
        done.frame = CGRect(x: size.width - 86, y: 12, width: 70, height: KlikTheme.controlHeight)
        tray.addSubview(done)
        setStatus(.scrollStarting)
    }

    func start(prepare: @escaping (Set<CGWindowID>) async throws -> any ScrollCaptureFrameSource) {
        outline.orderFrontRegardless()
        controls.orderFrontRegardless()
        let windowIDs = Set([outline, controls].compactMap { CGWindowID(exactly: $0.windowNumber) })
        task = Task { [weak self] in
            do {
                // Give the source application time to regain focus before streaming.
                try await Task.sleep(for: .milliseconds(120))
                let source = try await prepare(windowIDs)
                try Task.checkCancellation()
                self?.source = source
                defer {
                    self?.source = nil
                    Task { await source.stop() }
                }
                try await source.start()
                for try await frame in source.frames {
                    guard let self, !Task.isCancelled else { return }
                    let (update, length, axis) = await self.builder.append(frame)
                    guard !Task.isCancelled else { return }
                    if update == .limit {
                        if self.finishing { await self.presentResult(message: .scrollLimit) }
                        else { self.stop(with: .scrollLimit) }
                        return
                    }
                    if length == 0 {
                        self.stop(with: .scrollSourceFailed)
                        return
                    }
                    self.updateStatus(update, length: length, axis: axis)
                }
                guard let self, self.finishing, !Task.isCancelled else { return }
                let last = await self.builder.commitLatest()
                let message: UIKey? = last == .unaligned ? .scrollPartial : (last == .limit ? .scrollLimit : nil)
                await self.presentResult(message: message)
            } catch {
                guard !Task.isCancelled, let self else { return }
                if self.finishing { await self.presentResult(message: .scrollSourceFailed) }
                else { self.stop(with: .scrollSourceFailed) }
            }
        }
    }

    private func updateStatus(_ update: ScrollStitcher.Update, length: Int, axis: ScrollAxis?) {
        if update == .extended { hasExtension = true }
        if update == .unaligned {
            if unalignedSince == nil { unalignedSince = .now }
        } else {
            unalignedSince = nil
        }
        guard !finishing else { return }
        done.isEnabled = hasExtension
        if let unalignedSince, unalignedSince.duration(to: .now) >= .milliseconds(350) {
            setStatus(.scrollUnaligned)
        } else if hasExtension {
            setStatus(axis == .horizontal ? .scrollProgressWide : .scrollProgress, length: length)
        } else {
            setStatus(.scrollReady)
        }
    }

    func close() {
        finishTask?.cancel()
        task?.cancel()
        source?.finishFrames()
        task = nil
        controls.orderOut(nil)
        outline.orderOut(nil)
        preview?.orderOut(nil)
        preview = nil
    }

    @objc private func cancelCapture() { finish() }

    @objc private func complete() {
        guard hasExtension, !finishing else { return }
        finishing = true
        done.isEnabled = false
        setStatus(.scrollFinishing)
        if let stoppedMessage {
            task = Task { [weak self] in await self?.presentResult(message: stoppedMessage) }
        } else {
            finishTask = Task { [weak self] in
                // Keep the last composited frames after the Done click, even
                // when the stream has gone idle and has no new frame to yield.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.source?.finishFrames()
            }
        }
    }

    private func stop(with message: UIKey) {
        stoppedMessage = message
        done.isEnabled = hasExtension
        setStatus(message)
    }

    private func presentResult(message: UIKey?) async {
        let rendered = await builder.render()
        guard !Task.isCancelled else { return }
        guard let (image, axis) = rendered else {
            finishing = false
            stop(with: .renderError)
            return
        }
        let window = ScrollCapturePreview(image: image, axis: axis, screenFrame: screenFrame, strings: strings, message: message)
        window.onCancel = { [weak self] in
            guard let self, !self.exportCommitted else { return }
            self.finish()
        }
        window.onExport = { [weak self] destination, rendered in self?.export(rendered, to: destination) }
        preview = window
        controls.orderOut(nil)
        outline.orderOut(nil)
        window.present()
    }

    private func export(_ image: CGImage, to destination: CaptureView.Destination) {
        guard let preview, !preview.isExporting else { return }
        preview.isExporting = true
        task = Task { [weak self, weak preview] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PreparedCaptureExport.make(image: image, destination: destination) }
            }.value
            guard let self, let preview, !Task.isCancelled else { return }
            defer { preview.isExporting = false }
            let prepared: PreparedCaptureExport.Result
            switch result {
            case .failure(let error):
                preview.showStatus(self.strings(error as? PreparedCaptureExport.Failure == .download ? .downloadError : .renderError))
                return
            case .success(let value): prepared = value
            }
            switch destination {
            case .clipboard:
                guard ClipboardImage.write(png: prepared.png, tiff: prepared.tiff, to: .general) else {
                    preview.showStatus(self.strings(.clipboardError))
                    return
                }
            case .downloads:
                do { try prepared.download?.commit() }
                catch { preview.showStatus(self.strings(.downloadError)); return }
            }
            self.exportCommitted = true
            await self.record(prepared.png)
            self.exportCommitted = false
            guard !Task.isCancelled else { return }
            let confirmationFrame = destination == .downloads ? preview.saveButtonScreenFrame : nil
            self.finish()
            if let confirmationFrame { SaveConfirmation.show(at: confirmationFrame) }
        }
    }

    private func setStatus(_ key: UIKey, length: Int? = nil) {
        let message = length.map { strings(key, $0) } ?? strings(key)
        if status.stringValue != message { status.stringValue = message }
    }

    private static func controlsFrame(size: CGSize, selection: CGRect, visible: CGRect) -> CGRect {
        let shadowInset = KlikTheme.panelShadowInset
        let bounds = visible.insetBy(dx: shadowInset, dy: shadowInset)
        let gap = shadowInset + 2
        let rightAligned = min(bounds.maxX - size.width, max(bounds.minX, selection.maxX - size.width))
        let topAligned = min(bounds.maxY - size.height, max(bounds.minY, selection.maxY - size.height))
        let candidates = [
            CGPoint(x: rightAligned, y: selection.minY - size.height - gap),
            CGPoint(x: rightAligned, y: selection.maxY + gap),
            CGPoint(x: selection.maxX + gap, y: topAligned),
            CGPoint(x: selection.minX - size.width - gap, y: topAligned)
        ]
        let origin = candidates.first { bounds.contains(CGRect(origin: $0, size: size)) }
            ?? CGPoint(x: rightAligned, y: bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}

private final class ScrollPassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScrollControlButton: ForestButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ScrollOutlineView: NSView {
    override func draw(_ dirtyRect: CGRect) {
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        KlikTheme.selectionHalo.setStroke()
        outline.lineWidth = 3
        outline.stroke()
        KlikTheme.selection.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}
