import Foundation
import ModRunnerKit

/// Carries settings across the renamings of the classic skin and of the two
/// palettes.
///
/// The skin's stored value and two of the window keys were built from its case
/// name, so renaming the case renamed the keys with it. Without this, everyone
/// who had the old skin selected would find themselves in the native one, with
/// the window back at its default size in the middle of the screen — a change
/// they did not ask for and cannot easily reverse.
///
/// The palettes were renamed the same way, one release later, and their stored
/// value is a case name too.
///
/// Each pass runs once, before anything reads a default, and records that it
/// has: a second pass would overwrite a fresh choice with a stale one.
enum DefaultsMigration {

    private static let doneKey = "migrated.classicSkinRename"
    private static let paletteDoneKey = "migrated.paletteRename"

    /// The palettes used to be named after the projects their tokens came
    /// from. They are named after their own colours now, and the stored value
    /// went with the case name.
    private static let renamedPalettes = [
        "incudex": Palette.ember.rawValue,
        "lasse": Palette.neon.rawValue,
    ]

    /// Old key or value on the left, new one on the right.
    private static let renamedValues = ["amiga": Skin.classic.rawValue]
    private static let renamedKeys = [
        "windowExtraHeight.amiga": "windowExtraHeight.\(Skin.classic.rawValue)",
        "windowOrigin.amiga": "windowOrigin.\(Skin.classic.rawValue)",
    ]

    static func run(_ defaults: UserDefaults = .standard) {
        migratePalette(defaults)

        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        if let stored = defaults.string(forKey: Skin.storageKey),
           let replacement = renamedValues[stored] {
            defaults.set(replacement, forKey: Skin.storageKey)
        }

        for (old, new) in renamedKeys {
            // Only if the new key is still empty. If the app has already run
            // under the new name, whatever it stored there is the current
            // truth and the leftover is not.
            guard defaults.object(forKey: new) == nil,
                  let value = defaults.object(forKey: old) else { continue }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
        }
    }

    /// Its own pass, with its own marker: the skin rename shipped first, so
    /// anyone who has already run that migration would otherwise never see
    /// this one.
    private static func migratePalette(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: paletteDoneKey) else { return }
        defer { defaults.set(true, forKey: paletteDoneKey) }

        guard let stored = defaults.string(forKey: Palette.storageKey),
              let replacement = renamedPalettes[stored] else { return }
        defaults.set(replacement, forKey: Palette.storageKey)
    }
}
