import AppKit
import Carbon

enum CaptureDownload {
    static func save(_ png: Data, location: ScreenshotLocation = ScreenshotLocation()) throws {
        let folder = try location.resolve()
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss-SSS"
        let name = "Klik \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).png"
        try png.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

// Teach the gesture a few times, then stop once the user has used it.
final class MosaicScrollHintPolicy {
    private let defaults: UserDefaults?
    private var localCount = 0
    private var localUsed = false
    private let countKey = "mosaicScrollHintShownCount"
    private let usedKey = "mosaicScrollHintUsed"
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
         recognizeText: @escaping (CGImage) async throws -> String = { image in
             try await Task.detached(priority: .userInitiated) { try TextRecognition.recognize(image) }.value
         },
         saveDownload: @escaping (Data) throws -> Void = { try CaptureDownload.save($0) },
         pasteboard: NSPasteboard = .general,
         recordCapture: ((Data) -> Void)? = nil,
         finish: @escaping (Outcome) -> Void) {
        canvas = CaptureView(background: CaptureImage(image: image, size: frame.size),
                             windowTargets: windowTargets, strings: strings, guided: guided,
                             scrollHintPolicy: scrollHintPolicy, captureWindow: captureWindow, recognizeText: recognizeText,
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
        canvas.clearPointer()
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel && canvas.adjustMosaicSize(with: event) { return }
        if canvas.isRecognizingText {
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.type == .keyDown, !composing, modifiers.isEmpty,
               Int(event.keyCode) == kVK_Escape {
                canvas.cancel()
            } else if event.type == .keyDown, !composing,
                      Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
                      canvas.isEditingRecognitionMarkup, modifiers.isEmpty {
                canvas.finishRecognitionMarkupText()
            } else if event.type == .keyDown, !composing,
                      Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
                      (modifiers.isEmpty && !canvas.isEditingRecognitionText(firstResponder))
                        || modifiers == .command {
                canvas.saveImageFromTextRecognition()
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
        if event.type == .keyUp, Int(event.keyCode) == kVK_Space, canvas.isWindowSnapHeld {
            canvas.setWindowSnapHeld(false, at: mouseLocationOutsideOfEventStream)
            return
        }
        if event.type == .keyDown {
            let key = Int(event.keyCode)
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            if key == kVK_Escape && !composing {
                canvas.cancel()
                return
            }
            if !composing, key == kVK_Return || key == kVK_ANSI_KeypadEnter {
                if canvas.isEditingText {
                    canvas.finishTextEditing()
                } else {
                    canvas.export(.clipboard)
                }
                return
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if key == kVK_Space, modifiers.isEmpty, canvas.canSnapToWindow {
                if !event.isARepeat { canvas.setWindowSnapHeld(true, at: mouseLocationOutsideOfEventStream) }
                return
            }
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

private final class EyedropperPreview: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.85).cgColor
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

// A non-interactive, temporary cue beside the mosaic brush cursor.
private final class MosaicScrollHint: NSView {
    private let wheel = CALayer()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.88).cgColor
        layer?.cornerRadius = 7
        wheel.frame = CGRect(x: 10, y: 7, width: 2.5, height: 4)
        wheel.cornerRadius = 1.25
        wheel.backgroundColor = NSColor.white.cgColor
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

private final class CaptureHint: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
        NSColor.windowBackgroundColor.setFill()
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
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

enum Tool: CaseIterable {
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
        case resizeArrow(Int, Mark, Bool, CGPoint, [Mark])
        case resizeMark(Int, Mark, Selection.Handle, CGPoint, [Mark])
        case mark(Tool, CGPoint)
    }

    enum Pointer: Equatable {
        case crosshair, arrow, hand, openHand, closedHand, text, move, eyedropper
        case resize(Selection.Handle)

        var cursor: NSCursor {
            switch self {
            case .crosshair: return .crosshair
            case .arrow: return .arrow
            case .hand: return .pointingHand
            case .openHand: return .openHand
            case .closedHand: return .closedHand
            case .text: return .iBeam
            case .move: return Self.moveCursor
            case .eyedropper: return Self.eyedropperCursor
            case .resize(let handle): return handle.cursor
            }
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
    private var windowImage: CaptureImage?
    private var background: CaptureImage { windowImage ?? desktop }
    private let windowTargets: [WindowSnap]
    private let captureWindow: ((CGWindowID) async throws -> CGImage)?
    private let recognizeText: (CGImage) async throws -> String
    private let saveDownload: (Data) throws -> Void
    private var recognitionTask: Task<Void, Never>?
    private var recognitionView: TextRecognitionView?
    private var windowCaptureTask: Task<Void, Never>?
    private var lastWindowClick: WindowSnap?
    private var doubleClickStart: CGPoint?
    private var copyWhenWindowReady = false
    private let pasteboard: NSPasteboard
    private let recordCapture: ((Data) -> Void)?
    private let strings: AppStrings
    private let finish: (CapturePanel.Outcome) -> Void
    private let coach: CaptureCoach?
    private var practiceSteps: [CaptureCoach.Step] = []
    private let toolbar = NSVisualEffectView()
    private let palette = NSVisualEffectView()
    private let mosaicOptions: MosaicOptions
    private var showMosaicOptions = false
    private var mosaicStyle: MosaicStyle = .pixel
    private var strokeColor: CoverColor = .fallback
    private var pickingCoverColor = false
    private var pickingInkColor = false
    private let modeHint = CaptureHint(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let pointerView = PointerView()
    private let eyedropperPreview = EyedropperPreview(frame: CGRect(x: 0, y: 0, width: 17, height: 17))
    private let brushOutline = BrushOutline()
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
    private let toolbarDividers = [NSView(), NSView(), NSView()]
    private var toolbarButtons: [NSButton] = []
    private var toolButtons: [Tool: NSButton] = [:]
    private var paletteButtons: [Ink: NSButton] = [:]
    private var selection: CGRect?
    private var draftSelection: CGRect?
    private(set) var isWindowSnapHeld = false
    private var hoveredWindow: CGRect?
    private(set) var marks: [Mark] = []
    private var undoMarks: [[Mark]] = []
    private var redoMarks: [[Mark]] = []
    private var selectedMark: Int?
    private var preview: Mark?
    private var drag: Drag?
    private var strokePoints: [CGPoint] = []
    private var tool: Tool?
    private var ink: Ink = .red
    private var showPalette = false
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    private var pointerTracking: NSTrackingArea?
    private(set) var pointer: Pointer?
    private var pointerHotSpot = CGPoint.zero
    private var systemCursorHidden = false

    init(background: CaptureImage, windowTargets: [WindowSnap], strings: AppStrings, guided: Bool,
         scrollHintPolicy: MosaicScrollHintPolicy = MosaicScrollHintPolicy(), captureWindow: ((CGWindowID) async throws -> CGImage)?,
         recognizeText: @escaping (CGImage) async throws -> String,
         saveDownload: @escaping (Data) throws -> Void,
         pasteboard: NSPasteboard,
         recordCapture: ((Data) -> Void)?,
         finish: @escaping (CapturePanel.Outcome) -> Void) {
        self.desktop = background
        self.scrollHintPolicy = scrollHintPolicy
        self.scrollHintAvailable = scrollHintPolicy.shouldShow
        self.windowTargets = windowTargets
        self.captureWindow = captureWindow
        self.recognizeText = recognizeText
        self.saveDownload = saveDownload
        self.pasteboard = pasteboard
        self.recordCapture = recordCapture
        self.strings = strings
        self.mosaicOptions = MosaicOptions(strings: strings)
        self.coach = guided ? CaptureCoach(strings: strings) : nil
        self.finish = finish
        super.init(frame: CGRect(origin: .zero, size: background.size))
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
        guard bounds.contains(point) else {
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
                        case .rectangle(let rect, _) = marks[index],
                        let handle = Selection.Handle.hit(at: imagePoint, in: rect) { next = .resize(handle) }
                else if let index = selectedMark, marks.indices.contains(index),
                        case .rectangle(let rect, _) = marks[index], rect.contains(imagePoint) { next = .move }
                else if markIndex(at: imagePoint) != nil { next = .move }
                else if tool != nil { next = .crosshair }
                else { next = .arrow }
            } else { next = .arrow }
        } else if hoveredWindow != nil {
            next = .hand
        } else if let textField, textField.frame.contains(point) {
            next = .text
        } else if (!toolbar.isHidden && toolbar.frame.contains(point))
                    || (!palette.isHidden && palette.frame.contains(point))
                    || (!mosaicOptions.isHidden && mosaicOptions.frame.contains(point))
                    || coach?.hitTest(point) != nil {
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
        } else if drag == nil, let selection, let handle = Selection.Handle.hit(
            at: point, in: selection, retaining: pointer?.resizeHandle
        ) {
            next = .resize(handle)
        } else if drag == nil, let index = selectedMark, marks.indices.contains(index),
                  case .rectangle(let rect, _) = marks[index],
                  let handle = Selection.Handle.hit(at: point, in: rect) {
            next = .resize(handle)
        } else if drag == nil, let index = selectedMark, marks.indices.contains(index),
                  case .rectangle(let rect, _) = marks[index], rect.contains(point) {
            next = .move
        } else if drag == nil, selection?.contains(point) == true, markIndex(at: point) != nil {
            next = .move
        } else if drag == nil, tool == nil, let selection, selection.contains(point) {
            next = .openHand
        } else {
            next = .crosshair
        }
        let inImage: Bool
        let scale: CGFloat
        if let recognitionView {
            inImage = recognitionView.capturePoint(at: point) != nil && !recognitionView.paletteContains(point)
            scale = recognitionView.imageScale
        } else {
            inImage = selection?.contains(point) == true && (toolbar.isHidden || !toolbar.frame.contains(point))
            scale = 1
        }
        let showBrush = tool == .mosaic && inImage && drag == nil && next == .crosshair
        brushOutline.isHidden = !showBrush
        if showBrush {
            let size = mosaicDiameter * scale + 4
            brushOutline.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            brushOutline.needsDisplay = true
        }
        if !scrollHintStarted && !scrollHintPolicy.shouldShow { scrollHintAvailable = false }
        mosaicScrollHint.isHidden = !showBrush || !scrollHintAvailable
        if !mosaicScrollHint.isHidden {
            let gap = mosaicDiameter * scale / 2 + 9
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

    @discardableResult
    func adjustMosaicSize(with event: NSEvent) -> Bool {
        adjustMosaicSize(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                         at: event.locationInWindow)
    }

    @discardableResult
    func adjustMosaicSize(delta: CGFloat, precise: Bool, at windowPoint: CGPoint) -> Bool {
        guard tool == .mosaic, drag == nil, !pickingInkColor, !pickingCoverColor else { return false }
        let point = convert(windowPoint, from: nil)
        if let recognitionView {
            guard !recognitionView.paletteContains(point), !recognitionView.textContains(point),
                  recognitionView.capturePoint(at: point) != nil else { return false }
        } else {
            guard let selection, selection.contains(point),
                  (toolbar.isHidden || !toolbar.frame.contains(point)),
                  (palette.isHidden || !palette.frame.contains(point)),
                  (mosaicOptions.isHidden || !mosaicOptions.frame.contains(point)) else { return false }
        }
        guard delta != 0 else { return false }
        scrollHintAvailable = false
        scrollHintPolicy.didScroll()
        mosaicScrollHint.isHidden = true
        let step = precise ? delta * 0.6 : (delta > 0 ? 4 : -4)
        mosaicDiameter = max(10, min(100, mosaicDiameter + step))
        updatePointer(at: windowPoint)
        return true
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
            context.setFillColor(KlikTheme.panelTint.withAlphaComponent(1).cgColor)
            context.fill(windowImage.frame)
            windowImage.draw(in: context)
        }
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
            if let selectedMark, marks.indices.contains(selectedMark) {
                let mark = marks[selectedMark]
                if case .arrow(let start, let end, _) = mark {
                    for point in [start, end] {
                        let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        context.setFillColor(KlikTheme.selection.cgColor)
                        context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                        context.setLineWidth(1.5)
                        context.fillEllipse(in: dot)
                        context.strokeEllipse(in: dot)
                    }
                } else if case .rectangle(let rect, _) = mark {
                    for handle in Selection.Handle.allCases {
                        let point = handle.center(in: rect)
                        let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        context.setFillColor(KlikTheme.selection.cgColor)
                        context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
                        context.setLineWidth(1.5)
                        context.fillEllipse(in: dot)
                        context.strokeEllipse(in: dot)
                    }
                } else if let rect = mark.movableBounds {
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
        guard recognitionView == nil else { return }
        let point = mousePoint(event)
        if pickingInkColor { applyInkColor(at: point); return }
        if pickingCoverColor { applyCoverColor(at: point); return }
        doubleClickStart = event.clickCount == 2 ? point : nil
        if event.clickCount == 1, windowCaptureTask == nil { lastWindowClick = nil }
        guard windowCaptureTask == nil else { return }
        showPalette = false
        showMosaicOptions = false
        commitText()
        window?.makeFirstResponder(self)
        errorLabel.isHidden = true
        if let selection, let handle = Selection.Handle.hit(at: point, in: selection,
                                                             retaining: pointer?.resizeHandle) {
            drag = .resize(handle, selection, point)
        } else if let selection, selection.contains(point) {
            if let index = selectedMark, marks.indices.contains(index),
               case .rectangle(let rect, _) = marks[index],
               let handle = Selection.Handle.hit(at: point, in: rect) {
                drag = .resizeMark(index, marks[index], handle, point, marks)
            } else if let index = selectedMark, marks.indices.contains(index),
                      case .rectangle(let rect, _) = marks[index], rect.contains(point) {
                drag = .moveMark(index, marks[index], point, marks)
            } else if let index = markIndex(at: point) {
                selectedMark = index
                let mark = marks[index]
                if case .arrow(let start, let end, _) = mark,
                   min(hypot(point.x - start.x, point.y - start.y),
                       hypot(point.x - end.x, point.y - end.y)) <= 10 {
                    let isStart = hypot(point.x - start.x, point.y - start.y) <= hypot(point.x - end.x, point.y - end.y)
                    drag = .resizeArrow(index, mark, isStart, point, marks)
                } else {
                    drag = .moveMark(index, mark, point, marks)
                }
            } else {
                selectedMark = nil
                switch tool {
            case .text:
                beginText(at: point, in: selection)
            case .some(let tool):
                drag = .mark(tool, point)
                if tool == .pen || tool == .mosaic {
                    strokePoints = [point]
                    if tool == .mosaic && mosaicStyle == .solid { strokeColor = .fallback }
                    preview = tool == .pen ? .pen(strokePoints, ink) : .mosaic(strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
            case .none:
                drag = .move(selection, point)
                }
            }
        } else {
            let target: ClickTarget = isWindowSnapHeld
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
        updateDrag(at: point, shift: event.modifierFlags.contains(.shift))
        updateMagnifier(at: point)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard recognitionView == nil else { return }
        magnifier.isHidden = true
        let point = mousePoint(event)
        if event.clickCount == 2, let start = doubleClickStart,
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
                undoMarks.append(before)
                redoMarks.removeAll()
            }
        default: break
        }
        if let preview {
            addMark(preview)
            if case .mosaic(_, _, .solid, _) = preview { pickingCoverColor = true; showMosaicOptions = false }
        }
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

    private func updateDrag(at point: CGPoint, shift: Bool = false) {
        switch drag {
        case .select(let start, let moved, let target):
            let draft = Selection.between(start, point)
            draftSelection = draft
            if !moved, max(draft.width, draft.height) > 3 {
                drag = .select(start, moved: true, target: target)
            }
        case .resize(let handle, let original, let start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selection = handle.resize(original, delta: delta, in: windowImage?.frame ?? bounds)
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
            guard marks.indices.contains(index), let selection,
                  case .rectangle(let rect, let ink) = original else { return }
            let delta = CGPoint(x: point.x - grabPoint.x, y: point.y - grabPoint.y)
            marks[index] = .rectangle(handle.resize(rect, delta: delta, in: selection), ink)
        case .resizeArrow(let index, let original, let isStart, let grabPoint, _):
            guard marks.indices.contains(index), let selection,
                  case .arrow(let start, let end, let ink) = original else { return }
            let endpoint = isStart ? start : end
            let moved = CGPoint(x: endpoint.x + point.x - grabPoint.x,
                                y: endpoint.y + point.y - grabPoint.y)
            let clamped = CGPoint(x: min(max(moved.x, selection.minX), selection.maxX),
                                  y: min(max(moved.y, selection.minY), selection.maxY))
            marks[index] = .arrow(isStart ? clamped : start, isStart ? end : clamped, ink)
        case .mark(let tool, let start):
            guard let selection else { return }
            let end = CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                              y: min(max(point.y, selection.minY), selection.maxY))
            switch tool {
            case .rectangle:
                let final = shift ? MarkConstraint.squareEnd(from: start, toward: end, in: selection) : end
                let rect = Selection.between(start, final)
                preview = rect.width >= 2 && rect.height >= 2 ? .rectangle(rect, ink) : nil
            case .arrow:
                let final = shift ? MarkConstraint.snappedEnd(from: start, toward: end, in: selection) : end
                preview = hypot(final.x - start.x, final.y - start.y) >= 2 ? .arrow(start, final, ink) : nil
            case .pen, .mosaic:
                if strokePoints.last != end { strokePoints.append(end) }
                if tool == .pen {
                    preview = .pen(shift ? [start, end] : strokePoints, ink)
                } else {
                    preview = .mosaic(shift ? [start, end] : strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
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
            let button = HoverButton()
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
        configure(redoButton, ("redo", .toolRedo), action: #selector(redo))
        toolbarButtons.append(redoButton)
        practiceSteps.append(.init(button: redoButton, detail: .practiceRedo))
        let recognizeButton = HoverButton()
        configure(recognizeButton, ("scan-text", .toolRecognizeText), action: #selector(startTextRecognition))
        toolbarButtons.append(recognizeButton)
        practiceSteps.append(.init(button: recognizeButton, detail: .practiceRecognizeText))
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
        for divider in toolbarDividers {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            toolbar.addSubview(divider)
        }
        configureSwatch(inkButton, action: #selector(togglePalette))
        inkButton.wantsLayer = true
        inkButton.layer?.cornerRadius = 6
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
        visible.insert(inkButton, at: Tool.allCases.count)
        let width = MarkupToolbarLayout.width(buttonCount: visible.count)
        toolbar.setFrameSize(CGSize(width: width, height: MarkupToolbarLayout.height))
        MarkupToolbarLayout.arrange(buttons: visible, dividers: toolbarDividers, width: width)
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
        let title = strings(.inkPicker, strings(ink.label))
        inkButton.toolTip = title
        inkButton.setAccessibilityLabel(title)
        inkButton.image = MarkupToolbarLayout.swatch(ink)
        for (color, button) in paletteButtons {
            button.image = MarkupToolbarLayout.swatch(color, selected: color == ink)
        }
    }

    @objc private func togglePalette() {
        showMosaicOptions = false
        showPalette.toggle()
        refresh()
    }

    @objc private func pickInk(_ sender: NSButton) {
        cancelInkColorPick()
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
        if let selection, drag == nil {
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
        undoButton.isEnabled = !undoMarks.isEmpty || isEditingText
        redoButton.isEnabled = !redoMarks.isEmpty && !isEditingText
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
    }

    private func updateModeHint() {
        let capturingWindow = windowCaptureTask != nil
        modeHint.isHidden = !pickingCoverColor && !pickingInkColor && !capturingWindow && (selection != nil || drag != nil || coach != nil || windowTargets.isEmpty)
        guard !modeHint.isHidden else { return }
        let message: UIKey = (pickingCoverColor || pickingInkColor) ? .mosaicPickPrompt : (capturingWindow ? .windowCapturePending
            : (isWindowSnapHeld ? .windowSnapActive : .windowSnapHint))
        modeHint.stringValue = strings(message)
        modeHint.sizeToFit()
        let width = min(bounds.width - 16, modeHint.frame.width + 26)
        modeHint.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - 46, width: width, height: 28)
    }

    @objc private func pickTool(_ sender: NSButton) {
        guard !pickingCoverColor else { updateModeHint(); return }
        pickingCoverColor = false
        commitText()
        showPalette = false
        let chosen = Tool.allCases[sender.tag]
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
            addMark(.text(value, textOrigin, ink))
        }
        textField = nil
        field.removeFromSuperview()
    }

    private func markIndex(at point: CGPoint) -> Int? {
        marks.indices.reversed().first { marks[$0].hitTest(point) }
    }

    func finishTextEditing() {
        commitText()
        refresh()
    }

    private func addMark(_ mark: Mark) {
        undoMarks.append(marks)
        marks.append(mark)
        redoMarks.removeAll()
        switch mark {
        case .arrow, .rectangle: selectedMark = marks.count - 1
        default: selectedMark = nil
        }
    }

    @objc func undo() {
        commitText()
        if let prior = undoMarks.popLast() {
            redoMarks.append(marks)
            marks = prior
            selectedMark = nil
            pickingCoverColor = hasPendingCover
        }
        refresh()
    }

    @objc func redo() {
        guard !isEditingText else { return }
        if let next = redoMarks.popLast() {
            undoMarks.append(marks)
            marks = next
            selectedMark = nil
            pickingCoverColor = hasPendingCover
        }
        refresh()
    }

    @objc func cancel() { finish(.cancelled) }
    @objc private func download() { export(.downloads) }
    @objc private func confirm() { export(.clipboard) }

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
        view.setMarkupHandlers(down: { [weak self] in self?.recognitionMarkupDown($0) },
                               drag: { [weak self] point, flags in self?.recognitionMarkupDrag(point, flags: flags) },
                               up: { [weak self] point, flags in self?.recognitionMarkupUp(point, flags: flags) },
                               text: { [weak self] value, point in
                                   guard let self else { return }
                                   self.addMark(.text(value, point, self.ink))
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
        view.onTool = { [weak self] chosen in
            guard let self, !self.pickingCoverColor else { return }
            self.choose(chosen == .mosaic ? .mosaic : (self.tool == chosen ? nil : chosen))
            self.syncRecognitionMarkup()
        }
        view.onInk = { [weak self] ink in
            guard let self else { return }
            self.cancelInkColorPick()
            self.ink = ink
            self.updateSwatches()
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
        clearPointer()
        addSubview(view, positioned: .above, relativeTo: nil)
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
        guard let view = recognitionView, let selection else { return }
        var displayedMarks = marks
        if let preview { displayedMarks.append(preview) }
        if let image = background.render(selection: selection, marks: displayedMarks) {
            var points: [CGPoint] = []
            if let index = selectedMark, marks.indices.contains(index) {
                switch marks[index] {
                case .rectangle(let rect, _): points = Selection.Handle.allCases.map { $0.center(in: rect) }
                case .arrow(let start, let end, _): points = [start, end]
                default: break
                }
            }
            view.setImage(image, selectedPoints: points)
        }
        view.setMarkupState(tool: tool, ink: ink, canUndo: !undoMarks.isEmpty, canRedo: !redoMarks.isEmpty)
        view.setCanPickCoverColor(canPickCoverColor)
    }

    private func recognitionMarkupDown(_ point: CGPoint) {
        guard let selection, selection.contains(point) else { return }
        if pickingInkColor { applyInkColor(at: point); return }
        if pickingCoverColor { applyCoverColor(at: point); return }
        recognitionView?.hideMosaicOptions()
        if let index = selectedMark, marks.indices.contains(index),
           case .rectangle(let rect, _) = marks[index], let handle = Selection.Handle.hit(at: point, in: rect) {
            drag = .resizeMark(index, marks[index], handle, point, marks)
        } else if let index = selectedMark, marks.indices.contains(index),
                  case .rectangle(let rect, _) = marks[index], rect.contains(point) {
            drag = .moveMark(index, marks[index], point, marks)
        } else if let index = markIndex(at: point) {
            selectedMark = index
            let mark = marks[index]
            if case .arrow(let start, let end, _) = mark,
               min(hypot(point.x - start.x, point.y - start.y), hypot(point.x - end.x, point.y - end.y)) <= 10 {
                let isStart = hypot(point.x - start.x, point.y - start.y) <= hypot(point.x - end.x, point.y - end.y)
                drag = .resizeArrow(index, mark, isStart, point, marks)
            } else {
                drag = .moveMark(index, mark, point, marks)
            }
        } else {
            selectedMark = nil
            switch tool {
            case .text:
                recognitionView?.beginMarkupText(at: point)
            case .some(let chosen):
                if chosen == .mosaic {
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
                    preview = chosen == .pen ? .pen(strokePoints, ink) : .mosaic(strokePoints, diameter: mosaicDiameter, style: mosaicStyle, color: strokeColor)
                }
            case .none:
                break
            }
        }
        syncRecognitionMarkup()
    }

    private func recognitionMarkupDrag(_ point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard drag != nil else { return }
        updateDrag(at: point, shift: flags.contains(.shift))
        syncRecognitionMarkup()
    }

    private func recognitionMarkupUp(_ point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let active = drag else { return }
        updateDrag(at: point, shift: flags.contains(.shift))
        var refreshOCR = false
        if case .mark(.mosaic, _) = active { refreshOCR = true }
        switch active {
        case .moveMark(let index, _, _, let before), .resizeArrow(let index, _, _, _, let before),
             .resizeMark(let index, _, _, _, let before):
            if before.indices.contains(index), marks.indices.contains(index), before[index] != marks[index] {
                undoMarks.append(before)
                redoMarks.removeAll()
            }
        default: break
        }
        if let preview {
            addMark(preview)
            if case .mosaic(_, _, .solid, _) = preview { pickingCoverColor = true }
        }
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
        ink = .custom(color)
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
        undoMarks.append(marks)
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
        recognitionView?.commitMarkupText()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionView?.removeFromSuperview()
        recognitionView = nil
        window?.makeFirstResponder(self)
        refresh()
        if let window { updatePointer(at: window.mouseLocationOutsideOfEventStream, force: true) }
    }

    func saveImageFromTextRecognition() {
        recognitionView?.commitMarkupText()
        export(.downloads)
    }

    func export(_ destination: Destination) {
        guard drag == nil, windowCaptureTask == nil, let selection else { return }
        guard !pickingCoverColor else { updateModeHint(); NSSound.beep(); return }
        commitText()
        refresh()
        guard let image = background.render(selection: selection, marks: marks),
              let png = CaptureImage.png(image) else {
            report(strings(.renderError))
            return
        }

        switch destination {
        case .clipboard:
            guard ClipboardImage.write(png: png, image: image, to: pasteboard) else {
                report(strings(.clipboardError))
                return
            }
        case .downloads:
            do {
                try saveDownload(png)
            } catch {
                if let recognitionView { recognitionView.showSaveConfirmation(success: false) }
                else { downloadButton?.showBriefConfirmation(symbol: "xmark", color: .systemRed) }
                report(strings(.downloadError))
                return
            }
        }
        recordCapture?(png)
        let confirmationFrame: CGRect?
        if destination == .downloads {
            if let recognitionView {
                confirmationFrame = recognitionView.saveButtonScreenFrame
            } else if let button = downloadButton, let window = button.window {
                confirmationFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            } else {
                confirmationFrame = nil
            }
        } else {
            confirmationFrame = nil
        }
        finish(.exported)
        if let confirmationFrame { SaveConfirmation.show(at: confirmationFrame) }
    }

    private func report(_ message: String) {
        if let recognitionView {
            recognitionView.showStatus(message)
            NSSound.beep()
            return
        }
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
