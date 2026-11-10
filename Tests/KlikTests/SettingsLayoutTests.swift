import AppKit
import XCTest
@testable import Klik

final class SettingsLayoutTests: XCTestCase {
    @MainActor
    func testShortcutActionIsNextToShortcutInBothLanguages() throws {
        _ = NSApplication.shared
        for preference in [LanguagePreference.english, .simplifiedChinese] {
            let strings = AppStrings(language: preference.resolve())
            let setup = ShortcutSetup(shortcut: .defaultShortcut, firstRun: false, issue: nil,
                language: preference, changeLanguage: { _ in }, historyLimit: 10,
                changeHistoryLimit: { _ in }, startPractice: { _ in }, save: { _ in }, didClose: {})
            let root = try XCTUnwrap(setup.window?.contentView)
            root.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let views = descendants(root)
            let title = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.stringValue == strings(.shortcut) })
            let record = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == strings(.recordShortcut) })
            XCTAssertNil(views.compactMap { $0 as? NSButton }.first { $0.title == strings(.practiceReplay) })
            let language = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == strings(.language) })
            let history = try XCTUnwrap(views.compactMap { $0 as? NSSlider }.first { $0.accessibilityLabel() == strings(.historyLimit) })
            let location = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == strings(.chooseSaveLocation) })
            let locationFrame = location.convert(location.bounds, to: root)
            XCTAssertTrue(root.bounds.contains(locationFrame))
            let keyFrame = title.convert(title.bounds, to: root)
            let buttonFrame = record.convert(record.bounds, to: root)
            let update = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == strings(.checkForUpdates) })
            let updateFrame = update.convert(update.bounds, to: root)
            let languageFrame = language.convert(language.bounds, to: root)
            let historyFrame = history.convert(history.bounds, to: root)
            XCTAssertEqual(languageFrame.height, buttonFrame.height, accuracy: 0.5)
            XCTAssertEqual(updateFrame.height, buttonFrame.height, accuracy: 0.5)
            XCTAssertEqual(languageFrame.width, buttonFrame.width, accuracy: 0.5)
            XCTAssertEqual(historyFrame.width, buttonFrame.width, accuracy: 0.5)
            XCTAssertEqual(languageFrame.maxX, buttonFrame.maxX, accuracy: 0.5)
            XCTAssertEqual(historyFrame.maxX, buttonFrame.maxX, accuracy: 0.5)
            XCTAssertEqual(locationFrame.width, buttonFrame.width, accuracy: 0.5)
            XCTAssertEqual(locationFrame.maxX, buttonFrame.maxX, accuracy: 0.5)
            XCTAssertEqual(updateFrame.width, buttonFrame.width, accuracy: 0.5)
            XCTAssertEqual(updateFrame.maxX, buttonFrame.maxX, accuracy: 0.5)
            XCTAssertGreaterThan(buttonFrame.minX, keyFrame.maxX)
            XCTAssertLessThan(abs(buttonFrame.midY - keyFrame.midY), 60)
            setup.close()
        }
    }
}
