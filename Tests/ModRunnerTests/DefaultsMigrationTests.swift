#if os(macOS)
import XCTest
@testable import ModRunnerApp
@testable import ModRunnerKit

/// Renaming the classic skin renamed three stored settings with it, because all
/// three were built from the case name. Everyone who had that skin selected
/// would otherwise have found themselves in the native one, with the window
/// back at its default size in the middle of the screen.
final class DefaultsMigrationTests: XCTestCase {

    /// A defaults domain of its own, so the suite never touches the settings of
    /// whoever is running it.
    private var defaults: UserDefaults!
    private let suiteName = "de.modrunner.tests.migration"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testTheOldSkinNameBecomesTheNewOne() {
        defaults.set("amiga", forKey: Skin.storageKey)
        DefaultsMigration.run(defaults)
        XCTAssertEqual(defaults.string(forKey: Skin.storageKey), Skin.classic.rawValue)
    }

    func testTheNativeSkinIsLeftAlone() {
        defaults.set(Skin.native.rawValue, forKey: Skin.storageKey)
        DefaultsMigration.run(defaults)
        XCTAssertEqual(defaults.string(forKey: Skin.storageKey), Skin.native.rawValue)
    }

    func testTheWindowKeepsItsSizeAndPosition() {
        defaults.set(140.0, forKey: "windowExtraHeight.amiga")
        defaults.set(["x": 320.0, "y": 180.0], forKey: "windowOrigin.amiga")

        DefaultsMigration.run(defaults)

        XCTAssertEqual(defaults.double(forKey: "windowExtraHeight.classic"), 140)
        let origin = defaults.dictionary(forKey: "windowOrigin.classic")
        XCTAssertEqual(origin?["x"] as? Double, 320)
        XCTAssertEqual(origin?["y"] as? Double, 180)

        // The old keys are gone, so a later pass has nothing to find.
        XCTAssertNil(defaults.object(forKey: "windowExtraHeight.amiga"))
        XCTAssertNil(defaults.object(forKey: "windowOrigin.amiga"))
    }

    /// The one that would hurt: a second run must not put a stale value back
    /// over a choice the user has since made.
    func testItRunsOnlyOnce() {
        defaults.set("amiga", forKey: Skin.storageKey)
        DefaultsMigration.run(defaults)

        defaults.set(Skin.native.rawValue, forKey: Skin.storageKey)
        defaults.set("amiga", forKey: "leftover")
        DefaultsMigration.run(defaults)

        XCTAssertEqual(defaults.string(forKey: Skin.storageKey), Skin.native.rawValue)
    }

    func testTheOldPaletteNamesBecomeTheNewOnes() {
        defaults.set("incudex", forKey: Palette.storageKey)
        DefaultsMigration.run(defaults)
        XCTAssertEqual(defaults.string(forKey: Palette.storageKey), Palette.ember.rawValue)

        defaults.set(false, forKey: "migrated.paletteRename")
        defaults.set("lasse", forKey: Palette.storageKey)
        DefaultsMigration.run(defaults)
        XCTAssertEqual(defaults.string(forKey: Palette.storageKey), Palette.neon.rawValue)
    }

    /// The palette pass has a marker of its own, so it still runs for someone
    /// who has already been through the skin rename.
    func testThePaletteIsCarriedAfterTheSkinPassHasRun() {
        defaults.set(true, forKey: "migrated.classicSkinRename")
        defaults.set("incudex", forKey: Palette.storageKey)

        DefaultsMigration.run(defaults)

        XCTAssertEqual(defaults.string(forKey: Palette.storageKey), Palette.ember.rawValue)
    }

    func testThePaletteRunsOnlyOnce() {
        defaults.set("incudex", forKey: Palette.storageKey)
        DefaultsMigration.run(defaults)

        defaults.set(Palette.neon.rawValue, forKey: Palette.storageKey)
        DefaultsMigration.run(defaults)

        XCTAssertEqual(defaults.string(forKey: Palette.storageKey), Palette.neon.rawValue)
    }

    /// A value already stored under the new key is the current truth; the
    /// leftover under the old one is not.
    func testAnExistingNewValueWins() {
        defaults.set(140.0, forKey: "windowExtraHeight.amiga")
        defaults.set(60.0, forKey: "windowExtraHeight.classic")

        DefaultsMigration.run(defaults)

        XCTAssertEqual(defaults.double(forKey: "windowExtraHeight.classic"), 60)
    }
}
#endif
