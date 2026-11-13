import AppKit

struct RecognitionLayout {
    let image: CGRect
    let panel: CGRect
    let toolbar: CGRect

    static func make(bounds: CGRect, imageSize: CGSize) -> RecognitionLayout {
        let margin: CGFloat = min(24, bounds.width / 20, bounds.height / 20)
        let gap: CGFloat = min(10, bounds.width / 40, bounds.height / 40)
        let toolbarHeight = MarkupToolbarLayout.height
        let available = bounds.insetBy(dx: margin, dy: margin)
        let toolbarWidth = min(MarkupToolbarLayout.width(buttonCount: Tool.allCases.count + 6), available.width)
        let size = CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
        // Keep both cards identical while preserving the screenshot inside its card.
        // Extremely narrow/wide captures use a bounded card ratio so the text remains usable.
        let aspect = min(2.4, max(0.6, size.width / size.height))
        if size.width >= size.height {
            let preferredHeight = max(140, 240 / aspect, size.height, size.width / aspect)
            let height = min(preferredHeight, max(1, (available.height - toolbarHeight - 2 * gap) / 2),
                             available.width / aspect)
            let width = height * aspect
            let totalHeight = height * 2 + toolbarHeight + 2 * gap
            let y = available.midY - totalHeight / 2
            let x = available.midX - width / 2
            let toolbarX = max(available.minX, min(x + width - toolbarWidth, available.maxX - toolbarWidth))
            return RecognitionLayout(
                image: CGRect(x: x, y: y, width: width, height: height),
                panel: CGRect(x: x, y: y + height + toolbarHeight + 2 * gap, width: width, height: height),
                toolbar: CGRect(x: toolbarX, y: y + height + gap, width: toolbarWidth, height: toolbarHeight))
        }
        let preferredWidth = max(240, 140 * aspect, size.width, size.height * aspect)
        let maximumImageHeight = max(1, available.height - toolbarHeight - gap)
        let width = min(preferredWidth, max(1, (available.width - gap) / 2), maximumImageHeight * aspect)
        let height = width / aspect
        let totalWidth = width * 2 + gap
        let x = available.midX - totalWidth / 2
        let y = available.midY - (height + gap + toolbarHeight) / 2
        let toolbarX = max(available.minX, min(x + width - toolbarWidth, available.maxX - toolbarWidth))
        return RecognitionLayout(
            image: CGRect(x: x, y: y, width: width, height: height),
            panel: CGRect(x: x + width + gap, y: y, width: width, height: height),
            toolbar: CGRect(x: toolbarX, y: y + height + gap, width: toolbarWidth, height: toolbarHeight))
    }
}

final class TextRecognitionView: NSView {
    private let card = NSVisualEffectView()
    private let imageCard: RecognitionImageView
    private let imageSize: CGSize
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var recognizedText: String?
    private var editedTextNeedsReview = false
    private let markupToolbar = NSVisualEffectView()
    private var markupButtons: [NSButton] = []
    private let colorButton = HoverButton()
    private let mosaicOptions: MosaicOptions
    private var activeTool: Tool?
    var onMosaicStyle: ((MosaicStyle) -> Void)?
    var onPickCoverColor: (() -> Void)?
    private let palette = NSVisualEffectView()
    private var paletteButtons: [Ink: NSButton] = [:]
    private let markupUndo = HoverButton()
    private let markupRedo = HoverButton()
    private let cancelButton = HoverButton()
    private let confirmButton = HoverButton()
    private let strings: AppStrings
    private let saveButton = HoverButton()
    private let copyButton = HoverButton()
    private let refreshButton = HoverButton()
    private let refreshConfirmation = NSVisualEffectView()
    private let refreshConfirmTitle = NSTextField(labelWithString: "")
    private let refreshConfirmCancel = HoverButton()
    private let refreshConfirmReplace = ForestButton()
    private var confirmRefreshAction: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onTool: ((Tool, Bool) -> Void)?
    var onInk: ((Ink) -> Void)?
    var onPickInkColor: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    override var isFlipped: Bool { true }

