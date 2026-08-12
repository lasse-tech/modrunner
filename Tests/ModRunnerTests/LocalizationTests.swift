import XCTest
@testable import ModRunner

/// The interface is offered in English and German. A missing key does not fail
/// to build and does not crash — it silently shows the key itself — so it is
/// worth asserting that the two files stay in step.
final class LocalizationTests: XCTestCase {

    private func table(_ code: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.module.path(forResource: code, ofType: "lproj"),
                                 "\(code).lproj is missing from the resource bundle")
        let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        let contents = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                     "\(code)/Localizable.strings could not be parsed")
        return contents
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    func testEveryEnglishKeyIsTranslated() throws {
        let english = try table("en")
        let german = try table("de")

        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys).subtracting(german.keys), [],
                       "keys present in English but missing from German")
        XCTAssertEqual(Set(german.keys).subtracting(english.keys), [],
                       "keys present in German but missing from English")
    }

    /// A translation that drops or reorders a placeholder produces garbage at
    /// best and crashes `String(format:)` at worst.
    func testPlaceholdersMatchAcrossLanguages() throws {
        let english = try table("en")
        let german = try table("de")

        for (key, source) in english {
            let translation = try XCTUnwrap(german[key])
            XCTAssertEqual(Self.placeholders(in: source), Self.placeholders(in: translation),
                           "placeholders differ for '\(key)'")
        }
    }

    func testLanguageOverrideChangesTheStrings() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(L10n.t("menu.about"), "About ModRunner")

        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(L10n.t("menu.about"), "Über ModRunner")
    }

    func testFormattedStringsSubstitute() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(L10n.t("status.blocks", 12), "12 blocks")
        XCTAssertEqual(L10n.t("status.samples", 9, 14), "9/14 samples")

        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(L10n.t("status.blocks", 12), "12 Blöcke")
    }

    /// Nothing user-visible should be missing a translation and fall through to
    /// the key, which is what an unknown key returns.
    func testUnknownKeyIsVisiblyWrong() {
        XCTAssertEqual(L10n.t("no.such.key"), "no.such.key")
    }

    private static func placeholders(in text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfs]")
        let range = NSRange(text.startIndex..., in: text)
        return pattern?.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        } ?? []
    }
}
