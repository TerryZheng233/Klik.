import AppKit
import Carbon
import CoreText

private actor ScrollImageBuilder {
    private var stitcher = ScrollStitcher()
    private var latest: CGImage?

    func append(_ image: CGImage) -> (ScrollStitcher.Update, Int, ScrollAxis?, [ScrollVerticalEdge], Int?) {
        latest = image
        let update = stitcher.append(image)
        return (update, stitcher.length, stitcher.axis,
                ScrollVerticalEdge.allCases.filter { stitcher.isAtEdge($0) }, stitcher.scrollOrigin)
    }

    func commitLatest() -> ScrollStitcher.Update {
        guard let latest else { return .waiting }
        return stitcher.append(latest, final: true)
    }

    func prepareExtension(at edge: ScrollVerticalEdge, from image: CGImage) -> Int {
        let update = commitLatest()
        guard update != .limit, update != .unaligned else { return 0 }
        return stitcher.availableRows(at: edge, from: image)
    }

    func extendEdge(_ edge: ScrollVerticalEdge, from image: CGImage, rows: Int) -> ScrollStitcher.Update {
        stitcher.extendEdge(edge, from: image, extraRows: rows)
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
    private let screenSelection: CGRect
    private let visibleFrame: CGRect
    private let builder = ScrollImageBuilder()
    private let controls: ScrollPassivePanel
    private let outline: NSPanel
    private let extendPanel: ScrollPassivePanel
    private var controlsSurface: NSView?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let cancel = ScrollControlButton()
    private let done = ScrollControlButton()
    private let extendButton = ScrollExtendButton()
    private let record: (Data) async -> Void
    private let finish: () -> Void
    private var task: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var extensionTask: Task<Void, Never>?
    private var extendHintTask: Task<Void, Never>?
    private var extendDepartureTask: Task<Void, Never>?
    private var scrollMonitor: Any?
    private var eligibleEdges: [ScrollVerticalEdge] = []
    private var pendingExtendEdge: ScrollVerticalEdge?
    private var shownExtendEdge: ScrollVerticalEdge?
    private var extendShownAtOrigin: Int?
    private var lastScrollOrigin: Int?
    private var extensionPanel: ScrollExtensionPanel?
    private var source: (any ScrollCaptureFrameSource)?
    private var preview: ScrollCapturePreview?
    private var cancelHotKey: GlobalHotKey?
    private var hasExtension = false
    private var finishing = false
    private var exportCommitted = false
    private var stoppedMessage: UIKey?
    private var unalignedSince: ContinuousClock.Instant?
    private var lastLength = 0

    init(selection: CGRect, screenFrame: CGRect, visibleFrame: CGRect, strings: AppStrings,
         record: @escaping (Data) async -> Void, finish: @escaping () -> Void) {
        self.strings = strings
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.record = record
        self.finish = finish

        let screenSelection = CGRect(x: screenFrame.minX + selection.minX, y: screenFrame.maxY - selection.maxY,
                                     width: selection.width, height: selection.height)
        self.screenSelection = screenSelection
        let shadowInset = KlikTheme.panelShadowInset
        let size = CGSize(width: min(280, visibleFrame.width - 2 * shadowInset), height: 42)
        let controlsFrame = Self.controlsFrame(size: size, selection: screenSelection, visible: visibleFrame)
        controls = ScrollPassivePanel(contentRect: controlsFrame.insetBy(dx: -shadowInset, dy: -shadowInset),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        outline = ScrollPassivePanel(contentRect: screenSelection.insetBy(dx: -2, dy: -2), styleMask: .borderless,
                                     backing: .buffered, defer: false)
        extendPanel = ScrollPassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        super.init()

        for panel in [outline, controls, extendPanel] {
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
        controlsSurface = tray

        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = KlikTheme.mutedInk
        status.alignment = .center
        status.maximumNumberOfLines = 3
        tray.addSubview(status)

        MarkupToolbarLayout.configureButton(cancel, symbol: "x", fallback: "xmark",
            label: strings(.cancel), target: self, action: #selector(cancelCapture))
        cancel.setAccessibilityIdentifier("scrollCancel")
        tray.addSubview(cancel)
        MarkupToolbarLayout.configureButton(done, symbol: "check", fallback: "checkmark",
            label: strings(.done), target: self, action: #selector(complete))
        done.contentTintColor = KlikTheme.action
        done.setAccessibilityIdentifier("scrollDone")
        done.isEnabled = false
        tray.addSubview(done)
        extendButton.font = .systemFont(ofSize: 12, weight: .semibold)
        extendButton.isBordered = false
        extendButton.refusesFirstResponder = true
        extendButton.target = self
        extendButton.action = #selector(toggleExtension)
        extendButton.setAccessibilityIdentifier("scrollExtend")
        extendPanel.level = .statusBar
        extendPanel.animationBehavior = .none
        extendPanel.isOpaque = false
        extendPanel.backgroundColor = .clear
        extendPanel.hasShadow = false
        let extendSurface = NSView()
        extendSurface.wantsLayer = true
        extendButton.wantsLayer = true
        extendSurface.addSubview(extendButton)
        extendPanel.contentView = extendSurface
        configureExtendButton(at: .bottom, confirming: false)
        positionExtendButton(at: screenSelection.minY)
        setStatus(.scrollStarting)
    }

    func start(prepare: @escaping (Set<CGWindowID>) async throws -> any ScrollCaptureFrameSource) {
        do {
            let hotKey = try GlobalHotKey { [weak self] in self?.cancelCapture() }
            try hotKey.register(CaptureShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0, keyLabel: "Esc"))
            cancelHotKey = hotKey
        } catch {
            NSLog("Could not register Escape for scrolling capture: %@", String(describing: error))
        }
        outline.orderFrontRegardless()
        controls.orderFrontRegardless()
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard event.momentumPhase.isEmpty, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }
            self?.observeVerticalScroll(event.scrollingDeltaY, at: NSEvent.mouseLocation)
        }
        let windowIDs = Set([outline, controls, extendPanel].compactMap { CGWindowID(exactly: $0.windowNumber) })
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
                    guard self.extensionTask == nil, self.extensionPanel == nil else { continue }
                    let (update, length, axis, edges, origin) = await self.builder.append(frame)
                    guard !Task.isCancelled else { return }
                    guard self.extensionTask == nil, self.extensionPanel == nil else { continue }
                    if update == .limit {
                        if self.finishing { await self.finishCapture(message: .scrollLimit) }
                        else { self.stop(with: .scrollLimit) }
                        return
                    }
                    if length == 0 {
                        self.stop(with: .scrollSourceFailed)
                        return
                    }
                    self.updateStatus(update, length: length, axis: axis, edges: edges,
                                      origin: origin, frameHeight: frame.height)
                }
                guard let self, !Task.isCancelled else { return }
                if self.finishing, self.extensionPanel == nil { await self.finishCapture() }
                else { self.stop(with: .scrollSourceFailed) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                if self.finishing, self.extensionPanel == nil { await self.finishCapture(message: .scrollSourceFailed) }
                else { self.stop(with: .scrollSourceFailed) }
            }
        }
    }

    private func updateStatus(_ update: ScrollStitcher.Update, length: Int, axis: ScrollAxis?,
                              edges: [ScrollVerticalEdge], origin: Int?, frameHeight: Int) {
        if update == .extended { hasExtension = true }
        if update == .unaligned {
            if unalignedSince == nil { unalignedSince = .now }
        } else {
            unalignedSince = nil
        }
        guard !finishing, extensionTask == nil, extensionPanel == nil else { return }
        done.isEnabled = hasExtension
        eligibleEdges = hasExtension && update != .unaligned ? edges.filter {
            let available = $0 == .top ? visibleFrame.maxY - screenSelection.maxY
                                      : screenSelection.minY - visibleFrame.minY
            return available >= ScrollExtendButton.height / 2 + ScrollExtendButton.verticalPadding
        } : []
        let scrollChanged = origin != lastScrollOrigin || length != lastLength
        lastScrollOrigin = origin
        lastLength = length
        if let shownAt = extendShownAtOrigin {
            let pixelsPerPoint = CGFloat(frameHeight) / screenSelection.height
            let movedAway = update != .unaligned && origin.map { CGFloat(abs($0 - shownAt)) >= 16 * pixelsPerPoint } == true
            updateExtendDeparture(movedAway)
            return
        }
        if scrollChanged || pendingExtendEdge.map({ !eligibleEdges.contains($0) }) == true {
            resetExtendHint()
        }
        if let unalignedSince, unalignedSince.duration(to: .now) >= .milliseconds(350) {
            setStatus(.scrollUnaligned)
        } else if hasExtension {
            setStatus(axis == .horizontal ? .scrollProgressWide : .scrollProgress, length: length)
        } else {
            setStatus(.scrollReady)
        }
    }

    private func updateExtendDeparture(_ movedAway: Bool) {
        guard movedAway else {
            extendDepartureTask?.cancel()
            extendDepartureTask = nil
            return
        }
        guard extendDepartureTask == nil else { return }
        extendDepartureTask = Task { [weak self] in
            // Wait for the next frames to distinguish scrolling away from a brief bounce.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            self.resetExtendHint()
            self.setStatus(.scrollProgress, length: self.lastLength)
        }
    }

    func observeVerticalScroll(_ delta: CGFloat, at point: CGPoint) {
        guard !finishing, extensionTask == nil, extensionPanel == nil, screenSelection.contains(point) else { return }
        guard delta != 0, !extendPanel.isVisible else { return }
        let edge: ScrollVerticalEdge = delta > 0 ? .top : .bottom
        if let pendingExtendEdge, pendingExtendEdge != edge { resetExtendHint() }
        guard eligibleEdges.contains(edge), extendHintTask == nil else { return }
        pendingExtendEdge = edge
        extendHintTask = Task { [weak self] in
            // Allow the capture stream to report movement caused by this wheel event.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.extendHintTask = nil
            self.pendingExtendEdge = nil
            guard self.eligibleEdges.contains(edge), !self.finishing, self.extensionTask == nil, self.extensionPanel == nil,
                  let origin = self.lastScrollOrigin else { return }
            self.extendShownAtOrigin = origin
            self.shownExtendEdge = edge
            self.configureExtendButton(at: edge, confirming: false)
            self.positionExtendButton(at: edge == .top ? self.screenSelection.maxY : self.screenSelection.minY)
            self.setStatus(edge == .top ? .scrollTopReached : .scrollBottomReached)
            self.setExtendVisible(true)
        }
    }

    private func configureExtendButton(at edge: ScrollVerticalEdge, confirming: Bool) {
        let label = strings(confirming ? .scrollBottomApply : (edge == .top ? .scrollTopStart : .scrollBottomStart))
        extendButton.title = confirming ? "" : label
        extendButton.toolTip = label
        extendButton.setAccessibilityLabel(label)
        extendButton.isConfirming = confirming
        extendButton.edge = edge
    }

    private func positionExtendButton(at edgeY: CGFloat) {
        let height = ScrollExtendButton.height
        let labelWidth = (extendButton.title as NSString).size(
            withAttributes: [.font: extendButton.font ?? NSFont.systemFont(ofSize: 12)]).width
        let width = extendButton.isConfirming ? height : ceil(labelWidth) + 38
        // Leave room for the pulse inside the transparent panel without resizing it.
        let scaleInset = (ScrollExtendButton.attentionScale - 1) / 2
        let horizontalPadding = extendButton.isConfirming ? 0 : ceil(width * scaleInset)
        let verticalPadding = extendButton.isConfirming ? 0 : ScrollExtendButton.verticalPadding
        let x = min(visibleFrame.maxX - width - horizontalPadding,
                    max(visibleFrame.minX + horizontalPadding, screenSelection.midX - width / 2))
        let y = min(visibleFrame.maxY - height - verticalPadding,
                    max(visibleFrame.minY + verticalPadding, edgeY - height / 2))
        let frame = CGRect(x: x, y: y, width: width, height: height)
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        if extendPanel.frame != frame { extendPanel.setFrame(frame, display: false, animate: false) }
        extendButton.frame = CGRect(x: horizontalPadding, y: verticalPadding, width: width, height: height)
    }

    private func setExtendVisible(_ visible: Bool) {
        if !visible {
            extendShownAtOrigin = nil
            shownExtendEdge = nil
        }
        guard extendPanel.isVisible != visible else { return }
        if visible {
            extendPanel.orderFrontRegardless()
            extendButton.playAttentionPulse()
        } else {
            extendButton.stopAttentionPulse()
            extendPanel.orderOut(nil)
        }
    }

    private func resetExtendHint() {
        extendHintTask?.cancel()
        extendHintTask = nil
        pendingExtendEdge = nil
        extendDepartureTask?.cancel()
        extendDepartureTask = nil
        setExtendVisible(false)
    }

    private func stopObservingScroll() {
        resetExtendHint()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    func close() {
        cancelHotKey = nil
        stopObservingScroll()
        extensionTask?.cancel()
        extensionPanel?.orderOut(nil)
        extensionPanel = nil
        finishTask?.cancel()
        task?.cancel()
        source?.finishFrames()
        task = nil
        controls.orderOut(nil)
        outline.orderOut(nil)
        preview?.orderOut(nil)
        preview = nil
    }

    @objc private func cancelCapture() {
        if extensionTask != nil || extensionPanel != nil { leaveExtension() }
        else { finish() }
    }

    @objc private func toggleExtension() {
        if extensionPanel != nil { confirmExtension(); return }
        guard !finishing, extensionTask == nil, let source, let edge = shownExtendEdge else { return }
        extendHintTask?.cancel()
        extendHintTask = nil
        extendDepartureTask?.cancel()
        extendDepartureTask = nil
        extendButton.stopAttentionPulse()
        extendButton.isEnabled = false
        done.isEnabled = false
        let displayY = screenFrame.maxY - (edge == .top ? visibleFrame.maxY : visibleFrame.minY)
        extensionTask = Task { [weak self] in
            guard let self else { return }
            let image = try? await source.captureEdge(edge, through: displayY)
            guard !Task.isCancelled else { return }
            let rows = if let image { await builder.prepareExtension(at: edge, from: image) } else { 0 }
            guard !Task.isCancelled else { return }
            extensionTask = nil
            guard let image, rows > 0 else {
                extendButton.isEnabled = true
                done.isEnabled = hasExtension
                if stoppedMessage != nil { setExtendVisible(false) }
                setStatus(stoppedMessage ?? (edge == .top ? .scrollTopUnavailable : .scrollBottomUnavailable))
                return
            }
            let panel = ScrollExtensionPanel(image: image, extraRows: rows, at: edge,
                                             selection: screenSelection, strings: strings)
            panel.onConfirm = { [weak self] in self?.confirmExtension() }
            panel.onCancel = { [weak self] in self?.leaveExtension() }
            panel.onSelectionMoved = { [weak self] edgeY in self?.positionExtendButton(at: edgeY) }
            extensionPanel = panel
            let moveSelection: (NSEvent) -> Void = { [weak panel] in panel?.moveSelection(with: $0) }
            controls.onWheel = moveSelection
            extendPanel.onWheel = moveSelection
            configureExtendButton(at: edge, confirming: true)
            positionExtendButton(at: edge == .top ? screenSelection.maxY : screenSelection.minY)
            extendButton.isEnabled = true
            setDoneLabel(.scrollBottomApply)
            done.isEnabled = true
            setStatus(.scrollBottomInstructions)
            panel.revealMask()
            panel.makeKeyAndOrderFront(nil)
            outline.orderOut(nil)
        }
    }

    private func leaveExtension() {
        guard !finishing else { return }
        extensionTask?.cancel()
        extensionTask = nil
        extensionPanel?.orderOut(nil)
        extensionPanel = nil
        controls.onWheel = nil
        extendPanel.onWheel = nil
        outline.orderFrontRegardless()
        resetExtendHint()
        setDoneLabel(.done)
        extendButton.isEnabled = true
        done.isEnabled = hasExtension
        if let stoppedMessage {
            stopObservingScroll()
            setStatus(stoppedMessage)
        }
        else { setStatus(.scrollProgress, length: lastLength) }
    }

    private func confirmExtension() {
        guard !finishing, let panel = extensionPanel else { return }
        finishing = true
        done.isEnabled = false
        setExtendVisible(false)
        setStatus(.scrollFinishing)
        extensionTask = Task { [weak self] in
            guard let self else { return }
            let update = await builder.extendEdge(panel.edge, from: panel.image, rows: panel.selectedRows)
            guard !Task.isCancelled else { return }
            let message: UIKey? = update == .limit ? .scrollLimit : (update == .unaligned ? .scrollPartial : nil)
            task?.cancel()
            source?.finishFrames()
            await presentResult(message: message)
            extensionTask = nil
        }
    }

    @objc private func complete() {
        if extensionPanel != nil { confirmExtension(); return }
        guard hasExtension, !finishing, extensionTask == nil, extensionPanel == nil else { return }
        finishing = true
        done.isEnabled = false
        stopObservingScroll()
        setStatus(.scrollFinishing)
        if let stoppedMessage {
            task = Task { [weak self] in await self?.finishCapture(message: stoppedMessage) }
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

    private func setDoneLabel(_ key: UIKey) {
        done.toolTip = strings(key)
        done.setAccessibilityLabel(strings(key))
    }

    private func stop(with message: UIKey) {
        stoppedMessage = message
        if extensionPanel != nil || extensionTask != nil { return }
        done.isEnabled = hasExtension
        stopObservingScroll()
        setStatus(message)
    }

    private func finishCapture(message: UIKey? = nil) async {
        let last = await builder.commitLatest()
        guard !Task.isCancelled else { return }
        let alignmentMessage: UIKey? = last == .unaligned ? .scrollPartial : (last == .limit ? .scrollLimit : nil)
        await presentResult(message: message ?? alignmentMessage)
    }

    private func presentResult(message: UIKey?) async {
        let rendered = await builder.render()
        guard !Task.isCancelled else { return }
        guard let (image, axis) = rendered else {
            finishing = false
            if extensionPanel != nil { leaveExtension() }
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
        cancelHotKey = nil
        stopObservingScroll()
        controls.orderOut(nil)
        outline.orderOut(nil)
        extensionPanel?.orderOut(nil)
        extensionPanel = nil
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
        guard status.stringValue != message else { return }
        status.stringValue = message
        layoutControls(for: key)
    }

    private func layoutControls(for key: UIKey) {
        guard let tray = controlsSurface, let backing = controls.contentView else { return }
        let inset: CGFloat = 8
        let gap: CGFloat = 4
        let iconWidth: CGFloat = 30
        let buttonHeight = KlikTheme.controlHeight
        let actionsWidth = 2 * iconWidth + gap
        let shadowInset = KlikTheme.panelShadowInset
        let maxWidth = min(400, visibleFrame.width - 2 * shadowInset)
        // Keep the tray compact and reserve enough height for the extension instructions to wrap.
        let anchorToProgress = key == .scrollProgress || key == .scrollBottomReached || key == .scrollTopReached
            || key == .scrollBottomInstructions || (key == .scrollFinishing && extensionPanel != nil)
        let messages = anchorToProgress
            ? [strings(.scrollProgress, ScrollStitcher.maximumLength), strings(.scrollBottomReached), strings(.scrollTopReached)]
            : [status.stringValue]
        let font = status.font ?? NSFont.systemFont(ofSize: 11)
        let preferredTextWidth = ceil(messages.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0) + 4
        let textWidth = min(preferredTextWidth, max(1, maxWidth - actionsWidth - 3 * inset))
        let textBounds = CGRect(x: 0, y: 0, width: textWidth, height: 200)
        let textHeight = ceil(status.cell?.cellSize(forBounds: textBounds).height ?? 14)
        let sizingCell = status.cell?.copy() as? NSTextFieldCell
        let heightSamples = anchorToProgress ? messages + [strings(.scrollBottomInstructions)] : messages
        let reservedTextHeight = heightSamples.reduce(textHeight) { height, message in
            sizingCell?.stringValue = message
            return max(height, ceil(sizingCell?.cellSize(forBounds: textBounds).height ?? 0))
        }
        let size = CGSize(width: textWidth + actionsWidth + 3 * inset,
                          height: max(buttonHeight, reservedTextHeight) + 12)
        let surfaceFrame = Self.controlsFrame(size: size, selection: screenSelection, visible: visibleFrame)
        let windowFrame = surfaceFrame.insetBy(dx: -shadowInset, dy: -shadowInset)
        if controls.frame != windowFrame { controls.setFrame(windowFrame, display: false, animate: false) }
        tray.frame = backing.bounds.insetBy(dx: shadowInset, dy: shadowInset)
        backing.layer?.shadowPath = CGPath(roundedRect: tray.frame, cornerWidth: KlikTheme.cornerRadius,
                                           cornerHeight: KlikTheme.cornerRadius, transform: nil)

        status.frame = CGRect(x: inset, y: floor((size.height - textHeight) / 2),
                              width: textWidth, height: textHeight)
        let buttonY = floor((size.height - buttonHeight) / 2)
        let actionX = status.frame.maxX + inset
        cancel.frame = CGRect(x: actionX, y: buttonY, width: iconWidth, height: buttonHeight)
        done.frame = CGRect(x: size.width - inset - iconWidth, y: buttonY, width: iconWidth, height: buttonHeight)
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
    var onWheel: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let onWheel { onWheel(event); return }
        super.sendEvent(event)
    }
}

private final class ScrollControlButton: HoverButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ScrollExtendButton: HoverButton {
    static let height: CGFloat = 28
    static let attentionScale: CGFloat = 1.16
    static let verticalPadding = ceil(height * (attentionScale - 1) / 2)
    private static let attentionAnimationKey = "klik.extendAttention"

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isConfirming = false { didSet { needsDisplay = true } }
    var edge: ScrollVerticalEdge = .bottom { didSet { needsDisplay = true } }
    private var foreground: NSColor { isEnabled ? KlikTheme.overlayCanvas : KlikTheme.overlayMuted }

    override func updateSurface(animated: Bool) {
        needsDisplay = true
    }

    func playAttentionPulse() {
        guard !isConfirming, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let centerX = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let centerY = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        let pulse = CAKeyframeAnimation(keyPath: "transform")
        let scales: [CGFloat] = [1, Self.attentionScale, 1, 1.09, 1]
        pulse.values = scales.map { scale in
            let transform = CATransform3DMakeAffineTransform(
                CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                  tx: centerX * (1 - scale), ty: centerY * (1 - scale)))
            return NSValue(caTransform3D: transform)
        }
        pulse.keyTimes = [0, 0.20, 0.47, 0.66, 1]
        pulse.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: scales.count - 1)
        pulse.duration = 0.86
        pulse.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.add(pulse, forKey: Self.attentionAnimationKey)
    }

    func stopAttentionPulse() {
        layer?.removeAnimation(forKey: Self.attentionAnimationKey)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Use the current bounds, including on the first draw after sizing the panel.
        let pillBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = pillBounds.height / 2
        let pill = NSBezierPath(roundedRect: pillBounds, xRadius: radius, yRadius: radius)
        let background = isEnabled ? KlikTheme.accent : KlikTheme.overlaySurface
        let highlighted = isEnabled && (hovered || isHighlighted)
        let fill = highlighted ? background.blended(withFraction: 0.15, of: .white) ?? background : background
        fill.setFill()
        pill.fill()
        KlikTheme.selectionHalo.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.midY)
        if isFlipped { context.scaleBy(x: 1, y: -1) }
        context.setStrokeColor(foreground.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if isConfirming {
            context.setLineWidth(2)
            context.move(to: CGPoint(x: bounds.midX - 5, y: 0))
            context.addLine(to: CGPoint(x: bounds.midX - 1.5, y: -3.5))
            context.addLine(to: CGPoint(x: bounds.midX + 5, y: 3.5))
            context.strokePath()
            return
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: foreground
        ])
        let line = CTLineCreateWithAttributedString(text)
        let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let iconWidth: CGFloat = 8
        let spacing: CGFloat = 6
        let startX = bounds.midX - (iconWidth + spacing + inkBounds.width) / 2

        context.setLineWidth(1.4)
        let arrowX = startX + iconWidth / 2
        let direction: CGFloat = edge == .top ? 1 : -1
        context.move(to: CGPoint(x: arrowX, y: -4 * direction))
        context.addLine(to: CGPoint(x: arrowX, y: 4 * direction))
        context.move(to: CGPoint(x: arrowX - 3, y: direction))
        context.addLine(to: CGPoint(x: arrowX, y: 4 * direction))
        context.addLine(to: CGPoint(x: arrowX + 3, y: direction))
        context.strokePath()

        context.textMatrix = .identity
        context.textPosition = CGPoint(x: startX + iconWidth + spacing - inkBounds.minX, y: -inkBounds.midY)
        CTLineDraw(line, context)
    }
}

private final class ScrollExtensionPanel: NSPanel {
    let image: CGImage
    let edge: ScrollVerticalEdge
    private let canvas: ScrollExtensionView
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelectionMoved: ((CGFloat) -> Void)?
    var selectedRows: Int { canvas.selectedRows }
    func moveSelection(with event: NSEvent) { canvas.scrollWheel(with: event) }
    func revealMask() { canvas.revealMask() }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage, extraRows: Int, at edge: ScrollVerticalEdge, selection: CGRect, strings: AppStrings) {
        self.image = image
        self.edge = edge
        let scale = CGFloat(image.height - extraRows) / selection.height
        let extraHeight = CGFloat(extraRows) / scale
        let frame = CGRect(x: selection.minX, y: selection.minY - (edge == .bottom ? extraHeight : 0),
                           width: selection.width, height: selection.height + extraHeight)
        canvas = ScrollExtensionView(image: image, extraRows: extraRows, at: edge,
                                     frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = strings(edge == .top ? .scrollTopStart : .scrollBottomStart)
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        level = .floating
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        contentView = canvas
        canvas.onConfirm = { [weak self] in self?.onConfirm?() }
        canvas.onSelectionMoved = { [weak self] edgeY in
            guard let self else { return }
            onSelectionMoved?(self.frame.maxY - edgeY)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onConfirm?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

private final class ScrollExtensionView: NSView {
    private let image: NSImage
    private let dimming = ScrollExtensionDimmingView()
    private let totalRows: Int
    private let extraRows: Int
    private let edge: ScrollVerticalEdge
    private var offset: CGFloat = 0
    var onConfirm: (() -> Void)?
    var onSelectionMoved: ((CGFloat) -> Void)?
    var selectedRows: Int {
        let offsetRows = Int(offset.rounded())
        return edge == .top ? extraRows - offsetRows : offsetRows
    }
    override var isFlipped: Bool { true }

    init(image: CGImage, extraRows: Int, at edge: ScrollVerticalEdge, frame: CGRect) {
        self.image = NSImage(cgImage: image, size: frame.size)
        totalRows = image.height
        self.extraRows = extraRows
        self.edge = edge
        offset = edge == .top ? CGFloat(extraRows) : 0
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("scrollExtensionSelection")
        dimming.frame = bounds
        dimming.wantsLayer = true
        dimming.selection = selection
        addSubview(dimming)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func revealMask() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = dimming.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.20
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "klik.scrollBottomMaskFade")
    }

    override func scrollWheel(with event: NSEvent) {
        let points = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        let previousRows = selectedRows
        offset = min(CGFloat(extraRows), max(0, offset - points * CGFloat(totalRows) / bounds.height))
        guard selectedRows != previousRows else { return }
        dimming.selection = selection
        needsDisplay = true
        onSelectionMoved?(edge == .top ? selection.minY : selection.maxY)
    }

    private var selection: CGRect {
        let pointsPerRow = bounds.height / CGFloat(totalRows)
        return CGRect(x: 0, y: offset.rounded() * pointsPerRow, width: bounds.width,
                      height: CGFloat(totalRows - extraRows) * pointsPerRow)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, selection.contains(convert(event.locationInWindow, from: nil)) { onConfirm?() }
    }

    override func draw(_ dirtyRect: CGRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let outline = NSBezierPath(rect: selection.insetBy(dx: 1.5, dy: 1.5))
        KlikTheme.selectionHalo.setStroke()
        outline.lineWidth = 3
        outline.stroke()
        KlikTheme.selection.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

private final class ScrollExtensionDimmingView: NSView {
    var selection: CGRect = .zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: CGRect) {
        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(selection)
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.24).setFill()
        mask.fill()
    }
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
