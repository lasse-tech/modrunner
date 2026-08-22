import Foundation

/// Everything the skin draws, as plain values.
///
/// No module, no replayer, no clock: the renderer is handed strings and levels
/// and paints them. That is what lets a test draw a whole window without an
/// audio device, and what keeps the drawing code from growing opinions about
/// where the numbers came from.
public struct PlayerScreen {

    public struct TrackerRow {
        public var line: Int
        /// One cell per track, already written out: "C-3 04 0C10".
        public var cells: [String]
        public var isCurrent: Bool

        public init(line: Int, cells: [String], isCurrent: Bool = false) {
            self.line = line
            self.cells = cells
            self.isCurrent = isCurrent
        }
    }

    public var windowTitle = "ModRunner"
    public var moduleTitle = "— no module —"

    public var position = "--/--"
    public var block = "--"
    public var line = "--/--"
    public var tempo = "--/-"
    public var beatsPerMinute = "---"
    public var time = "0:00"

    public var trackerRows: [TrackerRow] = []
    public var trackCount = 4
    public var showTracker = true
    /// Whether the Amiga output filter is on, so the LED gadget can show it.
    public var filterEnabled = false

    public var meters: [Float] = [0, 0, 0, 0]
    public var progress = 0.0
    public var volume = 1.0
    public var isPlaying = false

    public var playlist: [String] = []
    public var currentIndex: Int?
    public var status = ""

    /// Set while the right button is held, and nil the rest of the time: the
    /// menu borrows the title bar rather than living anywhere.
    public var menu: MenuSelection?

    /// The About requester, which blocks the window under it while it is up.
    public var showAbout = false

    public init() {}
}

/// Draws the whole classic window into a canvas.
///
/// The measurements follow the macOS skin — 560 points wide, the same panel
/// order, the same eight-pixel gutter — so the two are recognisably one
/// interface rather than two programs that happen to share a name.
public enum PlayerScreenRenderer {

    public static let width = 560

    private static let margin = 8
    private static let gap = 8
    // Not private: the menu strip in Menu.swift borrows this bar.
    static let titleBarHeight = 22
    private static let songHeight = 40
    private static let statusHeight = 34
    private static let meterRowHeight = 16
    private static let positionHeight = 34
    private static let transportHeight = 32
    private static let transportButtonWidth = 34
    private static let viewOptionsHeight = 30
    private static let playlistRowHeight = 12
    private static let trackerRowHeight = 10

    public static func height(for screen: PlayerScreen) -> Int {
        var total = titleBarHeight + margin * 2
        total += songHeight + gap
        total += statusHeight + gap
        if screen.showTracker {
            total += trackerPanelHeight(rows: screen.trackerRows.count) + gap
        }
        total += metersHeight(channels: screen.meters.count) + gap
        total += positionHeight + gap
        total += transportHeight + gap
        total += viewOptionsHeight + gap
        total += playlistHeight(rows: screen.playlist.count)
        return total
    }

    private static func trackerPanelHeight(rows: Int) -> Int {
        Theme.bevel * 2 + 4 + Font.cellHeight + 2 + Swift.max(1, rows) * trackerRowHeight + 4
    }

    private static func metersHeight(channels: Int) -> Int {
        Theme.bevel * 2 + 4 + Swift.max(1, channels) * meterRowHeight + 4
    }

    private static func playlistHeight(rows: Int) -> Int {
        let list = Swift.max(4, rows) * playlistRowHeight + 8
        return Theme.bevel * 2 + 4 + Font.cellHeight + 2 + list + 4 + 18 + 4
    }

    /// A control the user can hit, and what it is for.
    ///
    /// The skin draws; it does not handle input. But it is the only thing that
    /// knows where it put the play button, so it says — and the window layer
    /// asks. That keeps one description of the layout instead of two that
    /// drift until the buttons stop matching their hit boxes.
    public enum ControlRole {
        case previousModule, previousPosition, playPause, stop, nextPosition, nextModule
        case tracker, songPosition
        /// The Amiga output filter, which on the machine itself was switched by
        /// the power LED -- which is what the gadget is still called.
        case filter
        /// The Load gadget, the same thing as Project > Open Files.
        case openFiles
        /// The title bar. Its gadgets are the whole of the window chrome on the
        /// platforms that hide the system one, so they have to be reachable
        /// here rather than being pixels that happen to look like buttons.
        case close, minimise, zoom, depth, titleBar
        /// The About requester's OK gadget.
        case dismissAbout
    }

