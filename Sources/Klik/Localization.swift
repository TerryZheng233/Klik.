import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

enum LanguagePreference: String, CaseIterable {
    case system
    case english
    case simplifiedChinese

    func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        switch self {
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .system:
            for tag in preferredLanguages {
                let language = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
                if language == "zh" { return .simplifiedChinese }
                if language == "en" { return .english }
            }
            return .english
        }
    }

    func title(using strings: AppStrings) -> String {
        switch self {
        case .system: return strings(.systemLanguage)
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

enum UIKey: String, CaseIterable {
    case settingsTitle
    case setupTitle
    case systemLanguage
    case language
    case interfaceLanguage
    case guideTitle
    case guideIntro
    case guidePermission
    case practicePress
    case practiceStart
    case practiceShortcutFallback
    case chooseAnotherShortcut
    case practiceReplay
    case practicePermissionBody
    case practiceSelectTitle
    case practiceSelectDetail
    case practiceStep
    case practiceHideTips
    case practiceEllipse
    case practiceRectangle
    case practiceArrow
    case practicePen
    case practiceText
    case practiceMosaic
    case practiceRecognizeText
    case practiceColor
    case practiceUndo
    case practiceRedo
    case practiceDownload
    case practiceCancel
    case practiceConfirm
    case windowSnapHint
    case windowSnapActive
    case windowCapturePending
    case windowCaptureFailed
    case next
    case back
    case done
    case shortcut
    case shortcutPrompt
    case shortcutIntro
    case settingsIntro
    case saveLocation
    case chooseSaveLocation
    case resetSaveLocation
    case saveLocationError
    case recording
    case recordingHint
    case reopenHint
    case cancelRecording
    case restoreDefault
    case recordShortcut
    case useDefault
    case useShortcut
    case shortcutModifierNeeded
    case shortcutTaken
    case shortcutUnavailable
    case shortcutFailed
    case keySpace
    case keyKeypadEnter
    case keyUnknown
    case permissionTitle
    case permissionBody
    case openSystemSettings
    case cancel
    case ok
    case displayUnavailable
    case captureRetry
    case captureFailed
    case displayChanged
    case overlayFocus
    case toolEllipse
    case toolRectangle
    case toolArrow
    case toolPen
    case penWidth
    case wheelMosaicSize
    case textSize
    case toolText
    case toolMosaic
    case mosaicPixel
    case mosaicBrush
    case mosaicSolid
    case mosaicPickColor
    case mosaicPickPrompt
    case toolRecognizeText
    case toolScrollCapture
    case scrollSelectionSmall
    case scrollSelectionMarked
    case scrollStarting
    case scrollReady
    case scrollProgress
    case scrollProgressWide
    case scrollTopStart
    case scrollTopReached
    case scrollTopUnavailable
    case scrollBottomStart
    case scrollBottomReached
    case scrollBottomApply
    case scrollBottomInstructions
    case scrollBottomUnavailable
    case scrollUnaligned
    case scrollLimit
    case scrollFinishing
    case scrollPartial
    case scrollSourceFailed
    case scrollPreviewTitle
    case scrollSizeHint
    case scrollDimensions
    case scrollMosaicHint
    case ocrTitle
    case ocrLoading
    case ocrEditedImageChanged
    case ocrRefresh
    case ocrReplaceTitle
    case ocrReplaceMessage
    case ocrReplaceButton
    case ocrEmpty
    case ocrFailed
    case ocrCopy
    case ocrCancel
    case ocrConfirm
    case ocrSaveImage
    case ocrSaveImageHint
    case toolUndo
    case toolRedo
    case toolDownload
    case toolCancel
    case toolConfirm
    case toolCrop
    case cropHint
    case inkPicker
    case inkCustom
    case inkSample
    case inkRed
    case inkOrange
    case inkYellow
    case inkGreen
    case inkBlue
    case inkPurple
    case inkWhite
    case inkBlack
    case textPlaceholder
    case renderError
    case clipboardError
    case downloadError
    case menuSettings
    case menuHistory
    case menuHistoryEmpty
    case menuHistoryClear
    case historyDelete
    case historyDeleteConfirmHint
    case menuHistoryConfirmClear
    case menuHistoryConfirmClearHint
    case historyToday
    case historyYesterday
    case historyPreview
    case historyCopy
    case menuQuit
    case historyErrorTitle
    case historyErrorBody
    case loginAtStartup
    case loginApproval
    case loginError
    case historyLimit
    case historyLimitCount
    case historyOff
    case historyOffNote
    case ocrCopied
    case historyStorageNote
    case appVersion
    case checkForUpdates
    case checkingUpdates
    case updateAvailableTitle
    case updateAvailableBody
    case updateAvailableFallbackBody
    case updateCurrentTitle
    case updateCurrentBody
    case updateErrorTitle
    case updateErrorBody
    case downloadUpdate
    case downloadingUpdate
    case updateDownloadedTitle
    case updateDownloadedBody
    case updateDownloadErrorTitle
    case updateDownloadErrorBody
    case showInFinder
    case openReleases
}

protocol KlikLocalizedError: Error {
    func message(using strings: AppStrings) -> String
}

struct AppStrings {
    let language: InterfaceLanguage
    private let bundle: Bundle

    init(language: InterfaceLanguage = LanguagePreference.system.resolve()) {
        self.language = language
        let resources = Self.resources
        let directory = resources.resourceURL?.appendingPathComponent(language.rawValue + ".lproj")
        bundle = directory.flatMap(Bundle.init(url:)) ?? resources
    }

    func callAsFunction(_ key: UIKey, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    func message(for error: Error, fallback: UIKey) -> String {
        (error as? KlikLocalizedError)?.message(using: self) ?? self(fallback)
    }

    private static var resources: Bundle {
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("en.lproj"),
           FileManager.default.fileExists(atPath: directory.path) {
            return .main
        }
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
