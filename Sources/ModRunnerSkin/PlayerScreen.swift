import Foundation
import ModRunnerKit

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

    /// Which of the three shapes the player is in. The same three the macOS app
    /// has, so the Mini and Full gadgets mean the same thing on both.
    public var layout: Layout = .window
    /// How much room the stage has, when the window has the whole screen. Only
    /// the stage layout reads it.
    public var stageWidth = 1280
    public var stageHeight = 720

    /// A window of the mixed output as it is being heard, for the scope and the
    /// ripple. Empty means there is nothing to trace.
    public var waveform: [Float] = []
    public var visualisation: Visualisation = .levels

    /// The help text under the pointer, and where the pointer was when it was
    /// asked for. Drawn last, over everything — which is what a tool tip is.
    public var tooltip: Tooltip?

    /// Set while the right button is held, and nil the rest of the time: the
    /// menu borrows the title bar rather than living anywhere.
    public var menu: MenuSelection?

    /// The About requester, which blocks the window under it while it is up.
    public var showAbout = false

    /// The window, the strip that stays out of the way, and the whole screen.
    public enum Layout: String, CaseIterable, Sendable {
        case window, mini, stage
    }

    public struct Tooltip {
        public var text: String
        public var x: Int
        public var y: Int

        public init(text: String, x: Int, y: Int) {
            self.text = text
            self.x = x
            self.y = y
        }
    }

    public init() {}
}

/// Draws the whole classic window into a canvas.
///
/// The measurements follow the macOS skin — 560 points wide, the same panel
/// order, the same eight-pixel gutter — so the two are recognisably one
/// interface rather than two programs that happen to share a name.
public enum PlayerScreenRenderer {

    /// The window layout's width. The other two have their own: the strip is
    /// narrower, and the stage is however big the screen turned out to be.
    public static let width = 560
    public static let miniWidth = 340

    /// How wide the canvas has to be for this screen. Everything that opens or
    /// resizes a window asks here rather than assuming the one width, which is
    /// what stops the hit testing and the picture from drifting apart.
    public static func width(for screen: PlayerScreen) -> Int {
        switch screen.layout {
        case .window: return width
        case .mini:   return miniWidth
        case .stage:  return Swift.max(width, screen.stageWidth)
        }
    }

    static let margin = 8
    static let gap = 8
    // Not private: the menu strip in Menu.swift borrows this bar.
    static let titleBarHeight = 22
    static let songHeight = 40
    static let statusHeight = 34
    private static let meterRowHeight = 16
    static let positionHeight = 34
    static let transportHeight = 32
    static let transportButtonWidth = 34
    static let viewOptionsHeight = 30
    static let playlistRowHeight = 12
    /// Room for the VIEW caption at the left of the options row. Eight cells,
    /// because the German for it is seven characters long.
    private static let captionWidth = 8 * Font.cellWidth
    static let trackerRowHeight = 10

    public static func height(for screen: PlayerScreen) -> Int {
        switch screen.layout {
        case .window: return windowHeight(for: screen)
        case .mini:   return miniHeight
        case .stage:  return Swift.max(240, screen.stageHeight)
        }
    }

    private static func windowHeight(for screen: PlayerScreen) -> Int {
        var total = titleBarHeight + margin * 2
        total += songHeight + gap
        total += statusHeight + gap
        if screen.showTracker {
            total += trackerPanelHeight(rows: screen.trackerRows.count) + gap
        }
        total += visualiserHeight(channels: screen.meters.count) + gap
        total += positionHeight + gap
        total += transportHeight + gap
        total += viewOptionsHeight + gap
        total += playlistHeight(rows: screen.playlist.count)
        return total
    }

    private static func trackerPanelHeight(rows: Int) -> Int {
        Theme.bevel * 2 + 4 + Font.cellHeight + 2 + Swift.max(1, rows) * trackerRowHeight + 4
    }

