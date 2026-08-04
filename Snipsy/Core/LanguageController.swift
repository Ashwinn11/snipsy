import Foundation
import SwiftUI

/// In-app language override, applied everywhere.
///
/// Two lookup paths need to agree or the app ends up half-translated:
///
/// * SwiftUI `Text("…")` takes a `LocalizedStringKey` and resolves against
///   the `\.locale` environment value.
/// * `String(localized:)` — every enum `label`, `blurb` and `captureCue` —
///   ignores that environment entirely and asks `Bundle.main`.
///
/// Setting only the environment would translate the chrome and leave the
/// template names in English. So the bundle is re-pointed at the chosen
/// `.lproj` as well, and `RootView` supplies the environment locale.
@Observable
final class LanguageController {

    static let shared = LanguageController()

    private static let defaultsKey = "SnipsyPreferredLanguage"

    /// Empty means "follow the device".
    private(set) var code: String

    private init() {
        code = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        Self.applyBundle(for: code)
    }

    /// The locale to hand SwiftUI. Nil-safe: an empty code yields the
    /// device's own locale so "System" behaves exactly as before.
    var locale: Locale {
        code.isEmpty ? Locale.autoupdatingCurrent : Locale(identifier: code)
    }

    /// Only languages actually present in the bundle. Deriving this from
    /// `Bundle.main.localizations` rather than a hand-kept list means a
    /// language appears in the picker the moment its translations ship —
    /// and never before, so nobody can select a half-empty locale.
    var available: [(code: String, name: String)] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .map { code in
                // Each language names itself — a Korean speaker scanning the
                // list looks for 한국어, not "Korean".
                let name = Locale(identifier: code)
                    .localizedString(forIdentifier: code)?
                    .localizedCapitalized ?? code
                return (code, name)
            }
            .sorted { $0.name < $1.name }
    }

    func select(_ newCode: String) {
        guard newCode != code else { return }
        code = newCode
        if newCode.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.set(newCode, forKey: Self.defaultsKey)
        }
        Self.applyBundle(for: newCode)
    }

    /// Re-point `Bundle.main` at one `.lproj`. Done by swapping in a
    /// subclass that forwards every lookup — no private API, and it takes
    /// effect immediately rather than on next launch the way writing
    /// `AppleLanguages` would.
    private static func applyBundle(for code: String) {
        if bundleClassSwapped == false {
            object_setClass(Bundle.main, LocalizedBundle.self)
            bundleClassSwapped = true
        }
        let path = code.isEmpty ? nil : Bundle.main.path(forResource: code, ofType: "lproj")
        LocalizedBundle.override = path.flatMap(Bundle.init(path:))
    }

    private static var bundleClassSwapped = false

    /// The bundle a lookup should read from right now.
    static var activeBundle: Bundle { LocalizedBundle.override ?? .main }
}

/// Localized lookup that honours the in-app picker.
///
/// `String(localized:)` goes through `LocalizedStringResource`, which reads
/// the *process* language list and never consults the swapped
/// `Bundle.main` — so it kept returning English while SwiftUI `Text` (which
/// resolves against `\.locale`) translated correctly. Passing the bundle and
/// locale explicitly is what makes the two agree.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key,
           bundle: LanguageController.activeBundle,
           locale: LanguageController.shared.locale)
}

extension DateFormatter {
    /// Formatters read `Locale.current`, not the picker, so month names and
    /// weekdays stayed English. Every formatter in the app goes through this.
    static func app(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = LanguageController.shared.locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}

/// `Bundle.main` after the swap. Falls straight through to normal behaviour
/// whenever no override is set, so "System" is genuinely untouched.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var override: Bundle?

    override func localizedString(
        forKey key: String, value: String?, table tableName: String?
    ) -> String {
        guard let bundle = LocalizedBundle.override else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
