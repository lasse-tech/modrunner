import Foundation

/// The menu, the way Intuition did it: hold the right button and the window's
/// title bar becomes a strip of menu titles; the title under the pointer drops
/// its items open; release over an item to choose it, release anywhere else and
/// nothing happened.
///
/// Not how Windows or X11 do menus, and that is the point. A Workbench window
/// spends no pixels on a menu bar it is not using, and the player has a fixed
/// height with no room to spare. The strip borrows the title bar for as long as
/// the button is down and gives it straight back.

public enum MenuRole {
    case openFiles, openDrawer, about, quit
    case playPause, stop
    case previousPosition, nextPosition
    case previousModule, nextModule
    case showTracker
    case minimise, sendToBack
    /// The two layout switches, the same pair the View menu has on macOS.
    case fullScreen, miniPlayer
    case visualisation(PlayerScreen.Visualisation)
}

public struct MenuEntry {
    public let title: String
    public let role: MenuRole
    /// Drawn as a tick to the left of the title, for the items that are a state
    /// rather than an action.
    public let checked: Bool

    public init(title: String, role: MenuRole, checked: Bool = false) {
        self.title = title
        self.role = role
        self.checked = checked
    }
}

public struct MenuHeading {
    public let title: String
    public let entries: [MenuEntry]

    public init(title: String, entries: [MenuEntry]) {
        self.title = title
        self.entries = entries
    }
}

extension PlayerScreen {

    /// Which title is open and which item is under the pointer. A screen whose
    /// `menu` is nil is a screen with no menu showing, which is nearly all of
    /// them — the strip only exists while the button is held.
    public struct MenuSelection: Equatable {
        public var heading: Int?
        public var entry: Int?

        public init(heading: Int? = nil, entry: Int? = nil) {
            self.heading = heading
            self.entry = entry
        }
    }
}

extension PlayerScreenRenderer {

    static let menuRowHeight = 12

    /// What the menu offers. Built from the screen rather than declared once,
    /// so Play/Pause says which one it will do and Show Tracker carries its
    /// tick. Every item does something: an Amiga menu full of greyed-out
    /// promises would be worse than no menu.
    public static func menu(for screen: PlayerScreen) -> [MenuHeading] {
        [
            MenuHeading(title: "Project", entries: [
                MenuEntry(title: "Open Files...", role: .openFiles),
                MenuEntry(title: "Open Drawer...", role: .openDrawer),
                MenuEntry(title: "About...", role: .about),
                MenuEntry(title: "Quit", role: .quit)
            ]),
            MenuHeading(title: "Window", entries: [
                MenuEntry(title: "Hide", role: .minimise),
                MenuEntry(title: "Behind", role: .sendToBack)
            ]),
            MenuHeading(title: "Play", entries: [
                MenuEntry(title: screen.isPlaying ? "Pause" : "Play", role: .playPause),
                MenuEntry(title: "Stop", role: .stop),
                MenuEntry(title: "Previous Position", role: .previousPosition),
                MenuEntry(title: "Next Position", role: .nextPosition),
                MenuEntry(title: "Previous Module", role: .previousModule),
                MenuEntry(title: "Next Module", role: .nextModule)
            ]),
            MenuHeading(title: "View", entries: [
                MenuEntry(title: "Show Tracker", role: .showTracker, checked: screen.showTracker),
                MenuEntry(title: "Full Screen", role: .fullScreen,
                          checked: screen.layout == .stage),
                MenuEntry(title: "Mini Player", role: .miniPlayer,
                          checked: screen.layout == .mini)
            ] + PlayerScreen.Visualisation.allCases.map {
                MenuEntry(title: $0.title, role: .visualisation($0),
                          checked: screen.visualisation == $0)
            })
        ]
    }

    // MARK: - Where it sits

    public static func menuHeadingRects(for screen: PlayerScreen) -> [Rect] {
        var rects: [Rect] = []
        var x = Theme.bevel + 4
        for heading in menu(for: screen) {
            let boxWidth = Font.width(of: heading.title) + 12
            rects.append(Rect(x, 0, boxWidth, titleBarHeight))
            x += boxWidth
        }
        return rects
    }

