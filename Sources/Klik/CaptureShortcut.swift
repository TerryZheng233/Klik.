import AppKit
import Carbon

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = CaptureShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey),
                                                 keyLabel: "A")

    func title(using strings: AppStrings) -> String {
        let prefix = Self.modifierSymbols
            .filter { modifiers & $0.mask != 0 }
            .map(\.symbol).joined()
        let label: String
        switch Int(keyCode) {
        case kVK_Space: label = strings(.keySpace)
        case kVK_ANSI_KeypadEnter: label = strings(.keyKeypadEnter)
        default:
            label = keyLabel.isEmpty || keyLabel == "键 \(keyCode)"
                ? strings(.keyUnknown, keyCode) : keyLabel
        }
        return prefix + label
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
            ?? ""
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
        kVK_Return: "Enter", kVK_ANSI_KeypadEnter: "Keypad Enter", kVK_Tab: "Tab",
        kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"
    ]
}

private enum ShortcutRecordingError: KlikLocalizedError {
    case modifierNeeded

    func message(using strings: AppStrings) -> String { strings(.shortcutModifierNeeded) }
}

struct KlikPreferences {
    private let defaults: UserDefaults
    private static let key = "captureShortcut"
    private static let languageKey = "interfaceLanguage"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var savedShortcut: CaptureShortcut? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(CaptureShortcut.self, from: data)
    }

    var shortcut: CaptureShortcut { savedShortcut ?? .defaultShortcut }

    var language: LanguagePreference {
        get { defaults.string(forKey: Self.languageKey).flatMap(LanguagePreference.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.languageKey) }
    }

    var strings: AppStrings { AppStrings(language: language.resolve()) }

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

private struct HotKeyError: KlikLocalizedError {
    let status: OSStatus

    func message(using strings: AppStrings) -> String {
        switch Int(status) {
        case eventHotKeyExistsErr:
            return strings(.shortcutTaken)
        case eventHotKeyInvalidErr, eventInternalErr:
            return strings(.shortcutUnavailable)
        default:
            return strings(.shortcutFailed, status)
        }
    }
}