    init(frame: CGRect, image: CGImage, imageSize: CGSize, selection: CGRect? = nil, strings: AppStrings) {
        self.imageSize = imageSize
        self.strings = strings
        self.mosaicOptions = MosaicOptions(strings: strings)
        self.imageCard = RecognitionImageView(image: image, selection: selection ?? CGRect(origin: .zero, size: imageSize))
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("ocrOverlay")
        wantsLayer = true
        layer?.backgroundColor = KlikTheme.overlayCanvas.withAlphaComponent(0.91).cgColor
        addSubview(imageCard)
        card.identifier = NSUserInterfaceItemIdentifier("ocrPanel")
        MarkupToolbarLayout.styleTray(card)
        addSubview(card)
        titleLabel.stringValue = strings(.ocrTitle)
        titleLabel.textColor = KlikTheme.overlayInk
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        card.addSubview(titleLabel)
        statusLabel.stringValue = strings(.ocrLoading)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = KlikTheme.overlayMuted
        statusLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(statusLabel)
        scrollView.hasVerticalScroller = true
        scrollView.identifier = NSUserInterfaceItemIdentifier("ocrEditorScroll")
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = KlikTheme.overlayCanvas
        KlikTheme.styleCaptureImage(scrollView)
        textView.isRichText = false
        textView.backgroundColor = KlikTheme.overlayCanvas
        textView.textColor = KlikTheme.overlayInk
        textView.insertionPointColor = KlikTheme.accent
        textView.selectedTextAttributes = [.backgroundColor: KlikTheme.buttonSelected, .foregroundColor: KlikTheme.overlayInk]
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.identifier = NSUserInterfaceItemIdentifier("ocrText")
        scrollView.documentView = textView
        card.addSubview(scrollView)
        configureIcon(saveButton, symbol: "download", fallback: "arrow.down.to.line", label: strings(.ocrSaveImage))
        saveButton.target = self
        saveButton.action = #selector(saveImage)
        saveButton.toolTip = strings(.ocrSaveImageHint)
        saveButton.identifier = NSUserInterfaceItemIdentifier("ocrSaveImage")
        saveButton.contentTintColor = KlikTheme.overlayInk
        configureIcon(copyButton, symbol: "copy", fallback: "doc.on.doc", label: strings(.ocrCopy))
        copyButton.toolTip = strings(.ocrCopy)
        copyButton.target = self
        copyButton.action = #selector(copyText)
        copyButton.isEnabled = false
        copyButton.identifier = NSUserInterfaceItemIdentifier("ocrCopy")
        card.addSubview(copyButton)
        configureIcon(refreshButton, symbol: "refresh-cw", fallback: "arrow.clockwise", label: strings(.ocrRefresh))
        refreshButton.toolTip = strings(.ocrRefresh)
        refreshButton.target = self
        refreshButton.action = #selector(refreshText)
        refreshButton.isEnabled = false
        refreshButton.identifier = NSUserInterfaceItemIdentifier("ocrRefresh")
        card.addSubview(refreshButton)
        refreshConfirmation.identifier = NSUserInterfaceItemIdentifier("ocrRefreshConfirmation")
        MarkupToolbarLayout.styleTray(refreshConfirmation, radius: KlikTheme.badgeRadius)
        refreshConfirmation.isHidden = true
        refreshConfirmTitle.stringValue = strings(.ocrReplaceTitle)
        refreshConfirmTitle.textColor = KlikTheme.overlayInk
        refreshConfirmTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        refreshConfirmTitle.alignment = .center
        refreshConfirmTitle.lineBreakMode = .byTruncatingTail
        refreshConfirmation.addSubview(refreshConfirmTitle)
        MarkupToolbarLayout.configureButton(refreshConfirmCancel, symbol: "x", fallback: "xmark",
            label: strings(.cancel), target: self, action: #selector(cancelRefreshConfirmation))
        refreshConfirmCancel.identifier = NSUserInterfaceItemIdentifier("ocrRefreshCancel")
        refreshConfirmation.addSubview(refreshConfirmCancel)
        refreshConfirmReplace.title = strings(.ocrReplaceButton)
        refreshConfirmReplace.isPrimary = true
        refreshConfirmReplace.identifier = NSUserInterfaceItemIdentifier("ocrRefreshReplace")
        refreshConfirmReplace.target = self
        refreshConfirmReplace.action = #selector(confirmRefresh)
        refreshConfirmation.addSubview(refreshConfirmReplace)
        card.addSubview(refreshConfirmation, positioned: .above, relativeTo: nil)
        buildMarkupToolbar()
        addSubview(mosaicOptions)
        mosaicOptions.onPickColor = { [weak self] in self?.onPickCoverColor?() }
        mosaicOptions.onSelect = { [weak self] style in
            self?.mosaicOptions.isHidden = true
            self?.onMosaicStyle?(style)
        }
        textView.isEditable = false
        layoutControls()
    }

    required init?(coder: NSCoder) { nil }

    // Consume background clicks so they cannot reach the selection canvas behind this view.
    override func mouseDown(with event: NSEvent) { palette.isHidden = true }
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func layout() {
        super.layout()
        layoutControls()
    }

    func textContains(_ point: CGPoint) -> Bool {
        textView.isEditable && scrollView.convert(scrollView.bounds, to: self).contains(point)
    }

    func isEditingText(_ responder: NSResponder?) -> Bool { responder === textView }
    var isEditingMarkupText: Bool { imageCard.isEditingMarkupText }
    func commitMarkupText() { imageCard.commitText() }
    func cancelMarkupText() { imageCard.cancelText() }
    func beginMarkupText(at point: CGPoint, size: CGFloat, ink: Ink, existing: String? = nil) { imageCard.beginText(at: point, size: size, ink: ink, existing: existing) }
    func updateMarkupTextSize(_ value: CGFloat) { imageCard.updateTextSize(value) }
    func setMarkupHandlers(down: @escaping (CGPoint, Int) -> Void, drag: @escaping (CGPoint, NSEvent.ModifierFlags) -> Void,
                           up: @escaping (CGPoint, NSEvent.ModifierFlags) -> Void, text: @escaping (String, CGPoint) -> Void) {
        imageCard.onDown = down; imageCard.onDrag = drag; imageCard.onUp = up; imageCard.onTextCommit = text
    }
    func setImage(_ image: CGImage, selectedPoints: [CGPoint]) { imageCard.update(image: image, selectedPoints: selectedPoints) }
    var imageScale: CGFloat { imageCard.imageScale }
    func paletteContains(_ point: CGPoint) -> Bool {
        (!palette.isHidden && palette.frame.contains(point)) || (!mosaicOptions.isHidden && mosaicOptions.frame.contains(point))
    }
    func setMosaicStyle(_ style: MosaicStyle) { mosaicOptions.select(style) }
    func hideMosaicOptions() { mosaicOptions.isHidden = true }
    func showMosaicOptions() { mosaicOptions.isHidden = false; needsLayout = true }
    func setCanPickCoverColor(_ available: Bool) { mosaicOptions.setCanPickColor(available); needsLayout = true }
    func refreshConfirmationContains(_ point: CGPoint) -> Bool {
        !refreshConfirmation.isHidden && refreshConfirmation.frame.contains(card.convert(point, from: self))
    }
    func markupInputContains(_ point: CGPoint) -> Bool {
        imageCard.inputContains(imageCard.convert(point, from: self))
    }
    func capturePoint(at point: CGPoint) -> CGPoint? {
        imageCard.capturePoint(for: imageCard.convert(point, from: self))
    }
    func imageContains(_ point: CGPoint) -> Bool {
        let local = imageCard.convert(point, from: self)
        return imageCard.imageRect.contains(local)
    }

    func setMarkupState(tool: Tool?, ink: Ink, canUndo: Bool, canRedo: Bool) {
        activeTool = tool
        for (index, button) in markupButtons.enumerated() {
            (button as? HoverButton)?.toolSelected = Tool.allCases[index] == tool
        }
        colorButton.image = MarkupToolbarLayout.swatch(ink)
        for (color, button) in paletteButtons {
            button.image = MarkupToolbarLayout.swatch(color, selected: color == ink)
        }
        colorButton.toolTip = strings(.inkPicker, strings(ink.label))
        colorButton.setAccessibilityLabel(colorButton.toolTip)
        markupUndo.isEnabled = canUndo
        markupRedo.isEnabled = canRedo
    }

    private func buildMarkupToolbar() {
        markupToolbar.identifier = NSUserInterfaceItemIdentifier("ocrMarkupToolbar")
        MarkupToolbarLayout.styleTray(markupToolbar)
        addSubview(markupToolbar)
        let fallbacks = ["circle", "rectangle", "arrow.up.right", "pencil", "textformat", "square.grid.3x3"]
        for (index, tool) in Tool.allCases.enumerated() {
            let button = HoverButton()
            let item = tool.item
            configureIcon(button, symbol: item.symbol, fallback: fallbacks[index], label: strings(item.label))
            button.contentTintColor = KlikTheme.overlayInk
            button.toolTip = strings(item.label)
            button.target = self
            button.action = #selector(selectMarkupTool(_:))
            button.tag = index
            button.wantsLayer = true
            KlikTheme.round(button.layer, radius: KlikTheme.controlRadius, clips: false)
            markupButtons.append(button)
            markupToolbar.addSubview(button)
        }
        colorButton.isBordered = false
        colorButton.imagePosition = .imageOnly
        colorButton.target = self
        colorButton.action = #selector(showColors(_:))
        markupToolbar.addSubview(colorButton)
        configureIcon(markupUndo, symbol: "undo", fallback: "arrow.uturn.backward", label: strings(.toolUndo))
        markupUndo.contentTintColor = KlikTheme.overlayInk
        markupUndo.toolTip = strings(.toolUndo)
        markupUndo.target = self; markupUndo.action = #selector(undoMarkup)
        markupToolbar.addSubview(markupUndo)
        configureIcon(markupRedo, symbol: "redo", fallback: "arrow.uturn.forward", label: strings(.toolRedo))
        markupRedo.contentTintColor = KlikTheme.overlayInk
        markupRedo.toolTip = strings(.toolRedo)
        markupRedo.target = self; markupRedo.action = #selector(redoMarkup)
        markupToolbar.addSubview(markupRedo)
        markupToolbar.addSubview(saveButton)
        configureIcon(cancelButton, symbol: "x", fallback: "xmark", label: strings(.ocrCancel))
        cancelButton.contentTintColor = KlikTheme.danger
        cancelButton.toolTip = strings(.ocrCancel)
        cancelButton.identifier = NSUserInterfaceItemIdentifier("ocrCancel")
        cancelButton.target = self; cancelButton.action = #selector(cancelCapture)
        markupToolbar.addSubview(cancelButton)
        configureIcon(confirmButton, symbol: "check", fallback: "checkmark", label: strings(.ocrConfirm))
        confirmButton.contentTintColor = KlikTheme.accent
        confirmButton.toolTip = strings(.ocrConfirm)
        confirmButton.identifier = NSUserInterfaceItemIdentifier("ocrConfirm")
        confirmButton.target = self; confirmButton.action = #selector(confirmCapture)
        markupToolbar.addSubview(confirmButton)
        palette.identifier = NSUserInterfaceItemIdentifier("ocrColorPalette")
        MarkupToolbarLayout.styleTray(palette)
        palette.isHidden = true
        addSubview(palette)
        for (index, ink) in Ink.allCases.enumerated() {
            let button = HoverButton(frame: CGRect(x: 5 + 27 * index, y: 4, width: 27, height: 27))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.refusesFirstResponder = true
            button.tag = index
            button.toolTip = strings(ink.label)
            button.setAccessibilityLabel(strings(ink.label))
            button.target = self
            button.action = #selector(selectColor(_:))
            palette.addSubview(button)
            paletteButtons[ink] = button
        }
        let picker = HoverButton(frame: CGRect(x: 5 + 27 * Ink.allCases.count, y: 4, width: 27, height: 27))
        picker.isBordered = false
        picker.imagePosition = .imageOnly
        picker.refusesFirstResponder = true
        picker.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        picker.contentTintColor = KlikTheme.overlayInk
        picker.toolTip = strings(.inkSample)
        picker.setAccessibilityLabel(strings(.inkSample))
        picker.target = self
        picker.action = #selector(pickInkColor)
        palette.addSubview(picker)
    }

    @objc private func pickInkColor() {
        palette.isHidden = true
        onPickInkColor?()
    }

    @objc private func selectMarkupTool(_ sender: NSButton) {
        palette.isHidden = true
        commitMarkupText()
        let chosen = Tool.allCases[sender.tag]
        var deselect = false
        if chosen == .mosaic {
            mosaicOptions.isHidden = activeTool == .mosaic ? !mosaicOptions.isHidden : false
        } else {
            mosaicOptions.isHidden = true
            deselect = activeTool == chosen
        }
        onTool?(chosen, deselect)
    }
    @objc private func undoMarkup() { palette.isHidden = true; commitMarkupText(); onUndo?() }
    @objc private func redoMarkup() { palette.isHidden = true; commitMarkupText(); onRedo?() }
    @objc private func showColors(_ sender: NSButton) {
        commitMarkupText()
        mosaicOptions.isHidden = true
        palette.isHidden.toggle()
    }
    @objc private func selectColor(_ sender: NSButton) {
        palette.isHidden = true
        onInk?(Ink.allCases[sender.tag])
    }

    private func configureIcon(_ button: NSButton, symbol: String, fallback: String, label: String) {
        let image = Bundle.main.url(forResource: symbol, withExtension: "svg", subdirectory: "Lucide")
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage(systemSymbolName: fallback, accessibilityDescription: label)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = KlikTheme.overlayInk
        button.setAccessibilityLabel(label)
    }

    private func layoutControls() {
        let placement = RecognitionLayout.make(bounds: bounds, imageSize: imageSize)
        imageCard.frame = placement.image
        card.frame = placement.panel
        let width = card.bounds.width, height = card.bounds.height
        let inset: CGFloat = 16
        let buttonSize = KlikTheme.controlHeight
        // NSVisualEffectView uses an unflipped coordinate system.
        titleLabel.frame = CGRect(x: 16, y: height - 34, width: width - 32, height: 20)
        statusLabel.frame = CGRect(x: 16, y: height - 52, width: width - 32, height: 16)
        let headerHeight: CGFloat = statusLabel.isHidden ? 42 : 60
        scrollView.frame = CGRect(x: 16, y: 50, width: max(1, width - 32),
                                  height: max(1, height - 50 - headerHeight))
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        if textView.frame.width != scrollView.contentSize.width {
            textView.setFrameSize(NSSize(width: scrollView.contentSize.width,
                                         height: max(textView.frame.height, scrollView.contentSize.height)))
        }
        copyButton.frame = CGRect(x: max(inset, width - inset - buttonSize), y: 10,
                                  width: buttonSize, height: buttonSize)
        refreshButton.frame = CGRect(x: max(inset, copyButton.frame.minX - buttonSize - 6), y: 10,
                                     width: buttonSize, height: buttonSize)
        let confirmationWidth = max(1, min(196, width - 16))
        let confirmationHeight: CGFloat = 64
        let confirmationX = max(8, min(refreshButton.frame.maxX - confirmationWidth + 8, width - confirmationWidth - 8))
        refreshConfirmation.frame = CGRect(x: confirmationX,
                                           y: max(4, min(refreshButton.frame.maxY + 4, height - confirmationHeight - 4)),
                                           width: confirmationWidth, height: confirmationHeight)
        refreshConfirmTitle.frame = CGRect(x: 8, y: 37, width: max(1, confirmationWidth - 16), height: 18)
        let buttonSpace = max(0, confirmationWidth - 20)
        let cancelWidth = min(MarkupToolbarLayout.buttonWidth, buttonSpace * 0.42)
        let replaceWidth = buttonSpace - cancelWidth
        refreshConfirmCancel.frame = CGRect(x: 7, y: 5, width: cancelWidth, height: KlikTheme.controlHeight)
        refreshConfirmReplace.frame = CGRect(x: refreshConfirmCancel.frame.maxX + 6, y: 5, width: replaceWidth, height: KlikTheme.controlHeight)
        markupToolbar.frame = placement.toolbar
        let paletteWidth: CGFloat = 10 + 27 * CGFloat(Ink.allCases.count + 1)
        let paletteX = max(5, min(placement.toolbar.minX + colorButton.frame.midX - paletteWidth / 2,
                                  bounds.width - paletteWidth - 5))
        let below = placement.toolbar.maxY + 6
        let paletteY = below + 35 <= bounds.maxY - 5 ? below : max(5, placement.toolbar.minY - 41)
        palette.frame = CGRect(x: paletteX, y: paletteY, width: paletteWidth, height: 35)
        let buttons = markupButtons + [colorButton, markupUndo, markupRedo, saveButton, cancelButton, confirmButton]
        MarkupToolbarLayout.arrange(buttons: buttons, width: placement.toolbar.width)
        palette.frame.origin.x = max(5, min(placement.toolbar.minX + colorButton.frame.midX - paletteWidth / 2,
                                            bounds.width - paletteWidth - 5))
        let anchor = markupButtons[Tool.allCases.firstIndex(of: .mosaic)!].frame.midX
        let optionsX = max(5, min(placement.toolbar.minX + anchor - mosaicOptions.frame.width / 2,
                                  bounds.maxX - mosaicOptions.frame.width - 5))
        let optionsY = below + mosaicOptions.frame.height <= bounds.maxY - 5 ? below
            : max(5, placement.toolbar.minY - mosaicOptions.frame.height - 6)
        mosaicOptions.setFrameOrigin(CGPoint(x: optionsX, y: optionsY))

    }

    func showCopiedConfirmation() {
        copyButton.showBriefConfirmation(symbol: "checkmark", color: KlikTheme.accent)
        copyButton.setAccessibilityHelp(strings(.ocrCopied))
    }

    var saveButtonScreenFrame: CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(saveButton.convert(saveButton.bounds, to: nil))
    }

