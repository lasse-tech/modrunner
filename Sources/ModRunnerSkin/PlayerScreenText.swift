import Foundation

/// One character of the text interface: what to draw, and in which two colours.
///
/// The same idea as a pixel, one step coarser. `TextCanvas` is to a terminal
/// what `Canvas` is to a window, and both are filled from the same
/// `PlayerScreen` — so the two pictures cannot describe different states.
public struct TextCell: Equatable {
    public var character: Character
    public var ink: Colour
    public var paper: Colour

    public init(character: Character = " ", ink: Colour = Theme.text, paper: Colour = Theme.face) {
        self.character = character
        self.ink = ink
        self.paper = paper
    }
}

/// A grid of characters with a colour each, drawn into and then handed to
/// whatever can put it on a terminal.
///
/// It knows nothing about escape sequences: that is the terminal's dialect, and
/// keeping it out of here is what lets a test assert on the picture without a
/// tty, exactly as `SkinTests` does with pixels.
public struct TextCanvas: Equatable {

    public let width: Int
    public let height: Int
    public private(set) var cells: [TextCell]

    public init(width: Int, height: Int, fill: TextCell = TextCell()) {
        self.width = Swift.max(0, width)
        self.height = Swift.max(0, height)
        self.cells = Array(repeating: fill, count: self.width * self.height)
    }

    public func cell(_ x: Int, _ y: Int) -> TextCell {
        guard x >= 0, x < width, y >= 0, y < height else { return TextCell() }
        return cells[y * width + x]
    }

    public mutating func set(_ x: Int, _ y: Int, _ cell: TextCell) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        cells[y * width + x] = cell
    }

    public mutating func fill(_ rect: Rect, _ cell: TextCell) {
        for y in Swift.max(0, rect.y)..<Swift.min(height, rect.maxY) {
            for x in Swift.max(0, rect.x)..<Swift.min(width, rect.maxX) {
                cells[y * width + x] = cell
            }
        }
    }

    /// Writes a string and returns the column after it. Anything past
    /// `maxWidth` is cut and marked, rather than spilling into the next panel.
    @discardableResult
    public mutating func text(_ string: String,
                              at x: Int,
                              _ y: Int,
                              ink: Colour = Theme.text,
                              paper: Colour = Theme.face,
                              maxWidth: Int? = nil) -> Int {
        let room = Swift.min(maxWidth ?? width, width - x)
        guard room > 0 else { return x }

        var characters = Array(string)
        if characters.count > room {
            characters = Array(characters.prefix(Swift.max(0, room - 1))) + ["…"]
        }
        for (offset, character) in characters.enumerated() {
            set(x + offset, y, TextCell(character: character, ink: ink, paper: paper))
        }
        return x + characters.count
    }

    /// One row as a string, for a test or for `--frames`, which writes the
    /// picture out with no colour at all.
    public func line(_ y: Int) -> String {
        guard y >= 0, y < height else { return "" }
        return String(cells[(y * width)..<((y + 1) * width)].map(\.character))
    }

    public var plainText: String {
        (0..<height).map { line($0) }.joined(separator: "\n")
    }
}

/// Draws the player as characters rather than as pixels.
///
/// The pixel skin is a fixed 560 points wide because a window can be whatever
/// size it likes; a terminal cannot, so this one lays itself out for the space
/// it is given. What it does not do is invent a second design: the panels are
/// the same panels in the same order, the bevel becomes a box rule, and every
/// colour still comes from `Theme`.
public enum PlayerScreenTextRenderer {

    /// Below this it stops being the same interface, and a sentence is more use
    /// than a picture squeezed into nothing.
    public static let minimumWidth = 48
    public static let minimumHeight = 16

    /// Rows that are there whatever else fits: two borders, the song readout,
    /// two rows of status fields, the position bar, the transport, the status
    /// line, and the rules between them.
    private static let fixedRows = 12

    private static let maxMeterRows = 8
    private static let maxPlaylistRows = 6

    /// One tracker cell, "C-3 04 0C10", and the gutter after it.
    private static let trackCellWidth = 13
    private static let lineNumberWidth = 4

