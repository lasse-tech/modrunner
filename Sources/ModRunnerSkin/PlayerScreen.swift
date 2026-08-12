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

    public var meters: [Float] = [0, 0, 0, 0]
    public var progress = 0.0
    public var volume = 1.0
    public var isPlaying = false

    public var playlist: [String] = []
    public var currentIndex: Int?
    public var status = ""

    public init() {}
}

/// Draws the whole Workbench window into a canvas.
///
/// The measurements follow the macOS skin — 560 points wide, the same panel
/// order, the same eight-pixel gutter — so the two are recognisably one
/// interface rather than two programs that happen to share a palette.
public enum PlayerScreenRenderer {

    public static let width = 560

    private static let margin = 8
    private static let gap = 8
    private static let titleBarHeight = 22
    private static let songHeight = 40
    private static let statusHeight = 34
    private static let meterRowHeight = 16
    private static let positionHeight = 34
    private static let transportHeight = 32
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
        Workbench.bevel * 2 + 4 + Font.cellHeight + 2 + Swift.max(1, rows) * trackerRowHeight + 4
    }

    private static func metersHeight(channels: Int) -> Int {
        Workbench.bevel * 2 + 4 + Swift.max(1, channels) * meterRowHeight + 4
    }

    private static func playlistHeight(rows: Int) -> Int {
        let list = Swift.max(4, rows) * playlistRowHeight + 8
        return Workbench.bevel * 2 + 4 + Font.cellHeight + 2 + list + 4 + 18 + 4
    }

    public static func render(_ screen: PlayerScreen) -> Canvas {
        var canvas = Canvas(width: width, height: height(for: screen), fill: Workbench.grey)
        var y = 0

        y = titleBar(&canvas, screen, y: y)
        y += margin

        let content = Rect(margin, y, width - margin * 2, 0)

        y = song(&canvas, screen, Rect(content.x, y, content.width, songHeight)) + gap
        y = status(&canvas, screen, Rect(content.x, y, content.width, statusHeight)) + gap

        if screen.showTracker {
            let panel = Rect(content.x, y, content.width,
                             trackerPanelHeight(rows: screen.trackerRows.count))
            y = tracker(&canvas, screen, panel) + gap
        }

        let metersPanel = Rect(content.x, y, content.width,
                               metersHeight(channels: screen.meters.count))
        y = meters(&canvas, screen, metersPanel) + gap
        y = songPosition(&canvas, screen, Rect(content.x, y, content.width, positionHeight)) + gap
        y = transport(&canvas, screen, Rect(content.x, y, content.width, transportHeight)) + gap
        y = viewOptions(&canvas, screen, Rect(content.x, y, content.width, viewOptionsHeight)) + gap
        _ = playlist(&canvas, screen,
                     Rect(content.x, y, content.width, playlistHeight(rows: screen.playlist.count)))

        return canvas
    }

    // MARK: - Panels

    private static func titleBar(_ canvas: inout Canvas, _ screen: PlayerScreen, y: Int) -> Int {
        let bar = Rect(0, y, width, titleBarHeight)
        canvas.bevel(bar, .raised, fill: Workbench.blue)

        // The depth gadget on the left, the rest on the right, as Intuition
        // arranged them.
        let gadget = titleBarHeight
        canvas.bevel(Rect(0, y, gadget, gadget), .raised)
        canvas.frame(Rect(6, y + 6, gadget - 12, gadget - 12), Workbench.black)

        canvas.text(screen.windowTitle, at: gadget + 8, y + (titleBarHeight - Font.cellHeight) / 2,
                    Workbench.white, maxWidth: width - gadget * 4 - 16)

        // Minimise, zoom and depth, in Intuition's order.
        for slot in 1...3 {
            canvas.bevel(Rect(width - gadget * slot, y, gadget, gadget), .raised)
        }
        // Distinguish them: a bar, a small square, two overlapping squares.
        canvas.fill(Rect(width - gadget * 3 + 6, y + gadget - 9, gadget - 12, 3), Workbench.black)
        canvas.frame(Rect(width - gadget * 2 + 5, y + 5, gadget - 10, gadget - 10), Workbench.black)
        canvas.frame(Rect(width - gadget + 4, y + 4, gadget - 11, gadget - 11), Workbench.black)
        canvas.frame(Rect(width - gadget + 8, y + 8, gadget - 11, gadget - 11), Workbench.black)

        return y + titleBarHeight
    }

    private static func song(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        canvas.readout(rect.inset(by: Workbench.bevel + 2), screen.moduleTitle)
        return rect.maxY
    }

    private static func status(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Workbench.bevel + 2)

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
        canvas.bevel(rect, .recessed, fill: Workbench.lightGrey)
        let inner = rect.inset(by: Workbench.bevel + 2)

        let lineColumn = 4 * Font.cellWidth
        let trackWidth = screen.trackCount > 0
            ? (inner.width - lineColumn) / screen.trackCount : inner.width

        canvas.text("LN", at: inner.x, inner.y, Workbench.darkGrey)
        for track in 0..<screen.trackCount {
            canvas.text("TRACK \(track + 1)", at: inner.x + lineColumn + track * trackWidth, inner.y,
                        Workbench.darkGrey, maxWidth: trackWidth - 4)
        }

        var y = inner.y + Font.cellHeight + 2
        for row in screen.trackerRows {
            if row.isCurrent {
                canvas.fill(Rect(rect.x + Workbench.bevel, y - 1,
                                 rect.width - Workbench.bevel * 2, trackerRowHeight), Workbench.blue)
            }
            let ink = row.isCurrent ? Workbench.white : Workbench.black
            // A row scrolled in from before the start of the block, or past its
            // end, has no line number to show — the panel is a window onto the
            // pattern, not a list that pads itself out.
            if !row.cells.isEmpty {
                canvas.text(String(format: "%03d", row.line), at: inner.x, y,
                            row.isCurrent ? Workbench.white : Workbench.darkGrey)
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
        canvas.bevel(rect, .recessed, fill: Workbench.grey)
        let inner = rect.inset(by: Workbench.bevel + 2)
        let labelWidth = 4 * Font.cellWidth

        for (index, level) in screen.meters.enumerated() {
            let y = inner.y + index * meterRowHeight
            canvas.text("CH\(index + 1)", at: inner.x, y + 2, Workbench.black)
            canvas.meter(Rect(inner.x + labelWidth, y, inner.width - labelWidth, meterRowHeight - 3),
                         level: level)
        }
        return rect.maxY
    }

    private static func songPosition(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Workbench.bevel + 2)
        canvas.text("SONG POSITION", at: inner.x, inner.y, Workbench.black)
        canvas.slider(Rect(inner.x, inner.y + Font.cellHeight + 2,
                           inner.width, inner.height - Font.cellHeight - 2),
                      value: screen.progress)
        return rect.maxY
    }

    private static func transport(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Workbench.bevel + 2)

        let labels = ["|<", "<<", screen.isPlaying ? "||" : ">", "[]", ">>", ">|"]
        var x = inner.x
        for label in labels {
            let buttonWidth = 34
            canvas.button(Rect(x, inner.y, buttonWidth, inner.height), label)
            x += buttonWidth + 4
        }

        canvas.text("VOL", at: x + 6, inner.y + (inner.height - Font.cellHeight) / 2, Workbench.black)
        let volumeX = x + 6 + 4 * Font.cellWidth
        canvas.slider(Rect(volumeX, inner.y + 2, inner.maxX - volumeX - 4, inner.height - 4),
                      value: screen.volume)
        return rect.maxY
    }

    private static func viewOptions(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) -> Int {
        canvas.bevel(rect, .raised)
        let inner = rect.inset(by: Workbench.bevel + 2)

        canvas.text("VIEW", at: inner.x, inner.y + (inner.height - Font.cellHeight) / 2, Workbench.black)
        var x = inner.x + 5 * Font.cellWidth
        for (label, width) in [("Tracks", 66), ("LED", 44), ("Load", 52)] {
            canvas.button(Rect(x, inner.y, width, inner.height), label)
            x += width + 6
        }
        // Right-aligned, laid out from the edge inwards.
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
        let inner = rect.inset(by: Workbench.bevel + 2)

        canvas.text("MODULES  —  drop files or a drawer here", at: inner.x, inner.y,
                    Workbench.black, maxWidth: inner.width)

        let listTop = inner.y + Font.cellHeight + 2
        let list = Rect(inner.x, listTop, inner.width, inner.maxY - listTop - 22)
        canvas.bevel(list, .recessed, fill: Workbench.lightGrey)

        let listInner = list.inset(by: Workbench.bevel + 2)
        for (index, entry) in screen.playlist.enumerated() {
            let y = listInner.y + index * playlistRowHeight
            guard y + playlistRowHeight <= listInner.maxY else { break }
            let selected = index == screen.currentIndex
            if selected {
                canvas.fill(Rect(list.x + Workbench.bevel, y - 1,
                                 list.width - Workbench.bevel * 2, playlistRowHeight), Workbench.blue)
            }
            canvas.text(entry, at: listInner.x + 2, y, selected ? Workbench.white : Workbench.black,
                        maxWidth: listInner.width - 4)
        }

        canvas.readout(Rect(inner.x, inner.maxY - 18, inner.width, 18), screen.status)
        return rect.maxY
    }
}
