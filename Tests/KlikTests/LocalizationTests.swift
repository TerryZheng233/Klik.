import XCTest
@testable import Klik

final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesFirstSupportedPreference() {
        XCTAssertEqual(LanguagePreference.system.resolve(preferredLanguages: ["en-SG", "zh-Hans"]), .english)
        XCTAssertEqual(LanguagePreference.system.resolve(preferredLanguages: ["fr", "zh-Hant-TW"]), .simplifiedChinese)
        XCTAssertEqual(LanguagePreference.system.resolve(preferredLanguages: ["ja"]), .english)
    }

    func testManualLanguageOverridesSystemPreference() {
        XCTAssertEqual(LanguagePreference.english.resolve(preferredLanguages: ["zh-Hans"]), .english)
        XCTAssertEqual(LanguagePreference.simplifiedChinese.resolve(preferredLanguages: ["en-SG"]), .simplifiedChinese)
    }

    func testBothLanguageTablesCoverEveryInterfaceKey() {
        for language in InterfaceLanguage.allCases {
            let strings = AppStrings(language: language)
            for key in UIKey.allCases {
                XCTAssertNotEqual(strings(key), key.rawValue, "\(language.rawValue): \(key)")
            }
        }
        let english = AppStrings(language: .english)
        let chinese = AppStrings(language: .simplifiedChinese)
        XCTAssertNotEqual(english(.toolConfirm), chinese(.toolConfirm))
        XCTAssertTrue(english(.inkPicker, english(.inkRed)).contains(english(.inkRed)))
        XCTAssertTrue(chinese(.inkPicker, chinese(.inkRed)).contains(chinese(.inkRed)))
    }
}
