import Foundation

/// Carries settings across the renaming of the classic skin.
///
/// The skin's stored value and two of the window keys were built from its case
/// name, so renaming the case renamed the keys with it. Without this, everyone
/// who had the old skin selected would find themselves in the native one, with
/// the window back at its default size in the middle of the screen — a change
/// they did not ask for and cannot easily reverse.
///
/// Runs once, before anything reads a default, and records that it has: a
/// second pass would overwrite a fresh choice with a stale one.
enum DefaultsMigration {

    private static let doneKey = "migrated.classicSkinRename"

    /// Old key or value on the left, new one on the right.
    private static let renamedValues = ["amiga": Skin.classic.rawValue]
    private static let renamedKeys = [
        "windowExtraHeight.amiga": "windowExtraHeight.\(Skin.classic.rawValue)",
        "windowOrigin.amiga": "windowOrigin.\(Skin.classic.rawValue)",
    ]

    static func run(_ defaults: UserDefaults = .standard) {
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
}
