import AppKit

/// A restrained hover surface for the capture controls, preserving selected tool state.
final class HoverButton: NSButton {
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    var toolSelected = false { didSet { updateSurface() } }

    override var isEnabled: Bool { didSet { updateSurface() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; updateSurface() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateSurface() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }

    private func updateSurface() {
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = 6
        let showHover = hovered && isEnabled
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor = toolSelected ? KlikTheme.buttonSelected : NSColor.labelColor.withAlphaComponent(0.13)
            layer.backgroundColor = (toolSelected || showHover) ? color.cgColor : NSColor.clear.cgColor
        }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = showHover ? 0.28 : 0
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }
}

extension NSButton {
    func showBriefConfirmation(symbol: String, color: NSColor, duration: TimeInterval = 0.7) {
        let previousImage = image
        let previousTint = contentTintColor
        guard let confirmation = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return }
        confirmation.size = NSSize(width: 18, height: 18)
        wantsLayer = true
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.16
        layer?.add(transition, forKey: "confirmationTransition")
        image = confirmation
        contentTintColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.image === confirmation else { return }
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.16
            self.layer?.add(transition, forKey: "confirmationTransition")
            self.image = previousImage
            self.contentTintColor = previousTint
        }
    }
}