    // MARK: - Layout

    /// Where every panel starts, in rows.
    ///
    /// Worked out once and read by both `render` and `controls`, for the same
    /// reason the pixel renderer has `panels(for:)`: two descriptions of a
    /// layout drift until the buttons stop matching their hit boxes.
    public struct Layout {
        public var width = 0
        public var height = 0

        public var songRow = 1
        public var captionRow = 3
        public var valueRow = 4

        /// The captioned rule above the panel; its header is one row below,
        /// and the note rows one below that.
        public var trackerRule: Int?
        public var trackerRows = 0

        public var meterRule: Int?
        public var meterRows = 0

        public var positionRow = 0
        public var transportRow = 0

        public var playlistRule: Int?
        public var playlistRows = 0

        public var statusRow = 0

        /// Where the content is, inside the frame and its one-column padding.
        public var contentX: Int { 2 }
        public var contentWidth: Int { Swift.max(0, width - 4) }

        /// How many tracks fit across the tracker panel.
        public var visibleTracks: Int {
            Swift.max(0, (contentWidth - lineNumberWidth) / trackCellWidth)
        }
    }

    /// The layout for a terminal of this size.
    ///
    /// Deliberately takes numbers rather than a `PlayerScreen`: the caller has
    /// to know how many pattern lines fit *before* it can build the screen, and
    /// this is the answer to that question as well as to the drawing one.
    public static func layout(width: Int,
                              height: Int,
                              channels: Int,
                              playlistCount: Int,
                              showTracker: Bool) -> Layout {
        var layout = Layout()
        layout.width = Swift.max(minimumWidth, width)
        layout.height = Swift.max(minimumHeight, height)

        var available = layout.height - fixedRows

        // The tracker is the reason to look at the screen, so it books its
        // first row before anything else and collects the leftovers at the end.
        var tracker = 0
        if showTracker, available >= 3 {
            tracker = 1
            available -= 3
        }

        var meters = 0
        let wantedMeters = Swift.min(Swift.max(0, channels), maxMeterRows)
        if wantedMeters > 0, available >= 2 {
            meters = Swift.min(wantedMeters, available - 1)
            available -= meters + 1
        }

        var playlist = 0
        let wantedPlaylist = Swift.min(Swift.max(0, playlistCount), maxPlaylistRows)
        if wantedPlaylist > 0, available >= 2 {
            playlist = Swift.min(wantedPlaylist, available - 1)
            available -= playlist + 1
        }

        if tracker > 0 {
            tracker += available
            // An odd count puts the playing line exactly in the middle, which
            // is what makes the pattern scroll under a fixed playhead.
            if tracker.isMultiple(of: 2) { tracker -= 1 }
        }

        // Whatever the panels did not take sits above the status line, so the
        // frame still closes on the last row and the transport does not float
        // in the middle of a tall terminal.
        let filler = layout.height - fixedRows
            - (tracker > 0 ? tracker + 2 : 0)
            - (meters > 0 ? meters + 1 : 0)
            - (playlist > 0 ? playlist + 1 : 0)

        var row = 1                              // row 0 is the top border
        layout.songRow = row; row += 1
        row += 1                                 // rule
        layout.captionRow = row; row += 1
        layout.valueRow = row; row += 1

        if tracker > 0 {
            layout.trackerRule = row
            layout.trackerRows = tracker
            row += 2 + tracker                   // rule, header, rows
        }
        if meters > 0 {
            layout.meterRule = row
            layout.meterRows = meters
            row += 1 + meters
        }

        row += 1                                 // rule
        layout.positionRow = row; row += 1
        row += 1                                 // rule
        layout.transportRow = row; row += 1

        if playlist > 0 {
            layout.playlistRule = row
            layout.playlistRows = playlist
            row += 1 + playlist
        }

        row += Swift.max(0, filler)
        row += 1                                 // rule
        layout.statusRow = row

        return layout
    }

    /// How many pattern lines the tracker panel shows at this size — what the
    /// caller passes to `PlayerScreen(module:snapshot:visibleRows:)`.
    public static func visibleRows(width: Int,
                                   height: Int,
                                   channels: Int,
                                   playlistCount: Int,
                                   showTracker: Bool) -> Int {
        layout(width: width, height: height, channels: channels,
               playlistCount: playlistCount, showTracker: showTracker).trackerRows
    }