    func showSaveConfirmation(success: Bool) {
        saveButton.showBriefConfirmation(symbol: success ? "checkmark" : "xmark",
                                         color: success ? KlikTheme.accent : KlikTheme.danger)
    }

    var hasUserEdits: Bool {
        guard let recognizedText else { return false }
        return editedTextNeedsReview || textView.string != recognizedText
    }

    func preserveEditedTextForChangedImage(isDrawing: Bool) -> Bool {
        guard hasUserEdits else { return false }
        editedTextNeedsReview = true
        statusLabel.textColor = KlikTheme.danger
        statusLabel.stringValue = strings(.ocrEditedImageChanged)
        statusLabel.toolTip = statusLabel.stringValue
        statusLabel.isHidden = false
        if !isDrawing {
            textView.isEditable = true
            refreshButton.isEnabled = true
        }
        copyButton.isEnabled = !isDrawing && !textView.string.isEmpty
        layoutControls()
        return true
    }

    func showResult(_ text: String, emptyMessage: String) {
        recognizedText = text
        editedTextNeedsReview = false
        textView.string = text
        textView.isEditable = !text.isEmpty
        copyButton.isEnabled = !text.isEmpty
        refreshButton.isEnabled = true
        statusLabel.textColor = KlikTheme.overlayMuted
        statusLabel.toolTip = nil
        statusLabel.stringValue = text.isEmpty ? emptyMessage : ""
        statusLabel.isHidden = !text.isEmpty
        layoutControls()
    }

