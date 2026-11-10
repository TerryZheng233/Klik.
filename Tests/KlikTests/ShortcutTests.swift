import AppKit
import Carbon
import XCTest
@testable import Klik

final class ShortcutTests: XCTestCase {
    private let english = AppStrings(language: .english)

    @MainActor
    func testShortcutConflictKeepsExistingRegistration() throws {
        let first = CaptureShortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "F19")
        let second = CaptureShortcut(keyCode: UInt32(kVK_F20), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "F20")
        let owner = try GlobalHotKey(action: {})
        let other = try GlobalHotKey(action: {})
        try owner.register(first)
        try other.register(second)
        XCTAssertThrowsError(try owner.register(second)) { error in
            XCTAssertEqual((error as? KlikLocalizedError)?.message(using: english), english(.shortcutTaken))
        }
        let third = try GlobalHotKey(action: {})
        XCTAssertThrowsError(try third.register(first), "The original shortcut must remain registered")
    }

    func testCaptureDoesNotStealFocusAfterUserChangesApp() {
        XCTAssertTrue(CaptureFocus.mayPresent(startingPID: 10, currentPID: 10, ownPID: 99))
        XCTAssertTrue(CaptureFocus.mayPresent(startingPID: 10, currentPID: 99, ownPID: 99))
        XCTAssertFalse(CaptureFocus.mayPresent(startingPID: 10, currentPID: 20, ownPID: 99))
        XCTAssertFalse(CaptureFocus.mayPresent(startingPID: 99, currentPID: 20, ownPID: 99))
    }

    func testHistoryLimitDefaultsToTenAndPersistsValidChoices() throws {
        let name = "KlikHistoryPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = KlikPreferences(defaults: defaults)
        XCTAssertEqual(preferences.historyLimit, 10)
        preferences.historyLimit = 50
        XCTAssertEqual(KlikPreferences(defaults: defaults).historyLimit, 50)
        preferences.historyLimit = 0
        XCTAssertEqual(KlikPreferences(defaults: defaults).historyLimit, 0)
        defaults.set(999, forKey: "historyLimit")
        XCTAssertEqual(preferences.historyLimit, 10)
    }

    func testRecordsPhysicalKeyAndModifiers() throws {
        let input = try key(kVK_ANSI_S, flags: [.control, .shift], characters: "S")
        let shortcut = try CaptureShortcut(recording: input)
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_S))
        XCTAssertEqual(shortcut.modifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(shortcut.title(using: english), "⌃⇧S")

        let defaultInput = try key(kVK_ANSI_A, flags: .option, characters: "a")
        XCTAssertEqual(try CaptureShortcut(recording: defaultInput), .defaultShortcut)
    }

    func testOrdinaryTypingIsNotRegisteredAndFunctionKeysAreAvailable() throws {
        let bare = try key(kVK_ANSI_A, flags: [], characters: "a")
        let capital = try key(kVK_ANSI_A, flags: .shift, characters: "A")
        XCTAssertThrowsError(try CaptureShortcut(recording: bare))
        XCTAssertThrowsError(try CaptureShortcut(recording: capital))

        let function = try key(kVK_F18, flags: .function, characters: "")
        XCTAssertEqual(try CaptureShortcut(recording: function).title(using: english), "F18")
    }

    func testEscapeCancelsOnlyWithoutModifiers() throws {
        XCTAssertTrue(CaptureShortcut.isCancelKey(try key(kVK_Escape, flags: [], characters: "")))
        let optionEscape = try key(kVK_Escape, flags: .option, characters: "")
        XCTAssertFalse(CaptureShortcut.isCancelKey(optionEscape))
        XCTAssertEqual(try CaptureShortcut(recording: optionEscape).title(using: english), "⌥Esc")
    }

    func testRecordedSpaceUsesTheCurrentInterfaceLanguage() throws {
        let input = try key(kVK_Space, flags: [.option], characters: " ")
        let shortcut = try CaptureShortcut(recording: input)
        let chinese = AppStrings(language: .simplifiedChinese)
        XCTAssertEqual(shortcut.title(using: english), "⌥" + english(.keySpace))
        XCTAssertEqual(shortcut.title(using: chinese), "⌥" + chinese(.keySpace))
        XCTAssertNotEqual(shortcut.title(using: english), shortcut.title(using: chinese))
    }

    private func key(_ code: Int, flags: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                      timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false,
                                      keyCode: UInt16(code)))
    }
}
