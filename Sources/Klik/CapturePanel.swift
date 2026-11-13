import AppKit
import Carbon

enum CaptureDownload {
    /// The final name only becomes visible after commit. Cancellation removes
    /// the staged file without leaving a screenshot in the destination.
    final class Pending {
        private var temporary: URL?
        private let destination: URL?
        private let folder: URL?
        private var access: Bool
        private let custom: (() throws -> Void)?

        init(temporary: URL, destination: URL, folder: URL, access: Bool) {
            self.temporary = temporary
            self.destination = destination
            self.folder = folder
            self.access = access
            self.custom = nil
        }
        init(custom: @escaping () throws -> Void) {
            self.temporary = nil
            self.destination = nil
            self.folder = nil
            self.access = false
            self.custom = custom
        }
        func commit() throws {
            if let custom { try custom(); return }
            guard let temporary, let destination else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.moveItem(at: temporary, to: destination)
            self.temporary = nil
            releaseAccess()
        }
        private func releaseAccess() {
            if access { folder?.stopAccessingSecurityScopedResource(); access = false }
        }
        deinit {
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
            releaseAccess()
        }
    }

    static func prepare(_ png: Data, location: ScreenshotLocation = ScreenshotLocation()) throws -> Pending {
        let folder = try location.resolve()
        let access = folder.startAccessingSecurityScopedResource()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss-SSS"
        let name = "Klik \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).png"
        let destination = folder.appendingPathComponent(name)
        let temporary = folder.appendingPathComponent(".klik-\(UUID().uuidString).tmp")
        do {
            try png.write(to: temporary, options: .atomic)
            return Pending(temporary: temporary, destination: destination, folder: folder, access: access)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if access { folder.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    static func save(_ png: Data, location: ScreenshotLocation = ScreenshotLocation()) throws {
        try prepare(png, location: location).commit()
    }
}

enum PreparedCaptureExport {
    struct Result {
        let png: Data
        let tiff: Data?
        let download: CaptureDownload.Pending?
    }
    enum Failure: Error, Equatable { case render, download }

    static func make(image: CGImage, destination: CaptureView.Destination,
                     saveOverride: ((Data) throws -> Void)? = nil) throws -> Result {
        guard let png = CaptureImage.png(image) else { throw Failure.render }
        switch destination {
        case .clipboard:
            return Result(png: png, tiff: ClipboardImage.tiff(image), download: nil)
        case .downloads:
            do {
                let pending = try saveOverride.map { save in CaptureDownload.Pending { try save(png) } }
                    ?? CaptureDownload.prepare(png)
                return Result(png: png, tiff: nil, download: pending)
            } catch { throw Failure.download }
        }
    }
}

// Teach the gesture a few times, then stop once the user has used it.
final class MosaicScrollHintPolicy {
    private let defaults: UserDefaults?
    private var localCount = 0
    private var localUsed = false
    private let countKey = "markupWheelHintShownCount"
    private let usedKey = "markupWheelHintUsed"
    init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    var shouldShow: Bool {
        !(defaults?.bool(forKey: usedKey) ?? localUsed) && (defaults?.integer(forKey: countKey) ?? localCount) < 3
    }
    func didShow() {
        if let defaults { defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey) }
        else { localCount += 1 }
    }
    func didScroll() {
        if let defaults { defaults.set(true, forKey: usedKey) }
        else { localUsed = true }
    }
}

final class CapturePanel: NSPanel {
    enum Outcome { case cancelled, exported }

    private let canvas: CaptureView

    init(frame: CGRect, image: CGImage, windowTargets: [WindowSnap] = [], strings: AppStrings = AppStrings(),
         guided: Bool = false, scrollHintPolicy: MosaicScrollHintPolicy = MosaicScrollHintPolicy(), captureWindow: ((CGWindowID) async throws -> CGImage)? = nil,
         startScrollCapture: ((CGRect) -> Void)? = nil,
         recognizeText: @escaping (CGImage) async throws -> String = { image in
             try await TextRecognitionWorker.shared.recognize(image)
         },
         saveDownload: ((Data) throws -> Void)? = nil,
         pasteboard: NSPasteboard = .general,
         recordCapture: ((Data) async -> Void)? = nil,
         finish: @escaping (Outcome) -> Void) {
        canvas = CaptureView(background: CaptureImage(image: image, size: frame.size),
                             windowTargets: windowTargets, strings: strings, guided: guided,
                             scrollHintPolicy: scrollHintPolicy, captureWindow: captureWindow,
                             startScrollCapture: startScrollCapture, recognizeText: recognizeText,
                             saveDownload: saveDownload, pasteboard: pasteboard,
                             recordCapture: recordCapture, finish: finish)
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

    var isRecognizingText: Bool { canvas.isRecognizingText }
    var isWindowSnapHeld: Bool {
        get { canvas.isWindowSnapHeld }
        set { canvas.setWindowSnapHeld(newValue, at: mouseLocationOutsideOfEventStream) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() -> Bool {
        makeKeyAndOrderFront(nil)
        guard NSApp.isActive, isKeyWindow else { return false }
        canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
        alphaValue = 1
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, self.isKeyWindow else { return }
            self.canvas.updatePointer(at: self.mouseLocationOutsideOfEventStream, force: true)
        }
        return true
    }

    override func orderOut(_ sender: Any?) {
        canvas.cancelWindowCapture()
        canvas.cancelExport()
        isWindowSnapHeld = false
        canvas.clearPointer()
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel && canvas.adjustMarkupSize(with: event) { return }
        if canvas.isRecognizingText {
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.type == .keyDown, !composing, modifiers.isEmpty,
               Int(event.keyCode) == kVK_Escape {
                if canvas.isEditingRecognitionMarkup {
                    canvas.cancelActiveTextEditing()
                } else if canvas.isEditingRecognitionText(firstResponder) {
                    makeFirstResponder(canvas)
                } else {
                    canvas.cancel()
                }
            } else if event.type == .keyDown, !composing,
                      Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
                      canvas.isEditingRecognitionMarkup, modifiers.isEmpty {
                canvas.finishRecognitionMarkupText()
            } else if event.type == .keyDown, !composing,
                      Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
                      canvas.isEditingRecognitionMarkup, modifiers == .shift {
                (firstResponder as? InlineMarkupTextView)?.insertNewline(nil)
            } else if event.type == .keyDown, !composing,
                      Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
                      !canvas.isEditingRecognitionMarkup,
                      (modifiers.isEmpty && !canvas.isEditingRecognitionText(firstResponder)) || modifiers == .command {
                if !event.isARepeat { canvas.copyImageFromTextRecognition() }
            } else if event.type == .keyDown, !composing, modifiers.isEmpty,
                      [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)),
                      !canvas.isEditingRecognitionText(firstResponder), !canvas.isEditingRecognitionMarkup {
                canvas.deleteSelectedMark()
            } else if event.type == .keyDown, !composing, Int(event.keyCode) == kVK_ANSI_Z,
                      !canvas.isEditingRecognitionText(firstResponder), !canvas.isEditingRecognitionMarkup,
                      modifiers == .command {
                canvas.recognitionUndo()
            } else if event.type == .keyDown, !composing, Int(event.keyCode) == kVK_ANSI_Z,
                      !canvas.isEditingRecognitionText(firstResponder), !canvas.isEditingRecognitionMarkup,
                      modifiers == [.command, .shift] {
                canvas.recognitionRedo()
            } else {
                super.sendEvent(event)
            }
            if isVisible && [.mouseMoved, .mouseEntered, .mouseExited,
                             .leftMouseDown, .leftMouseDragged, .leftMouseUp, .cursorUpdate].contains(event.type) {
                canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
            }
            return
        }
        if event.type == .flagsChanged { canvas.selectionModifiersChanged(event.modifierFlags) }
        if event.type == .keyUp, Int(event.keyCode) == kVK_Space, isWindowSnapHeld {
            isWindowSnapHeld = false
            return
        }
        if event.type == .keyDown {
            let key = Int(event.keyCode)
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            if key == kVK_Escape && !composing {
                if canvas.isCropping { canvas.cancelCrop() }
                else if canvas.isEditingText { canvas.cancelActiveTextEditing() }
                else { canvas.cancel() }
                return
            }
            if !composing, key == kVK_Return || key == kVK_ANSI_KeypadEnter {
                if canvas.isCropping {
                    canvas.applyCrop()
                    return
                } else if canvas.isEditingText {
                    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    if modifiers.isEmpty {
                        canvas.finishTextEditing()
                        return
                    } else if modifiers == .shift {
                        (firstResponder as? InlineMarkupTextView)?.insertNewline(nil)
                        return
                    }
                } else {
                    if !event.isARepeat { canvas.export(.clipboard) }
                    return
                }
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if key == kVK_Space, modifiers.isEmpty, canvas.canSnapToWindow {
                if !event.isARepeat { isWindowSnapHeld = true }
                return
            }
            if !composing, !canvas.isEditingText, modifiers.isEmpty,
               [kVK_Delete, kVK_ForwardDelete].contains(key), canvas.deleteSelectedMark() { return }
            if !canvas.isEditingText, key == kVK_ANSI_Z {
                if modifiers == .command { canvas.undo(); return }
                if modifiers == [.command, .shift] { canvas.redo(); return }
            }
        }
        if event.type == .cursorUpdate, isVisible {
            canvas.updatePointer(at: mouseLocationOutsideOfEventStream, force: true)
            return
        }
        super.sendEvent(event)
        if isVisible && [.mouseMoved, .mouseEntered, .mouseExited,
                         .leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            canvas.updatePointer(at: mouseLocationOutsideOfEventStream)
        }
    }
}

private final class PointerView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class TextSizePreview: NSView {
    var fontSize: CGFloat = 18 { didSet { needsDisplay = true } }
    var ink: Ink = .red { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func updateSize() {
        let size = ("A" as NSString).size(withAttributes: [.font: MarkupTextStyle.font(size: fontSize)])
        frame.size = CGSize(width: ceil(size.width) + 4, height: ceil(size.height) + 4)
    }
    override func draw(_ dirtyRect: NSRect) {
        ("A" as NSString).draw(at: CGPoint(x: 2, y: 2), withAttributes: MarkupTextStyle.attributes(ink: ink, size: fontSize))
    }
}

private final class EyedropperPreview: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        KlikTheme.round(layer, radius: 4)
        layer?.borderWidth = 1
        layer?.borderColor = KlikTheme.selectionHalo.cgColor
        let innerBorder = CALayer()
        innerBorder.frame = bounds.insetBy(dx: 1, dy: 1)
        innerBorder.cornerRadius = 3
        innerBorder.borderWidth = 1
        innerBorder.borderColor = NSColor.white.cgColor
        layer?.addSublayer(innerBorder)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.65
        layer?.shadowRadius = 2
        layer?.shadowOffset = .zero
    }
    required init?(coder: NSCoder) { nil }
    func update(color: CoverColor) { layer?.backgroundColor = color.cgColor }
}

private final class BrushOutline: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor.black.withAlphaComponent(0.75).setStroke()
        outline.lineWidth = 3
        outline.stroke()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

private final class MosaicCursorView: NSView {
    var source: CaptureImage?
    var capturePoint = CGPoint.zero
    var diameter: CGFloat = 30
    var imageScale: CGFloat = 1
    var style: MosaicStyle = .pixel
    var color: CoverColor = .fallback
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let source, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: imageScale, y: imageScale)
        context.translateBy(x: -capturePoint.x, y: -capturePoint.y)
        Mark.mosaic([capturePoint], diameter: diameter, style: style, color: color)
            .draw(in: context, background: source, isPreview: true)
        context.restoreGState()
        let outline = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor.black.withAlphaComponent(0.85).setStroke()
        outline.lineWidth = 3
        outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

// A non-interactive, temporary cue beside the mosaic brush cursor.
private final class MosaicScrollHint: NSView {
    private let wheel = CALayer()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = KlikTheme.panelTint.cgColor
        KlikTheme.round(layer, radius: KlikTheme.badgeRadius)
        wheel.frame = CGRect(x: 10, y: 7, width: 2.5, height: 4)
        wheel.cornerRadius = 1.25
        wheel.backgroundColor = KlikTheme.overlayInk.cgColor
        layer?.addSublayer(wheel)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let movement = CABasicAnimation(keyPath: "transform.translation.y")
            movement.fromValue = -1.5
            movement.toValue = 2.5
            movement.duration = 0.65
            movement.autoreverses = true
            movement.repeatCount = .infinity
            wheel.add(movement, forKey: "scroll")
        }
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.94).setStroke()
        let mouse = NSBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 11, height: 18), xRadius: 5, yRadius: 5)
        mouse.lineWidth = 1.2
        mouse.stroke()
        let arrows = NSBezierPath()
        arrows.lineWidth = 1.2
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.move(to: CGPoint(x: 21, y: 10)); arrows.line(to: CGPoint(x: 23, y: 8)); arrows.line(to: CGPoint(x: 25, y: 10))
        arrows.move(to: CGPoint(x: 21, y: 16)); arrows.line(to: CGPoint(x: 23, y: 18)); arrows.line(to: CGPoint(x: 25, y: 16))
        arrows.stroke()
    }
}