    /// One height for all three visualisations, so switching between them does
    /// not change the size of the window.
    private static func visualiserHeight(channels: Int) -> Int {
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
    public enum ControlRole: Equatable {
        case previousModule, previousPosition, playPause, stop, nextPosition, nextModule
        case tracker, songPosition
        /// The Amiga output filter, which on the machine itself was switched by
        /// the power LED -- which is what the gadget is still called.
        case filter
        /// The Load gadget, the same thing as Project > Open Files.
        case openFiles
        /// The gadget that cycles the visualisation, and separately the panel
        /// it draws in — clicking the picture changes it too, which is the only
        /// way to change it in the layouts that have no VIEW row. Two roles for
        /// two rectangles: one control that answered to both would be reported
        /// twice and found in whichever order the list happened to be in.
        case visualiser, visualiserPanel
        /// The two that switch layout: the strip and the whole screen.
        case miniPlayer, fullScreen
        /// The output level, which was drawn long before anything read it.
        case volume
        /// One line of the playlist. Clicking it plays that module — the only
        /// thing the list was ever going to be for.
        case playlistEntry(Int)
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
        switch screen.layout {
        case .window: return windowControls(for: screen)
        case .mini:   return miniControls(for: screen)
        case .stage:  return stageControls(for: screen)
        }
    }

    private static func windowControls(for screen: PlayerScreen) -> [Control] {
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

        controls.append(Control(rect: volumeSlider(in: stack.transport), role: .volume))
        controls.append(Control(rect: stack.visualiser, role: .visualiserPanel))

        for gadget in viewGadgets(for: screen, in: stack.viewOptions) {
            controls.append(Control(rect: gadget.rect, role: gadget.role))
        }
        for row in playlistRows(for: screen, in: stack.playlist) {
            controls.append(Control(rect: row.rect, role: .playlistEntry(row.index)))
        }
        return controls
    }

    /// Where each panel sits. The renderer and the hit testing both come from
    /// here, so there is one answer rather than two.
    private struct Panels {
        var song = Rect(0, 0, 0, 0)
        var status = Rect(0, 0, 0, 0)
        var tracker: Rect?
        var visualiser = Rect(0, 0, 0, 0)
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

        panels.visualiser = Rect(x, y, contentWidth,
                                 visualiserHeight(channels: screen.meters.count))
        y = panels.visualiser.maxY + gap

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
        var canvas: Canvas
        switch screen.layout {
        case .window: canvas = renderWindow(screen)
        case .mini:   canvas = renderMini(screen)
        case .stage:  canvas = renderStage(screen)
        }

        if screen.showAbout {
            about(&canvas, screen)
        }
        // Last, so it covers what it drops over.
        if let selection = screen.menu {
            menuStrip(&canvas, screen, selection)
        }
        drawTooltip(&canvas, screen)
        return canvas
    }

    private static func renderWindow(_ screen: PlayerScreen) -> Canvas {
        var canvas = Canvas(width: width, height: height(for: screen), fill: Theme.faceDark)
        let stack = panels(for: screen)

        _ = titleBar(&canvas, screen, y: 0)
        _ = song(&canvas, screen, stack.song)
        _ = status(&canvas, screen, stack.status)
        if let panel = stack.tracker {
            _ = tracker(&canvas, screen, panel)
        }
        VisualiserRenderer.draw(&canvas, screen, in: stack.visualiser)
        _ = songPosition(&canvas, screen, stack.songPosition)
        _ = transport(&canvas, screen, stack.transport)
        _ = viewOptions(&canvas, screen, stack.viewOptions)
        _ = playlist(&canvas, screen, stack.playlist)
        return canvas
    }

    // MARK: - Panels

    /// Close on the left, iconify / zoom / depth on the right — the arrangement
    /// a hand trained on 16-bit desktops reaches for. The glyphs themselves are
    /// the app's own; `Canvas.gadget` draws them, so this side and the SwiftUI
    /// side cannot end up with different pictures on the same button.
    static func titleBar(_ canvas: inout Canvas, _ screen: PlayerScreen, y: Int) -> Int {
        let barWidth = width(for: screen)
        canvas.bevel(Rect(0, y, barWidth, titleBarHeight), .raised)

        let gadget = titleBarHeight
        canvas.gadget(Rect(0, y, gadget, gadget), .close)

        canvas.text(screen.windowTitle, at: gadget + 8, y + (titleBarHeight - Font.cellHeight) / 2,
                    Theme.text, maxWidth: barWidth - gadget * 4 - 16)

        for (slot, kind) in [(3, Theme.Gadget.iconify), (2, .zoom), (1, .depth)] {
            canvas.gadget(Rect(barWidth - gadget * slot, y, gadget, gadget), kind)
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
        canvas.slider(volumeSlider(in: rect), value: screen.volume)
        return rect.maxY
    }

    /// Where the volume slider sits inside the transport panel.
    ///
    /// The same bargain the view gadgets make. It was drawn from one set of
    /// numbers and hit-tested from none at all, which is why it moved and
    /// nothing happened.
    static func volumeSlider(in rect: Rect) -> Rect {
        let inner = rect.inset(by: Theme.bevel + 2)
        let afterButtons = inner.x + 6 * (transportButtonWidth + 4)
        let x = afterButtons + 6 + 4 * Font.cellWidth
        return Rect(x, inner.y + 2, Swift.max(0, inner.maxX - x - 4), inner.height - 4)
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
            (.tracker, L10n.t("button.tracks"), 66, screen.showTracker),
            (.filter, L10n.t("button.filter"), 44, screen.filterEnabled),
            (.openFiles, L10n.t("button.load"), 52, false),
            // Named after what it is showing rather than after what it does,
            // which is how the app's picker reads too.
            (.visualiser, screen.visualisation.title, 88, false)
        ]

        var gadgets: [(role: ControlRole, rect: Rect, label: String, on: Bool)] = []
        var x = inner.x + captionWidth
        for entry in entries {
            gadgets.append((entry.role, Rect(x, inner.y, entry.width, inner.height),
                            entry.label, entry.on))
            x += entry.width + 6
        }

        // The two on the right, which switch layout. They used to be drawn here
        // and registered nowhere, with a comment explaining that the portable
        // interface could not do either one yet. It can now.
        var right = inner.maxX
        let switches: [(role: ControlRole, label: String, width: Int, on: Bool)] = [
            (.fullScreen, L10n.t("button.fullScreen"), 52, screen.layout == .stage),
            (.miniPlayer, L10n.t("button.miniPlayer"), 52, screen.layout == .mini)
        ]
        for entry in switches {
            right -= entry.width
            gadgets.append((entry.role, Rect(right, inner.y, entry.width, inner.height),
                            entry.label, entry.on))
            right -= 6
        }
        return gadgets
    }

    private static func viewOptions(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        canvas.text(L10n.t("player.view"), at: inner.x,
                    inner.y + (inner.height - Font.cellHeight) / 2, Theme.text,
                    maxWidth: captionWidth - 6)
        for gadget in viewGadgets(for: screen, in: rect) {
            canvas.button(gadget.rect, gadget.label, on: gadget.on)
        }

        return rect.maxY
    }

    /// The recessed box the entries are listed in.
    private static func playlistBox(in rect: Rect) -> Rect {
        let inner = rect.inset(by: Theme.bevel + 2)
        let top = inner.y + Font.cellHeight + 2
        return Rect(inner.x, top, inner.width, inner.maxY - top - 22)
    }

    /// Where each entry that fits sits, for the drawing and the hit testing
    /// both. Without this the list was a picture of a playlist: it showed which
    /// module was playing and there was no way to say which one should.
    static func playlistRows(for screen: PlayerScreen,
                             in rect: Rect) -> [(index: Int, rect: Rect)] {
        let list = playlistBox(in: rect)
        let listInner = list.inset(by: Theme.bevel + 2)
        var rows: [(index: Int, rect: Rect)] = []
        for index in screen.playlist.indices {
            let y = listInner.y + index * playlistRowHeight
            guard y + playlistRowHeight <= listInner.maxY else { break }
            rows.append((index, Rect(list.x + Theme.bevel, y - 1,
                                     list.width - Theme.bevel * 2, playlistRowHeight)))
        }
        return rows
    }

    private static func playlist(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Theme.bevel + 2)

        canvas.text("MODULES  —  drop files or a drawer here", at: inner.x, inner.y,
                    Theme.text, maxWidth: inner.width)

        let list = playlistBox(in: rect)
        canvas.bevel(list, .recessed, fill: Theme.sunken)

        for row in playlistRows(for: screen, in: rect) {
            let selected = row.index == screen.currentIndex
            if selected { canvas.fill(row.rect, Theme.highlight) }
            canvas.text(screen.playlist[row.index], at: row.rect.x + 4, row.rect.y + 1,
                        selected ? Theme.highlightText : Theme.text,
                        maxWidth: row.rect.width - 8)
        }

        canvas.readout(Rect(inner.x, inner.maxY - 18, inner.width, 18), screen.status)
        return rect.maxY
    }
}