    public struct Control {
        public let rect: Rect
        public let role: ControlRole
    }

    public static func controls(for screen: PlayerScreen) -> [Control] {
        // A requester blocks the window under it, the way Intuition's did. It
        // is done by leaving the other controls out rather than by a flag the
        // event handling has to remember, so there is nothing to forget.
        if screen.showAbout {
            return [Control(rect: aboutButton(for: screen), role: .dismissAbout)]
        }

        let stack = panels(for: screen)
        var controls: [Control] = []

        // The title bar, laid out exactly as `titleBar(_:_:y:)` draws it. The
        // gadgets go in before the bar itself, because the bar covers them and
        // hit testing takes the first rectangle that matches.
        let gadget = titleBarHeight
        controls.append(Control(rect: Rect(0, 0, gadget, gadget), role: .close))
        controls.append(Control(rect: Rect(width - gadget * 3, 0, gadget, gadget), role: .minimise))
        controls.append(Control(rect: Rect(width - gadget * 2, 0, gadget, gadget), role: .zoom))
        controls.append(Control(rect: Rect(width - gadget, 0, gadget, gadget), role: .depth))
        controls.append(Control(rect: Rect(0, 0, width, titleBarHeight), role: .titleBar))

        let transport = stack.transport.inset(by: Theme.bevel + 2)
        let roles: [ControlRole] = [.previousModule, .previousPosition, .playPause,
                                     .stop, .nextPosition, .nextModule]
        for (index, role) in roles.enumerated() {
            controls.append(Control(rect: Rect(transport.x + index * (transportButtonWidth + 4),
                                               transport.y, transportButtonWidth, transport.height),
                                    role: role))
        }

        let position = stack.songPosition.inset(by: Theme.bevel + 2)
        controls.append(Control(rect: Rect(position.x, position.y + Font.cellHeight + 2,
                                           position.width, position.height - Font.cellHeight - 2),
                                role: .songPosition))

        for gadget in viewGadgets(for: screen, in: stack.viewOptions) {
            controls.append(Control(rect: gadget.rect, role: gadget.role))
        }
        return controls
    }

    /// Where each panel sits. The renderer and the hit testing both come from
    /// here, so there is one answer rather than two.
    private struct Panels {
        var song = Rect(0, 0, 0, 0)
        var status = Rect(0, 0, 0, 0)
        var tracker: Rect?
        var meters = Rect(0, 0, 0, 0)
        var songPosition = Rect(0, 0, 0, 0)
        var transport = Rect(0, 0, 0, 0)
        var viewOptions = Rect(0, 0, 0, 0)
        var playlist = Rect(0, 0, 0, 0)
    }

    private static func panels(for screen: PlayerScreen) -> Panels {
        var panels = Panels()
        let x = margin
        let contentWidth = width - margin * 2
        var y = titleBarHeight + margin

        panels.song = Rect(x, y, contentWidth, songHeight)
        y = panels.song.maxY + gap

        panels.status = Rect(x, y, contentWidth, statusHeight)
        y = panels.status.maxY + gap

        if screen.showTracker {
            let panel = Rect(x, y, contentWidth, trackerPanelHeight(rows: screen.trackerRows.count))
            panels.tracker = panel
            y = panel.maxY + gap
        }

        panels.meters = Rect(x, y, contentWidth, metersHeight(channels: screen.meters.count))
        y = panels.meters.maxY + gap

        panels.songPosition = Rect(x, y, contentWidth, positionHeight)
        y = panels.songPosition.maxY + gap

        panels.transport = Rect(x, y, contentWidth, transportHeight)
        y = panels.transport.maxY + gap

        panels.viewOptions = Rect(x, y, contentWidth, viewOptionsHeight)
        y = panels.viewOptions.maxY + gap

        panels.playlist = Rect(x, y, contentWidth, playlistHeight(rows: screen.playlist.count))
        return panels
    }

