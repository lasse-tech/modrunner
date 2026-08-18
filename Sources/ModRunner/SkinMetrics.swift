import SwiftUI
import ModRunnerKit

/// The window's measurements, and the one preference both skins read.
///
/// These used to live on the classic skin's view, which meant the native path
/// called into the other skin's type for its own window size and for the state
/// of a menu item. Deleting or renaming that view would have taken the native
/// skin with it. They belong to neither skin, so they live on their own.
///
/// Deliberately not `@MainActor`: `WindowChrome` is a plain enum and reads
/// these while sizing the window. For the same reason the tracker's height
/// comes from `TrackerLayout`, which is a plain struct, rather than from
/// `TrackerView` — a `View` is main-actor isolated by its conformance, and
/// reaching into one from here would be an error under the Swift 6 language
/// mode.
enum SkinMetrics {

    /// The classic skin is drawn for one width and nothing in it stretches
    /// sideways, so the width is pinned and only the height is the user's.
    static let windowWidth: CGFloat = 560

    /// The height without the module list's slack, tracker panel excluded.
    private static let baseHeight: CGFloat = 486 + ClassicViewOptions.height

    /// One entry in the module list: the title and its padding.
    private static let playlistRow: CGFloat = 19

    /// How tall the list is at the height the window opens at — with the
    /// module's own annotation on show, which is the shorter of the two cases
    /// and so the one the minimum has to survive.
    private static let playlistHeight: CGFloat = 103

    /// Three entries, whole, is as small as the list is allowed to get.
    private static let playlistFloor: CGFloat = 3 * playlistRow + 6

    /// How far the window can be dragged shorter, all of it out of the list.
    static let playlistFlex: CGFloat = playlistHeight - playlistFloor

    /// The height the window opens at.
    static func windowHeight(showingTracker: Bool) -> CGFloat {
        showingTracker ? baseHeight + TrackerLayout.panel.height + 8 : baseHeight
    }

    static func minimumHeight(showingTracker: Bool) -> CGFloat {
        windowHeight(showingTracker: showingTracker) - playlistFlex
    }

    /// Whether the tracker panel was visible when the app last ran. Both skins
    /// honour it, and the View menu shows its state.
    static var trackerVisiblePreference: Bool {
        UserDefaults.standard.object(forKey: "showTracker") as? Bool ?? true
    }
}