private final class CaptureBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private let insets: CGSize
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; needsLayout = true }
    }

    init(font: NSFont, horizontalPadding: CGFloat = 12, verticalPadding: CGFloat = 6) {
        insets = CGSize(width: horizontalPadding, height: verticalPadding)
        super.init(frame: .zero)
        KlikTheme.styleOverlay(self, radius: KlikTheme.badgeRadius)
        label.font = font
        label.textColor = KlikTheme.overlayInk
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func size(maximumWidth: CGFloat) -> CGSize {
        let measured = (label.stringValue as NSString).size(withAttributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)])
        let cellWidth = label.cell?.cellSize.width ?? 0
        let textWidth = ceil(max(measured.width + 8, cellWidth))
        return CGSize(width: max(1, min(maximumWidth, textWidth + 2 * insets.width)),
                      height: ceil(label.intrinsicContentSize.height) + 2 * insets.height)
    }

    override func layout() {
        super.layout()
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: insets.width, y: (bounds.height - height) / 2,
                             width: max(0, bounds.width - 2 * insets.width), height: height)
    }
}

enum MagnifierLayout {
    static func frame(near point: CGPoint, in bounds: CGRect, size: CGFloat = 112) -> CGRect {
        let side = min(size, bounds.width, bounds.height)
        let gap: CGFloat = 22
        let right = point.x + gap
        let below = point.y + gap
        let x = right + side <= bounds.maxX ? right : point.x - gap - side
        let y = below + side <= bounds.maxY ? below : point.y - gap - side
        return CGRect(x: max(bounds.minX, min(x, bounds.maxX - side)),
                      y: max(bounds.minY, min(y, bounds.maxY - side)), width: side, height: side)
    }
}

private final class CaptureMagnifier: NSView {
    var source: CaptureImage? { didSet { needsDisplay = true } }
    var samplePoint = CGPoint.zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let source else { return }
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        context.saveGState()
        outline.addClip()
        KlikTheme.overlayCanvas.setFill()
        bounds.fill()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: 4, y: 4)
        context.translateBy(x: -samplePoint.x, y: -samplePoint.y)
        context.interpolationQuality = .none
        source.draw(in: context)
        context.restoreGState()

        let crosshair = NSBezierPath()
        crosshair.move(to: NSPoint(x: bounds.midX, y: 0))
        crosshair.line(to: NSPoint(x: bounds.midX, y: bounds.height))
        crosshair.move(to: NSPoint(x: 0, y: bounds.midY))
        crosshair.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        KlikTheme.selectionHalo.setStroke()
        crosshair.lineWidth = 3
        crosshair.stroke()
        KlikTheme.selection.setStroke()
        crosshair.lineWidth = 1
        crosshair.stroke()
        KlikTheme.overlayOutline.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

enum Tool: CaseIterable {
    case ellipse, rectangle, arrow, pen, text, mosaic

    var item: (symbol: String, label: UIKey, detail: UIKey) {
        switch self {
        case .ellipse: return ("circle", .toolEllipse, .practiceEllipse)
        case .rectangle: return ("rectangle-horizontal", .toolRectangle, .practiceRectangle)
        case .arrow: return ("arrow-up-right", .toolArrow, .practiceArrow)
        case .pen: return ("pencil", .toolPen, .practicePen)
        case .text: return ("type", .toolText, .practiceText)
        case .mosaic: return ("grid-3x3", .toolMosaic, .practiceMosaic)
        }
    }

    var usesInk: Bool { self != .mosaic }
    var usesLineWidth: Bool { self == .ellipse || self == .rectangle || self == .arrow || self == .pen }
}

enum MarkConstraint {
    static func squareEnd(from start: CGPoint, toward end: CGPoint, in bounds: CGRect) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let sx: CGFloat = dx < 0 ? -1 : 1
        let sy: CGFloat = dy < 0 ? -1 : 1
        let maxX = sx > 0 ? bounds.maxX - start.x : start.x - bounds.minX
        let maxY = sy > 0 ? bounds.maxY - start.y : start.y - bounds.minY
        let length = max(0, min(max(abs(dx), abs(dy)), maxX, maxY))
        return CGPoint(x: start.x + sx * length, y: start.y + sy * length)
    }

    static func snappedEnd(from start: CGPoint, toward end: CGPoint, in bounds: CGRect) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return start }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let x = cos(angle), y = sin(angle)
        let xLimit = abs(x) < 0.0001 ? CGFloat.infinity : (x > 0 ? bounds.maxX - start.x : start.x - bounds.minX) / abs(x)
        let yLimit = abs(y) < 0.0001 ? CGFloat.infinity : (y > 0 ? bounds.maxY - start.y : start.y - bounds.minY) / abs(y)
        let distance = max(0, min(length, xLimit, yLimit))
        return CGPoint(x: start.x + x * distance, y: start.y + y * distance)
    }
}

final class CaptureView: NSView {
    enum Destination { case clipboard, downloads }

    private enum ClickTarget {
        case display
        case window(WindowSnap?)
    }

    private enum Drag {
        case select(CGPoint, moved: Bool, target: ClickTarget)
        case resize(Selection.Handle, CGRect, CGPoint)
        case move(CGRect, CGPoint)
        case moveMark(Int, Mark, CGPoint, [Mark])
        case resizeArrow(Int, Mark, Int, CGPoint, [Mark])
        case resizeMark(Int, Mark, Selection.Handle, CGPoint, [Mark])
        case mark(Tool, CGPoint)
        case selectMark(Int, CGPoint)
        case cropDraw(CGPoint)
        case cropResize(Selection.Handle, CGRect, CGPoint)
        case cropMove(CGRect, CGPoint)
    }

    private struct EditSnapshot {
        let marks: [Mark]
        let selection: CGRect?
    }

    enum Pointer: Equatable {
        case crosshair, arrow, canvasPoint, hand, openHand, closedHand, text, move, eyedropper
        case resize(Selection.Handle)

        var cursor: NSCursor {
            switch self {
            case .crosshair: return .crosshair
            case .arrow: return .arrow
            case .canvasPoint: return Self.canvasPointCursor(for: .red, diameter: 5)
            case .hand: return .pointingHand
            case .openHand: return .openHand
            case .closedHand: return .closedHand
            case .text: return .iBeam
            case .move: return Self.moveCursor
            case .eyedropper: return Self.eyedropperCursor
            case .resize(let handle): return handle.cursor
            }
        }

        static func canvasPointCursor(for ink: Ink, diameter: CGFloat = 5) -> NSCursor {
            let side = ceil(diameter + 12)
            let center = side / 2
            let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
                let dot = NSBezierPath(ovalIn: NSRect(x: center - diameter / 2, y: center - diameter / 2,
                                                       width: diameter, height: diameter))
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = ink.color.withAlphaComponent(0.55)
                glow.shadowBlurRadius = 3
                glow.shadowOffset = .zero
                glow.set()
                ink.color.setFill()
                dot.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.withAlphaComponent(0.7).setStroke()
                dot.lineWidth = 2.5
                dot.stroke()
                NSColor.white.withAlphaComponent(0.95).setStroke()
                dot.lineWidth = 1
                dot.stroke()
                ink.color.setFill()
                dot.fill()
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
        }

        static func textCursor(for ink: Ink, size: CGFloat) -> NSCursor {
            let attributes = MarkupTextStyle.attributes(ink: ink, size: size)
            let textSize = ("A" as NSString).size(withAttributes: attributes)
            let image = NSImage(size: NSSize(width: ceil(textSize.width) + 4, height: ceil(textSize.height) + 4), flipped: true) { _ in
                ("A" as NSString).draw(at: CGPoint(x: 2, y: 2), withAttributes: attributes)
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 2))
        }

