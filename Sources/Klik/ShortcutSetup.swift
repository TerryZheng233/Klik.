import AppKit

@MainActor
final class ShortcutSetup: NSWindowController, NSWindowDelegate {
    private enum Step { case guide, shortcut }

    private let firstRun: Bool
    private let save: (CaptureShortcut) throws -> Void
    private let changeLanguage: (LanguagePreference) -> Void
    private let didClose: () -> Void
    private var step: Step
    private var selected: CaptureShortcut
    private var issue: Error?
    private var recordingMonitor: Any?
    private var language: LanguagePreference
    private var strings: AppStrings

    init(shortcut: CaptureShortcut, firstRun: Bool, issue: Error?,
         language: LanguagePreference, changeLanguage: @escaping (LanguagePreference) -> Void,
         save: @escaping (CaptureShortcut) throws -> Void, didClose: @escaping () -> Void) {
        self.firstRun = firstRun
        self.save = save
        self.changeLanguage = changeLanguage
        self.didClose = didClose
        self.step = firstRun ? .guide : .shortcut
        self.selected = shortcut
        self.issue = issue
        self.language = language
        self.strings = AppStrings(language: language.resolve())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 544, height: 474),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        window.delegate = self
        render()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        if strings.language != language.resolve() {
            strings = AppStrings(language: language.resolve())
            render()
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // An already registered shortcut arrives through Carbon.
    func handleRegisteredShortcut(_ shortcut: CaptureShortcut) -> Bool {
        guard window?.isKeyWindow == true else { return false }
        if recordingMonitor != nil { accept(shortcut) }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        didClose()
    }

    @objc private func goToShortcut() {
        step = .shortcut
        render()
    }

    @objc private func goBack() {
        stopRecording()
        step = .guide
        render()
    }

    @objc private func chooseLanguage(_ sender: NSPopUpButton) {
        let choices = LanguagePreference.allCases
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        let selected = choices[sender.indexOfSelectedItem]
        guard selected != language else { return }
        stopRecording()
        language = selected
        changeLanguage(selected)
        strings = AppStrings(language: selected.resolve())
        render()
    }

    @objc private func restoreDefault() { accept(.defaultShortcut) }

    @objc private func beginRecording() {
        guard recordingMonitor == nil else { return }
        issue = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if !event.isARepeat {
                if CaptureShortcut.isCancelKey(event) {
                    self.cancelRecording()
                } else {
                    do {
                        self.accept(try CaptureShortcut(recording: event))
                    } catch {
                        self.issue = error
                        self.render()
                    }
                }
            }
            return nil
        }
        render()
    }

    @objc private func cancelRecording() {
        stopRecording()
        issue = nil
        render()
    }

    private func stopRecording() {
        guard let recordingMonitor else { return }
        NSEvent.removeMonitor(recordingMonitor)
        self.recordingMonitor = nil
    }

    private func accept(_ shortcut: CaptureShortcut) {
        stopRecording()
        issue = nil
        selected = shortcut
        render()
    }

    @objc private func finish() {
        do {
            try save(selected)
            close()
        } catch {
            issue = error
            render()
        }
    }

