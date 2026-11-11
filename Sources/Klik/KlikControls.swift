import AppKit

class ForestButton: HoverButton {
    var isPrimary = false { didSet { updateSurface(animated: true) } }
    var isDestructive = false { didSet { updateSurface(animated: true) } }
    private var focusBorder: NSColor { isPrimary && isEnabled ? KlikTheme.actionInk : KlikTheme.action }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width, 65), height: 26)
    }

    override func updateSurface(animated: Bool) {
        wantsLayer = true
        guard let layer else { return }
        KlikTheme.round(layer, radius: KlikTheme.controlRadius, clips: false)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let activeFill = isDestructive ? KlikTheme.dangerSurface : (isPrimary ? KlikTheme.action : KlikTheme.keycap)
            let base = isEnabled ? activeFill : KlikTheme.card
            let tone = isDestructive ? KlikTheme.danger : (isPrimary ? KlikTheme.actionInk : KlikTheme.action)
            let amount: CGFloat = isHighlighted ? 0.17 : hovered ? 0.08 : 0
            let fill = amount > 0 && isEnabled ? (base.blended(withFraction: amount, of: tone) ?? base) : base
            KlikTheme.setBackground(fill.cgColor, on: layer,
                                    animated: animated && window?.isVisible == true)
            layer.borderWidth = 1
            let border = isDestructive ? KlikTheme.danger : KlikTheme.outline
            layer.borderColor = (window?.firstResponder === self ? focusBorder : border).cgColor
        }
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = focusBorder.cgColor }
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.borderColor = (isDestructive ? KlikTheme.danger : KlikTheme.outline).cgColor
            }
        }
        return resigned
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let ink = isDestructive ? KlikTheme.danger : (isPrimary ? KlikTheme.actionInk : KlikTheme.ink)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isEnabled ? ink : KlikTheme.mutedInk,
            .paragraphStyle: paragraph
        ]
        let title = title as NSString
        let height = ceil(title.size(withAttributes: attributes).height)
        title.draw(in: CGRect(x: 7, y: (bounds.height - height) / 2, width: max(0, bounds.width - 14), height: height),
                   withAttributes: attributes)
    }
}

final class ForestSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = CGRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        KlikTheme.outline.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let progress = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        KlikTheme.action.setFill()
        let width = track.width * CGFloat(progress)
        if width > 0 {
            NSBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: width, height: track.height),
                         xRadius: 2, yRadius: 2).fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let side = min(knobRect.width, knobRect.height, 14)
        let disc = NSBezierPath(ovalIn: CGRect(x: knobRect.midX - side / 2, y: knobRect.midY - side / 2,
                                             width: side, height: side))
        KlikTheme.action.setFill()
        disc.fill()
        KlikTheme.card.setStroke()
        disc.lineWidth = 1
        disc.stroke()
    }
}
