import AppKit
import Carbon

final class CapturePanel: NSPanel {
    enum Outcome { case cancelled, exported }

    private let canvas: CaptureView

    init(frame: CGRect, image: CGImage, windowFrames: [CGRect] = [], strings: AppStrings = AppStrings(),
         guided: Bool = false, finish: @escaping (Outcome) -> Void) {
        canvas = CaptureView(background: CaptureImage(image: image, size: frame.size),
                             windowFrames: windowFrames, strings: strings, guided: guided, finish: finish)
        super.init(contentRect: frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        level = .screenSaver
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        contentView = canvas
        initialFirstResponder = canvas
        // The overlay owns the cursor. AppKit cursor rectangles would otherwise compete with it.
        disableCursorRects()
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() -> Bool {
        makeKeyAndOrderFront(nil)
        guard isKeyWindow else { return false }
        canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, self.isKeyWindow else { return }
            self.canvas.updatePointer(at: self.mouseLocationOutsideOfEventStream, force: true)
        }
        return true
    }

    override func orderOut(_ sender: Any?) {
        canvas.clearPointer()
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let key = Int(event.keyCode)
            if key == kVK_Escape {
                canvas.cancel()
                return
            }
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            if !composing, key == kVK_Return || key == kVK_ANSI_KeypadEnter {
                canvas.export(.clipboard)
                return
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if !canvas.isEditingText, modifiers == .command, event.charactersIgnoringModifiers == "z" {
                canvas.undo()
                return
            }
        }
        if event.type == .cursorUpdate, isVisible {
            canvas.updatePointer(at: mouseLocationOutsideOfEventStream, force: true)
            return
        }
        super.sendEvent(event)
        if isVisible && [.mouseMoved, .mouseEntered, .mouseExited, .flagsChanged,
                         .leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
        }
    }
}

private final class PointerView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class CaptureHint: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private enum Tool: CaseIterable {
    case rectangle, arrow, pen, text, mosaic

    var item: (symbol: String, label: UIKey, detail: UIKey) {
        switch self {
        case .rectangle: return ("rectangle-horizontal", .toolRectangle, .practiceRectangle)
        case .arrow: return ("arrow-up-right", .toolArrow, .practiceArrow)
        case .pen: return ("pencil", .toolPen, .practicePen)
        case .text: return ("type", .toolText, .practiceText)
        case .mosaic: return ("grid-3x3", .toolMosaic, .practiceMosaic)
        }
    }

    var usesInk: Bool { self != .mosaic }
}

private final class CaptureView: NSView {
    enum Destination { case clipboard, downloads }

    private enum Drag {
        case select(CGPoint, moved: Bool)
        case resize(Selection.Handle, CGRect, CGPoint)
        case move(CGRect, CGPoint)
        case mark(Tool, CGPoint)
    }

    private enum Pointer: Equatable {
        case crosshair, arrow, hand, text
        case resize(Selection.Handle)

        var cursor: NSCursor {
            switch self {
            case .crosshair: return .crosshair
            case .arrow: return .arrow
            case .hand: return .pointingHand
            case .text: return .iBeam
            case .resize(let handle): return handle.cursor
            }
        }

        var resizeHandle: Selection.Handle? {
            if case .resize(let handle) = self { return handle }
            return nil
        }
    }

