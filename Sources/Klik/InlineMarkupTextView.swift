import AppKit

// An unframed, multiline editor that uses the same typography as the saved mark.
final class InlineMarkupTextView: NSTextView {
    private let maximumWidth: CGFloat

    init(origin: CGPoint, maximumWidth: CGFloat, ink: Ink, size: CGFloat, text: String) {
        self.maximumWidth = max(1, maximumWidth)
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: 100_000, height: 100_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: CGRect(origin: origin, size: CGSize(width: max(1, maximumWidth), height: size * 1.5)), textContainer: container)
        identifier = NSUserInterfaceItemIdentifier("inlineMarkupText")
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = CGSize(width: 100_000, height: 100_000)
        let attributes = MarkupTextStyle.attributes(ink: ink, size: size)
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        typingAttributes = attributes
        insertionPointColor = ink.outline
        resizeForText()
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeText() {
        super.didChangeText()
        resizeForText()
    }

    private func resizeForText() {
        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 18)
        let lines = string.components(separatedBy: "\n")
        let lineWidth = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let lineHeight = ceil(layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.3)
        setFrameSize(CGSize(width: min(maximumWidth, max(24, ceil(lineWidth) + 12)),
                            height: max(lineHeight + 4, CGFloat(lines.count) * lineHeight + 4)))
    }
}