    func showLoading(preservingText: Bool = false) {
        if !preservingText {
            recognizedText = nil
            textView.string = ""
        }
        textView.isEditable = false
        copyButton.isEnabled = false
        refreshButton.isEnabled = false
        statusLabel.textColor = KlikTheme.overlayMuted
        statusLabel.toolTip = nil
        statusLabel.stringValue = strings(.ocrLoading)
        statusLabel.isHidden = false
        layoutControls()
    }

    func showError(_ message: String, preservingText: Bool = false) {
        statusLabel.textColor = KlikTheme.overlayMuted
        statusLabel.toolTip = nil
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        if !preservingText { textView.string = "" }
        textView.isEditable = preservingText
        copyButton.isEnabled = preservingText && !textView.string.isEmpty
        refreshButton.isEnabled = true
        layoutControls()
    }

    func showStatus(_ message: String) {
        statusLabel.textColor = KlikTheme.overlayMuted
        statusLabel.toolTip = nil
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        layoutControls()
    }

    @objc private func saveImage() { commitMarkupText(); onSave?() }
    @objc private func cancelCapture() { onCancel?() }
    @objc private func confirmCapture() { commitMarkupText(); onConfirm?() }
    @objc private func copyText() { commitMarkupText(); onCopy?(textView.string) }
    func showRefreshConfirmation(_ action: @escaping () -> Void) {
        confirmRefreshAction = action
        refreshConfirmation.isHidden = false
        layoutControls()
    }

    @objc private func cancelRefreshConfirmation() {
        refreshConfirmation.isHidden = true
        confirmRefreshAction = nil
    }

    @objc private func confirmRefresh() {
        let action = confirmRefreshAction
        cancelRefreshConfirmation()
        action?()
    }

    @objc private func refreshText() {
        commitMarkupText()
        if !refreshConfirmation.isHidden { cancelRefreshConfirmation(); return }
        onRefresh?()
    }
}