    private let background: CaptureImage
    private let windowFrames: [CGRect]
    private let strings: AppStrings
    private let finish: (CapturePanel.Outcome) -> Void
    private let coach: CaptureCoach?
    private var practiceSteps: [CaptureCoach.Step] = []
    private let toolbar = NSVisualEffectView()
    private let palette = NSVisualEffectView()
    private let modeHint = CaptureHint(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let pointerView = PointerView()
    private let undoButton = NSButton()
    private let inkButton = NSButton()
    private let toolbarDividers = [NSView(), NSView()]
    private var toolbarButtons: [NSButton] = []
    private var toolButtons: [Tool: NSButton] = [:]
    private var paletteButtons: [Ink: NSButton] = [:]
    private var selection: CGRect?
    private var draftSelection: CGRect?
    private var hoveredWindow: CGRect?
    private var marks: [Mark] = []
    private var preview: Mark?
    private var drag: Drag?
    private var strokePoints: [CGPoint] = []
    private var tool: Tool?
    private var ink: Ink = .red
    private var showPalette = false
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    private var pointerTracking: NSTrackingArea?
    private var pointer: Pointer?
    private var pointerHotSpot = CGPoint.zero
    private var systemCursorHidden = false

    init(background: CaptureImage, windowFrames: [CGRect], strings: AppStrings, guided: Bool,
         finish: @escaping (CapturePanel.Outcome) -> Void) {
        self.background = background
        self.windowFrames = windowFrames
        self.strings = strings
        self.coach = guided ? CaptureCoach(strings: strings) : nil
        self.finish = finish
        super.init(frame: CGRect(origin: .zero, size: background.size))
        buildToolbar()
        buildPalette()
        if let coach {
            addSubview(coach)
            coach.onChange = { [weak self] in self?.refresh() }
        }
        modeHint.font = .systemFont(ofSize: 12, weight: .medium)
        modeHint.textColor = KlikTheme.overlayInk
        modeHint.alignment = .center
        modeHint.wantsLayer = true
        modeHint.layer?.cornerRadius = 9
        modeHint.layer?.backgroundColor = KlikTheme.panelTint.cgColor
        addSubview(modeHint)
        errorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.backgroundColor = NSColor(white: 0.12, alpha: 0.96)
        errorLabel.drawsBackground = true
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        addSubview(errorLabel)
        pointerView.imageScaling = .scaleNone
        pointerView.wantsLayer = true
        pointerView.isHidden = true
        pointerView.setAccessibilityElement(false)
        addSubview(pointerView, positioned: .above, relativeTo: nil)
        refresh()
    }

    deinit {
        if systemCursorHidden { CGDisplayShowCursor(CGMainDisplayID()) }
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var isEditingText: Bool { textField != nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTracking = area
    }

    func clearPointer() {
        if systemCursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            systemCursorHidden = false
        } else if pointer != nil {
            NSCursor.arrow.set()
        }
        pointerView.isHidden = true
        pointer = nil
    }

    func updatePointer(at windowPoint: CGPoint, force: Bool = false) {
        let point = convert(windowPoint, from: nil)
        let candidate = selection == nil && drag == nil && !NSEvent.modifierFlags.contains(.shift)
            ? WindowSnap.target(at: point, in: windowFrames) : nil
        if hoveredWindow != candidate {
            hoveredWindow = candidate
            needsDisplay = true
        }
        guard bounds.contains(point) else {
            clearPointer()
            return
        }

        let next: Pointer
        if hoveredWindow != nil {
            next = .hand
        } else if let textField, textField.frame.contains(point) {
            next = .text
        } else if (!toolbar.isHidden && toolbar.frame.contains(point))
                    || (!palette.isHidden && palette.frame.contains(point))
                    || coach?.hitTest(point) != nil {
            next = .arrow
        } else if case .resize(let handle, _, _) = drag {
            next = .resize(handle)
        } else if drag == nil, let selection, let handle = Selection.Handle.hit(
            at: point, in: selection, retaining: pointer?.resizeHandle
        ) {
            next = .resize(handle)
        } else {
            next = .crosshair
        }
        let shapeChanged = pointer != next
        if shapeChanged {
            pointer = next
            let cursor = next.cursor
            pointerView.image = cursor.image
            pointerView.setFrameSize(cursor.image.size)
            pointerHotSpot = cursor.hotSpot
        }
        if !systemCursorHidden, shapeChanged || force {
            // The system may replace NSCursor.set() after an event. A single
            // pointer drawn in the overlay cannot be overwritten by AppKit.
            systemCursorHidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
            if !systemCursorHidden { next.cursor.set() }
        }
        if systemCursorHidden {
            pointerView.setFrameOrigin(CGPoint(x: point.x - pointerHotSpot.x, y: point.y - pointerHotSpot.y))
            pointerView.isHidden = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        background.draw(in: context)
        let active = draftSelection ?? selection ?? (drag == nil ? hoveredWindow : nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        let mask = CGMutablePath()
        mask.addRect(bounds)
        if let active { mask.addRect(active) }
        context.addPath(mask)
        context.drawPath(using: .eoFill)

        guard let active else { return }
        if selection != nil, draftSelection == nil {
            context.saveGState()
            context.clip(to: active)
            for mark in marks { mark.draw(in: context, background: background) }
            preview?.draw(in: context, background: background)
            context.restoreGState()
        }
        let outline = NSColor(srgbRed: 0.19, green: 0.65, blue: 1, alpha: 1).cgColor
        context.setStrokeColor(outline)
        context.setLineWidth(1.5)
        context.stroke(active)
        if selection != nil, draftSelection == nil {
            for handle in Selection.Handle.allCases {
                let center = handle.center(in: active)
                let dot = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        showPalette = false
        commitText()
        window?.makeFirstResponder(self)
        errorLabel.isHidden = true
        let point = mousePoint(event)
        if let selection, let handle = Selection.Handle.hit(at: point, in: selection,
                                                             retaining: pointer?.resizeHandle) {
            drag = .resize(handle, selection, point)
        } else if let selection, selection.contains(point) {
            switch tool {
            case .text:
                beginText(at: point, in: selection)
            case .some(let tool):
                drag = .mark(tool, point)
                if tool == .pen || tool == .mosaic {
                    strokePoints = [point]
                    preview = tool == .pen ? .pen(strokePoints, ink) : .mosaic(strokePoints)
                }
            case .none:
                drag = .move(selection, point)
            }
        } else {
            drag = .select(point, moved: false)
            draftSelection = CGRect(origin: point, size: .zero)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(at: mousePoint(event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        let point = mousePoint(event)
        updateDrag(at: point)
        if case .select(_, let moved) = drag, let draftSelection {
            if !moved, selection == nil {
                let target = event.modifierFlags.contains(.shift)
                    ? nil : WindowSnap.target(at: point, in: windowFrames)
                replaceSelection(with: target ?? bounds)
            } else if draftSelection.width >= Selection.minimum && draftSelection.height >= Selection.minimum {
                replaceSelection(with: draftSelection)
            }
        }
        if let preview { marks.append(preview) }
        self.drag = nil
        draftSelection = nil
        preview = nil
        strokePoints.removeAll(keepingCapacity: true)
        refresh()
    }

    private func replaceSelection(with rect: CGRect) {
        selection = rect
        marks.removeAll()
        choose(nil)
    }

    private func mousePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func updateDrag(at point: CGPoint) {
        switch drag {
        case .select(let start, let moved):
            let draft = Selection.between(start, point)
            draftSelection = draft
            if !moved, max(draft.width, draft.height) > 3 {
                drag = .select(start, moved: true)
            }
        case .resize(let handle, let original, let start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selection = handle.resize(original, delta: delta, in: bounds)
        case .move(let original, let start):
            selection = Selection.move(original, from: start, to: point, in: bounds)
        case .mark(let tool, let start):
            guard let selection else { return }
            let end = CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                              y: min(max(point.y, selection.minY), selection.maxY))
            let rect = Selection.between(start, end)
            switch tool {
            case .rectangle:
                preview = rect.width >= 2 && rect.height >= 2 ? .rectangle(rect, ink) : nil
            case .arrow:
                preview = hypot(end.x - start.x, end.y - start.y) >= 2 ? .arrow(start, end, ink) : nil
            case .pen, .mosaic:
                if strokePoints.last != end { strokePoints.append(end) }
                preview = tool == .pen ? .pen(strokePoints, ink) : .mosaic(strokePoints)
            case .text:
                break
            }
        case .none:
            break
        }
    }

    private func buildToolbar() {
        configureTray(toolbar)
        for (index, tool) in Tool.allCases.enumerated() {
            let button = NSButton()
            button.tag = index
            let item = tool.item
            configure(button, (item.symbol, item.label), action: #selector(pickTool(_:)))
            toolButtons[tool] = button
            toolbarButtons.append(button)
            practiceSteps.append(.init(button: button, detail: item.detail))
        }
        practiceSteps.append(.init(button: inkButton, detail: .practiceColor))
        configure(undoButton, ("undo", .toolUndo), action: #selector(undo))
        toolbarButtons.append(undoButton)
        practiceSteps.append(.init(button: undoButton, detail: .practiceUndo))
        let actions: [(String, UIKey, UIKey, Selector)] = [
            ("download", .toolDownload, .practiceDownload, #selector(download)),
            ("x", .toolCancel, .practiceCancel, #selector(cancel)),
            ("check", .toolConfirm, .practiceConfirm, #selector(confirm))
        ]
        for (symbol, label, detail, action) in actions {
            let button = NSButton()
            configure(button, (symbol, label), action: action)
            toolbarButtons.append(button)
            practiceSteps.append(.init(button: button, detail: detail))
        }
        for button in toolbarButtons {
            toolbar.addSubview(button)
        }
        for divider in toolbarDividers {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            toolbar.addSubview(divider)
        }
        configureSwatch(inkButton, action: #selector(togglePalette))
        inkButton.wantsLayer = true
        inkButton.layer?.cornerRadius = 6
        inkButton.isHidden = true
        toolbar.addSubview(inkButton)
        layoutToolbarButtons()
    }

    private func configureTray(_ tray: NSVisualEffectView) {
        tray.material = .hudWindow
        tray.blendingMode = .withinWindow
        tray.state = .active
        tray.appearance = NSAppearance(named: .darkAqua)
        tray.wantsLayer = true
        tray.layer?.cornerRadius = 12
        tray.layer?.backgroundColor = KlikTheme.panelTint.cgColor
        tray.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        tray.layer?.borderWidth = 1
        tray.layer?.masksToBounds = true
        tray.isHidden = true
        addSubview(tray)
    }

    private func layoutToolbarButtons() {
        var visible = toolbarButtons
        if !inkButton.isHidden { visible.insert(inkButton, at: Tool.allCases.count) }
        let afterTools = Tool.allCases.count + (inkButton.isHidden ? 0 : 1)
        let dividerPositions = [afterTools, visible.count - 2]
        var x: CGFloat = 5
        for (index, button) in visible.enumerated() {
            if let dividerIndex = dividerPositions.firstIndex(of: index) {
                toolbarDividers[dividerIndex].frame = CGRect(x: x + 3, y: 11, width: 1, height: 18)
                x += 8
            }
            button.frame = CGRect(x: x, y: 5, width: 33, height: 30)
            x += 33
        }
        toolbar.setFrameSize(CGSize(width: x + 5, height: 40))
    }

    private func buildPalette() {
        configureTray(palette)
        for (index, color) in Ink.allCases.enumerated() {
            let button = NSButton(frame: CGRect(x: 5 + 27 * index, y: 4, width: 27, height: 27))
            configureSwatch(button, action: #selector(pickInk(_:)))
            button.tag = index
            button.toolTip = strings(color.label)
            button.setAccessibilityLabel(strings(color.label))
            palette.addSubview(button)
            paletteButtons[color] = button
        }
        palette.setFrameSize(CGSize(width: 10 + 27 * Ink.allCases.count, height: 35))
        updateSwatches()
    }

    private func configureSwatch(_ button: NSButton, action: Selector) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.target = self
        button.action = action
    }

    private func updateSwatches() {
        let title = strings(.inkPicker, strings(ink.label))
        inkButton.toolTip = title
        inkButton.setAccessibilityLabel(title)
        inkButton.image = swatch(ink, selected: false)
        for (color, button) in paletteButtons {
            button.image = swatch(color, selected: color == ink)
        }
    }

    private func swatch(_ ink: Ink, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 23, height: 23), flipped: false) { _ in
            let disc = NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 15, height: 15))
            ink.color.setFill()
            disc.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 20, height: 20))
                NSColor.white.setStroke()
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }

    @objc private func togglePalette() {
        showPalette.toggle()
        refresh()
    }

    @objc private func pickInk(_ sender: NSButton) {
        ink = Ink.allCases[sender.tag]
        showPalette = false
        updateSwatches()
        refresh()
    }

    private func configure(_ button: NSButton, _ item: (symbol: String, label: UIKey), action: Selector) {
        if let url = Bundle.main.url(forResource: item.symbol, withExtension: "svg", subdirectory: "Lucide"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
        }
        let title = strings(item.label)
        if button.image == nil { button.title = title }
        button.imagePosition = button.image == nil ? .noImage : .imageOnly
        button.setAccessibilityLabel(title)
        button.toolTip = title
        button.isBordered = false
        button.target = self
        button.action = action
        button.refusesFirstResponder = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        switch item.symbol {
        case "x": button.contentTintColor = .systemRed
        case "check": button.contentTintColor = KlikTheme.accent
        default: button.contentTintColor = KlikTheme.overlayInk
        }
    }

    private func refresh() {
        needsDisplay = true
        let needsInk = tool?.usesInk == true || coach?.isDismissed == false
        if inkButton.isHidden == needsInk {
            inkButton.isHidden = !needsInk
            layoutToolbarButtons()
        }
        if let selection, drag == nil {
            let size = toolbar.frame.size
            let x = max(5, min(selection.maxX - size.width, bounds.maxX - size.width - 5))
            let below = selection.maxY + 9
            let above = selection.minY - size.height - 9
            let y = below + size.height + 5 <= bounds.maxY ? below : max(5, above)
            toolbar.setFrameOrigin(CGPoint(x: x, y: y))
            toolbar.isHidden = false
            palette.isHidden = !showPalette || !needsInk
            if !palette.isHidden {
                let paletteSize = palette.frame.size
                let centerX = toolbar.frame.minX + inkButton.frame.midX
                let paletteX = max(5, min(centerX - paletteSize.width / 2, bounds.maxX - paletteSize.width - 5))
                let above = toolbar.frame.minY - paletteSize.height - 6
                let below = toolbar.frame.maxY + 6
                let fitsBelow = below + paletteSize.height + 5 <= bounds.maxY
                let paletteY = fitsBelow && (above < 5 || toolbar.frame.minY >= selection.maxY)
                    ? below : max(5, above)
                palette.setFrameOrigin(CGPoint(x: paletteX, y: paletteY))
            }
        } else {
            toolbar.isHidden = true
            palette.isHidden = true
        }
        undoButton.isEnabled = !marks.isEmpty || isEditingText
        if let coach {
            if drag != nil || isEditingText {
                coach.hide()
            } else if let selection {
                coach.showToolbar(practiceSteps, toolbar: toolbar.frame,
                                  palette: palette.isHidden ? nil : palette.frame,
                                  selection: selection, in: bounds)
            } else {
                coach.showSelectionPrompt(in: bounds)
            }
        }
        updateModeHint()
    }

    private func updateModeHint() {
        modeHint.isHidden = selection != nil || drag != nil || coach != nil || windowFrames.isEmpty
        guard !modeHint.isHidden else { return }
        modeHint.stringValue = strings(.windowSnapHint)
        modeHint.sizeToFit()
        let width = min(bounds.width - 16, modeHint.frame.width + 26)
        modeHint.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - 46, width: width, height: 28)
    }

    @objc private func pickTool(_ sender: NSButton) {
        commitText()
        showPalette = false
        let chosen = Tool.allCases[sender.tag]
        choose(tool == chosen ? nil : chosen)
        refresh()
    }

    private func choose(_ chosen: Tool?) {
        tool = chosen
        for (tool, button) in toolButtons {
            button.layer?.backgroundColor = tool == chosen ? KlikTheme.buttonSelected.cgColor : nil
        }
    }

    private func beginText(at point: CGPoint, in selection: CGRect) {
        let x = min(point.x, max(selection.minX, selection.maxX - 52))
        let y = min(point.y, max(selection.minY, selection.maxY - 24))
        textOrigin = CGPoint(x: x + 3, y: y + 2)
        let field = NSTextField(frame: CGRect(x: x, y: y, width: min(280, max(52, selection.maxX - x)), height: 26))
        field.font = Mark.textFont
        field.placeholderString = strings(.textPlaceholder)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        addSubview(field, positioned: .below, relativeTo: pointerView)
        textField = field
        window?.makeFirstResponder(field)
    }

    private func commitText() {
        guard let field = textField else { return }
        window?.makeFirstResponder(self)
        let value = field.stringValue
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            marks.append(.text(value, textOrigin, ink))
        }
        textField = nil
        field.removeFromSuperview()
    }

    @objc func undo() {
        commitText()
        if !marks.isEmpty { marks.removeLast() }
        refresh()
    }

    @objc func cancel() { finish(.cancelled) }
    @objc private func download() { export(.downloads) }
    @objc private func confirm() { export(.clipboard) }

    func export(_ destination: Destination) {
        guard drag == nil, let selection else { return }
        commitText()
        refresh()
        guard let image = background.render(selection: selection, marks: marks),
              let png = CaptureImage.png(image) else {
            report(strings(.renderError))
            return
        }

        switch destination {
        case .clipboard:
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                report(strings(.clipboardError))
                return
            }
        case .downloads:
            do {
                let folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss-SSS"
                let name = "Klik \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).png"
                try png.write(to: folder.appendingPathComponent(name), options: .atomic)
            } catch {
                report(strings(.downloadError))
                return
            }
        }
        finish(.exported)
    }

    private func report(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.sizeToFit()
        let width = min(bounds.width - 16, errorLabel.frame.width + 24)
        errorLabel.frame = CGRect(x: bounds.midX - width / 2, y: 12, width: width, height: 27)
        errorLabel.isHidden = false
        NSSound.beep()
    }
}

private extension Selection.Handle {
    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .left: position = .left
            case .right: position = .right
            case .bottomLeft: position = .bottomLeft
            case .bottom: position = .bottom
            case .bottomRight: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        switch self {
        case .top, .bottom: return .resizeUpDown
        default: return .resizeLeftRight
        }
    }
}
