import AppKit

/// A restrained hover surface for the capture controls, preserving selected tool state.
class HoverButton: NSButton {
    private var hoverTracking: NSTrackingArea?
    private(set) var hovered = false
    var tracksHover: Bool { true }
    var coachHighlighted = false { didSet { updateSurface(animated: true) } }
    var toolSelected = false {
        didSet {
            contentTintColor = toolSelected ? KlikTheme.accent : KlikTheme.overlayInk
            updateSurface(animated: true)
        }
    }

    override var isEnabled: Bool { didSet { updateSurface(animated: true) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard tracksHover else { return }
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    func setHovered(_ hovered: Bool) {
        guard self.hovered != hovered else { return }
        self.hovered = hovered
        updateSurface(animated: true)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateSurface(animated: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovered = false
        updateSurface(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface(animated: false)
    }

    func updateSurface(animated: Bool) {
        wantsLayer = true
        guard let layer else { return }
        KlikTheme.round(layer, radius: KlikTheme.controlRadius, clips: false)
        let showHover = hovered && isEnabled
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = toolSelected || coachHighlighted ? KlikTheme.buttonSelected : KlikTheme.hover
            let pressed = isHighlighted && isEnabled
            let color = pressed ? (base.blended(withFraction: 0.18, of: KlikTheme.action) ?? base) : base
            let fill = (toolSelected || coachHighlighted || showHover || pressed) ? color : NSColor.clear
            KlikTheme.setBackground(fill.cgColor, on: layer, animated: animated && window?.isVisible == true)
        }
    }
}

extension NSButton {
    func showBriefConfirmation(symbol: String, color: NSColor, duration: TimeInterval = 0.7) {
        let previousImage = image
        let previousTint = contentTintColor
        guard let confirmation = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return }
        confirmation.size = NSSize(width: 18, height: 18)
        wantsLayer = true
        fadeConfirmation()
        image = confirmation
        contentTintColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.image === confirmation else { return }
            self.fadeConfirmation()
            self.image = previousImage
            self.contentTintColor = previousTint
        }
    }

    private func fadeConfirmation() {
        let duration = KlikTheme.transitionDuration
        guard duration > 0 else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        layer?.add(transition, forKey: "confirmationTransition")
    }
}
