import Foundation

/// Which language the interface is drawn in. `system` is the default and means
/// "whatever the Mac is set to"; the other cases override that, because a
/// player people keep in a corner is often wanted in a different language than
/// the system they run it on.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german  = "de"

    var id: String { rawValue }

    /// The `.lproj` to load, or nil to let the bundle decide.
    var localeCode: String? {
        self == .system ? nil : rawValue
    }

    var title: String {
        switch self {
        case .system:  return L10n.t("settings.language.system")
        case .english: return L10n.t("settings.language.en")
        case .german:  return L10n.t("settings.language.de")
        }
    }

    static let storageKey = "language"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

/// Look-up of the interface strings.
///
/// This does not use `NSLocalizedString` directly, because that resolves
/// against the bundle's own idea of the preferred language and would need a
/// restart to follow a change. Resolving the `.lproj` ourselves lets the choice
/// in the settings take effect immediately.
enum L10n {

    static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// The formatted variants keep `%@`/`%d` in the translation, so word order
    /// stays the translator's decision.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    private static var bundle: Bundle {
        guard let code = AppLanguage.current.localeCode,
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let localised = Bundle(path: path) else {
            return .module
        }
        return localised
    }
}
