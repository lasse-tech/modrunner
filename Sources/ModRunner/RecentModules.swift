import Foundation
import ModRunnerKit

/// The modules that were played most recently, for the File menu.
///
/// Deliberately not `NSDocumentController`'s recent-documents list: this app is
/// not document-based, and its list should follow what was actually *played*
/// rather than what was opened — a folder drop loads twenty modules and plays
/// one.
@MainActor
enum RecentModules {

    struct Entry {
        let url: URL
        /// The module's own title, which is usually more use than its file name
        /// — Amiga modules are full of names like `mod.stardust`.
        let title: String
    }

    static let limit = 12
    private static let storageKey = "recentModules"

    static var entries: [Entry] {
        let stored = UserDefaults.standard.array(forKey: storageKey) as? [[String: String]] ?? []
        return stored.compactMap { item in
            guard let path = item["path"] else { return nil }
            let url = URL(fileURLWithPath: path)
            return Entry(url: url, title: item["title"] ?? url.lastPathComponent)
        }
    }

    /// Records a module at the top of the list, moving it up if it is already
    /// there. Modules that have since been deleted are dropped on the way past.
    static func record(url: URL, title: String) {
        var items = entries
            .filter { $0.url != url && FileManager.default.fileExists(atPath: $0.url.path) }
        items.insert(Entry(url: url, title: title), at: 0)
        write(Array(items.prefix(limit)))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func write(_ items: [Entry]) {
        let stored = items.map { ["path": $0.url.path, "title": $0.title] }
        UserDefaults.standard.set(stored, forKey: storageKey)
    }
}
