import AppKit
import Carbon

final class ScrollCapturePreview: NSPanel {
    var onCancel: (() -> Void)?
    var onExport: ((CaptureView.Destination, CGImage) -> Void)?
    private var canvas: CaptureView!
    private let scroll = NSScrollView()
    private let dimensions = NSTextField(labelWithString: "")
    private let sizeHint = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")

    var isExporting = false {
        didSet { canvas.setDocumentExporting(isExporting) }
    }

    var saveButtonScreenFrame: CGRect? { canvas.downloadButtonScreenFrame }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage, axis: ScrollAxis, screenFrame: CGRect, strings: AppStrings, message: UIKey?) {
        let size = CGSize(width: min(680, screenFrame.width * 0.83), height: min(740, screenFrame.height * 0.8))
        let rect = CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2,
                          width: size.width, height: size.height)
        let shadowInset = KlikTheme.panelShadowInset
        super.init(contentRect: rect.insetBy(dx: -shadowInset, dy: -shadowInset),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = strings(.scrollPreviewTitle)
        appearance = NSAppearance(named: .darkAqua)
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]

        let root = KlikTheme.installPanelSurface(in: self, radius: KlikTheme.windowRadius,
                                                 identifier: "scrollPreviewSurface")

        let inset: CGFloat = 16
        let footerHeight: CGFloat = 54
        let imageFrame = CGRect(x: inset, y: inset + footerHeight,
                                width: size.width - 2 * inset, height: size.height - footerHeight - 2 * inset)
        let imageWell = NSView(frame: imageFrame)
        KlikTheme.styleCaptureImage(imageWell)
        root.addSubview(imageWell)

        scroll.frame = imageWell.bounds
        scroll.identifier = NSUserInterfaceItemIdentifier("scrollPreviewImage")
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light
        scroll.backgroundColor = KlikTheme.overlayCanvas
        scroll.minMagnification = 0.5
        scroll.maxMagnification = 4
        scroll.allowsMagnification = true
        let padding: CGFloat = 10
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let fittingScale = axis == .vertical
            ? (scroll.contentSize.width - 2 * padding) / imageWidth
            : (scroll.contentSize.height - 2 * padding) / imageHeight
        let scale = min(1, fittingScale)
        let imageSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
        let documentSize = CGSize(width: max(scroll.contentSize.width, imageSize.width + 2 * padding),
                                  height: max(scroll.contentSize.height, imageSize.height + 2 * padding))
        let origin = CGPoint(x: (documentSize.width - imageSize.width) / 2,
                             y: (documentSize.height - imageSize.height) / 2)
        let document = CaptureImage(image: image, size: imageSize, origin: origin)
        canvas = CaptureView(document: document, size: documentSize, strings: strings) { [weak self] in
            self?.onCancel?()
        }
        canvas.onDocumentExport = { [weak self] destination, rendered in self?.onExport?(destination, rendered) }
        canvas.onDocumentStatus = { [weak self] in self?.showStatus($0) }
        canvas.onDocumentSizeChange = { [weak self] size in
            self?.dimensions.stringValue = strings(.scrollDimensions, Int(size.width), Int(size.height))
        }
        scroll.documentView = canvas
        imageWell.addSubview(scroll)
        initialFirstResponder = canvas

        let toolbar = canvas.pinDocumentToolbar(to: root, inset: inset)
        let labelWidth = max(1, toolbar.minX - inset - 18)
        dimensions.stringValue = strings(.scrollDimensions, image.width, image.height)
        dimensions.textColor = KlikTheme.overlayMuted
        dimensions.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dimensions.frame = CGRect(x: inset, y: toolbar.midY + 1, width: labelWidth, height: 16)
        root.addSubview(dimensions)
        sizeHint.identifier = NSUserInterfaceItemIdentifier("scrollPreviewSizeHint")
        sizeHint.stringValue = strings(.scrollSizeHint)
        sizeHint.textColor = KlikTheme.overlayMuted
        sizeHint.font = .systemFont(ofSize: 11)
        sizeHint.lineBreakMode = .byTruncatingTail
        sizeHint.toolTip = strings(.scrollSizeHint)
        sizeHint.frame = CGRect(x: inset, y: toolbar.midY - 15, width: labelWidth, height: 16)
        root.addSubview(sizeHint)
        status.font = .systemFont(ofSize: 11)
        status.textColor = KlikTheme.overlayMuted
        status.maximumNumberOfLines = 2
        status.frame = CGRect(x: inset, y: 11, width: labelWidth, height: 27)
        status.isHidden = true
        root.addSubview(status)
        if let message { showStatus(strings(message)) }
    }

    func present() {
        let duration = KlikTheme.transitionDuration
        alphaValue = duration > 0 ? 0 : 1
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }
    }

    func showStatus(_ message: String) {
        sizeHint.isHidden = true
        status.stringValue = message
        status.toolTip = message
        status.isHidden = false
        dimensions.frame.origin.y = status.frame.maxY + 2
    }

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .scrollWheel {
            if modifiers == .command {
                let point = event.window == nil ? convertPoint(fromScreen: event.locationInWindow) : event.locationInWindow
                let clip = scroll.contentView
                let anchor = clip.convert(point, from: nil)
                if clip.bounds.contains(anchor) {
                    zoom(with: event, anchoredAt: anchor, windowPoint: point)
                    return
                }
            }
            if canvas.adjustMarkupSize(with: event) { return }
        }
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if canvas.isCropping, modifiers.isEmpty {
                    canvas.applyCrop()
                    return
                } else if canvas.isEditingText, modifiers.isEmpty {
                    canvas.finishTextEditing()
                    return
                } else if canvas.isEditingText, modifiers == .shift {
                    (firstResponder as? InlineMarkupTextView)?.insertNewline(nil)
                    return
                } else if !canvas.isEditingText, modifiers.isEmpty {
                    if !event.isARepeat { canvas.export(.clipboard) }
                    return
                }
            case kVK_Escape where modifiers.isEmpty:
                if canvas.isCropping { canvas.cancelCrop() }
                else if canvas.isEditingText { canvas.cancelActiveTextEditing() }
                else { onCancel?() }
                return
            case kVK_Delete, kVK_ForwardDelete:
                if modifiers.isEmpty && !canvas.isEditingText && canvas.deleteSelectedMark() { return }
            case kVK_ANSI_Z where !canvas.isEditingText:
                if modifiers == .command { canvas.undo(); return }
                if modifiers == [.command, .shift] { canvas.redo(); return }
            default: break
            }
        }
        super.sendEvent(event)
        if isVisible, [.mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
                       .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .magnify].contains(event.type) {
            if event.type == .scrollWheel || event.type == .magnify { canvas.updateDocumentViewport() }
            canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
        }
    }

    private func zoom(with event: NSEvent, anchoredAt anchor: CGPoint, windowPoint: CGPoint) {
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }
        let steps = event.hasPreciseScrollingDeltas ? delta / 12 : delta
        let factor = pow(1.12, max(-20, min(20, steps)))
        scroll.setMagnification(scroll.magnification * factor, centeredAt: anchor)
        canvas.updateDocumentViewport()
        canvas.updatePointer(at: windowPoint)
    }

    override func orderOut(_ sender: Any?) {
        canvas?.clearPointer()
        super.orderOut(sender)
    }

    override func performClose(_ sender: Any?) { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
