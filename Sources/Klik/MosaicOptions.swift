import AppKit

enum MosaicStyle: Int, CaseIterable {
    case pixel, brush, solid, manual

    var label: UIKey {
        switch self {
        case .pixel: return .mosaicPixel
        case .brush: return .mosaicBrush
        case .solid, .manual: return .mosaicSolid
        }
    }
    var icon: NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            switch self {
            case .pixel:
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 18, height: 18), xRadius: 2, yRadius: 2).addClip()
                for row in 0..<3 {
                    for column in 0..<3 {
                        NSColor.white.withAlphaComponent((row + column).isMultiple(of: 2) ? 1 : 0.35).setFill()
                        NSBezierPath(rect: CGRect(x: 1 + column * 6, y: 1 + row * 6, width: 6, height: 6)).fill()
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            case .brush:
                let outline = NSBezierPath(roundedRect: CGRect(x: 1.5, y: 1.5, width: 17, height: 17), xRadius: 2, yRadius: 2)
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                let strokes = NSBezierPath()
                strokes.lineWidth = 1.8
                strokes.lineCapStyle = .round
                for row in 0..<4 {
                    for segment in 0..<3 {
                        let x = CGFloat(segment * 7 - (row % 2) * 3)
                        let y = CGFloat(row * 5 + 2) + x * 0.35
                        strokes.move(to: CGPoint(x: x, y: y))
                        strokes.line(to: CGPoint(x: x + 4, y: y + 1.4))
                    }
                }
                NSColor.white.withAlphaComponent(0.8).setStroke()
                strokes.stroke()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.white.setStroke()
                outline.lineWidth = 1.4
                outline.stroke()
            case .solid, .manual:
                NSColor.white.setFill()
                NSBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 16, height: 16), xRadius: 2, yRadius: 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class MosaicOptions: NSVisualEffectView {
    private var buttons: [HoverButton] = []
    var onSelect: ((MosaicStyle) -> Void)?
    var onPickColor: (() -> Void)?
    private let eyedropper = HoverButton(frame: CGRect(x: 104, y: 3, width: 33, height: 30))
    init(strings: AppStrings) {
        super.init(frame: CGRect(x: 0, y: 0, width: 110, height: 36))
        identifier = NSUserInterfaceItemIdentifier("mosaicOptions")
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = KlikTheme.panelTint.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        for style in [MosaicStyle.pixel, .brush, .solid] {
            let button = HoverButton(frame: CGRect(x: 5 + style.rawValue * 33, y: 3, width: 33, height: 30))
            button.image = style.icon
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = KlikTheme.overlayInk
            button.refusesFirstResponder = true
            button.setAccessibilityLabel(strings(style.label))
            button.toolTip = strings(style.label)
            button.tag = style.rawValue
            button.target = self; button.action = #selector(choose(_:))
            addSubview(button)
            buttons.append(button)
        }
        eyedropper.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: strings(.mosaicPickColor))
        eyedropper.imagePosition = .imageOnly
        eyedropper.isBordered = false
        eyedropper.contentTintColor = KlikTheme.overlayInk
        eyedropper.refusesFirstResponder = true
        eyedropper.toolTip = strings(.mosaicPickColor)
        eyedropper.setAccessibilityLabel(strings(.mosaicPickColor))
        eyedropper.target = self; eyedropper.action = #selector(pickColor)
        addSubview(eyedropper)
        setCanPickColor(false)
        isHidden = true
        select(.pixel)
    }
    required init?(coder: NSCoder) { nil }
    func select(_ style: MosaicStyle) {
        for (index, button) in buttons.enumerated() { button.toolSelected = index == (style == .manual ? MosaicStyle.solid.rawValue : style.rawValue) }
    }
    func setCanPickColor(_ available: Bool) {
        eyedropper.isHidden = !available
        setFrameSize(CGSize(width: available ? 143 : 110, height: 36))
    }
    @objc private func pickColor() { onPickColor?() }
    @objc private func choose(_ sender: NSButton) {
        guard let style = MosaicStyle(rawValue: sender.tag) else { return }
        select(style)
        onSelect?(style)
    }
}
