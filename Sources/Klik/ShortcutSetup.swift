import AppKit
import ServiceManagement

@MainActor
final class ShortcutSetup: NSWindowController, NSWindowDelegate {
    private enum Step { case practice, review, settings }

    private let firstRun: Bool
    private let currentShortcut: CaptureShortcut
    private let startPractice: (ShortcutSetup) -> Void
    private let save: (CaptureShortcut) throws -> Void
    private let changeLanguage: (LanguagePreference) -> Void
    private let changeHistoryLimit: (Int) throws -> Void
    private let didClose: () -> Void
    private var step: Step
    private var selected: CaptureShortcut
    private var issue: Error?
    private var recordingMonitor: Any?
    private var language: LanguagePreference
    private var strings: AppStrings
    private var historyLimit: Int
    private var isCheckingUpdates = false
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    init(shortcut: CaptureShortcut, firstRun: Bool, issue: Error?,
         language: LanguagePreference, changeLanguage: @escaping (LanguagePreference) -> Void,
         historyLimit: Int, changeHistoryLimit: @escaping (Int) throws -> Void,
         startPractice: @escaping (ShortcutSetup) -> Void,
         save: @escaping (CaptureShortcut) throws -> Void, didClose: @escaping () -> Void) {
        self.firstRun = firstRun
        self.currentShortcut = shortcut
        self.startPractice = startPractice
        self.save = save
        self.changeLanguage = changeLanguage
        self.historyLimit = historyLimit
        self.changeHistoryLimit = changeHistoryLimit
        self.didClose = didClose
        self.step = firstRun ? .practice : .settings
        self.selected = shortcut
        self.issue = issue
        self.language = language
        self.strings = AppStrings(language: language.resolve())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 544, height: firstRun ? 620 : 540),
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

    func showSettings() {
        stopRecording()
        step = .settings
        render()
        present()
    }