    /// The dropped-open box under one title, kept on the canvas if the title is
    /// far enough right that its items would hang off the edge.
    public static func menuBox(forHeading index: Int, in screen: PlayerScreen) -> Rect {
        let headings = menu(for: screen)
        guard headings.indices.contains(index) else { return Rect(0, 0, 0, 0) }
        let entries = headings[index].entries
        let widest = entries.map { Font.width(of: $0.title) }.max() ?? 0
        let boxWidth = Theme.bevel * 2 + Font.cellWidth + 8 + widest + 8
        let x = Swift.max(0, Swift.min(menuHeadingRects(for: screen)[index].x,
                                       width(for: screen) - boxWidth))
        return Rect(x, titleBarHeight,
                    boxWidth, entries.count * menuRowHeight + Theme.bevel * 2)
    }

    public static func menuEntryRects(forHeading index: Int, in screen: PlayerScreen) -> [Rect] {
        let headings = menu(for: screen)
        guard headings.indices.contains(index) else { return [] }
        let inner = menuBox(forHeading: index, in: screen).inset(by: Theme.bevel)
        return headings[index].entries.indices.map {
            Rect(inner.x, inner.y + $0 * menuRowHeight, inner.width, menuRowHeight)
        }
    }

    /// Where the pointer is now, given where it was.
    ///
    /// The current selection is an input because Intuition's menu is a drag:
    /// crossing a title opens it, moving down into the items keeps it open, and
    /// wandering off the items leaves the title open rather than closing
    /// everything under the hand that is still holding the button.
    public static func menuSelection(at x: Int, y: Int,
                                     current: PlayerScreen.MenuSelection,
                                     in screen: PlayerScreen) -> PlayerScreen.MenuSelection {
        if y < titleBarHeight {
            let heading = menuHeadingRects(for: screen).firstIndex { x >= $0.x && x < $0.maxX }
            return PlayerScreen.MenuSelection(heading: heading, entry: nil)
        }
        guard let open = current.heading else { return current }
        let entry = menuEntryRects(forHeading: open, in: screen).firstIndex {
            x >= $0.x && x < $0.maxX && y >= $0.y && y < $0.maxY
        }
        return PlayerScreen.MenuSelection(heading: open, entry: entry)
    }

    // MARK: - Drawing it

    static func menuStrip(_ canvas: inout Canvas, _ screen: PlayerScreen,
                          _ selection: PlayerScreen.MenuSelection) {
        let headings = menu(for: screen)

        canvas.bevel(Rect(0, 0, width(for: screen), titleBarHeight), .raised)
        for (index, rect) in menuHeadingRects(for: screen).enumerated() {
            let open = selection.heading == index
            if open { canvas.fill(rect, Theme.highlight) }
            canvas.text(headings[index].title,
                        at: rect.x + 6, rect.y + (titleBarHeight - Font.cellHeight) / 2,
                        open ? Theme.highlightText : Theme.text,
                        maxWidth: rect.width - 12)
        }

        guard let open = selection.heading, headings.indices.contains(open) else { return }
        canvas.bevel(menuBox(forHeading: open, in: screen), .raised)
        for (index, rect) in menuEntryRects(forHeading: open, in: screen).enumerated() {
            let entry = headings[open].entries[index]
            let under = selection.entry == index
            if under { canvas.fill(rect, Theme.highlight) }
            let ink = under ? Theme.highlightText : Theme.text
            if entry.checked { tick(&canvas, at: rect.x + 4, rect.y + 2, ink) }
            canvas.text(entry.title,
                        at: rect.x + Font.cellWidth + 8,
                        rect.y + (menuRowHeight - Font.cellHeight) / 2, ink,
                        maxWidth: rect.width - Font.cellWidth - 12)
        }
    }

    /// A checkmark, drawn rather than typed: the font is the Topaz-alike used
    /// for everything else and has no glyph for one.
    private static func tick(_ canvas: inout Canvas, at x: Int, _ y: Int, _ colour: Colour) {
        for step in 0..<3 { canvas.fill(Rect(x + step, y + 3 + step, 1, 2), colour) }
        for step in 0..<4 { canvas.fill(Rect(x + 3 + step, y + 5 - step, 1, 2), colour) }
    }
}