    public static func render(_ screen: PlayerScreen) -> Canvas {
        var canvas = Canvas(width: width, height: height(for: screen), fill: Theme.faceDark)
        let stack = panels(for: screen)

        _ = titleBar(&canvas, screen, y: 0)
        _ = song(&canvas, screen, stack.song)
        _ = status(&canvas, screen, stack.status)
        if let panel = stack.tracker {
            _ = tracker(&canvas, screen, panel)
        }
        _ = meters(&canvas, screen, stack.meters)
        _ = songPosition(&canvas, screen, stack.songPosition)
        _ = transport(&canvas, screen, stack.transport)
        _ = viewOptions(&canvas, screen, stack.viewOptions)
        _ = playlist(&canvas, screen, stack.playlist)

        if screen.showAbout {
            about(&canvas, screen)
        }
        // Last, so it covers what it drops over.
        if let selection = screen.menu {
            menuStrip(&canvas, screen, selection)
        }

        return canvas
    }

    // MARK: - Panels

    /// Close on the left, iconify / zoom / depth on the right — the arrangement
    /// a hand trained on 16-bit desktops reaches for. The glyphs themselves are
    /// the app's own; `Canvas.gadget` draws them, so this side and the SwiftUI
    /// side cannot end up with different pictures on the same button.
    private static func titleBar(_ canvas: inout Canvas, _ screen: PlayerScreen, y: Int) -> Int {
        let bar = Rect(0, y, width, titleBarHeight)
        canvas.bevel(bar, .raised)

        let gadget = titleBarHeight
        canvas.gadget(Rect(0, y, gadget, gadget), .close)

        canvas.text(screen.windowTitle, at: gadget + 8, y + (titleBarHeight - Font.cellHeight) / 2,
                    Theme.text, maxWidth: width - gadget * 4 - 16)

        for (slot, kind) in [(3, Theme.Gadget.iconify), (2, .zoom), (1, .depth)] {
            canvas.gadget(Rect(width - gadget * slot, y, gadget, gadget), kind)
        }

        return y + titleBarHeight
    }

    private static func song(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        canvas.readout(rect.inset(by: Theme.bevel + 2), screen.moduleTitle)
        return rect.maxY
    }

    private static func status(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        let fields = [("POS", screen.position), ("BLOCK", screen.block), ("LINE", screen.line),
                      ("TEMPO", screen.tempo), ("BPM", screen.beatsPerMinute), ("TIME", screen.time)]
        let fieldWidth = (inner.width - (fields.count - 1) * 4) / fields.count

        for (index, field) in fields.enumerated() {
            canvas.field(Rect(inner.x + index * (fieldWidth + 4), inner.y, fieldWidth, inner.height),
                         caption: field.0, value: field.1)
        }
        return rect.maxY
    }

    private static func tracker(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .recessed, fill: Theme.sunken)
        let inner = rect.inset(by: Theme.bevel + 2)

        let lineColumn = 4 * Font.cellWidth
        let trackWidth = screen.trackCount > 0
            ? (inner.width - lineColumn) / screen.trackCount : inner.width

        canvas.text("LN", at: inner.x, inner.y, Theme.caption)
        for track in 0..<screen.trackCount {
            canvas.text("TRACK \(track + 1)", at: inner.x + lineColumn + track * trackWidth, inner.y,
                        Theme.caption, maxWidth: trackWidth - 4)
        }