    @objc private func toggleLogin(_ sender: ForestSwitch) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            issue = nil
        } catch {
            issue = LoginSettingError()
        }
        render()
    }

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func chooseHistoryLimit(_ sender: NSPopUpButton) {
        let choices = KlikPreferences.historyLimits
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        do {
            try changeHistoryLimit(choices[sender.indexOfSelectedItem])
            historyLimit = choices[sender.indexOfSelectedItem]
            issue = nil
        } catch {
            issue = HistorySettingError()
        }
        render()
    }

    @objc private func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        render()
        let version = appVersion
        Task { @MainActor [weak self] in
            let result = await UpdateChecker.check(currentVersion: version)
            guard let self else { return }
            self.isCheckingUpdates = false
            guard let window = self.window, window.isVisible else { return }
            self.render()
            let alert = NSAlert()
            switch result {
            case .upToDate:
                alert.messageText = self.strings(.updateCurrentTitle)
                alert.informativeText = self.strings(.updateCurrentBody)
                alert.addButton(withTitle: self.strings(.ok))
            case .available(let version):
                alert.messageText = self.strings(.updateAvailableTitle)
                alert.informativeText = self.strings(.updateAvailableBody, version)
                alert.addButton(withTitle: self.strings(.openReleases))
                alert.addButton(withTitle: self.strings(.cancel))
            case .unavailable:
                alert.messageText = self.strings(.updateErrorTitle)
                alert.informativeText = self.strings(.updateErrorBody)
                alert.addButton(withTitle: self.strings(.ok))
                alert.addButton(withTitle: self.strings(.openReleases))
            }
            alert.beginSheetModal(for: window) { response in
                if (result == .unavailable && response == .alertSecondButtonReturn)
                    || (result != .unavailable && result != .upToDate && response == .alertFirstButtonReturn) {
                    NSWorkspace.shared.open(UpdateChecker.releasePage)
                }
            }
        }
    }

    // An already registered shortcut arrives through Carbon.
    func handleRegisteredShortcut(_ shortcut: CaptureShortcut) -> Bool {
        if step == .practice {
            startPractice(self)
            return true
        }
        guard window?.isKeyWindow == true, recordingMonitor != nil else { return false }
        accept(shortcut)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        didClose()
    }

    func returnFromPractice(_ outcome: CapturePanel.Outcome) {
        if outcome == .exported {
            step = .review
            selected = currentShortcut
            render()
        }
        present()
    }

    @objc private func openPractice() {
        step = .practice
        render()
    }

    @objc private func startPracticeFromButton() { startPractice(self) }

    @objc private func chooseAnotherShortcut() {
        step = .review
        render()
    }

    @objc private func returnToSettings() {
        step = .settings
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
        window?.title = "Klik. · " + strings(step == .settings ? .settingsTitle : .setupTitle)
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

        if step == .practice {
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
        let stepLabel = step == .settings ? nil : (step == .practice ? "01 / 02" : "02 / 02")
        let subtitle = strings(step == .settings ? .settingsTitle : .setupTitle)
        words.addArrangedSubview(label([subtitle, stepLabel].compactMap { $0 }.joined(separator: "  ·  "),
                                       size: 11, weight: .medium, color: .secondaryLabelColor))
        row.addArrangedSubview(words)
        if step != .settings {
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
        let keys = stack(.vertical, spacing: 6)
        keys.addArrangedSubview(label(strings(.practicePress), size: 12, weight: .semibold, color: .secondaryLabelColor))
        keys.addArrangedSubview(label(currentShortcut.title(using: strings), size: 42, weight: .bold))
        let card = SetupSurface(color: KlikTheme.keycap, cornerRadius: 15, content: keys, inset: 18)
        content.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.addArrangedSubview(label(strings(.guidePermission), size: 12, color: .secondaryLabelColor))
        if issue != nil {
            content.addArrangedSubview(label(strings(.practiceShortcutFallback, currentShortcut.title(using: strings)),
                                             size: 12, color: .systemRed))
            footer.addArrangedSubview(button(strings(.chooseAnotherShortcut), #selector(chooseAnotherShortcut)))
        }
        if !firstRun { footer.addArrangedSubview(button(strings(.back), #selector(returnToSettings))) }
        footer.addArrangedSubview(button(strings(.practiceStart), #selector(startPracticeFromButton), primary: true))
    }

    private func addShortcut(to content: NSStackView, footer: NSStackView) {
        let recording = recordingMonitor != nil
        let reviewing = step == .review
        let title = reviewing ? strings(.shortcutPrompt) : strings(.settingsTitle)
        content.addArrangedSubview(label(title, size: 30, weight: .bold))
        content.addArrangedSubview(label(strings(reviewing ? .shortcutIntro : .settingsIntro), color: .secondaryLabelColor))

        let settingsRows = stack(.vertical, spacing: 10)
        let settingsControlWidth: CGFloat = 146
        if !reviewing {
            let row = stack(.horizontal, spacing: 10)
            let words = stack(.vertical, spacing: 4)
            words.addArrangedSubview(label(strings(.language), weight: .semibold))
            words.addArrangedSubview(label(strings(.interfaceLanguage), size: 12, color: .secondaryLabelColor))
            row.addArrangedSubview(words)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            let languageControl = languagePicker()
            languageControl.widthAnchor.constraint(equalToConstant: settingsControlWidth).isActive = true
            row.addArrangedSubview(languageControl)
            settingsRows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true

            let loginRow = stack(.horizontal, spacing: 10)
            loginRow.addArrangedSubview(label(strings(.loginAtStartup), weight: .semibold))
            let loginSpacer = NSView()
            loginSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            loginRow.addArrangedSubview(loginSpacer)
            let login = ForestSwitch()
            login.target = self
            login.action = #selector(toggleLogin(_:))
            login.setAccessibilityLabel(strings(.loginAtStartup))
            let loginStatus = SMAppService.mainApp.status
            login.state = loginStatus == .enabled || loginStatus == .requiresApproval ? .on : .off
            loginRow.addArrangedSubview(login)
            settingsRows.addArrangedSubview(loginRow)
            loginRow.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true
            if loginStatus == .requiresApproval {
                settingsRows.addArrangedSubview(label(strings(.loginApproval), size: 12, color: .secondaryLabelColor))
                settingsRows.addArrangedSubview(button(strings(.openSystemSettings), #selector(openLoginItems)))
            }

            let historyRow = stack(.horizontal, spacing: 10)
            let historyWords = stack(.vertical, spacing: 4)
            historyWords.addArrangedSubview(label(strings(.historyLimit), weight: .semibold))
            let historyNote = label(strings(.historyStorageNote), size: 12, color: .secondaryLabelColor)
            historyNote.preferredMaxLayoutWidth = 280
            historyWords.addArrangedSubview(historyNote)
            historyWords.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
            historyRow.addArrangedSubview(historyWords)
            let historySpacer = NSView()
            historySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            historyRow.addArrangedSubview(historySpacer)
            let picker = ForestPicker(frame: .zero, pullsDown: false)
            picker.addItems(withTitles: KlikPreferences.historyLimits.map { strings(.historyLimitCount, $0) })
            picker.selectItem(at: KlikPreferences.historyLimits.firstIndex(of: historyLimit) ?? 1)
            picker.target = self
            picker.action = #selector(chooseHistoryLimit(_:))
            picker.setAccessibilityLabel(strings(.historyLimit))
            picker.bezelColor = KlikTheme.keycap
            picker.widthAnchor.constraint(equalToConstant: settingsControlWidth).isActive = true
            historyRow.addArrangedSubview(picker)
            settingsRows.addArrangedSubview(historyRow)
            historyRow.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true

        }

        let keys = stack(.vertical, spacing: 5)
        keys.addArrangedSubview(label(strings(.shortcut), size: reviewing ? 11 : 14, weight: .semibold,
                                     color: reviewing ? .secondaryLabelColor : .labelColor))
        let value = recording ? strings(.recording) : selected.title(using: strings)
        keys.addArrangedSubview(label(value, size: reviewing ? (recording ? 23 : 30) : 16, weight: .semibold))
        let keyContent: NSView
        if reviewing {
            keyContent = keys
        } else {
            let row = stack(.horizontal, spacing: 12)
            row.addArrangedSubview(keys)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            let actions = stack(.vertical, spacing: 5)
            actions.alignment = .trailing
            if recording {
                actions.addArrangedSubview(button(strings(.cancelRecording), #selector(cancelRecording)))
            } else {
                actions.addArrangedSubview(button(strings(.recordShortcut), #selector(beginRecording)))
                if !selected.matches(.defaultShortcut) {
                    actions.addArrangedSubview(button(strings(.restoreDefault), #selector(restoreDefault)))
                }
            }
            for control in actions.arrangedSubviews {
                control.widthAnchor.constraint(equalToConstant: settingsControlWidth).isActive = true
            }
            row.addArrangedSubview(actions)
            keyContent = row
        }
        let card: SetupSurface
        if reviewing {
            card = SetupSurface(color: KlikTheme.keycap, cornerRadius: 14, content: keyContent)
        } else {
            settingsRows.addArrangedSubview(keyContent)
            keyContent.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true
            card = SetupSurface(color: KlikTheme.card, cornerRadius: 14, outlined: true, content: settingsRows)
        }
        if !reviewing {
            let versionRow = stack(.horizontal, spacing: 10)
            let versionWords = stack(.vertical, spacing: 5)
            versionWords.addArrangedSubview(label(strings(.appVersion), weight: .semibold))
            versionWords.addArrangedSubview(label(appVersion, size: 13, color: .secondaryLabelColor))
            versionRow.addArrangedSubview(versionWords)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            versionRow.addArrangedSubview(spacer)
            let update = button(strings(isCheckingUpdates ? .checkingUpdates : .checkForUpdates), #selector(checkForUpdates))
            update.isEnabled = !isCheckingUpdates
            update.widthAnchor.constraint(equalToConstant: settingsControlWidth).isActive = true
            versionRow.addArrangedSubview(update)
            settingsRows.addArrangedSubview(versionRow)
            versionRow.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true
        }
        content.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        if let issue {
            content.addArrangedSubview(label(strings.message(for: issue, fallback: .shortcutUnavailable),
                                             size: 12, color: .systemRed))
        } else if recording {
            content.addArrangedSubview(label(strings(.recordingHint), size: 12, color: .secondaryLabelColor))
        } else if reviewing {
            content.addArrangedSubview(label(strings(.reopenHint), size: 12, color: .secondaryLabelColor))
        }

        if reviewing {
            if recording {
                footer.addArrangedSubview(button(strings(.cancelRecording), #selector(cancelRecording)))
            } else {
                if !selected.matches(.defaultShortcut) {
                    footer.addArrangedSubview(button(strings(.restoreDefault), #selector(restoreDefault)))
                }
                footer.addArrangedSubview(button(strings(.recordShortcut), #selector(beginRecording)))
                let action: UIKey = selected.matches(.defaultShortcut) ? .useDefault : .useShortcut
                footer.addArrangedSubview(button(strings(action), #selector(finish), primary: true))
            }
        } else if !recording {
            footer.addArrangedSubview(button(strings(.done), #selector(finish), primary: true))
        }
    }

    private func languagePicker() -> NSPopUpButton {
        let picker = ForestPicker(frame: .zero, pullsDown: false)
        let choices = LanguagePreference.allCases
        picker.addItems(withTitles: choices.map { $0.title(using: strings) })
        picker.selectItem(at: choices.firstIndex(of: language) ?? 0)
        picker.target = self
        picker.action = #selector(chooseLanguage(_:))
        picker.setAccessibilityLabel(strings(.language))
        picker.bezelColor = KlikTheme.keycap
        return picker
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
        button.bezelColor = KlikTheme.keycap
        if primary {
            button.bezelColor = KlikTheme.primary
            button.keyEquivalent = "\r"
        }
        return button
    }
}

// A native button-backed toggle gives the login setting a consistent accent,
// while retaining keyboard and accessibility activation.
private final class ForestSwitch: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        setButtonType(.pushOnPushOff)
        isBordered = false
        focusRingType = .none
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: "AXSwitch"))
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }
    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = CGRect(x: 0, y: 2, width: 40, height: 20)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10)
        (state == .on ? KlikTheme.primary : NSColor.secondaryLabelColor.withAlphaComponent(0.34)).setFill()
        trackPath.fill()
        let knob = CGRect(x: state == .on ? 21 : 3, y: 4, width: 16, height: 16)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        if window?.firstResponder === self {
            KlikTheme.selection.setStroke()
            trackPath.lineWidth = 2
            trackPath.stroke()
        }
    }
}

private struct LoginSettingError: KlikLocalizedError {
    func message(using strings: AppStrings) -> String { strings(.loginError) }
}

private struct HistorySettingError: KlikLocalizedError {
    func message(using strings: AppStrings) -> String { strings(.historyErrorBody) }
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
