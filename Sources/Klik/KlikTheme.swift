import AppKit

enum KlikTheme {
    static let primary = rgb(0x3E462B)
    static let accent = rgb(0xCED99D)
    private static let sand = rgb(0xE8E2CD)
    private static let cream = rgb(0xF8F5EA)
    private static let lightOutline = rgb(0xCFC5A1)

    // Selection and its contrast halo stay legible over both bright and dark content.
    static let selection = accent
    static let selectionHalo = rgb(0x191B11).withAlphaComponent(0.90)
    static let overlayInk = cream
    static let overlaySurface = rgb(0x2C3223)
    static let overlayCanvas = rgb(0x20251B)
    static let panelTint = overlaySurface.withAlphaComponent(0.94)
    static let buttonSelected = rgb(0x535E3E)

    static let window = adaptive(light: cream, dark: overlaySurface)
    static let card = adaptive(light: rgb(0xEFEBDE), dark: rgb(0x353D2C))
    static let keycap = adaptive(light: sand, dark: rgb(0x454E37))

    static let windowRadius: CGFloat = 18
    static let cornerRadius: CGFloat = 14
    static let controlRadius: CGFloat = 8
    static let controlHeight: CGFloat = 30
    static let badgeRadius: CGFloat = 9

    static let ink = adaptive(light: primary, dark: cream)
    static let mutedInk = adaptive(light: rgb(0x646145), dark: sand)
    static let historyTimestamp = adaptive(light: rgb(0x646657), dark: rgb(0xB1B5A2))
    static let outline = adaptive(light: lightOutline, dark: rgb(0x686B49))
    static let inset = adaptive(light: rgb(0xEFE9D2), dark: overlayCanvas)
    static let action = adaptive(light: primary, dark: accent)
    static let actionInk = adaptive(light: cream, dark: overlayCanvas)
    static let danger = adaptive(light: rgb(0xa92d37), dark: rgb(0xff746e))
    static let dangerSurface = adaptive(light: rgb(0xF7E3DC), dark: rgb(0x472D27))
    static let hover = adaptive(light: rgb(0xE4DECA), dark: rgb(0x424B36))
    static let overlayMuted = overlayInk.withAlphaComponent(0.82)
    static let overlayOutline = overlayInk.withAlphaComponent(0.15)
    static let panelShadowInset: CGFloat = 14

    @MainActor
    static var transitionDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
    }

    static func round(_ layer: CALayer?, radius: CGFloat, clips: Bool = true) {
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = clips
    }

    @MainActor
    static func setBackground(_ color: CGColor, on layer: CALayer, animated: Bool) {
        guard layer.backgroundColor != color else { return }
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        layer.removeAnimation(forKey: "klik.backgroundColor")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
        let duration = animated ? transitionDuration : 0
        guard duration > 0, let previous else { return }
        let change = CABasicAnimation(keyPath: "backgroundColor")
        change.fromValue = previous
        change.toValue = color
        change.duration = duration
        change.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(change, forKey: "klik.backgroundColor")
    }

    static func styleOverlay(_ view: NSView, radius: CGFloat = cornerRadius) {
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        round(view.layer, radius: radius)
        view.layer?.backgroundColor = overlaySurface.cgColor
    }

    @MainActor
    static func installPanelSurface(in panel: NSPanel, radius: CGFloat, identifier: String) -> NSView {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        // Draw the rounded surface and shadow entirely inside the clear window backing.
        let backing = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        backing.wantsLayer = true
        backing.layer?.isOpaque = false
        let surface = PanelSurface(frame: backing.bounds.insetBy(dx: panelShadowInset, dy: panelShadowInset))
        surface.identifier = NSUserInterfaceItemIdentifier(identifier)
        surface.wantsLayer = true
        round(surface.layer, radius: radius)
        backing.addSubview(surface)
        backing.layer?.shadowColor = NSColor.black.cgColor
        backing.layer?.shadowOpacity = 0.22
        backing.layer?.shadowRadius = 8
        backing.layer?.shadowOffset = CGSize(width: 0, height: -3)
        backing.layer?.shadowPath = CGPath(roundedRect: surface.frame, cornerWidth: radius,
                                           cornerHeight: radius, transform: nil)
        panel.contentView = backing
        surface.updateColors()
        return surface
    }

    static func styleCaptureImage(_ view: NSView, radius: CGFloat = badgeRadius) {
        view.wantsLayer = true
        round(view.layer, radius: radius)
        view.layer?.backgroundColor = overlayCanvas.cgColor
    }

    static func styleMarkupField(_ field: NSTextField) {
        field.appearance = NSAppearance(named: .darkAqua)
        field.textColor = overlayInk
        field.backgroundColor = overlayCanvas
        field.drawsBackground = true
        field.focusRingType = .none
        field.wantsLayer = true
        round(field.layer, radius: controlRadius)
        field.layer?.borderWidth = 1
        field.layer?.borderColor = selection.cgColor
    }

    @MainActor
    static func styleAlert(_ alert: NSAlert, in parent: NSWindow? = nil) {
        alert.icon = NSApp.applicationIconImage
        alert.layout()
        let dialog = alert.window
        let appearance = parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        dialog.appearance = appearance
        dialog.backgroundColor = window
        appearance.performAsCurrentDrawingAppearance {
            // Fill the content so desktop colours do not tint the alert material.
            if let content = dialog.contentView {
                content.wantsLayer = true
                round(content.layer, radius: windowRadius)
                content.layer?.backgroundColor = window.cgColor
            }
            for button in alert.buttons {
                button.bezelColor = button.keyEquivalent == "\r" ? action : keycap
            }
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

private final class PanelSurface: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = KlikTheme.window.cgColor
        }
    }
}