    // MARK: - Controls

    /// Where the clickable things are, in character cells. Same roles and same
    /// hit-testing shape as the pixel renderer, so the two players share the
    /// code that decides what a click meant.
    public static func controls(for screen: PlayerScreen, layout: Layout) -> [PlayerScreenRenderer.Control] {
        var controls: [PlayerScreenRenderer.Control] = []

        var x = layout.contentX
        for (label, role) in transportButtons(playing: screen.isPlaying) {
            let width = label.count + 2
            controls.append(.init(rect: Rect(x, layout.transportRow, width, 1), role: role))
            x += width + 1
        }

        controls.append(.init(rect: Rect(layout.contentX, layout.positionRow,
                                         positionBarWidth(layout), 1),
                              role: .songPosition))
        return controls
    }

    private static func transportButtons(playing: Bool) -> [(String, PlayerScreenRenderer.ControlRole)] {
        [("|<", .previousModule), ("<<", .previousPosition), (playing ? "||" : ">", .playPause),
         ("[]", .stop), (">>", .nextPosition), (">|", .nextModule)]
    }

    /// The bar leaves room for the position and the clock at its right end.
    private static func positionBarWidth(_ layout: Layout) -> Int {
        Swift.max(1, layout.contentWidth - 16)
    }

    // MARK: - Drawing

    public static func render(_ screen: PlayerScreen, width: Int, height: Int) -> TextCanvas {
        let layout = layout(width: width, height: height,
                            channels: screen.meters.count,
                            playlistCount: screen.playlist.count,
                            showTracker: screen.showTracker)
        return render(screen, layout: layout)
    }

    public static func render(_ screen: PlayerScreen, layout: Layout) -> TextCanvas {
        var canvas = TextCanvas(width: layout.width, height: layout.height,
                                fill: TextCell(paper: Theme.face))

        frame(&canvas, layout, title: screen.windowTitle)
        song(&canvas, layout, screen)
        status(&canvas, layout, screen)

        if let rule = layout.trackerRule {
            self.rule(&canvas, layout, row: rule, caption: "TRACKER")
            tracker(&canvas, layout, screen, top: rule + 1)
        }
        if let rule = layout.meterRule {
            self.rule(&canvas, layout, row: rule, caption: "LEVELS")
            meters(&canvas, layout, screen, top: rule + 1)
        }

        rule(&canvas, layout, row: layout.positionRow - 1)
        songPosition(&canvas, layout, screen)
        rule(&canvas, layout, row: layout.transportRow - 1)
        transport(&canvas, layout, screen)

        if let rule = layout.playlistRule {
            self.rule(&canvas, layout, row: rule, caption: "MODULES")
            playlist(&canvas, layout, screen, top: rule + 1)
        }

        rule(&canvas, layout, row: layout.statusRow - 1)
        canvas.text(screen.status, at: layout.contentX, layout.statusRow,
                    ink: Theme.textDim, paper: Theme.face, maxWidth: layout.contentWidth)
        return canvas
    }

    // MARK: - Panels

    /// The bevel, one character thick. A terminal has no two-pixel edge to
    /// light from the top left, so the frame carries the shine colour and the
    /// recessed panels carry the sunken ground — the depth is in the colours
    /// rather than in the geometry.
    private static func frame(_ canvas: inout TextCanvas, _ layout: Layout, title: String) {
        let bottom = layout.height - 1
        let edge = TextCell(character: "─", ink: Theme.shine, paper: Theme.face)

        for x in 0..<layout.width {
            canvas.set(x, 0, edge)
            canvas.set(x, bottom, edge)
        }
        for y in 1..<bottom {
            canvas.set(0, y, TextCell(character: "│", ink: Theme.shine, paper: Theme.face))
            canvas.set(layout.width - 1, y, TextCell(character: "│", ink: Theme.shine, paper: Theme.face))
        }
        canvas.set(0, 0, TextCell(character: "┌", ink: Theme.shine, paper: Theme.face))
        canvas.set(layout.width - 1, 0, TextCell(character: "┐", ink: Theme.shine, paper: Theme.face))
        canvas.set(0, bottom, TextCell(character: "└", ink: Theme.shine, paper: Theme.face))
        canvas.set(layout.width - 1, bottom, TextCell(character: "┘", ink: Theme.shine, paper: Theme.face))

        canvas.text(" \(title) ", at: 2, 0, ink: Theme.text, paper: Theme.face,
                    maxWidth: layout.width - 4)
    }

