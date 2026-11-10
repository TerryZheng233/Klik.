import AppKit

/// A click-through confirmation that never takes focus or delays the capture ending.
@MainActor
enum SaveConfirmation {
    private static var visible: [UUID: NSPanel] = [:]

    static func show(at frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        let icon = NSImageView(frame: background.bounds.insetBy(dx: (frame.width - 18) / 2,
                                                                 dy: (frame.height - 18) / 2))
        icon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        icon.contentTintColor = KlikTheme.accent
        icon.imageScaling = .scaleProportionallyUpOrDown
        background.addSubview(icon)
        panel.contentView = background
        let id = UUID()
        visible[id] = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    visible.removeValue(forKey: id)
                }
            })
        }
    }
}
