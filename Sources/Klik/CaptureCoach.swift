import AppKit

final class CaptureCoach: NSView {
    struct Step {
        let button: HoverButton
        let detail: UIKey
    }

    var onChange: (() -> Void)?
    var isDismissed = false

    private let strings: AppStrings
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let back = HoverButton()
    private let next = HoverButton()
    private var stepIndex = 0
    private var stepCount = 0
    private weak var highlightedButton: HoverButton?

    init(strings: AppStrings) {
        self.strings = strings
        super.init(frame: .zero)
        KlikTheme.styleOverlay(self)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = KlikTheme.overlayInk
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = KlikTheme.overlayMuted
        detail.maximumNumberOfLines = 2
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        count.textColor = KlikTheme.accent
        count.alignment = .right
        MarkupToolbarLayout.configureButton(back, symbol: "chevron-left", fallback: "chevron.left",
            label: strings(.back), target: self, action: #selector(previousStep))
        configureNext(isLast: false)
        for child in [title, detail, count, back, next] as [NSView] { addSubview(child) }
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let target = super.hitTest(point)
        return target === back || target === next ? target : nil
    }

    func showSelectionPrompt(in screen: CGRect) {
        hide()
        guard !isDismissed else { return }
        let width = min(320, screen.width - 20)
        frame = CGRect(x: screen.midX - width / 2, y: screen.minY + 26, width: width, height: 69)
        setCopy(strings(.practiceSelectTitle), strings(.practiceSelectDetail), countText: nil)
        isHidden = false
    }

    func showToolbar(_ steps: [Step], toolbar: CGRect, palette: CGRect?, selection: CGRect, in screen: CGRect) {
        hide()
        guard !isDismissed,
              let position = Self.placement(toolbar: toolbar, palette: palette, selection: selection, in: screen)
        else { return }

        stepCount = steps.count
        let step = steps[stepIndex]
        frame = position
        setCopy(step.button.accessibilityLabel() ?? "", strings(step.detail),
                countText: strings(.practiceStep, stepIndex + 1, stepCount))
        back.isEnabled = stepIndex > 0
        configureNext(isLast: stepIndex == stepCount - 1)
        let buttonWidth = MarkupToolbarLayout.buttonWidth
        next.frame = CGRect(x: bounds.width - buttonWidth - 12, y: 74, width: buttonWidth, height: KlikTheme.controlHeight)
        back.frame = CGRect(x: next.frame.minX - buttonWidth - 5, y: 74, width: buttonWidth, height: KlikTheme.controlHeight)
        highlightedButton = step.button
        step.button.coachHighlighted = true
        isHidden = false
    }

    func hide() {
        highlightedButton?.coachHighlighted = false
        highlightedButton = nil
        isHidden = true
    }

    static func placement(toolbar: CGRect, palette: CGRect?, selection: CGRect, in screen: CGRect) -> CGRect? {
        let visible = screen.insetBy(dx: 6, dy: 6)
        let controls = palette.map(toolbar.union) ?? toolbar
        let size = CGSize(width: min(320, visible.width), height: 116)
        let x = max(visible.minX, min(toolbar.maxX - size.width, visible.maxX - size.width))
        let above = CGRect(x: x, y: controls.minY - size.height - 8, width: size.width, height: size.height)
        let below = CGRect(x: x, y: controls.maxY + 8, width: size.width, height: size.height)
        let candidates = toolbar.midY < selection.midY ? [above, below] : [below, above]
        return candidates.first { visible.contains($0) }
    }

    private func setCopy(_ heading: String, _ body: String, countText: String?) {
        title.stringValue = heading
        detail.stringValue = body
        let navigating = countText != nil
        count.stringValue = countText ?? ""
        count.isHidden = !navigating
        back.isHidden = !navigating
        next.isHidden = !navigating
        title.frame = CGRect(x: 13, y: 11, width: bounds.width - (navigating ? 85 : 26), height: 20)
        count.frame = CGRect(x: bounds.width - 66, y: 13, width: 53, height: 17)
        detail.frame = CGRect(x: 13, y: 34, width: bounds.width - 26, height: 35)
    }

    private func configureNext(isLast: Bool) {
        let label = strings(isLast ? .practiceHideTips : .next)
        guard next.toolTip != label else { return }
        MarkupToolbarLayout.configureButton(next, symbol: isLast ? "x" : "chevron-right",
            fallback: isLast ? "xmark" : "chevron.right", label: label,
            target: self, action: #selector(nextStep))
        next.contentTintColor = KlikTheme.overlayInk
    }

    @objc private func previousStep() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        onChange?()
    }

    @objc private func nextStep() {
        if stepIndex + 1 < stepCount { stepIndex += 1 } else { isDismissed = true }
        onChange?()
    }
}
