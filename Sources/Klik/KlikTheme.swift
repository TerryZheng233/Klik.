import AppKit

enum KlikTheme {
    static let accent = NSColor(srgbRed: 0.76, green: 0.95, blue: 0.39, alpha: 1)
    // Selection and its contrast halo stay legible over both bright and dark content.
    static let selection = NSColor(srgbRed: 0.46, green: 0.65, blue: 0.32, alpha: 1)
    static let selectionHalo = NSColor(srgbRed: 0.07, green: 0.10, blue: 0.07, alpha: 0.85)
    static let overlayInk = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.93, alpha: 1)
    static let panelTint = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.10, alpha: 0.88)
    static let buttonSelected = NSColor(srgbRed: 0.27, green: 0.35, blue: 0.20, alpha: 1)
    static let primary = NSColor(srgbRed: 0.23, green: 0.39, blue: 0.18, alpha: 1)

    static let window = adaptive(
        light: NSColor(srgbRed: 0.95, green: 0.96, blue: 0.93, alpha: 1),
        dark: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.11, alpha: 1)
    )
    static let card = adaptive(
        light: NSColor(srgbRed: 0.99, green: 0.995, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.15, green: 0.17, blue: 0.15, alpha: 1)
    )
    static let keycap = adaptive(
        light: NSColor(srgbRed: 0.88, green: 0.92, blue: 0.83, alpha: 1),
        dark: NSColor(srgbRed: 0.24, green: 0.30, blue: 0.19, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

// Shared sizing and grouping for capture and recognition toolbars.
enum MarkupToolbarLayout {
    static let height: CGFloat = 40
    static let buttonWidth: CGFloat = 33
    static let padding: CGFloat = 5
    static let separatorWidth: CGFloat = 8

    static func width(buttonCount: Int) -> CGFloat {
        2 * padding + CGFloat(buttonCount) * buttonWidth + 3 * separatorWidth
    }

    static func arrange(buttons: [NSButton], dividers: [NSView], width: CGFloat) {
        let positions = [Tool.allCases.count + 1, Tool.allCases.count + 3, buttons.count - 2]
        let itemWidth = max(1, min(buttonWidth, (width - 2 * padding - 3 * separatorWidth) / CGFloat(buttons.count)))
        var x = max(0, (width - CGFloat(buttons.count) * itemWidth - 3 * separatorWidth) / 2)
        for (index, button) in buttons.enumerated() {
            if let dividerIndex = positions.firstIndex(of: index) {
                dividers[dividerIndex].frame = CGRect(x: x + 3, y: 11, width: 1, height: 18)
                x += separatorWidth
            }
            button.frame = CGRect(x: x, y: 5, width: itemWidth, height: 30)
            x += itemWidth
        }
    }

    static func swatch(_ ink: Ink, selected: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: 23, height: 23), flipped: false) { _ in
            let disc = NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 15, height: 15))
            ink.color.setFill(); disc.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            disc.lineWidth = 1; disc.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 20, height: 20))
                NSColor.white.setStroke(); ring.lineWidth = 1.5; ring.stroke()
            }
            return true
        }
    }
}