    private func render() {
        window?.title = "Klik. · " + strings(firstRun ? .setupTitle : .settingsTitle)
        let root = SetupSurface(color: KlikTheme.window, cornerRadius: 0)
        let content = stack(.vertical, spacing: 12)
        let footer = stack(.horizontal, spacing: 8)
        root.addSubview(content)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 39),
            content.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -10),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -23)
        ])

        let header = header()
        content.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(22, after: header)

        if step == .guide {
            addGuide(to: content, footer: footer)
        } else {
            addShortcut(to: content, footer: footer)
        }
        window?.contentView = root
    }

    private func header() -> NSStackView {
        let row = stack(.horizontal, spacing: 10)
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 45).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 45).isActive = true
        row.addArrangedSubview(icon)

        let words = stack(.vertical, spacing: 3)
        words.addArrangedSubview(label("Klik.", size: 17, weight: .bold))
        let stepLabel = firstRun ? (step == .guide ? "01 / 02" : "02 / 02") : nil
        let subtitle = strings(firstRun ? .setupTitle : .settingsTitle)
        words.addArrangedSubview(label([subtitle, stepLabel].compactMap { $0 }.joined(separator: "  ·  "),
                                       size: 11, weight: .medium, color: .secondaryLabelColor))
        row.addArrangedSubview(words)
        if firstRun {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(languagePicker())
        }
        return row
    }

    private func addGuide(to content: NSStackView, footer: NSStackView) {
        content.addArrangedSubview(label(strings(.guideTitle), size: 30, weight: .bold))
        content.addArrangedSubview(label(strings(.guideIntro), color: .secondaryLabelColor))
        let operations = stack(.vertical, spacing: 10)
        operations.addArrangedSubview(operation(selected.title(using: strings), strings(.guideCapture)))
        operations.addArrangedSubview(operation(strings(.guideToolbar), strings(.guideMarkup)))
        operations.addArrangedSubview(operation("Enter", strings(.guideCopy)))
        operations.addArrangedSubview(operation("Esc", strings(.guideCancel)))
        let card = SetupSurface(color: KlikTheme.card, cornerRadius: 15, outlined: true, content: operations)
        content.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.addArrangedSubview(label(strings(.guidePermission), size: 11, color: .secondaryLabelColor))
        footer.addArrangedSubview(button(strings(.next), #selector(goToShortcut), primary: true))
    }

    private func addShortcut(to content: NSStackView, footer: NSStackView) {
        let recording = recordingMonitor != nil
        let title = firstRun ? strings(.shortcutPrompt) : strings(.settingsTitle)
        content.addArrangedSubview(label(title, size: 30, weight: .bold))
        content.addArrangedSubview(label(strings(firstRun ? .shortcutIntro : .settingsIntro), color: .secondaryLabelColor))

        if !firstRun {
            let row = stack(.horizontal, spacing: 10)
            let words = stack(.vertical, spacing: 4)
            words.addArrangedSubview(label(strings(.language), weight: .semibold))
            words.addArrangedSubview(label(strings(.interfaceLanguage), size: 12, color: .secondaryLabelColor))
            row.addArrangedSubview(words)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(languagePicker())
            let card = SetupSurface(color: KlikTheme.card, cornerRadius: 14, outlined: true, content: row)
            content.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        let keys = stack(.vertical, spacing: 6)
        keys.addArrangedSubview(label(strings(.shortcut), size: 11, weight: .semibold, color: .secondaryLabelColor))
        let value = recording ? strings(.recording) : selected.title(using: strings)
        keys.addArrangedSubview(label(value, size: recording ? 23 : 30, weight: .bold))
        let card = SetupSurface(color: KlikTheme.keycap, cornerRadius: 14, content: keys)
        content.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        if let issue {
            content.addArrangedSubview(label(strings.message(for: issue, fallback: .shortcutUnavailable),
                                             size: 12, color: .systemRed))
        } else if recording {
            content.addArrangedSubview(label(strings(.recordingHint), size: 12, color: .secondaryLabelColor))
        } else if firstRun {
            content.addArrangedSubview(label(strings(.reopenHint), size: 12, color: .secondaryLabelColor))
        }

        if recording {
            footer.addArrangedSubview(button(strings(.cancelRecording), #selector(cancelRecording)))
        } else {
            if firstRun { footer.addArrangedSubview(button(strings(.back), #selector(goBack))) }
            if !selected.matches(.defaultShortcut) {
                footer.addArrangedSubview(button(strings(.restoreDefault), #selector(restoreDefault)))
            }
            footer.addArrangedSubview(button(strings(.recordShortcut), #selector(beginRecording)))
            let action: UIKey = firstRun ? (selected.matches(.defaultShortcut) ? .useDefault : .useShortcut) : .done
            footer.addArrangedSubview(button(strings(action), #selector(finish), primary: true))
        }
    }

    private func languagePicker() -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        let choices = LanguagePreference.allCases
        picker.addItems(withTitles: choices.map { $0.title(using: strings) })
        picker.selectItem(at: choices.firstIndex(of: language) ?? 0)
        picker.target = self
        picker.action = #selector(chooseLanguage(_:))
        picker.setAccessibilityLabel(strings(.language))
        return picker
    }

    private func operation(_ key: String, _ description: String) -> NSStackView {
        let row = stack(.horizontal, spacing: 12)
        let keyLabel = label(key, size: 12, weight: .semibold)
        keyLabel.alignment = .center
        let keycap = SetupSurface(color: KlikTheme.keycap, cornerRadius: 7, content: keyLabel, inset: 6)
        keycap.widthAnchor.constraint(equalToConstant: 70).isActive = true
        row.addArrangedSubview(keycap)
        row.addArrangedSubview(label(description, size: 13))
        return row
    }

    private func stack(_ orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = orientation
        stack.alignment = orientation == .vertical ? .leading : .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func label(_ text: String, size: CGFloat = 14, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = 484
        return field
    }

    private func button(_ title: String, _ action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if primary {
            button.bezelColor = KlikTheme.primary
            button.keyEquivalent = "\r"
        }
        return button
    }
}

private final class SetupSurface: NSView {
    private let color: NSColor
    private let cornerRadius: CGFloat
    private let outlined: Bool

    init(color: NSColor, cornerRadius: CGFloat, outlined: Bool = false, content: NSView? = nil,
         inset: CGFloat = 14) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.outlined = outlined
        super.init(frame: .zero)
        guard let content else { return }
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = outlined ? bounds.insetBy(dx: 0.5, dy: 0.5) : bounds
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        color.setFill()
        path.fill()
        if outlined {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
