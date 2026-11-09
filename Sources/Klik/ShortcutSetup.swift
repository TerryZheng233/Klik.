import AppKit

@MainActor
final class ShortcutSetup: NSWindowController, NSWindowDelegate {
    private enum Step { case guide, shortcut }

    private let firstRun: Bool
    private let save: (CaptureShortcut) throws -> Void
    private let didClose: () -> Void
    private var step: Step
    private var selected: CaptureShortcut
    private var issue: String?
    private var recordingMonitor: Any?

    init(shortcut: CaptureShortcut, firstRun: Bool, issue: String?,
         save: @escaping (CaptureShortcut) throws -> Void, didClose: @escaping () -> Void) {
        self.firstRun = firstRun
        self.save = save
        self.didClose = didClose
        self.step = firstRun ? .guide : .shortcut
        self.selected = shortcut
        self.issue = issue
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 496, height: 438),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Klik."
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        window.delegate = self
        render()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // A combination already registered by Klik arrives through Carbon rather than the window.
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

    @objc private func restoreDefault() {
        accept(.defaultShortcut)
    }

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
                        self.issue = error.localizedDescription
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
            issue = error.localizedDescription
            render()
        }
    }

    private func render() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 496, height: 438))
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 35),
            content.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -12),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -23)
        ])

        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 9
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 38).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 38).isActive = true
        brand.addArrangedSubview(icon)
        brand.addArrangedSubview(label(step == .guide ? "KLIK.   /   01—02" : firstRun ? "KLIK.   /   02—02" : "KLIK.   /   设置",
                                       size: 11, weight: .semibold, color: .secondaryLabelColor))
        content.addArrangedSubview(brand)
        content.setCustomSpacing(17, after: brand)

        switch step {
        case .guide:
            content.addArrangedSubview(label("一按、一框、一贴。", size: 28, weight: .bold))
            content.addArrangedSubview(label("Klik. 平时在后台等你。截图只需要这几步。", color: .secondaryLabelColor))
            let operations = NSStackView()
            operations.orientation = .vertical
            operations.alignment = .leading
            operations.spacing = 11
            operations.addArrangedSubview(operation(selected.title, "唤出截图，拖动框选，再拖边角微调。"))
            operations.addArrangedSubview(operation("工具栏", "画框、画箭头、自由画、写字或涂马赛克。"))
            operations.addArrangedSubview(operation("Enter", "复制到剪贴板；点下载会保存 PNG。"))
            operations.addArrangedSubview(operation("Esc", "随时取消截图。"))
            content.addArrangedSubview(operations)
            content.setCustomSpacing(12, after: operations)
            content.addArrangedSubview(label("第一次截图时，macOS 会询问屏幕录制权限。",
                                             size: 11, color: .secondaryLabelColor))
            footer.addArrangedSubview(button("下一步", #selector(goToShortcut), primary: true))
        case .shortcut:
            let recording = recordingMonitor != nil
            let title = firstRun ? "这组快捷键顺手吗？" : "截图快捷键"
            content.addArrangedSubview(label(title, size: 28, weight: .bold))
            content.addArrangedSubview(label("可以保留默认的 ⌥A，也可以换成你习惯的组合键。", color: .secondaryLabelColor))

            let keyCard = NSBox()
            keyCard.boxType = .custom
            keyCard.borderWidth = 1
            keyCard.cornerRadius = 12
            keyCard.fillColor = .controlBackgroundColor
            keyCard.borderColor = .separatorColor
            keyCard.titlePosition = .noTitle
            keyCard.widthAnchor.constraint(equalToConstant: 440).isActive = true
            keyCard.heightAnchor.constraint(equalToConstant: 70).isActive = true
            let keyLabel = label(recording ? "按下新快捷键" : selected.title, size: 28, weight: .semibold)
            keyLabel.alignment = .center
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            let cardContent = NSView()
            keyCard.contentView = cardContent
            cardContent.addSubview(keyLabel)
            NSLayoutConstraint.activate([
                keyLabel.centerXAnchor.constraint(equalTo: cardContent.centerXAnchor),
                keyLabel.centerYAnchor.constraint(equalTo: cardContent.centerYAnchor),
                keyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cardContent.leadingAnchor, constant: 8),
                keyLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardContent.trailingAnchor, constant: -8)
            ])
            content.addArrangedSubview(keyCard)
            if let issue {
                content.addArrangedSubview(label(issue, size: 12, color: .systemRed))
            } else if recording {
                content.addArrangedSubview(label("例如 ⌃⇧S。按 Esc 可以取消录制。", size: 12, color: .secondaryLabelColor))
            } else {
                content.addArrangedSubview(label("以后重新打开 Klik.，也可以在这里改键。", size: 12, color: .secondaryLabelColor))
            }

            if recording {
                footer.addArrangedSubview(button("取消录制", #selector(cancelRecording)))
            } else {
                if firstRun { footer.addArrangedSubview(button("返回", #selector(goBack))) }
                if !selected.matches(.defaultShortcut) {
                    footer.addArrangedSubview(button("恢复默认", #selector(restoreDefault)))
                }
                footer.addArrangedSubview(button("自定义快捷键…", #selector(beginRecording)))
                let action = selected.matches(.defaultShortcut) ? "使用 ⌥A" : "使用这组快捷键"
                footer.addArrangedSubview(button(action, #selector(finish), primary: true))
            }
        }
        window?.contentView = root
    }

    private func operation(_ key: String, _ description: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        let keyLabel = label(key, size: 13, weight: .semibold)
        keyLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(keyLabel)
        row.addArrangedSubview(label(description, size: 13, color: .secondaryLabelColor))
        return row
    }

    private func label(_ text: String, size: CGFloat = 14, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = 440
        return field
    }

    private func button(_ title: String, _ action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        if primary { button.keyEquivalent = "\r" }
        return button
    }
}
