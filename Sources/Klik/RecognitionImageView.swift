import AppKit

// Draws the captured image at its original logical size or smaller and maps
// pointer events back to the capture's coordinates, even with letterboxing.
final class RecognitionImageView: NSView {
    private let selection: CGRect
    private let imageSize: CGSize
    private var image: NSImage
    private var selectedPoints: [CGPoint] = []
    private var input: NSTextField?
    private var inputOrigin = CGPoint.zero
    var onDown: ((CGPoint, Int) -> Void)?
    var onDrag: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onUp: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onTextCommit: ((String, CGPoint) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var imageScale: CGFloat { imageRect.width / max(1, selection.width) }
    var isEditingMarkupText: Bool { input != nil }
    func inputContains(_ point: CGPoint) -> Bool { input?.frame.contains(point) ?? false }

    init(image: CGImage, selection: CGRect) {
        self.selection = selection
        self.imageSize = selection.size
        self.image = NSImage(cgImage: image, size: selection.size)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("ocrImageCard")
        KlikTheme.styleCaptureImage(self, radius: KlikTheme.cornerRadius)
    }
    required init?(coder: NSCoder) { nil }

    var imageRect: CGRect {
        let scale = min(1, bounds.width / max(1, imageSize.width), bounds.height / max(1, imageSize.height))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    func capturePoint(for point: CGPoint, clamp: Bool = false) -> CGPoint? {
        let rect = imageRect
        guard !rect.isEmpty, clamp || rect.contains(point) else { return nil }
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return CGPoint(x: selection.minX + (x - rect.minX) * selection.width / rect.width,
                       y: selection.minY + (y - rect.minY) * selection.height / rect.height)
    }

    func displayPoint(for point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: rect.minX + (point.x - selection.minX) * rect.width / selection.width,
                       y: rect.minY + (point.y - selection.minY) * rect.height / selection.height)
    }

    func update(image: CGImage, selectedPoints: [CGPoint]) {
        self.image = NSImage(cgImage: image, size: imageSize)
        self.selectedPoints = selectedPoints
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for position in selectedPoints {
            let p = displayPoint(for: position)
            let dot = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            context.setFillColor(KlikTheme.selection.cgColor)
            context.setStrokeColor(KlikTheme.selectionHalo.cgColor)
            context.setLineWidth(1.5)
            context.fillEllipse(in: dot)
            context.strokeEllipse(in: dot)
        }
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        let point = convert(event.locationInWindow, from: nil)
        guard let point = capturePoint(for: point) else { return }
        window?.makeFirstResponder(self)
        onDown?(point, event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) {
        if let point = capturePoint(for: convert(event.locationInWindow, from: nil), clamp: true) { onDrag?(point, event.modifierFlags) }
    }
    override func mouseUp(with event: NSEvent) {
        if let point = capturePoint(for: convert(event.locationInWindow, from: nil), clamp: true) { onUp?(point, event.modifierFlags) }
    }

    func beginText(at point: CGPoint, placeholder: String, size: CGFloat, existing: String? = nil) {
        commitText()
        let position = displayPoint(for: point)
        let offset: CGFloat = existing == nil ? 0 : 3
        let x = min(max(imageRect.minX, position.x - offset), max(imageRect.minX, imageRect.maxX - 52))
        let y = min(max(imageRect.minY, position.y - (existing == nil ? 0 : 2)), max(imageRect.minY, imageRect.maxY - 24))
        inputOrigin = capturePoint(for: CGPoint(x: x + 3, y: y + 2), clamp: true) ?? point
        let displaySize = size * imageScale
        let field = NSTextField(frame: CGRect(x: x, y: y, width: min(280, max(52, imageRect.maxX - x)), height: max(26, displaySize * 1.4)))
        field.font = MarkupTextStyle.font(size: displaySize)
        field.placeholderString = placeholder
        field.stringValue = existing ?? ""
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        KlikTheme.styleMarkupField(field)
        field.usesSingleLineMode = true
        addSubview(field)
        input = field
        window?.makeFirstResponder(field)
    }

    func updateTextSize(_ size: CGFloat) {
        guard let input else { return }
        let displaySize = size * imageScale
        input.font = MarkupTextStyle.font(size: displaySize)
        input.frame.size.height = max(26, displaySize * 1.4)
    }

    func commitText() {
        guard let field = input else { return }
        let text = field.stringValue
        input = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        onTextCommit?(text, inputOrigin)
    }
}