    /// A rule across the frame, optionally with a small capital caption sitting
    /// in it — which is how a panel gets a label without spending a row on one.
    private static func rule(_ canvas: inout TextCanvas, _ layout: Layout, row: Int, caption: String = "") {
        for x in 1..<(layout.width - 1) {
            canvas.set(x, row, TextCell(character: "─", ink: Theme.shine, paper: Theme.face))
        }
        canvas.set(0, row, TextCell(character: "├", ink: Theme.shine, paper: Theme.face))
        canvas.set(layout.width - 1, row, TextCell(character: "┤", ink: Theme.shine, paper: Theme.face))

        if !caption.isEmpty {
            canvas.text(" \(caption) ", at: 2, row, ink: Theme.caption, paper: Theme.face,
                        maxWidth: layout.width - 4)
        }
    }

    private static func song(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen) {
        canvas.fill(Rect(layout.contentX, layout.songRow, layout.contentWidth, 1),
                    TextCell(paper: Theme.sunken))
        canvas.text(screen.moduleTitle, at: layout.contentX, layout.songRow,
                    ink: Theme.text, paper: Theme.sunken, maxWidth: layout.contentWidth)
    }

    private static func status(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen) {
        let fields = [("POS", screen.position), ("BLOCK", screen.block), ("LINE", screen.line),
                      ("TEMPO", screen.tempo), ("BPM", screen.beatsPerMinute), ("TIME", screen.time)]

        var x = layout.contentX
        for (caption, value) in fields {
            let width = Swift.max(caption.count, value.count)
            guard x + width <= layout.contentX + layout.contentWidth else { break }
            canvas.text(caption, at: x, layout.captionRow, ink: Theme.caption, paper: Theme.face)
            canvas.fill(Rect(x, layout.valueRow, width, 1), TextCell(paper: Theme.sunken))
            canvas.text(value, at: x, layout.valueRow, ink: Theme.text, paper: Theme.sunken)
            x += width + 2
        }
    }

    private static func tracker(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen, top: Int) {
        let tracks = Swift.min(screen.trackCount, layout.visibleTracks)
        let x = layout.contentX

        canvas.text("LN", at: x, top, ink: Theme.caption, paper: Theme.face)
        for track in 0..<tracks {
            canvas.text("TRACK \(track + 1)", at: x + lineNumberWidth + track * trackCellWidth, top,
                        ink: Theme.caption, paper: Theme.face, maxWidth: trackCellWidth - 1)
        }
        // Say so rather than silently dropping voices off the right edge.
        if tracks < screen.trackCount {
            canvas.text("+\(screen.trackCount - tracks)",
                        at: layout.contentX + layout.contentWidth - 3, top,
                        ink: Theme.accent, paper: Theme.face)
        }

        for (offset, row) in screen.trackerRows.prefix(layout.trackerRows).enumerated() {
            let y = top + 1 + offset
            let paper = row.isCurrent ? Theme.highlight : Theme.sunken
            let ink = row.isCurrent ? Theme.highlightText : Theme.text

            canvas.fill(Rect(1, y, layout.width - 2, 1), TextCell(paper: paper))
            // A row scrolled in from before the start of the block, or past its
            // end, has no line number to show either.
            guard !row.cells.isEmpty else { continue }

            canvas.text(String(format: "%03d", row.line), at: x, y,
                        ink: row.isCurrent ? Theme.highlightText : Theme.caption, paper: paper)
            for (track, cell) in row.cells.prefix(tracks).enumerated() {
                canvas.text(cell, at: x + lineNumberWidth + track * trackCellWidth, y,
                            ink: ink, paper: paper, maxWidth: trackCellWidth - 1)
            }
        }
    }

