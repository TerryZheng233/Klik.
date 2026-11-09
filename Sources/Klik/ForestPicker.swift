import AppKit

/// Keeps the familiar pop-up control and accessibility while drawing its choices
/// with Klik.'s colours instead of the system-wide menu highlight colour.
final class ForestPicker: NSPopUpButton, NSPopoverDelegate {
    private let choicePopover = NSPopover()
    private var keyMonitor: Any?
    private var highlightedIndex = 0
    private var rows: [ForestPickerRow] = []

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        choicePopover.behavior = .transient
        choicePopover.delegate = self
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        KlikTheme.keycap.setFill()
        shape.fill()
        (window?.firstResponder === self ? KlikTheme.selection : NSColor.separatorColor).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let title = (selectedItem?.title ?? "") as NSString
        let font = NSFont.systemFont(ofSize: 13)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let textHeight = title.size(withAttributes: [.font: font]).height
        title.draw(in: CGRect(x: 9, y: (bounds.height - textHeight) / 2,
                              width: max(0, bounds.width - 30), height: textHeight + 2),
                   withAttributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        let x = bounds.maxX - 12
        let y = bounds.midY
        let chevrons = NSBezierPath()
        chevrons.lineWidth = 1.2
        chevrons.lineCapStyle = .round
        chevrons.lineJoinStyle = .round
        chevrons.move(to: NSPoint(x: x - 3, y: y - 1.5))
        chevrons.line(to: NSPoint(x: x, y: y - 4.5))
        chevrons.line(to: NSPoint(x: x + 3, y: y - 1.5))
        chevrons.move(to: NSPoint(x: x - 3, y: y + 1.5))
        chevrons.line(to: NSPoint(x: x, y: y + 4.5))
        chevrons.line(to: NSPoint(x: x + 3, y: y + 1.5))
        NSColor.labelColor.setStroke()
        chevrons.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if choicePopover.isShown { choicePopover.performClose(nil) } else { showChoices() }
    }

    override func performClick(_ sender: Any?) { showChoices() }

    override func accessibilityPerformPress() -> Bool {
        showChoices()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if [" ", "\r", "\n"].contains(event.charactersIgnoringModifiers ?? "") || event.keyCode == 125 {
            showChoices()
        } else {
            super.keyDown(with: event)
        }
    }

    private func showChoices() {
        guard !choicePopover.isShown, numberOfItems > 0 else { return }
        highlightedIndex = max(0, indexOfSelectedItem)
        let width = max(bounds.width, 146)
        let height = CGFloat(numberOfItems) * 29 + 8
        let content = FlippedPickerView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        rows = itemArray.enumerated().map { index, item in
            let row = ForestPickerRow(frame: NSRect(x: 4, y: 4 + CGFloat(index) * 29, width: width - 8, height: 27))
            row.title = item.title
            row.tag = index
            row.target = self
            row.action = #selector(selectChoice(_:))
            row.isChosen = index == indexOfSelectedItem
            row.isKeyboardHighlighted = index == highlightedIndex
            row.onHover = { [weak self] in
                guard let self else { return }
                self.highlightedIndex = index
                for (rowIndex, option) in self.rows.enumerated() {
                    option.isKeyboardHighlighted = rowIndex == index
                }
            }
            content.addSubview(row)
            return row
        }
        let controller = NSViewController()
        controller.view = content
        choicePopover.contentViewController = controller
        choicePopover.contentSize = content.frame.size
        choicePopover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        guard choicePopover.isShown else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.choicePopover.isShown else { return event }
            switch event.keyCode {
            case 53: self.choicePopover.performClose(nil); return nil // Escape
            case 125: self.highlightedIndex = min(self.highlightedIndex + 1, self.rows.count - 1)
            case 126: self.highlightedIndex = max(self.highlightedIndex - 1, 0)
            case 36, 76, 49:
                self.choose(self.highlightedIndex)
                return nil
            default: return event
            }
            for (index, row) in self.rows.enumerated() { row.isKeyboardHighlighted = index == self.highlightedIndex }
            return nil
        }
    }

    @objc private func selectChoice(_ sender: NSButton) { choose(sender.tag) }

    private func choose(_ index: Int) {
        guard index >= 0, index < numberOfItems else { return }
        selectItem(at: index)
        needsDisplay = true
        choicePopover.performClose(nil)
        if let action { NSApp.sendAction(action, to: target, from: self) }
    }

    func popoverDidClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        rows.removeAll()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

private final class FlippedPickerView: NSView {
    override var isFlipped: Bool { true }
}

private final class ForestPickerRow: NSButton {
    var isChosen = false { didSet { needsDisplay = true } }
    var isKeyboardHighlighted = false { didSet { needsDisplay = true } }
    var onHover: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; onHover?() }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted || isKeyboardHighlighted {
            KlikTheme.keycap.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let text = (isChosen ? "✓  " : "    ") + title
        (text as NSString).draw(in: bounds.insetBy(dx: 8, dy: 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ])
    }
}