// Shared sizing and grouping for capture and recognition toolbars.
enum MarkupToolbarLayout {
    static let height: CGFloat = 40
    static let buttonWidth: CGFloat = 33
    static let padding: CGFloat = 5
    static let groupGap: CGFloat = 8

    static func styleTray(_ tray: NSVisualEffectView, blending: NSVisualEffectView.BlendingMode = .withinWindow,
                          radius: CGFloat = KlikTheme.cornerRadius) {
        tray.material = .hudWindow
        tray.blendingMode = blending
        tray.state = .active
        KlikTheme.styleOverlay(tray, radius: radius)
    }

    static func configureButton(_ button: HoverButton, symbol: String, fallback: String? = nil,
                                label: String, target: AnyObject, action: Selector) {
        let image = Bundle.main.url(forResource: symbol, withExtension: "svg", subdirectory: "Lucide")
            .flatMap(NSImage.init(contentsOf:))
            ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: label) }
        image?.size = CGSize(width: 18, height: 18)
        image?.isTemplate = true
        button.image = image
        if image == nil { button.title = label }
        button.imagePosition = image == nil ? .noImage : .imageOnly
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.isBordered = false
        button.target = target
        button.action = action
        button.refusesFirstResponder = true
        button.wantsLayer = true
        KlikTheme.round(button.layer, radius: KlikTheme.controlRadius, clips: false)
        switch symbol {
        case "x": button.contentTintColor = KlikTheme.danger
        case "check": button.contentTintColor = KlikTheme.accent
        default: button.contentTintColor = KlikTheme.overlayInk
        }
    }

    static func width(buttonCount: Int) -> CGFloat {
        2 * padding + CGFloat(buttonCount) * buttonWidth + 3 * groupGap
    }

    static func arrange(buttons: [NSButton], width: CGFloat) {
        let positions = [Tool.allCases.count + 1, Tool.allCases.count + 3, buttons.count - 2]
        let itemWidth = max(1, min(buttonWidth, (width - 2 * padding - 3 * groupGap) / CGFloat(buttons.count)))
        var x = max(0, (width - CGFloat(buttons.count) * itemWidth - 3 * groupGap) / 2)
        for (index, button) in buttons.enumerated() {
            if positions.contains(index) { x += groupGap }
            button.frame = CGRect(x: x, y: (height - KlikTheme.controlHeight) / 2,
                                  width: itemWidth, height: KlikTheme.controlHeight)
            x += itemWidth
        }
    }

    static func swatch(_ ink: Ink, selected: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: 23, height: 23), flipped: false) { _ in
            let disc = NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 15, height: 15))
            ink.color.setFill(); disc.fill()
            KlikTheme.overlayInk.withAlphaComponent(0.35).setStroke()
            disc.lineWidth = 1; disc.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 20, height: 20))
                KlikTheme.overlayInk.setStroke(); ring.lineWidth = 1.5; ring.stroke()
            }
            return true
        }
    }
}