    /// Lit and unlit cells as two different characters rather than as two
    /// different backgrounds, so the bar is still a bar when the colour is
    /// stripped — over a pipe, or in a test.
    private static func meters(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen, top: Int) {
        let labelWidth = 4
        let barWidth = Swift.max(1, layout.contentWidth - labelWidth)

        for (index, level) in screen.meters.prefix(layout.meterRows).enumerated() {
            let y = top + index
            canvas.text("CH\(index + 1)", at: layout.contentX, y, ink: Theme.text, paper: Theme.face)

            let lit = Int((Double(Swift.max(0, Swift.min(1, level))) * Double(barWidth)).rounded())
            for cell in 0..<barWidth {
                let fraction = Double(cell) / Double(Swift.max(1, barWidth - 1))
                let on = cell < lit
                canvas.set(layout.contentX + labelWidth + cell, y,
                           TextCell(character: on ? "█" : "░",
                                    ink: on ? Theme.meterCell(at: fraction) : Theme.meterOff,
                                    paper: Theme.face))
            }
        }
    }

    private static func songPosition(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen) {
        let width = positionBarWidth(layout)
        bar(&canvas, x: layout.contentX, y: layout.positionRow, width: width, value: screen.progress)

        let trailer = "\(screen.position)  \(screen.time)"
        canvas.text(trailer, at: layout.contentX + layout.contentWidth - trailer.count,
                    layout.positionRow, ink: Theme.textDim, paper: Theme.face)
    }

    private static func transport(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen) {
        var x = layout.contentX
        for (label, role) in transportButtons(playing: screen.isPlaying) {
            let lit = role == .playPause && screen.isPlaying
            canvas.text(" \(label) ", at: x, layout.transportRow,
                        ink: lit ? Theme.highlightText : Theme.text,
                        paper: lit ? Theme.highlight : Theme.faceLight)
            x += label.count + 3
        }

        let volumeLabel = "VOL"
        let volumeWidth = 8
        let volumeX = layout.contentX + layout.contentWidth - volumeWidth
        guard volumeX > x + volumeLabel.count + 1 else { return }
        canvas.text(volumeLabel, at: volumeX - volumeLabel.count - 1, layout.transportRow,
                    ink: Theme.caption, paper: Theme.face)
        bar(&canvas, x: volumeX, y: layout.transportRow, width: volumeWidth, value: screen.volume)
    }

    private static func playlist(_ canvas: inout TextCanvas, _ layout: Layout, _ screen: PlayerScreen, top: Int) {
        // The playing entry is kept in view when the list is longer than the
        // rows on offer, which is the whole reason to scroll it at all.
        let rows = layout.playlistRows
        var first = 0
        if let current = screen.currentIndex, screen.playlist.count > rows {
            first = Swift.min(Swift.max(0, current - rows / 2), screen.playlist.count - rows)
        }

        for offset in 0..<rows {
            let index = first + offset
            guard index < screen.playlist.count else { break }
            let y = top + offset
            let selected = index == screen.currentIndex
            let paper = selected ? Theme.highlight : Theme.sunken
            let ink = selected ? Theme.highlightText : Theme.text

            canvas.fill(Rect(1, y, layout.width - 2, 1), TextCell(paper: paper))
            canvas.text(selected ? "▶ " : "  ", at: layout.contentX, y, ink: ink, paper: paper)
            canvas.text(screen.playlist[index], at: layout.contentX + 2, y,
                        ink: ink, paper: paper, maxWidth: layout.contentWidth - 2)
        }
    }

    private static func bar(_ canvas: inout TextCanvas, x: Int, y: Int, width: Int, value: Double) {
        let filled = Int((Swift.max(0, Swift.min(1, value)) * Double(width)).rounded())
        for cell in 0..<width {
            let on = cell < filled
            canvas.set(x + cell, y, TextCell(character: on ? "█" : "░",
                                             ink: on ? Theme.highlight : Theme.meterOff,
                                             paper: Theme.face))
        }
    }
}
