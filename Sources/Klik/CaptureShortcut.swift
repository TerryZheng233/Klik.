import AppKit
import Carbon

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = CaptureShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey),
                                                 keyLabel: "A")

    var title: String {
        let prefix = Self.modifierSymbols
            .filter { modifiers & $0.mask != 0 }
            .map(\.symbol).joined()
        return prefix + keyLabel
    }

    func matches(_ other: CaptureShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init(recording event: NSEvent) throws {
        let flags = event.modifierFlags
        let code = Int(event.keyCode)
        let modifiers = Self.modifierSymbols
            .filter { flags.contains($0.flag) }
            .reduce(UInt32(0)) { $0 | $1.mask }

        // Keep ordinary typing available in the foreground app.
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command)
                || Self.functionKeys[code] != nil else {
            throw ShortcutRecordingError.modifierNeeded
        }

        let printable = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .controlCharacters)
            .uppercased()
        let label = Self.specialKeys[code] ?? Self.functionKeys[code]
            ?? printable.flatMap { $0.isEmpty ? nil : $0 }
            ?? "键 \(code)"
        self.init(keyCode: UInt32(code), modifiers: modifiers, keyLabel: label)
    }

    static func isCancelKey(_ event: NSEvent) -> Bool {
        Int(event.keyCode) == kVK_Escape
            && !modifierSymbols.contains(where: { event.modifierFlags.contains($0.flag) })
    }

    private static let modifierSymbols: [(flag: NSEvent.ModifierFlags, mask: UInt32, symbol: String)] = [
        (.control, UInt32(controlKey), "⌃"),
        (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧"),
        (.command, UInt32(cmdKey), "⌘")
    ]

    private static let functionKeys = Dictionary(uniqueKeysWithValues: [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ].enumerated().map { ($0.element, "F\($0.offset + 1)") })

    private static let specialKeys: [Int: String] = [
        kVK_Return: "Enter", kVK_ANSI_KeypadEnter: "小键盘 Enter", kVK_Tab: "Tab",
        kVK_Space: "空格", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"
    ]
}

private enum ShortcutRecordingError: LocalizedError {
    case modifierNeeded

    var errorDescription: String? { "请加上 ⌥、⌃ 或 ⌘，也可以使用 F1 到 F20。" }
}

struct ShortcutPreferences {
    private let defaults: UserDefaults
    private static let key = "captureShortcut"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var savedShortcut: CaptureShortcut? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(CaptureShortcut.self, from: data)
    }

    var shortcut: CaptureShortcut { savedShortcut ?? .defaultShortcut }

    func save(_ shortcut: CaptureShortcut) throws {
        let data = try JSONEncoder().encode(shortcut)
        defaults.set(data, forKey: Self.key)
    }
}

final class GlobalHotKey {
    private static let signature: OSType = 0x54534E50

    private var handler: EventHandlerRef?
    private var key: EventHotKeyRef?
    private var registrationID: UInt32 = 0
    private var serial: UInt32 = 0
    private var shortcut: CaptureShortcut?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) throws {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == GlobalHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            let incomingID = id.id
            guard incomingID == hotKey.registrationID else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { [weak hotKey] in
                guard let hotKey, hotKey.registrationID == incomingID else { return }
                hotKey.action()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        guard status == noErr else { throw HotKeyError(status: status) }
    }

    func register(_ shortcut: CaptureShortcut) throws {
        guard self.shortcut?.matches(shortcut) != true else { return }

        serial &+= 1
        let id = EventHotKeyID(signature: Self.signature, id: serial)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive),
                                         &replacement)
        guard status == noErr, let replacement else {
            throw HotKeyError(status: status == noErr ? OSStatus(eventHotKeyInvalidErr) : status)
        }
        // Only release the previous combination once its replacement is registered.
        if let key { UnregisterEventHotKey(key) }
        key = replacement
        registrationID = id.id
        self.shortcut = shortcut
    }

    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}

private struct HotKeyError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        switch Int(status) {
        case eventHotKeyExistsErr:
            return "这组快捷键已被其他应用占用，请换一组。"
        case eventHotKeyInvalidErr, eventInternalErr:
            return "macOS 无法使用这组快捷键，请换一组。"
        default:
            return "无法启用快捷键，请重试或换一组。（\(status)）"
        }
    }
}