        private static let eyedropperCursor: NSCursor = {
            guard let symbol = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil) else { return .crosshair }
            symbol.size = NSSize(width: 22, height: 22)
            return NSCursor(image: symbol, hotSpot: NSPoint(x: 2, y: 20))
        }()

        private static let moveCursor: NSCursor = {
            let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
                let path = NSBezierPath()
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                for points in [
                    [NSPoint(x: 12, y: 3), NSPoint(x: 12, y: 21)],
                    [NSPoint(x: 9, y: 6), NSPoint(x: 12, y: 3), NSPoint(x: 15, y: 6)],
                    [NSPoint(x: 9, y: 18), NSPoint(x: 12, y: 21), NSPoint(x: 15, y: 18)],
                    [NSPoint(x: 3, y: 12), NSPoint(x: 21, y: 12)],
                    [NSPoint(x: 6, y: 9), NSPoint(x: 3, y: 12), NSPoint(x: 6, y: 15)],
                    [NSPoint(x: 18, y: 9), NSPoint(x: 21, y: 12), NSPoint(x: 18, y: 15)]
                ] {
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.line(to: point) }
                }
                NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
                NSColor.black.setStroke(); path.lineWidth = 1.6; path.stroke()
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
        }()

        var resizeHandle: Selection.Handle? {
            if case .resize(let handle) = self { return handle }
            return nil
        }
    }

    private let desktop: CaptureImage
    private let isDocument: Bool
    private weak var documentToolbarHost: NSView?
    private var documentExportInProgress = false
    private var exportTask: Task<Void, Never>?
    var isExporting: Bool { documentExportInProgress }
    private var exportCommitted = false
    var onDocumentExport: ((Destination, CGImage) -> Void)?
    var onDocumentStatus: ((String) -> Void)?
    var onDocumentSizeChange: ((CGSize) -> Void)?
    private var windowImage: CaptureImage?
    private var background: CaptureImage { windowImage ?? desktop }
    private let windowTargets: [WindowSnap]
    private let captureWindow: ((CGWindowID) async throws -> CGImage)?
    private let startScrollCapture: ((CGRect) -> Void)?
    private let recognizeText: (CGImage) async throws -> String
    private let saveDownload: ((Data) throws -> Void)?
    private var recognitionTask: Task<Void, Never>?
    private var recognitionRedraw: DispatchWorkItem?
    private var recognitionView: TextRecognitionView?
    private var windowCaptureTask: Task<Void, Never>?
    private var lastWindowClick: WindowSnap?
    private var doubleClickStart: CGPoint?
    private var copyWhenWindowReady = false
    private let pasteboard: NSPasteboard
    private let recordCapture: ((Data) async -> Void)?
    private let strings: AppStrings
    private let finish: (CapturePanel.Outcome) -> Void
    private let coach: CaptureCoach?
    private var practiceSteps: [CaptureCoach.Step] = []
    private let toolbar = NSVisualEffectView()
    private let palette = NSVisualEffectView()
    private let mosaicOptions: MosaicOptions
    private var shapeWidth: CGFloat = 2.5
    private var penWidth: CGFloat = 2.5
    private var textSize: CGFloat = 18
    private var scrollUndoIndex: Int?
    private var lastScrollUndoTime: TimeInterval = 0
    private var feedbackGeneration = 0
    private var feedbackWork: DispatchWorkItem?
    private var ocrRefreshWork: DispatchWorkItem?
    private var recognitionMosaicChanging = false
    private var showMosaicOptions = false
    private var mosaicStyle: MosaicStyle = .pixel
    private var strokeColor: CoverColor = .fallback
    private var pickingCoverColor = false
    private var pickingInkColor = false
    private let sizeOutline = BrushOutline()
    private let sizeFeedback = TextSizePreview(frame: .zero)
    private let modeHint = CaptureBadge(font: .systemFont(ofSize: 12, weight: .medium))
    private let errorLabel = CaptureBadge(font: .systemFont(ofSize: 13, weight: .medium))
    private let selectionSize = CaptureBadge(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                             horizontalPadding: 8, verticalPadding: 4)
    private let pointerView = PointerView()
    private let eyedropperPreview = EyedropperPreview(frame: CGRect(x: 0, y: 0, width: 17, height: 17))
    private let brushOutline = MosaicCursorView()
    private let mosaicScrollHint = MosaicScrollHint(frame: CGRect(x: 0, y: 0, width: 30, height: 26))
    private var scrollHintAvailable: Bool
    private let scrollHintPolicy: MosaicScrollHintPolicy
    private var scrollHintStarted = false
    private(set) var mosaicDiameter: CGFloat = 30
    private let magnifier = CaptureMagnifier()
    private let undoButton = HoverButton()
    private let redoButton = HoverButton()
    private let inkButton = HoverButton()
    private weak var downloadButton: NSButton?
    private var toolbarButtons: [NSButton] = []
    private var toolButtons: [Tool: NSButton] = [:]
    private var paletteButtons: [Ink: NSButton] = [:]
    private var selection: CGRect? {
        didSet {
            guard let onDocumentSizeChange, let selection, selection != oldValue else { return }
            onDocumentSizeChange(background.pixelRect(for: selection).size)
        }
    }
    private var draftSelection: CGRect?
    private(set) var isWindowSnapHeld = false
    private var hoveredWindow: CGRect?
    private(set) var marks: [Mark] = []
    private var undoMarks: [EditSnapshot] = []
    private var redoMarks: [EditSnapshot] = []
    private var snapshot: EditSnapshot { EditSnapshot(marks: marks, selection: selection) }
    private(set) var cropRect: CGRect?
    private var cropBounds: CGRect?
    var isCropping: Bool { cropRect != nil }
    private let cropButton = HoverButton()
    private let cropHint = CaptureBadge(font: .systemFont(ofSize: 12, weight: .medium))
    private var selectedMark: Int?
    private var preview: Mark?
    private var drag: Drag?
    private var pendingMarkSelection: (index: Int, start: CGPoint)?
    private var dragPoint: CGPoint?
    private var strokePoints: [CGPoint] = []
    private var tool: Tool?
    private var ink: Ink = .red
    private var showPalette = false
    private var textField: InlineMarkupTextView?
    private var textOrigin = CGPoint.zero
    private var editingTextMark: (index: Int, original: Mark)?
    private var pointerTracking: NSTrackingArea?
    private(set) var pointer: Pointer?
    private var pointerHotSpot = CGPoint.zero
    private var pointCursorInk: Ink?
    private var pointCursorDiameter: CGFloat?
    private var pointCursorTextSize: CGFloat?
    private var cachedPointCursor: NSCursor?
    private var systemCursorHidden = false

    init(background: CaptureImage, windowTargets: [WindowSnap], strings: AppStrings, guided: Bool,
         scrollHintPolicy: MosaicScrollHintPolicy = MosaicScrollHintPolicy(), captureWindow: ((CGWindowID) async throws -> CGImage)?,
         startScrollCapture: ((CGRect) -> Void)? = nil,
         documentSize: CGSize? = nil,
         recognizeText: @escaping (CGImage) async throws -> String = { image in try TextRecognition.recognize(image) },
         saveDownload: ((Data) throws -> Void)? = nil,
         pasteboard: NSPasteboard = .general,
         recordCapture: ((Data) async -> Void)?,
         finish: @escaping (CapturePanel.Outcome) -> Void) {
        self.desktop = background
        self.isDocument = documentSize != nil
        self.scrollHintPolicy = scrollHintPolicy
        self.scrollHintAvailable = documentSize == nil && scrollHintPolicy.shouldShow
        self.windowTargets = windowTargets
        self.captureWindow = captureWindow
        self.startScrollCapture = startScrollCapture
        self.recognizeText = recognizeText
        self.saveDownload = saveDownload
        self.pasteboard = pasteboard
        self.recordCapture = recordCapture
        self.strings = strings
        self.mosaicOptions = MosaicOptions(strings: strings)
        self.coach = guided ? CaptureCoach(strings: strings) : nil
        self.finish = finish
        super.init(frame: CGRect(origin: .zero, size: documentSize ?? background.size))
        if isDocument {
            selection = background.frame
            identifier = NSUserInterfaceItemIdentifier("scrollMarkupDocument")
        }
        buildToolbar()
        buildPalette()
        addSubview(mosaicOptions)
        mosaicOptions.onSelect = { [weak self] style in
            self?.cancelInkColorPick()
            self?.mosaicStyle = style
            self?.pickingCoverColor = false
            self?.showMosaicOptions = false
            self?.refresh()
        }
        mosaicOptions.onPickColor = { [weak self] in self?.beginCoverColorPick() }
        if let coach {
            addSubview(coach)
            coach.onChange = { [weak self] in self?.refresh() }
        }
        modeHint.identifier = NSUserInterfaceItemIdentifier("captureModeHint")
        selectionSize.identifier = NSUserInterfaceItemIdentifier("capturePixelSize")
        addSubview(modeHint)
        cropHint.text = strings(.cropHint)
        cropHint.isHidden = true
        addSubview(cropHint)
        addSubview(errorLabel)
        addSubview(selectionSize)
        sizeFeedback.identifier = NSUserInterfaceItemIdentifier("markupSizeFeedback")
        sizeFeedback.isHidden = true
        sizeFeedback.setAccessibilityElement(false)
        addSubview(sizeFeedback)
        sizeOutline.identifier = NSUserInterfaceItemIdentifier("markupSizeOutline")
        sizeOutline.isHidden = true
        sizeOutline.setAccessibilityElement(false)
        addSubview(sizeOutline)
        magnifier.isHidden = true
        magnifier.setAccessibilityElement(false)
        magnifier.identifier = NSUserInterfaceItemIdentifier("captureMagnifier")
        addSubview(magnifier, positioned: .above, relativeTo: nil)
        brushOutline.isHidden = true
        brushOutline.setAccessibilityElement(false)
        brushOutline.identifier = NSUserInterfaceItemIdentifier("mosaicBrushOutline")
        addSubview(brushOutline, positioned: .above, relativeTo: nil)
        mosaicScrollHint.isHidden = true
        mosaicScrollHint.identifier = NSUserInterfaceItemIdentifier("mosaicScrollHint")
        mosaicScrollHint.setAccessibilityElement(false)
        addSubview(mosaicScrollHint, positioned: .above, relativeTo: brushOutline)
        eyedropperPreview.identifier = NSUserInterfaceItemIdentifier("eyedropperPreview")
        eyedropperPreview.setAccessibilityElement(false)
        eyedropperPreview.isHidden = true
        addSubview(eyedropperPreview, positioned: .above, relativeTo: mosaicScrollHint)
        pointerView.imageScaling = .scaleNone
        pointerView.wantsLayer = true
        pointerView.isHidden = true
        pointerView.identifier = NSUserInterfaceItemIdentifier("capturePointer")
        pointerView.setAccessibilityElement(false)
        addSubview(pointerView, positioned: .above, relativeTo: nil)
        refresh()
    }

    convenience init(document: CaptureImage, size: CGSize, strings: AppStrings, cancel: @escaping () -> Void) {
        self.init(background: document, windowTargets: [], strings: strings, guided: false, captureWindow: nil,
                  documentSize: size, recordCapture: nil) { _ in cancel() }
    }

    deinit {
        if systemCursorHidden { CGDisplayShowCursor(CGMainDisplayID()) }
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var isEditingText: Bool { textField != nil }
    var isRecognizingText: Bool { recognitionView != nil }
    var isEditingRecognitionMarkup: Bool { recognitionView?.isEditingMarkupText == true }
    func isEditingRecognitionText(_ responder: NSResponder?) -> Bool {
        recognitionView?.isEditingText(responder) == true
    }
    var canSnapToWindow: Bool { selection == nil && !windowTargets.isEmpty && windowCaptureTask == nil }

    func cancelWindowCapture() {
        recognitionTask?.cancel()
        recognitionTask = nil
        ocrRefreshWork?.cancel()
        ocrRefreshWork = nil
        recognitionView?.removeFromSuperview()
        recognitionView = nil
        windowCaptureTask?.cancel()
        windowCaptureTask = nil
        lastWindowClick = nil
        doubleClickStart = nil
        copyWhenWindowReady = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTracking = area
    }

    func clearPointer() {
        magnifier.isHidden = true
        brushOutline.isHidden = true
        sizeOutline.isHidden = true
        sizeFeedback.isHidden = true
        mosaicScrollHint.isHidden = true
        eyedropperPreview.isHidden = true
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
        let candidate = isWindowSnapHeld && canSnapToWindow && drag == nil
            ? WindowSnap.target(at: point, in: windowTargets)?.frame.intersection(bounds) : nil
        if hoveredWindow != candidate {
            hoveredWindow = candidate
            needsDisplay = true
        }
        guard (isDocument ? visibleRect : bounds).contains(point) else {
            clearPointer()
            return
        }

        let next: Pointer
        if (pickingCoverColor || pickingInkColor) && (recognitionView?.capturePoint(at: point) != nil || (recognitionView == nil && background.frame.contains(point))) {
            next = .eyedropper
        } else if let recognitionView {
            if recognitionView.refreshConfirmationContains(point) || recognitionView.paletteContains(point) { next = .arrow }
            else if recognitionView.textContains(point) || recognitionView.markupInputContains(point) {
                next = .text
            } else if let imagePoint = recognitionView.capturePoint(at: point) {
                if case .moveMark = drag { next = .move }
                else if case .resizeArrow = drag { next = .move }
                else if case .resizeMark(_, _, let handle, _, _) = drag { next = .resize(handle) }
                else if let index = selectedMark, marks.indices.contains(index),
                        let rect = marks[index].resizableBounds,
                        let handle = Selection.Handle.hit(at: imagePoint, in: rect) { next = .resize(handle) }
                else if let index = selectedMark, marks.indices.contains(index),
                        let rect = marks[index].resizableBounds, rect.contains(imagePoint) { next = .move }
                else if let index = selectedMark, marks.indices.contains(index),
                        marks[index].hitTest(imagePoint) || arrowHandle(for: marks[index], at: imagePoint) != nil { next = .move }
                else { next = .canvasPoint }
            } else { next = .arrow }
        } else if hoveredWindow != nil {
            next = .hand
        } else if let cropRect {
            if let handle = Selection.Handle.hit(at: point, in: cropRect) { next = .resize(handle) }
            else { next = .crosshair }
        } else if let textField, textField.frame.contains(point) {
            next = .text
        } else if !isDocument && ((!toolbar.isHidden && toolbar.frame.contains(point))
                    || (!palette.isHidden && palette.frame.contains(point))
                    || (!mosaicOptions.isHidden && mosaicOptions.frame.contains(point))
                    || coach?.hitTest(point) != nil) {
            next = .arrow
        } else if case .resize(let handle, _, _) = drag {
            next = .resize(handle)
        } else if case .move = drag {
            next = .closedHand
        } else if case .moveMark = drag {
            next = .move
        } else if case .resizeArrow = drag {
            next = .move
        } else if case .resizeMark(_, _, let handle, _, _) = drag {
            next = .resize(handle)
        } else if !isDocument, drag == nil, let selection, let handle = Selection.Handle.hit(
            at: point, in: selection, retaining: pointer?.resizeHandle
        ) {
            next = .resize(handle)
        } else if drag == nil, let index = selectedMark, marks.indices.contains(index),
                  let rect = marks[index].resizableBounds,
                  let handle = Selection.Handle.hit(at: point, in: rect) {
            next = .resize(handle)
        } else if drag == nil, let index = selectedMark, marks.indices.contains(index),
                  let rect = marks[index].resizableBounds, rect.contains(point) {
            next = .move
        } else if drag == nil, selection?.contains(point) == true, let index = selectedMark,
                  marks.indices.contains(index), (marks[index].hitTest(point) || arrowHandle(for: marks[index], at: point) != nil) {
            next = .move
        } else if selection?.contains(point) == true {
            next = .canvasPoint
        } else if isDocument {
            next = .arrow
        } else {
            next = .crosshair
        }
        let inImage: Bool
        let scale: CGFloat
        if let recognitionView {
            inImage = recognitionView.capturePoint(at: point) != nil && !recognitionView.paletteContains(point)
            scale = recognitionView.imageScale
        } else {
            inImage = selection?.contains(point) == true && (isDocument ||
                ((toolbar.isHidden || !toolbar.frame.contains(point)) &&
                 (palette.isHidden || !palette.frame.contains(point)) &&
                 (mosaicOptions.isHidden || !mosaicOptions.frame.contains(point))))
            scale = 1
        }
        let showBrush = tool == .mosaic && inImage && drag == nil && next == .canvasPoint
        brushOutline.isHidden = !showBrush
        if !sizeFeedback.isHidden { positionTextSizePreview(at: point) }
        if !sizeOutline.isHidden {
            sizeOutline.frame.origin = CGPoint(x: point.x - sizeOutline.frame.width / 2,
                                               y: point.y - sizeOutline.frame.height / 2)
        }
        if showBrush {
            let size = mosaicDiameter * scale + 4
            brushOutline.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            brushOutline.source = background
            brushOutline.capturePoint = recognitionView?.capturePoint(at: point) ?? point
            brushOutline.diameter = mosaicDiameter
            brushOutline.imageScale = scale
            brushOutline.style = mosaicStyle
            brushOutline.color = strokeColor
            brushOutline.needsDisplay = true
        }
        if !scrollHintStarted && !scrollHintPolicy.shouldShow { scrollHintAvailable = false }
        let wheelEligible = !isCropping && (tool != nil || selectedMark != nil) && inImage && drag == nil
            && !isEditingText && !isEditingRecognitionMarkup && !pickingInkColor && !pickingCoverColor
            && next != .text
        mosaicScrollHint.isHidden = !wheelEligible || !scrollHintAvailable
        if !mosaicScrollHint.isHidden {
            let gap = tool == .mosaic ? mosaicDiameter * scale / 2 + 9 : 18
            let width = mosaicScrollHint.frame.width
            let height = mosaicScrollHint.frame.height
            let right = point.x + gap
            let x = right + width <= bounds.maxX - 4 ? right : point.x - gap - width
            mosaicScrollHint.frame.origin = CGPoint(x: max(bounds.minX + 4, min(x, bounds.maxX - width - 4)),
                                                     y: max(bounds.minY + 4, min(point.y - height / 2, bounds.maxY - height - 4)))
            if !scrollHintStarted {
                scrollHintStarted = true
                scrollHintPolicy.didShow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.scrollHintAvailable = false
                    self?.mosaicScrollHint.isHidden = true
                }
            }
        }
        let samplePoint = recognitionView == nil ? point : recognitionView?.capturePoint(at: point)
        if next == .eyedropper, let samplePoint, let color = colorForEyedropper(at: samplePoint) {
            eyedropperPreview.update(color: color)
            let width = eyedropperPreview.frame.width
            let height = eyedropperPreview.frame.height
            let right = point.x + 25
            let x = right + width <= bounds.maxX - 4 ? right : point.x - width - 10
            eyedropperPreview.frame.origin = CGPoint(x: max(bounds.minX + 4, min(x, bounds.maxX - width - 4)),
                                                       y: max(bounds.minY + 4, min(point.y - height - 16, bounds.maxY - height - 4)))
            eyedropperPreview.isHidden = false
        } else {
            eyedropperPreview.isHidden = true
        }
        if isDocument {
            pointer = next
            (showBrush ? Self.invisibleCursor : (next == .canvasPoint ? canvasPointCursor() : next.cursor)).set()
            return
        }
        let shapeChanged = pointer != next || (next == .canvasPoint &&
            (pointCursorInk != ink || pointCursorDiameter != canvasPointDiameter || pointCursorTextSize != canvasTextSize))
        if shapeChanged {
            pointer = next
            let cursor = next == .canvasPoint ? canvasPointCursor() : next.cursor
            pointerView.image = cursor.image
            pointerView.setFrameSize(cursor.image.size)
            pointerHotSpot = cursor.hotSpot
        }
        if !systemCursorHidden, shapeChanged || force {
            // The system may replace NSCursor.set() after an event. A single
            // pointer drawn in the overlay cannot be overwritten by AppKit.
            systemCursorHidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
            if !systemCursorHidden { (showBrush ? Self.invisibleCursor : (next == .canvasPoint ? canvasPointCursor() : next.cursor)).set() }
        }
        if !systemCursorHidden {
            (showBrush ? Self.invisibleCursor : (next == .canvasPoint ? canvasPointCursor() : next.cursor)).set()
        }
        if systemCursorHidden {
            pointerView.setFrameOrigin(CGPoint(x: point.x - pointerHotSpot.x, y: point.y - pointerHotSpot.y))
            pointerView.isHidden = showBrush
        }
    }

    private static let invisibleCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)

    private var canvasPointDiameter: CGFloat {
        let width: CGFloat
        if let index = selectedMark, marks.indices.contains(index), let selectedWidth = marks[index].lineWidth {
            width = selectedWidth
        } else if tool == .pen {
            width = penWidth
        } else if tool?.usesLineWidth == true {
            width = shapeWidth
        } else {
            return 5
        }
        return max(0.1, width * (recognitionView?.imageScale ?? 1))
    }

    private var canvasTextSize: CGFloat? {
        guard tool == .text else { return nil }
        return textSize * (recognitionView?.imageScale ?? 1)
    }

    private func canvasPointCursor() -> NSCursor {
        let diameter = canvasPointDiameter
        let textSize = canvasTextSize
        if pointCursorInk != ink || pointCursorDiameter != diameter || pointCursorTextSize != textSize || cachedPointCursor == nil {
            if let textSize {
                cachedPointCursor = Pointer.textCursor(for: ink, size: textSize)
            } else {
                cachedPointCursor = Pointer.canvasPointCursor(for: ink, diameter: diameter)
            }
            pointCursorInk = ink
            pointCursorDiameter = diameter
            pointCursorTextSize = textSize
        }
        return cachedPointCursor!
    }

    @discardableResult
    func adjustMarkupSize(with event: NSEvent) -> Bool {
        adjustMarkupSize(delta: event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY,
                         precise: event.hasPreciseScrollingDeltas,
                         at: event.locationInWindow, modifiers: event.modifierFlags)
    }

    // Retained for the existing mosaic interaction and its focused tests.
    @discardableResult
    func adjustMosaicSize(delta: CGFloat, precise: Bool, at windowPoint: CGPoint) -> Bool {
        guard tool == .mosaic else { return false }
        return adjustMarkupSize(delta: delta, precise: precise, at: windowPoint,
                                modifiers: isDocument ? .option : [])
    }

    private func resetScrollUndo() {
        scrollUndoIndex = nil
        lastScrollUndoTime = 0
    }

    @discardableResult
    func adjustMarkupSize(delta: CGFloat, precise: Bool, at windowPoint: CGPoint,
                          modifiers: NSEvent.ModifierFlags = []) -> Bool {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        guard flags == (isDocument ? .option : []), delta != 0,
              drag == nil, !pickingInkColor, !pickingCoverColor, !documentExportInProgress,
              !isEditingText, !isEditingRecognitionMarkup else { return false }
        let point = convert(windowPoint, from: nil)
        if let recognitionView {
            guard !recognitionView.paletteContains(point), !recognitionView.textContains(point),
                  !recognitionView.markupInputContains(point),
                  recognitionView.capturePoint(at: point) != nil else { return false }
        } else {
            guard let selection, selection.contains(point) else { return false }
            if isDocument {
                guard visibleRect.contains(point) else { return false }
            } else {
                guard (toolbar.isHidden || !toolbar.frame.contains(point)),
                      (palette.isHidden || !palette.frame.contains(point)),
                      (mosaicOptions.isHidden || !mosaicOptions.frame.contains(point)) else { return false }
            }
        }
        let index = selectedMark.flatMap { marks.indices.contains($0) ? $0 : nil }
        let selected = index.map { marks[$0] }
        let increment: CGFloat = precise ? delta * 0.25 : (delta > 0 ? 1 : -1)
        let direction: CGFloat = delta > 0 ? 1 : -1
        var value: CGFloat
        var title: UIKey
        var updated: Mark?
        var affectsMosaic = false
        if let selected {
            switch selected {
            case .text(let text, let origin, let ink, let oldSize):
                value = max(10, min(72, oldSize + (precise ? delta * 0.5 : direction * 2)))
                title = .textSize
                updated = .text(text, origin, ink, size: value)
                textSize = value
            case .mosaic(let points, let diameter, let style, let color):
                value = max(10, min(100, diameter + (precise ? delta * 0.6 : direction * 4)))
                title = .wheelMosaicSize
                updated = .mosaic(points, diameter: value, style: style, color: color)
                mosaicDiameter = value
                affectsMosaic = true
            default:
                guard let width = selected.lineWidth else { return false }
                value = max(1, min(20, width + increment))
                title = .penWidth
                updated = selected.withLineWidth(value)
                if case .pen = selected { penWidth = value } else { shapeWidth = value }
            }
        } else if let tool {
            switch tool {
            case .mosaic:
                value = max(10, min(100, mosaicDiameter + (precise ? delta * 0.6 : direction * 4)))
                mosaicDiameter = value
                title = .wheelMosaicSize
                scrollHintAvailable = false
                scrollHintPolicy.didScroll()
                mosaicScrollHint.isHidden = true
            case .text:
                value = max(10, min(72, textSize + (precise ? delta * 0.5 : direction * 2)))
                textSize = value
                title = .textSize
            case .pen:
                value = max(1, min(20, penWidth + increment))
                penWidth = value
                title = .penWidth
            case .ellipse, .rectangle, .arrow:
                value = max(1, min(20, shapeWidth + increment))
                shapeWidth = value
                title = .penWidth
            }
        } else { return false }

        scrollHintAvailable = false
        scrollHintPolicy.didScroll()
        mosaicScrollHint.isHidden = true
        if let index, let updated, updated != marks[index] {
            let now = ProcessInfo.processInfo.systemUptime
            if scrollUndoIndex != index || now - lastScrollUndoTime > 0.6 {
                undoMarks.append(snapshot)
                redoMarks.removeAll()
            }
            scrollUndoIndex = index
            lastScrollUndoTime = now
            marks[index] = updated
            background.clearSampleCache()
            if affectsMosaic, let recognitionView {
                recognitionTask?.cancel()
                recognitionTask = nil
                if !recognitionView.preserveEditedTextForChangedImage(isDrawing: true) { recognitionView.showLoading() }
                ocrRefreshWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.rerunRecognitionForCurrentCapture() }
                ocrRefreshWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
            syncRecognitionMarkup()
            refresh()
        }
        if title == .penWidth || title == .wheelMosaicSize || (title == .textSize && selectedMark == nil && tool == .text) {
            hideSizeFeedback()
        } else {
            showSizeFeedback(title: title, value: value, at: point)
        }
        updatePointer(at: windowPoint)
        return true
    }

    private func hideSizeFeedback() {
        feedbackGeneration += 1
        feedbackWork?.cancel()
        sizeFeedback.isHidden = true
        sizeOutline.isHidden = true
    }

    private func showSizeFeedback(title: UIKey, value: CGFloat, at point: CGPoint) {
        feedbackGeneration += 1
        let generation = feedbackGeneration
        feedbackWork?.cancel()
        sizeFeedback.layer?.removeAllAnimations()
        sizeOutline.layer?.removeAllAnimations()
        let feedback: NSView
        if title == .textSize {
            sizeOutline.isHidden = true
            sizeFeedback.alphaValue = 1
            sizeFeedback.fontSize = value * (recognitionView?.imageScale ?? 1)
            sizeFeedback.ink = ink
            sizeFeedback.updateSize()
            positionTextSizePreview(at: point)
            sizeFeedback.isHidden = false
            feedback = sizeFeedback
        } else {
            sizeFeedback.isHidden = true
            let diameter = value * (recognitionView?.imageScale ?? 1)
            let side = diameter + 4
            sizeOutline.frame = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            sizeOutline.alphaValue = 1
            sizeOutline.needsDisplay = true
            sizeOutline.isHidden = false
            feedback = sizeOutline
        }
        let work = DispatchWorkItem { [weak self, weak feedback] in
            guard let self, let feedback, self.feedbackGeneration == generation else { return }
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                feedback.animator().alphaValue = 0
            } completionHandler: { [weak self, weak feedback] in
                guard let self, let feedback, self.feedbackGeneration == generation else { return }
                feedback.isHidden = true
                if let window = self.window { self.updatePointer(at: window.mouseLocationOutsideOfEventStream) }
            }
        }
        feedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func positionTextSizePreview(at point: CGPoint) {
        let area = isDocument ? visibleRect : bounds
        let height = sizeFeedback.frame.height
        sizeFeedback.frame.origin = CGPoint(x: point.x - sizeFeedback.frame.width - 8,
                                           y: max(area.minY, min(point.y - height / 2, area.maxY - height)))
    }

    func setWindowSnapHeld(_ held: Bool, at windowPoint: CGPoint) {
        guard held != isWindowSnapHeld else { return }
        isWindowSnapHeld = held
        updatePointer(at: windowPoint)
        updateModeHint()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        desktop.draw(in: context)
        if let windowImage {
            context.setFillColor(KlikTheme.overlaySurface.cgColor)
            context.fill(windowImage.frame)
            windowImage.draw(in: context)
        }
        let active = draftSelection ?? selection ?? (drag == nil ? hoveredWindow : nil)
        if !isDocument {
            context.setFillColor(KlikTheme.overlayCanvas.withAlphaComponent(0.32).cgColor)
            let mask = CGMutablePath()
            mask.addRect(bounds)
            if let active { mask.addRect(active) }
            context.addPath(mask)
            context.drawPath(using: .eoFill)
        }

        guard let active else { return }
        if selection != nil, draftSelection == nil {
            context.saveGState()
            context.clip(to: active)
            for (index, mark) in marks.enumerated() where index != editingTextMark?.index { mark.draw(in: context, background: background) }
            preview?.draw(in: context, background: background, isPreview: true)
            if let selectedMark, marks.indices.contains(selectedMark) {
                let mark = marks[selectedMark]
                if let arrow = mark.arrowGeometry {
                    for point in [arrow.start, arrow.middle, arrow.end] {
                        let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        context.setFillColor(KlikTheme.selection.cgColor)
                        context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                        context.setLineWidth(1.5)
                        context.fillEllipse(in: dot)
                        context.strokeEllipse(in: dot)
                    }
                } else if let rect = mark.resizableBounds {
                    for handle in Selection.Handle.allCases {
                        let point = handle.center(in: rect)
                        let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        context.setFillColor(KlikTheme.selection.cgColor)
                        context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                        context.setLineWidth(1.5)
                        context.fillEllipse(in: dot)
                        context.strokeEllipse(in: dot)
                    }
                } else if let rect = mark.selectionBounds {
                    context.setLineDash(phase: 0, lengths: [4, 3])
                    context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                    context.setLineWidth(3)
                    context.stroke(rect.insetBy(dx: -5, dy: -5))
                    context.setStrokeColor(KlikTheme.selection.cgColor)
                    context.setLineWidth(1)
                    context.stroke(rect.insetBy(dx: -5, dy: -5))
                    context.setLineDash(phase: 0, lengths: [])
                }
            }
            context.restoreGState()
        }
        if let cropRect, let cropBounds {
            context.saveGState()
            let shade = CGMutablePath()
            shade.addRect(cropBounds)
            shade.addRect(cropRect)
            context.addPath(shade)
            context.setFillColor(NSColor.black.withAlphaComponent(0.52).cgColor)
            context.drawPath(using: .eoFill)
            context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
            context.setLineWidth(3)
            context.stroke(cropRect)
            context.setStrokeColor(KlikTheme.selection.cgColor)
            context.setLineWidth(1.5)
            context.stroke(cropRect)
            for handle in Selection.Handle.allCases {
                let center = handle.center(in: cropRect)
                let dot = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.setFillColor(KlikTheme.selection.cgColor)
                context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                context.setLineWidth(1)
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            }
            context.restoreGState()
            return
        }
        if isDocument {
            if active != background.frame {
                context.saveGState()
                let mask = CGMutablePath()
                mask.addRect(background.frame)
                mask.addRect(active)
                context.addPath(mask)
                context.setFillColor(NSColor.black.withAlphaComponent(0.64).cgColor)
                context.drawPath(using: .eoFill)
                context.restoreGState()
            }
            return
        }
        context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
        context.setLineWidth(3.5)
        context.stroke(active)
        context.setStrokeColor(KlikTheme.selection.cgColor)
        context.setLineWidth(1.5)
        context.stroke(active)
        if selection != nil, draftSelection == nil {
            for handle in Selection.Handle.allCases {
                let center = handle.center(in: active)
                let dot = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                context.setFillColor(KlikTheme.selection.cgColor)
                context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                context.setLineWidth(1.2)
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard recognitionView == nil, !documentExportInProgress else { return }
        let point = mousePoint(event)
        if let rect = cropRect, let limit = cropBounds {
            if let handle = Selection.Handle.hit(at: point, in: rect) {
                drag = .cropResize(handle, rect, point)
            } else if rect != limit && rect.contains(point) {
                drag = .cropMove(rect, point)
            } else if limit.contains(point) {
                drag = .cropDraw(point)
            }
            dragPoint = point
            refresh()
            return
        }
        if pickingInkColor { applyInkColor(at: point); return }
        if pickingCoverColor { applyCoverColor(at: point); return }
        doubleClickStart = event.clickCount == 2 ? point : nil
        if event.clickCount == 1, windowCaptureTask == nil { lastWindowClick = nil }
        guard windowCaptureTask == nil else { return }
        dragPoint = point
        showPalette = false
        showMosaicOptions = false
        resetScrollUndo()
        hideSizeFeedback()
        let wasEditingText = isEditingText
        commitText()
        window?.makeFirstResponder(self)
        if wasEditingText { refresh(); return }
        errorLabel.isHidden = true
        if event.clickCount == 2, let index = markIndex(at: point), case .text = marks[index] {
            doubleClickStart = nil
            drag = nil
            pendingMarkSelection = nil
            beginEditingTextMark(at: index)
            refresh()
            return
        }
        if !isDocument, let selection, let handle = Selection.Handle.hit(at: point, in: selection,
                                                             retaining: pointer?.resizeHandle) {
            drag = .resize(handle, selection, point)
        } else if let selection, selection.contains(point) {
            if let index = selectedMark, marks.indices.contains(index),
               let rect = marks[index].resizableBounds,
               let handle = Selection.Handle.hit(at: point, in: rect) {
                drag = .resizeMark(index, marks[index], handle, point, marks)
            } else if let index = selectedMark, marks.indices.contains(index),
                      let rect = marks[index].resizableBounds, rect.contains(point) {
                drag = .moveMark(index, marks[index], point, marks)
            } else if let index = selectedMark, marks.indices.contains(index), (marks[index].hitTest(point) || arrowHandle(for: marks[index], at: point) != nil) {
                let mark = marks[index]
                if let handle = arrowHandle(for: mark, at: point) {
                    drag = .resizeArrow(index, mark, handle, point, marks)
                } else {
                    drag = .moveMark(index, mark, point, marks)
                }
            } else {
                let candidate = markIndex(at: point)
                selectedMark = nil
                if let candidate, tool == nil || tool == .text {
                    drag = .selectMark(candidate, point)
                } else {
                    if let candidate { pendingMarkSelection = (candidate, point) }
                switch tool {
            case .text:
                beginText(at: point, in: selection)
            case .some(let tool):
                drag = .mark(tool, point)
                if tool == .pen || tool == .mosaic {
                    strokePoints = [point]
                    if tool == .mosaic && mosaicStyle == .solid { strokeColor = .fallback }
                    preview = tool == .pen ? .pen(strokePoints, ink, width: penWidth) : .mosaic(strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
            case .none:
                if !isDocument { drag = .move(selection, point) }
                }
                }
            }
        } else if !isDocument {
            let target: ClickTarget = isWindowSnapHeld && canSnapToWindow
                ? .window(WindowSnap.target(at: point, in: windowTargets)) : .display
            drag = .select(point, moved: false, target: target)
            draftSelection = CGRect(origin: point, size: .zero)
        }
        updateMagnifier(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard recognitionView == nil else { return }
        let point = mousePoint(event)
        dragPoint = point
        updateDrag(at: point, shift: event.modifierFlags.contains(.shift))
        updateMagnifier(at: point)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard recognitionView == nil else { return }
        if isCropping {
            updateDrag(at: mousePoint(event))
            if let rect = cropRect, rect.width < Selection.minimum || rect.height < Selection.minimum {
                cropRect = cropBounds
            }
            drag = nil
            dragPoint = nil
            refresh()
            return
        }
        magnifier.isHidden = true
        defer { dragPoint = nil }
        let point = mousePoint(event)
        if !isDocument, event.clickCount == 2, let start = doubleClickStart,
           hypot(point.x - start.x, point.y - start.y) <= 3 {
            doubleClickStart = nil
            if let target = lastWindowClick, target.frame.contains(point) {
                drag = nil
                draftSelection = nil
                if windowCaptureTask != nil {
                    copyWhenWindowReady = true
                } else if windowImage != nil || target.usesDesktopImage {
                    export(.clipboard)
                }
                return
            }
            if tool == nil, textField == nil, selection?.contains(point) == true {
                drag = nil
                draftSelection = nil
                export(.clipboard)
                return
            }
        }
        doubleClickStart = nil
        guard drag != nil else { return }
        updateDrag(at: point, shift: event.modifierFlags.contains(.shift))
        if case .select(_, let moved, let target) = drag, let draftSelection {
            if !moved, selection == nil {
                switch target {
                case .display:
                    replaceSelection(with: bounds)
                case .window(let window):
                    if let window {
                        lastWindowClick = window
                        if window.usesDesktopImage {
                            replaceSelection(with: window.frame.intersection(bounds))
                        } else if let captureWindow {
                            selectWindow(window, using: captureWindow)
                        }
                    }
                }
            } else if draftSelection.width >= Selection.minimum && draftSelection.height >= Selection.minimum {
                replaceSelection(with: draftSelection)
            }
        }
        switch drag {
        case .moveMark(let index, _, _, let before), .resizeArrow(let index, _, _, _, let before),
             .resizeMark(let index, _, _, _, let before):
            if before.indices.contains(index), marks.indices.contains(index), before[index] != marks[index] {
                undoMarks.append(EditSnapshot(marks: before, selection: selection))
                redoMarks.removeAll()
            }
        default: break
        }
        if case .selectMark(let index, let start) = drag,
           hypot(point.x - start.x, point.y - start.y) <= 3 {
            selectedMark = index
        } else if let pending = pendingMarkSelection,
                  hypot(point.x - pending.start.x, point.y - pending.start.y) <= 3 {
            selectedMark = pending.index
            preview = nil
        }
        if selectedMark != nil { syncInkWithSelectedMark() }
        if let preview {
            addMark(preview)
            if case .mosaic(_, _, .solid, _) = preview { pickingCoverColor = true; showMosaicOptions = false }
        }
        pendingMarkSelection = nil
        self.drag = nil
        draftSelection = nil
        preview = nil
        strokePoints.removeAll(keepingCapacity: true)
        refresh()
    }

    private func replaceSelection(with rect: CGRect, windowImage: CaptureImage? = nil) {
        self.windowImage = windowImage
        selection = rect
        marks.removeAll()
        undoMarks.removeAll()
        redoMarks.removeAll()
        selectedMark = nil
        choose(nil)
    }

    private func selectWindow(_ target: WindowSnap, using capture: @escaping (CGWindowID) async throws -> CGImage) {
        windowCaptureTask = Task { @MainActor [weak self] in
            do {
                let image = try await capture(target.id)
                guard !Task.isCancelled, let self else { return }
                let frame = target.previewFrame(in: self.bounds)
                self.windowCaptureTask = nil
                self.replaceSelection(with: frame,
                                      windowImage: CaptureImage(image: image, size: frame.size, origin: frame.origin))
                if self.copyWhenWindowReady {
                    self.copyWhenWindowReady = false
                    self.export(.clipboard)
                    return
                }
                self.refresh()
                if let window = self.window { self.updatePointer(at: window.mouseLocationOutsideOfEventStream) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.windowCaptureTask = nil
                self.lastWindowClick = nil
                self.copyWhenWindowReady = false
                self.report(self.strings(.windowCaptureFailed))
                self.refresh()
            }
        }
    }

    private func mousePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func updateMagnifier(at point: CGPoint) {
        let sample: CGPoint
        switch drag {
        case .select:
            sample = point
        case .resize(let handle, _, _):
            guard let selection else { magnifier.isHidden = true; return }
            sample = handle.boundaryPoint(in: selection, near: point)
        default:
            magnifier.isHidden = true
            return
        }
        magnifier.frame = MagnifierLayout.frame(near: point, in: bounds)
        magnifier.source = background
        magnifier.samplePoint = sample
        magnifier.isHidden = false
    }

    func selectionModifiersChanged(_ modifiers: NSEvent.ModifierFlags) {
        guard let point = dragPoint else { return }
        switch drag {
        case .select, .resize:
            updateDrag(at: point, shift: modifiers.contains(.shift))
            updateMagnifier(at: point)
            refresh()
        default: break
        }
    }

    private func updateDrag(at point: CGPoint, shift: Bool = false) {
        switch drag {
        case .cropDraw(let start):
            guard let cropBounds else { return }
            let end = CGPoint(x: min(max(point.x, cropBounds.minX), cropBounds.maxX),
                              y: min(max(point.y, cropBounds.minY), cropBounds.maxY))
            cropRect = Selection.between(start, end)
        case .cropResize(let handle, let original, let start):
            guard let cropBounds else { return }
            cropRect = handle.resize(original, delta: CGPoint(x: point.x - start.x, y: point.y - start.y), in: cropBounds)
        case .cropMove(let original, let start):
            guard let cropBounds else { return }
            cropRect = Selection.move(original, from: start, to: point, in: cropBounds)
        case .select(let start, let moved, let target):
            draftSelection = shift ? desktop.squareSelection(from: start, to: point) : Selection.between(start, point)
            if !moved, max(abs(point.x - start.x), abs(point.y - start.y)) > 3 {
                drag = .select(start, moved: true, target: target)
            }
        case .resize(let handle, let original, let start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selection = shift ? background.squareSelection(resizing: original, handle: handle, delta: delta)
                              : handle.resize(original, delta: delta, in: windowImage?.frame ?? bounds)
        case .move(let original, let start):
            selection = Selection.move(original, from: start, to: point, in: windowImage?.frame ?? bounds)
        case .moveMark(let index, let original, let start, _):
            guard marks.indices.contains(index), let selection, let frame = original.movableBounds else { return }
            var dx = point.x - start.x, dy = point.y - start.y
            if frame.width <= selection.width {
                dx = max(selection.minX - frame.minX, min(dx, selection.maxX - frame.maxX))
            }
            if frame.height <= selection.height {
                dy = max(selection.minY - frame.minY, min(dy, selection.maxY - frame.maxY))
            }
            marks[index] = original.translated(by: CGPoint(x: dx, y: dy))
        case .resizeMark(let index, let original, let handle, let grabPoint, _):
            guard marks.indices.contains(index), let selection, let rect = original.resizableBounds else { return }
            let delta = CGPoint(x: point.x - grabPoint.x, y: point.y - grabPoint.y)
            let resized = shift ? handle.resizeSquare(rect, delta: delta, in: selection, minimum: Selection.minimum)
                                : handle.resize(rect, delta: delta, in: selection)
            marks[index] = original.resized(to: resized)
        case .resizeArrow(let index, let original, let handle, let grabPoint, _):
            guard marks.indices.contains(index), let selection, let arrow = original.arrowGeometry else { return }
            let handles = [arrow.start, arrow.middle, arrow.end]
            let old = handles[handle]
            let target = CGPoint(x: old.x + point.x - grabPoint.x, y: old.y + point.y - grabPoint.y)
            let clamped = CGPoint(x: min(max(target.x, selection.minX), selection.maxX),
                                  y: min(max(target.y, selection.minY), selection.maxY))
            if clamped == old { marks[index] = original; return }
            if handle == 1 {
                marks[index] = .curvedArrow(arrow.start, clamped, arrow.end, arrow.ink, width: arrow.width)
            } else if arrow.curved {
                marks[index] = .curvedArrow(handle == 0 ? clamped : arrow.start, arrow.middle,
                                            handle == 2 ? clamped : arrow.end, arrow.ink, width: arrow.width)
            } else {
                marks[index] = .arrow(handle == 0 ? clamped : arrow.start,
                                      handle == 2 ? clamped : arrow.end, arrow.ink, width: arrow.width)
            }
        case .mark(let tool, let start):
            guard let selection else { return }
            let end = CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                              y: min(max(point.y, selection.minY), selection.maxY))
            switch tool {
            case .ellipse, .rectangle:
                let final = shift ? MarkConstraint.squareEnd(from: start, toward: end, in: selection) : end
                let rect = Selection.between(start, final)
                preview = rect.width >= 2 && rect.height >= 2
                    ? (tool == .ellipse ? .ellipse(rect, ink, width: shapeWidth) : .rectangle(rect, ink, width: shapeWidth)) : nil
            case .arrow:
                let final = shift ? MarkConstraint.snappedEnd(from: start, toward: end, in: selection) : end
                preview = hypot(final.x - start.x, final.y - start.y) >= 2 ? .arrow(start, final, ink, width: shapeWidth) : nil
            case .pen, .mosaic:
                if strokePoints.last != end { strokePoints.append(end) }
                if tool == .pen {
                    preview = .pen(shift ? [start, end] : strokePoints, ink, width: penWidth)
                } else {
                    preview = .mosaic(shift ? [start, end] : strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
            case .text:
                break
            }
        case .selectMark, .none:
            break
        }
    }

    private func buildToolbar() {
        configureTray(toolbar)
        for (index, tool) in Tool.allCases.enumerated() {
            let button = HoverButton()
            button.tag = index
            let item = tool.item
            if tool == .ellipse {
                MarkupToolbarLayout.configureButton(button, symbol: item.symbol, fallback: "circle",
                                                    label: strings(item.label), target: self, action: #selector(pickTool(_:)))
            } else {
                configure(button, (item.symbol, item.label), action: #selector(pickTool(_:)))
            }
            if isDocument, tool == .mosaic { button.toolTip = strings(.scrollMosaicHint) }
            toolButtons[tool] = button
            toolbarButtons.append(button)
            practiceSteps.append(.init(button: button, detail: item.detail))
        }
        if isDocument {
            MarkupToolbarLayout.configureButton(cropButton, symbol: "crop", fallback: "crop",
                                                label: strings(.toolCrop), target: self, action: #selector(toggleCrop))
            cropButton.identifier = NSUserInterfaceItemIdentifier("cropButton")
            toolbarButtons.append(cropButton)
        }
        practiceSteps.append(.init(button: inkButton, detail: .practiceColor))
        configure(undoButton, ("undo", .toolUndo), action: #selector(undo))
        toolbarButtons.append(undoButton)
        practiceSteps.append(.init(button: undoButton, detail: .practiceUndo))
        configure(redoButton, ("redo", .toolRedo), action: #selector(redo))
        toolbarButtons.append(redoButton)
        practiceSteps.append(.init(button: redoButton, detail: .practiceRedo))
        if !isDocument {
            let recognizeButton = HoverButton()
            configure(recognizeButton, ("scan-text", .toolRecognizeText), action: #selector(startTextRecognition))
            toolbarButtons.append(recognizeButton)
            practiceSteps.append(.init(button: recognizeButton, detail: .practiceRecognizeText))
        }
        if startScrollCapture != nil {
            let scrollButton = HoverButton()
            MarkupToolbarLayout.configureButton(scrollButton, symbol: "scroll-capture", fallback: "arrow.up.and.down",
                                                label: strings(.toolScrollCapture), target: self, action: #selector(beginScrollCapture))
            toolbarButtons.append(scrollButton)
        }
        let actions: [(String, UIKey, UIKey, Selector)] = [
            ("download", .toolDownload, .practiceDownload, #selector(download)),
            ("x", .toolCancel, .practiceCancel, #selector(cancel)),
            ("check", .toolConfirm, .practiceConfirm, #selector(confirm))
        ]
        for (symbol, label, detail, action) in actions {
            let button = HoverButton()
            configure(button, (symbol, label), action: action)
            if symbol == "download" { downloadButton = button }
            toolbarButtons.append(button)
            practiceSteps.append(.init(button: button, detail: detail))
        }
        for button in toolbarButtons {
            toolbar.addSubview(button)
        }
        configureSwatch(inkButton, action: #selector(togglePalette))
        inkButton.wantsLayer = true
        KlikTheme.round(inkButton.layer, radius: KlikTheme.controlRadius, clips: false)
        toolbar.addSubview(inkButton)
        layoutToolbarButtons()
    }

    private func configureTray(_ tray: NSVisualEffectView) {
        MarkupToolbarLayout.styleTray(tray)
        tray.isHidden = true
        addSubview(tray)
    }

    private func layoutToolbarButtons(maximumWidth: CGFloat = .greatestFiniteMagnitude) {
        var visible = toolbarButtons
        visible.insert(inkButton, at: Tool.allCases.count)
        let width = min(maximumWidth, MarkupToolbarLayout.width(buttonCount: visible.count))
        toolbar.setFrameSize(CGSize(width: width, height: MarkupToolbarLayout.height))
        MarkupToolbarLayout.arrange(buttons: visible, width: width)
    }

    func pinDocumentToolbar(to host: NSView, inset: CGFloat) -> CGRect {
        documentToolbarHost = host
        toolbar.identifier = NSUserInterfaceItemIdentifier("scrollPreviewToolbar")
        for view in [toolbar, palette, mosaicOptions] {
            view.removeFromSuperview()
            host.addSubview(view)
        }
        layoutToolbarButtons(maximumWidth: host.bounds.width - 2 * inset)
        toolbar.setFrameOrigin(CGPoint(x: host.bounds.maxX - toolbar.frame.width - inset, y: inset))
        refresh()
        return toolbar.frame
    }

    func setDocumentExporting(_ exporting: Bool) {
        documentExportInProgress = exporting
        for button in toolbarButtons where button.action != #selector(cancel) { button.isEnabled = !exporting }
        inkButton.isEnabled = !exporting
        refresh()
    }

    var downloadButtonScreenFrame: CGRect? {
        guard let button = downloadButton, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func updateDocumentViewport() {
        updateModeHint()
        updateCropHint()
    }

    private func layoutDocumentToolbar(in host: NSView) {
        toolbar.isHidden = false
        mosaicOptions.setCanPickColor(canPickCoverColor)
        palette.isHidden = !showPalette || documentExportInProgress
        mosaicOptions.isHidden = !showMosaicOptions || tool != .mosaic || documentExportInProgress
        let popupY = toolbar.frame.maxY + 6
        let width = host.bounds.width
        if !palette.isHidden {
            let x = toolbar.frame.minX + inkButton.frame.midX - palette.frame.width / 2
            palette.setFrameOrigin(CGPoint(x: max(5, min(x, width - palette.frame.width - 5)), y: popupY))
        }
        if !mosaicOptions.isHidden, let mosaicButton = toolButtons[.mosaic] {
            let x = toolbar.frame.minX + mosaicButton.frame.midX - mosaicOptions.frame.width / 2
            mosaicOptions.setFrameOrigin(CGPoint(x: max(5, min(x, width - mosaicOptions.frame.width - 5)), y: popupY))
            mosaicOptions.select(mosaicStyle)
        }

    }

    private func buildPalette() {
        configureTray(palette)
        for (index, color) in Ink.allCases.enumerated() {
            let button = HoverButton(frame: CGRect(x: 5 + 27 * index, y: 4, width: 27, height: 27))
            configureSwatch(button, action: #selector(pickInk(_:)))
            button.tag = index
            button.toolTip = strings(color.label)
            button.setAccessibilityLabel(strings(color.label))
            palette.addSubview(button)
            paletteButtons[color] = button
        }
        let picker = HoverButton(frame: CGRect(x: 5 + 27 * Ink.allCases.count, y: 4, width: 27, height: 27))
        configureSwatch(picker, action: #selector(beginInkColorPick))
        picker.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        picker.contentTintColor = KlikTheme.overlayInk
        picker.toolTip = strings(.inkSample)
        picker.setAccessibilityLabel(strings(.inkSample))
        palette.addSubview(picker)
        palette.setFrameSize(CGSize(width: 10 + 27 * (Ink.allCases.count + 1), height: 35))
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
        sizeFeedback.ink = ink
        let title = strings(.inkPicker, strings(ink.label))
        inkButton.toolTip = title
        inkButton.setAccessibilityLabel(title)
        inkButton.image = MarkupToolbarLayout.swatch(ink)
        for (color, button) in paletteButtons {
            button.image = MarkupToolbarLayout.swatch(color, selected: color == ink)
        }
        if pointer == .canvasPoint {
            let cursor = canvasPointCursor()
            if isDocument || !systemCursorHidden { cursor.set() }
            else { pointerView.image = cursor.image }
        }
    }

    private func syncInkWithSelectedMark() {
        guard let index = selectedMark, marks.indices.contains(index), let color = marks[index].editableInk else { return }
        ink = color
        updateSwatches()
    }

    private func applyInk(_ color: Ink) {
        ink = color
        if let index = selectedMark, marks.indices.contains(index), let changed = marks[index].withInk(color), changed != marks[index] {
            let wasMosaic: Bool
            if case .mosaic = marks[index] { wasMosaic = true } else { wasMosaic = false }
            undoMarks.append(snapshot)
            redoMarks.removeAll()
            marks[index] = changed
            resetScrollUndo()
            background.clearSampleCache()
            if wasMosaic, recognitionView != nil { rerunRecognitionForCurrentCapture() }
        }
        updateSwatches()
        syncRecognitionMarkup()
        refresh()
    }

    @objc private func togglePalette() {
        commitText()
        showMosaicOptions = false
        showPalette.toggle()
        refresh()
    }

    @objc private func pickInk(_ sender: NSButton) {
        cancelInkColorPick()
        applyInk(Ink.allCases[sender.tag])
        showPalette = false
        updateSwatches()
        refresh()
    }

    private func configure(_ button: HoverButton, _ item: (symbol: String, label: UIKey), action: Selector) {
        MarkupToolbarLayout.configureButton(button, symbol: item.symbol, label: strings(item.label),
                                            target: self, action: action)
    }

    private func refresh() {
        needsDisplay = true
        updateCropHint()
        if let host = documentToolbarHost {
            layoutDocumentToolbar(in: host)
        } else if let selection, !isDocument, drag == nil {
            mosaicOptions.setCanPickColor(canPickCoverColor)
            let size = toolbar.frame.size
            let x = max(5, min(selection.maxX - size.width, bounds.maxX - size.width - 5))
            let below = selection.maxY + 9
            let above = selection.minY - size.height - 9
            let y = below + size.height + 5 <= bounds.maxY ? below : max(5, above)
            toolbar.setFrameOrigin(CGPoint(x: x, y: y))
            toolbar.isHidden = false
            palette.isHidden = !showPalette
            mosaicOptions.isHidden = !showMosaicOptions || tool != .mosaic
            if !mosaicOptions.isHidden, let mosaicButton = toolButtons[.mosaic] {
                let center = toolbar.frame.minX + mosaicButton.frame.midX
                let x = max(5, min(center - mosaicOptions.frame.width / 2, bounds.maxX - mosaicOptions.frame.width - 5))
                let below = toolbar.frame.maxY + 6
                let y = below + mosaicOptions.frame.height <= bounds.maxY - 5 ? below : max(5, toolbar.frame.minY - mosaicOptions.frame.height - 6)
                mosaicOptions.setFrameOrigin(CGPoint(x: x, y: y))
                mosaicOptions.select(mosaicStyle)
            }
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
            mosaicOptions.isHidden = true
        }
        for button in toolbarButtons {
            if isCropping {
                button.isEnabled = button === cropButton || button.action == #selector(cancel) || button.action == #selector(confirm)
            } else if !documentExportInProgress {
                button.isEnabled = true
            }
        }
        inkButton.isEnabled = !isCropping && !documentExportInProgress
        undoButton.isEnabled = !isCropping && !documentExportInProgress && (!undoMarks.isEmpty || isEditingText)
        redoButton.isEnabled = !isCropping && !documentExportInProgress && !redoMarks.isEmpty && !isEditingText
        if let coach {
            if drag != nil || isEditingText || windowCaptureTask != nil || !errorLabel.isHidden {
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
        updateSelectionSize()
    }

    private func updateCropHint() {
        cropHint.isHidden = !isCropping
        guard isCropping else { return }
        let area = isDocument ? visibleRect : bounds
        let size = cropHint.size(maximumWidth: max(1, area.width - 16))
        cropHint.frame = CGRect(x: area.midX - size.width / 2, y: area.minY + 10,
                                width: size.width, height: size.height)
    }

    private func updateSelectionSize() {
        guard !isDocument, recognitionView == nil, let region = draftSelection ?? selection,
              region.width > 0, region.height > 0 else { selectionSize.isHidden = true; return }
        let pixels = (draftSelection == nil ? background : desktop).pixelRect(for: region)
        guard !pixels.isEmpty else { selectionSize.isHidden = true; return }
        selectionSize.text = "\(Int(pixels.width)) x \(Int(pixels.height))"
        let size = selectionSize.size(maximumWidth: bounds.width - 8)
        let above = region.minY - size.height - 5
        let fitsAbove = above >= bounds.minY + 4
        let x = max(bounds.minX + 4, min(region.minX + (fitsAbove ? 0 : 6), bounds.maxX - size.width - 4))
        let y = fitsAbove ? above : min(region.minY + 6, bounds.maxY - size.height - 4)
        selectionSize.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        selectionSize.isHidden = false
    }

    private func updateModeHint() {
        let capturingWindow = windowCaptureTask != nil
        modeHint.isHidden = !pickingCoverColor && !pickingInkColor && !capturingWindow && (selection != nil || drag != nil || coach != nil || windowTargets.isEmpty)
        guard !modeHint.isHidden else { return }
        let message: UIKey = (pickingCoverColor || pickingInkColor) ? .mosaicPickPrompt : (capturingWindow ? .windowCapturePending
            : (isWindowSnapHeld ? .windowSnapActive : .windowSnapHint))
        modeHint.text = strings(message)
        let area = isDocument ? visibleRect : bounds
        let size = modeHint.size(maximumWidth: area.width - 16)
        modeHint.frame = CGRect(origin: CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 18),
                                size: size)
    }

    @objc private func pickTool(_ sender: NSButton) {
        if isCropping { cancelCrop() }
        guard !pickingCoverColor else { updateModeHint(); return }
        guard drag == nil else { return }
        pickingCoverColor = false
        commitText()
        showPalette = false
        let chosen = Tool.allCases[sender.tag]
        resetScrollUndo()
        if tool != chosen { selectedMark = nil }
        if chosen == .mosaic {
            if tool == .mosaic { showMosaicOptions.toggle() }
            else { choose(.mosaic); showMosaicOptions = true }
        } else {
            showMosaicOptions = false
            choose(tool == chosen ? nil : chosen)
        }
        refresh()
    }

    private func cancelInkColorPick() {
        guard pickingInkColor else { return }
        pickingInkColor = false
        eyedropperPreview.isHidden = true
        background.clearSampleCache()
        updateModeHint()
    }

    private func choose(_ chosen: Tool?) {
        cancelInkColorPick()
        tool = chosen
        for (tool, button) in toolButtons {
            (button as? HoverButton)?.toolSelected = tool == chosen
        }
    }

    @objc private func toggleCrop() {
        if isCropping { applyCrop(); return }
        guard !documentExportInProgress, !pickingCoverColor, !pickingInkColor,
              drag == nil, let selection else { return }
        commitText()
        choose(nil)
        selectedMark = nil
        showPalette = false
        showMosaicOptions = false
        cropBounds = selection
        cropRect = selection
        cropButton.toolSelected = true
        refresh()
    }

    func applyCrop() {
        guard let cropRect, let original = cropBounds else { return }
        if cropRect != original {
            undoMarks.append(snapshot)
            redoMarks.removeAll()
            selection = cropRect
            background.clearSampleCache()
        }
        self.cropRect = nil
        cropBounds = nil
        cropButton.toolSelected = false
        drag = nil
        refresh()
    }

    func cancelCrop() {
        guard isCropping else { return }
        cropRect = nil
        cropBounds = nil
        cropButton.toolSelected = false
        drag = nil
        refresh()
    }

    private func beginText(at point: CGPoint, in selection: CGRect, existing: String? = nil, size: CGFloat? = nil) {
        let area = isDocument ? selection.intersection(visibleRect) : selection
        let x = min(max(area.minX, point.x), max(area.minX, area.maxX - 24))
        let y = min(max(area.minY, point.y), max(area.minY, area.maxY - 24))
        textOrigin = CGPoint(x: x, y: y)
        let currentSize = size ?? textSize
        let field = InlineMarkupTextView(origin: textOrigin, maximumWidth: area.maxX - x,
                                         ink: ink, size: currentSize, text: existing ?? "")
        addSubview(field, positioned: .below, relativeTo: pointerView)
        textField = field
        window?.makeFirstResponder(field)
    }

    private func beginEditingTextMark(at index: Int) {
        guard marks.indices.contains(index), let selection,
              case .text(let value, let origin, let color, let size) = marks[index] else { return }
        editingTextMark = (index, marks[index])
        selectedMark = nil
        ink = color
        textSize = size
        updateSwatches()
        if let recognitionView {
            recognitionView.beginMarkupText(at: origin, size: size, ink: color, existing: value)
            syncRecognitionMarkup()
        } else {
            beginText(at: origin, in: selection, existing: value, size: size)
        }
    }

    private func commitTextValue(_ value: String, origin: CGPoint) {
        let nonempty = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let editing = editingTextMark {
            editingTextMark = nil
            guard marks.indices.contains(editing.index), case .text(_, let oldOrigin, let oldInk, let size) = editing.original else { return }
            let replacement = Mark.text(value, oldOrigin, oldInk, size: size)
            if !nonempty || replacement != editing.original {
                undoMarks.append(snapshot)
                redoMarks.removeAll()
                if nonempty { marks[editing.index] = replacement; selectedMark = editing.index }
                else { marks.remove(at: editing.index); selectedMark = nil }
                resetScrollUndo()
            } else { selectedMark = editing.index }
        } else if nonempty {
            addMark(.text(value, origin, ink, size: textSize))
        }
    }

    private func commitText() {
        guard let field = textField else { return }
        let value = field.string
        textField = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        commitTextValue(value, origin: textOrigin)
    }

    private func lineTool(for mark: Mark) -> Tool? {
        switch mark {
        case .ellipse: return .ellipse
        case .rectangle: return .rectangle
        case .arrow, .curvedArrow: return .arrow
        case .pen: return .pen
        default: return nil
        }
    }

    private func arrowHandle(for mark: Mark, at point: CGPoint) -> Int? {
        guard let arrow = mark.arrowGeometry else { return nil }
        let points = [arrow.start, arrow.middle, arrow.end]
        return points.indices.min(by: { hypot(point.x - points[$0].x, point.y - points[$0].y)
            < hypot(point.x - points[$1].x, point.y - points[$1].y) }).flatMap {
                hypot(point.x - points[$0].x, point.y - points[$0].y) <= 10 ? $0 : nil
            }
    }

    private func markIndex(at point: CGPoint) -> Int? {
        marks.indices.reversed().first { marks[$0].hitTest(point) }
    }

    func finishTextEditing() {
        commitText()
        refresh()
    }

    func cancelActiveTextEditing() {
        guard isEditingText || isEditingRecognitionMarkup else { return }
        let previousIndex = editingTextMark?.index
        editingTextMark = nil
        textField?.removeFromSuperview()
        textField = nil
        recognitionView?.cancelMarkupText()
        if let previousIndex, marks.indices.contains(previousIndex) { selectedMark = previousIndex }
        window?.makeFirstResponder(self)
        refresh()
        syncRecognitionMarkup()
    }

    private func addMark(_ mark: Mark) {
        undoMarks.append(snapshot)
        marks.append(mark)
        redoMarks.removeAll()
        selectedMark = nil
    }

    @discardableResult
    func deleteSelectedMark() -> Bool {
        guard drag == nil, !pickingCoverColor, !pickingInkColor, !documentExportInProgress,
              let index = selectedMark, marks.indices.contains(index) else { return false }
        let removed = marks[index]
        undoMarks.append(snapshot)
        marks.remove(at: index)
        redoMarks.removeAll()
        selectedMark = nil
        background.clearSampleCache()
        refresh()
        if recognitionView != nil {
            syncRecognitionMarkup()
            if case .mosaic = removed { rerunRecognitionForCurrentCapture() }
        }
        return true
    }

    @objc func undo() {
        guard !documentExportInProgress else { return }
        if isCropping { cancelCrop(); return }
        commitText()
        if let prior = undoMarks.popLast() {
            redoMarks.append(snapshot)
            marks = prior.marks
            selection = prior.selection
            selectedMark = nil
            resetScrollUndo()
            pickingCoverColor = hasPendingCover
        }
        refresh()
    }

    @objc func redo() {
        guard !isCropping, !isEditingText, !documentExportInProgress else { return }
        if let next = redoMarks.popLast() {
            undoMarks.append(snapshot)
            marks = next.marks
            selection = next.selection
            selectedMark = nil
            resetScrollUndo()
            pickingCoverColor = hasPendingCover
        }
        refresh()
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        if documentExportInProgress { setDocumentExporting(false) }
    }

    @objc func cancel() {
        if isCropping { cancelCrop(); return }
        guard !exportCommitted else { return }
        cancelExport()
        finish(.cancelled)
    }
    @objc private func download() { export(.downloads) }
    @objc private func confirm() { if isCropping { applyCrop() } else { export(.clipboard) } }

    @objc private func beginScrollCapture() {
        guard !pickingCoverColor, !pickingInkColor, drag == nil, windowCaptureTask == nil,
              recognitionView == nil, let selection else { return }
        guard selection.width >= 64, selection.height >= 96 else {
            report(strings(.scrollSelectionSmall))
            return
        }
        commitText()
        guard marks.isEmpty else {
            report(strings(.scrollSelectionMarked))
            return
        }
        startScrollCapture?(selection)
    }

    @objc private func startTextRecognition() {
        guard !pickingCoverColor else { updateModeHint(); return }
        guard drag == nil, windowCaptureTask == nil, recognitionView == nil, let selection else { return }
        commitText()
        guard let image = background.render(selection: selection, marks: marks) else {
            report(strings(.renderError))
            return
        }
        let view = TextRecognitionView(frame: bounds, image: image, imageSize: selection.size,
                                       selection: selection, strings: strings)
        view.autoresizingMask = [.width, .height]
        view.setMarkupHandlers(down: { [weak self] point, clicks in self?.recognitionMarkupDown(point, clickCount: clicks) },
                               drag: { [weak self] point, flags in self?.recognitionMarkupDrag(point, flags: flags) },
                               up: { [weak self] point, flags in self?.recognitionMarkupUp(point, flags: flags) },
                               text: { [weak self] value, point in
                                   guard let self else { return }
                                   self.commitTextValue(value, origin: point)
                                   self.syncRecognitionMarkup()
                               })
        view.onPickCoverColor = { [weak self] in self?.beginCoverColorPick() }
        view.onPickInkColor = { [weak self] in self?.beginInkColorPick() }
        view.onMosaicStyle = { [weak self] style in
            self?.cancelInkColorPick()
            self?.pickingCoverColor = false
            self?.mosaicStyle = style
            self?.mosaicOptions.select(style)
        }
        view.setMosaicStyle(mosaicStyle)
        view.onTool = { [weak self] chosen, deselect in
            guard let self, !self.pickingCoverColor else { return }
            if self.tool != chosen || deselect { self.selectedMark = nil }
            self.choose(deselect ? nil : chosen)
            self.syncRecognitionMarkup()
        }
        view.onInk = { [weak self] ink in
            guard let self else { return }
            self.cancelInkColorPick()
            self.applyInk(ink)
            self.syncRecognitionMarkup()
        }
        view.onRefresh = { [weak self] in self?.requestRecognitionRefresh() }
        view.onUndo = { [weak self] in self?.recognitionUndo() }
        view.onRedo = { [weak self] in self?.recognitionRedo() }
        view.onSave = { [weak self] in self?.saveImageFromTextRecognition() }
        view.onCancel = { [weak self] in self?.cancel() }
        view.onConfirm = { [weak self] in self?.export(.clipboard) }
        view.onCopy = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            guard !self.pickingCoverColor else { self.updateModeHint(); return }
            self.pasteboard.clearContents()
            guard self.pasteboard.setString(text, forType: .string) else {
                self.recognitionView?.showStatus(self.strings(.clipboardError))
                return
            }
            self.recognitionView?.showCopiedConfirmation()
        }
        recognitionView = view
        selectionSize.isHidden = true
        clearPointer()
        addSubview(view, positioned: .above, relativeTo: nil)
        addSubview(sizeFeedback, positioned: .above, relativeTo: view)
        addSubview(sizeOutline, positioned: .above, relativeTo: sizeFeedback)
        addSubview(modeHint, positioned: .above, relativeTo: view)
        addSubview(brushOutline, positioned: .above, relativeTo: modeHint)
        addSubview(mosaicScrollHint, positioned: .above, relativeTo: brushOutline)
        addSubview(eyedropperPreview, positioned: .above, relativeTo: mosaicScrollHint)
        addSubview(pointerView, positioned: .above, relativeTo: eyedropperPreview)
        window?.makeFirstResponder(self)
        syncRecognitionMarkup()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
        runRecognition(image)
    }

    private func runRecognition(_ image: CGImage, preservingText: Bool = false) {
        guard let view = recognitionView else { return }
        recognitionTask?.cancel()
        view.showLoading(preservingText: preservingText)
        recognitionTask = Task { @MainActor [weak self, weak view] in
            guard let self else { return }
            do {
                let text = try await self.recognizeText(image)
                guard !Task.isCancelled, let view, self.recognitionView === view else { return }
                view.showResult(text, emptyMessage: self.strings(.ocrEmpty))
                if let window = self.window { self.updatePointer(at: window.mouseLocationOutsideOfEventStream) }
            } catch {
                guard !Task.isCancelled, let view, self.recognitionView === view else { return }
                view.showError(self.strings(.ocrFailed), preservingText: preservingText)
            }
            self.recognitionTask = nil
        }
    }

    private func syncRecognitionMarkup() {
        recognitionRedraw?.cancel()
        recognitionRedraw = nil
        guard let view = recognitionView, let selection else { return }
        let visibleMarks = marks.enumerated().compactMap { $0.offset == editingTextMark?.index ? nil : $0.element }
        if let image = background.render(selection: selection, marks: visibleMarks, preview: preview) {
            var points: [CGPoint] = []
            if let index = selectedMark, marks.indices.contains(index) {
                switch marks[index] {
                case .ellipse(let rect, _, _), .rectangle(let rect, _, _): points = Selection.Handle.allCases.map { $0.center(in: rect) }
                case .arrow, .curvedArrow:
                    if let arrow = marks[index].arrowGeometry { points = [arrow.start, arrow.middle, arrow.end] }
                case .mosaic:
                    if let rect = marks[index].selectionBounds {
                        points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                  CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                    }
                default:
                    if let rect = marks[index].selectionBounds {
                        points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                  CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                    }
                }
            }
            view.setImage(image, selectedPoints: points)
        }
        view.setMarkupState(tool: tool, ink: ink, canUndo: !undoMarks.isEmpty, canRedo: !redoMarks.isEmpty)
        view.setCanPickCoverColor(canPickCoverColor)
    }

    private func recognitionMarkupDown(_ point: CGPoint, clickCount: Int) {
        guard let selection, selection.contains(point) else { return }
        if pickingInkColor { applyInkColor(at: point); return }
        if pickingCoverColor { applyCoverColor(at: point); return }
        recognitionView?.hideMosaicOptions()
        resetScrollUndo()
        hideSizeFeedback()
        if clickCount == 2, let index = markIndex(at: point), case .text = marks[index] {
            drag = nil
            pendingMarkSelection = nil
            beginEditingTextMark(at: index)
            return
        }
        if let index = selectedMark, marks.indices.contains(index),
           let rect = marks[index].resizableBounds, let handle = Selection.Handle.hit(at: point, in: rect) {
            drag = .resizeMark(index, marks[index], handle, point, marks)
        } else if let index = selectedMark, marks.indices.contains(index),
                  let rect = marks[index].resizableBounds, rect.contains(point) {
            drag = .moveMark(index, marks[index], point, marks)
        } else if let index = selectedMark, marks.indices.contains(index), (marks[index].hitTest(point) || arrowHandle(for: marks[index], at: point) != nil) {
            let mark = marks[index]
            if let handle = arrowHandle(for: mark, at: point) {
                drag = .resizeArrow(index, mark, handle, point, marks)
            } else {
                drag = .moveMark(index, mark, point, marks)
            }
        } else {
            let candidate = markIndex(at: point)
            selectedMark = nil
            if let candidate, tool == nil || tool == .text {
                drag = .selectMark(candidate, point)
            } else {
                if let candidate { pendingMarkSelection = (candidate, point) }
            switch tool {
            case .text:
                recognitionView?.beginMarkupText(at: point, size: textSize, ink: ink)
            case .some(let chosen):
                if chosen == .mosaic {
                    ocrRefreshWork?.cancel()
                    ocrRefreshWork = nil
                    recognitionTask?.cancel()
                    recognitionTask = nil
                    if recognitionView?.preserveEditedTextForChangedImage(isDrawing: true) != true {
                        recognitionView?.showLoading()
                    }
                }
                drag = .mark(chosen, point)
                if chosen == .pen || chosen == .mosaic {
                    strokePoints = [point]
                    if chosen == .mosaic && mosaicStyle == .solid { strokeColor = .fallback }
                    preview = chosen == .pen ? .pen(strokePoints, ink, width: penWidth) : .mosaic(strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
            case .none:
                break
            }
            }
        }
        syncRecognitionMarkup()
    }

    private func recognitionMarkupDrag(_ point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard drag != nil else { return }
        if !recognitionMosaicChanging, case .moveMark(let index, _, let start, _) = drag,
           point != start, marks.indices.contains(index), case .mosaic = marks[index] {
            recognitionMosaicChanging = true
            ocrRefreshWork?.cancel()
            ocrRefreshWork = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            if recognitionView?.preserveEditedTextForChangedImage(isDrawing: true) != true {
                recognitionView?.showLoading()
            }
        }
        updateDrag(at: point, shift: flags.contains(.shift))
        if recognitionRedraw == nil {
            let work = DispatchWorkItem { [weak self] in self?.syncRecognitionMarkup() }
            recognitionRedraw = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
        }
    }

    private func recognitionMarkupUp(_ point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let active = drag else { return }
        updateDrag(at: point, shift: flags.contains(.shift))
        var refreshOCR = recognitionMosaicChanging
        recognitionMosaicChanging = false
        if case .mark(.mosaic, _) = active { refreshOCR = true }
        switch active {
        case .moveMark(let index, _, _, let before), .resizeArrow(let index, _, _, _, let before),
             .resizeMark(let index, _, _, _, let before):
            if before.indices.contains(index), marks.indices.contains(index), before[index] != marks[index] {
                undoMarks.append(EditSnapshot(marks: before, selection: selection))
                redoMarks.removeAll()
                if case .mosaic = marks[index] { refreshOCR = true }
            }
        default: break
        }
        if case .selectMark(let index, let start) = active,
           hypot(point.x - start.x, point.y - start.y) <= 3 {
            selectedMark = index
        } else if let pending = pendingMarkSelection,
                  hypot(point.x - pending.start.x, point.y - pending.start.y) <= 3 {
            selectedMark = pending.index
            preview = nil
        }
        if selectedMark != nil { syncInkWithSelectedMark() }
        if let preview {
            addMark(preview)
            if case .mosaic(_, _, .solid, _) = preview { pickingCoverColor = true }
        }
        pendingMarkSelection = nil
        drag = nil
        preview = nil
        strokePoints.removeAll(keepingCapacity: true)
        syncRecognitionMarkup()
        updateModeHint()
        if refreshOCR { rerunRecognitionForCurrentCapture() }
    }

    private var hasPendingCover: Bool {
        guard let last = marks.last, case .mosaic(_, _, .solid, _) = last else { return false }
        return true
    }

    private var canPickCoverColor: Bool {
        guard let last = marks.last, case .mosaic(_, _, let style, _) = last else { return false }
        return style == .solid || style == .manual
    }

    private func colorForEyedropper(at point: CGPoint) -> CoverColor? {
        guard let selection, background.frame.contains(point) else { return nil }
        let visibleMarks = pickingCoverColor && hasPendingCover ? Array(marks.dropLast()) : marks
        return background.visibleColor(at: point, selection: selection, marks: visibleMarks)
    }

    @objc private func beginInkColorPick() {
        guard !pickingCoverColor else { return }
        pickingInkColor = true
        showPalette = false
        showMosaicOptions = false
        recognitionView?.hideMosaicOptions()
        refresh()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    private func applyInkColor(at point: CGPoint) {
        guard let color = colorForEyedropper(at: point) else { return }
        applyInk(.custom(color))
        pickingInkColor = false
        eyedropperPreview.isHidden = true
        background.clearSampleCache()
        updateSwatches()
        syncRecognitionMarkup()
        refresh()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    private func beginCoverColorPick() {
        guard canPickCoverColor else { return }
        pickingInkColor = false
        pickingCoverColor = true
        updateModeHint()
        showMosaicOptions = false
        mosaicOptions.isHidden = true
        recognitionView?.hideMosaicOptions()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    private func applyCoverColor(at point: CGPoint) {
        guard canPickCoverColor, let index = marks.indices.last,
              case .mosaic(let points, let diameter, _, _) = marks[index] else { return }
        // Pending stripes are excluded from both the preview and the chosen color.
        guard let color = colorForEyedropper(at: point) else { return }
        undoMarks.append(snapshot)
        redoMarks.removeAll()
        marks[index] = .mosaic(points, diameter: diameter, style: .manual, color: color)
        pickingCoverColor = false
        eyedropperPreview.isHidden = true
        background.clearSampleCache()
        updateModeHint()
        mosaicOptions.setCanPickColor(true)
        if recognitionView != nil {
            syncRecognitionMarkup()
            recognitionView?.showMosaicOptions()
            rerunRecognitionForCurrentCapture()
        } else {
            showMosaicOptions = true
            refresh()
        }
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    private func mosaics(in marks: [Mark]) -> [Mark] {
        marks.filter { if case .mosaic = $0 { return true }; return false }
    }

    private func requestRecognitionRefresh() {
        guard !pickingCoverColor, drag == nil, let view = recognitionView,
              let selection else { return }
        let refresh: () -> Void = { [weak self, weak view] in
            guard let self, let view, self.recognitionView === view,
                  !self.pickingCoverColor, self.drag == nil,
                  let image = self.background.render(selection: selection, marks: self.marks) else { return }
            self.runRecognition(image, preservingText: view.hasUserEdits)
        }
        guard view.hasUserEdits else { refresh(); return }
        view.showRefreshConfirmation(refresh)
    }

    private func rerunRecognitionForCurrentCapture() {
        ocrRefreshWork?.cancel()
        ocrRefreshWork = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if recognitionView?.preserveEditedTextForChangedImage(isDrawing: false) == true { return }
        guard let selection, let image = background.render(selection: selection, marks: marks) else {
            recognitionView?.showError(strings(.renderError))
            return
        }
        runRecognition(image)
    }

    func recognitionUndo() {
        recognitionView?.commitMarkupText()
        let prior = mosaics(in: marks)
        undo()
        syncRecognitionMarkup()
        if prior != mosaics(in: marks) { rerunRecognitionForCurrentCapture() }
    }

    func recognitionRedo() {
        recognitionView?.commitMarkupText()
        let prior = mosaics(in: marks)
        redo()
        syncRecognitionMarkup()
        if prior != mosaics(in: marks) { rerunRecognitionForCurrentCapture() }
    }

    func finishRecognitionMarkupText() { recognitionView?.commitMarkupText() }

    func closeTextRecognition() {
        recognitionRedraw?.cancel()
        recognitionRedraw = nil
        ocrRefreshWork?.cancel()
        ocrRefreshWork = nil
        recognitionView?.commitMarkupText()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionView?.removeFromSuperview()
        recognitionView = nil
        recognitionMosaicChanging = false
        window?.makeFirstResponder(self)
        refresh()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    func saveImageFromTextRecognition() {
        recognitionView?.commitMarkupText()
        export(.downloads)
    }

    func copyImageFromTextRecognition() {
        recognitionView?.commitMarkupText()
        export(.clipboard)
    }

    func export(_ destination: Destination) {
        guard drag == nil, windowCaptureTask == nil, !documentExportInProgress, let selection else { return }
        guard !pickingCoverColor else { updateModeHint(); NSSound.beep(); return }
        commitText()
        refresh()
        guard let image = background.render(selection: selection, marks: marks) else {
            report(strings(.renderError))
            return
        }
        if let onDocumentExport {
            onDocumentExport(destination, image)
            return
        }
        setDocumentExporting(true)
        let saveOverride = saveDownload
        exportTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PreparedCaptureExport.make(image: image, destination: destination, saveOverride: saveOverride) }
            }.value
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .failure(let error):
                if error as? PreparedCaptureExport.Failure == .download {
                    self.reportDownloadFailure()
                } else {
                    self.report(self.strings(.renderError))
                }
            case .success(let prepared):
                await self.completeExport(destination, prepared: prepared)
            }
            self.exportTask = nil
            self.setDocumentExporting(false)
        }
    }

    private func completeExport(_ destination: Destination, prepared: PreparedCaptureExport.Result) async {
        switch destination {
        case .clipboard:
            guard ClipboardImage.write(png: prepared.png, tiff: prepared.tiff, to: pasteboard) else {
                report(strings(.clipboardError))
                return
            }
        case .downloads:
            do { try prepared.download?.commit() }
            catch {
                reportDownloadFailure()
                return
            }
        }
        exportCommitted = true
        await recordCapture?(prepared.png)
        exportCommitted = false
        guard !Task.isCancelled else { return }
        let confirmationFrame: CGRect?
        if destination == .downloads {
            if let recognitionView {
                confirmationFrame = recognitionView.saveButtonScreenFrame
            } else {
                confirmationFrame = downloadButtonScreenFrame
            }
        } else {
            confirmationFrame = nil
        }
        finish(.exported)
        if let confirmationFrame { SaveConfirmation.show(at: confirmationFrame) }
    }

    private func reportDownloadFailure() {
        if let recognitionView { recognitionView.showSaveConfirmation(success: false) }
        else { downloadButton?.showBriefConfirmation(symbol: "xmark", color: KlikTheme.danger) }
        report(strings(.downloadError))
    }

    private func report(_ message: String) {
        if let onDocumentStatus {
            onDocumentStatus(message)
            NSSound.beep()
            return
        }
        if let recognitionView {
            recognitionView.showStatus(message)
            NSSound.beep()
            return
        }
        errorLabel.text = message
        let size = errorLabel.size(maximumWidth: bounds.width - 16)
        errorLabel.frame = CGRect(origin: CGPoint(x: bounds.midX - size.width / 2, y: 12), size: size)
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