        var y = inner.y + Font.cellHeight + 2
        for row in screen.trackerRows {
            if row.isCurrent {
                canvas.fill(Rect(rect.x + Theme.bevel, y - 1,
                                 rect.width - Theme.bevel * 2, trackerRowHeight), Theme.highlight)
            }
            let ink = row.isCurrent ? Theme.highlightText : Theme.text
            // A row scrolled in from before the start of the block, or past its
            // end, has no line number to show — the panel is a window onto the
            // pattern, not a list that pads itself out.
            if !row.cells.isEmpty {
                canvas.text(String(format: "%03d", row.line), at: inner.x, y,
                            row.isCurrent ? Theme.highlightText : Theme.caption)
            }
            for (track, cell) in row.cells.enumerated() where track < screen.trackCount {
                canvas.text(cell, at: inner.x + lineColumn + track * trackWidth, y, ink,
                            maxWidth: trackWidth - 4)
            }
            y += trackerRowHeight
        }
        return rect.maxY
    }

    private static func meters(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .recessed, fill: Theme.faceDark)
        let inner = rect.inset(by: Theme.bevel + 2)
        let labelWidth = 4 * Font.cellWidth

        for (index, level) in screen.meters.enumerated() {
            let y = inner.y + index * meterRowHeight
            canvas.text("CH\(index + 1)", at: inner.x, y + 2, Theme.text)
            canvas.meter(Rect(inner.x + labelWidth, y, inner.width - labelWidth, meterRowHeight - 3),
                         level: level)
        }
        return rect.maxY
    }

    private static func songPosition(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)
        canvas.text("SONG POSITION", at: inner.x, inner.y, Theme.text)
        canvas.slider(Rect(inner.x, inner.y + Font.cellHeight + 2,
                           inner.width, inner.height - Font.cellHeight - 2),
                      value: screen.progress)
        return rect.maxY
    }

    private static func transport(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        let labels = ["|<", "<<", screen.isPlaying ? "||" : ">", "[]", ">>", ">|"]
        var x = inner.x
        for label in labels {
            canvas.button(Rect(x, inner.y, transportButtonWidth, inner.height), label)
            x += transportButtonWidth + 4
        }

        canvas.text("VOL", at: x + 6, inner.y + (inner.height - Font.cellHeight) / 2, Theme.text)
        let volumeX = x + 6 + 4 * Font.cellWidth
        canvas.slider(Rect(volumeX, inner.y + 2, inner.maxX - volumeX - 4, inner.height - 4),
                      value: screen.volume)
        return rect.maxY
    }

    /// The gadgets in the VIEW row, laid out once.
    ///
    /// The same bargain `Panels` makes: the renderer draws from this and the
    /// hit testing registers from it, so a gadget cannot be painted on without
    /// also being clickable. Both used to carry their own copy of the widths,
    /// and LED and Load were only ever in the drawing one -- which is why they
    /// looked like buttons and did nothing.
    static func viewGadgets(for screen: PlayerScreen,
                            in rect: Rect) -> [(role: ControlRole, rect: Rect, label: String, on: Bool)] {
        let inner = rect.inset(by: Theme.bevel + 2)
        let entries: [(role: ControlRole, label: String, width: Int, on: Bool)] = [
            (.tracker, "Tracks", 66, screen.showTracker),
            (.filter, "LED", 44, screen.filterEnabled),
            (.openFiles, "Load", 52, false)
        ]

        var gadgets: [(role: ControlRole, rect: Rect, label: String, on: Bool)] = []
        var x = inner.x + 5 * Font.cellWidth
        for entry in entries {
            gadgets.append((entry.role, Rect(x, inner.y, entry.width, inner.height),
                            entry.label, entry.on))
            x += entry.width + 6
        }
        return gadgets
    }

    private static func viewOptions(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        canvas.text("VIEW", at: inner.x, inner.y + (inner.height - Font.cellHeight) / 2, Theme.text)
        for gadget in viewGadgets(for: screen, in: rect) {
            canvas.button(gadget.rect, gadget.label, on: gadget.on)
        }

        // Mini and Full are the two the portable interface cannot do yet: one
        // needs a full-screen mode in the window backends, the other a second
        // layout that does not exist outside the macOS app. They are drawn
        // because the row is the same row on both, and deliberately left out of
        // `viewGadgets` so nothing here claims they are wired up.
        var right = inner.maxX
        for (label, width) in [("Mini", 52), ("Full", 52)] {
            right -= width
            canvas.button(Rect(right, inner.y, width, inner.height), label)
            right -= 6
        }
        return rect.maxY
    }

    private static func playlist(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        canvas.text("MODULES  —  drop files or a drawer here", at: inner.x, inner.y,
                    Theme.text, maxWidth: inner.width)

        let listTop = inner.y + Font.cellHeight + 2
        let list = Rect(inner.x, listTop, inner.width, inner.maxY - listTop - 22)
        canvas.bevel(list, .recessed, fill: Theme.sunken)

        let listInner = list.inset(by: Theme.bevel + 2)
        for (index, entry) in screen.playlist.enumerated() {
            let y = listInner.y + index * playlistRowHeight
            guard y + playlistRowHeight <= listInner.maxY else { break }
            let selected = index == screen.currentIndex
            if selected {
                canvas.fill(Rect(list.x + Theme.bevel, y - 1,
                                 list.width - Theme.bevel * 2, playlistRowHeight), Theme.highlight)
            }
            canvas.text(entry, at: listInner.x + 2, y, selected ? Theme.highlightText : Theme.text,
                        maxWidth: listInner.width - 4)
        }

        canvas.readout(Rect(inner.x, inner.maxY - 18, inner.width, 18), screen.status)
        return rect.maxY
    }
}
