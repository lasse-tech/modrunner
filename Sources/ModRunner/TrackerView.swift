import SwiftUI

/// How much of the pattern to draw, and how big. The small panel in the player
/// window and the full-screen stage are the same view with different numbers,
/// so the notation is written in exactly one place.
struct TrackerLayout {
    var rowHeight: CGFloat = 14
    var fontSize: CGFloat = 11
    var headerHeight: CGFloat = 12
    /// Lines shown above and below the playhead.
    var context: Int = 5
    /// Tracks there is room for. Wider modules are cut off here rather than
    /// squeezed until the notation stops being readable.
    var maxTracks: Int = 8
    var showsBevel: Bool = true
    /// Draws the instrument and command columns in their own pens. Only worth
    /// doing when the text is big enough to tell the columns apart.
    var tintsColumns: Bool = false

    /// The layout of the panel inside the player window.
    static let panel = TrackerLayout()

    /// Exact height of the panel, so the window can be sized without guessing.
    var height: CGFloat {
        headerHeight + rowHeight * CGFloat(context * 2 + 1) + 2 * (Amiga.bevel + 1)
    }
}

/// The note data of the block being played, scrolling under a fixed playhead —
/// the view every tracker has had since the eighties.
struct TrackerView: View {

    let module: MMDModule?
    let block: Int
    let line: Int
    var layout: TrackerLayout = .panel

    static let rowHeight: CGFloat = TrackerLayout.panel.rowHeight
    static let headerHeight: CGFloat = TrackerLayout.panel.headerHeight

    /// Exact height of the panel, so the window can be sized without guessing.
    static var panelHeight: CGFloat { TrackerLayout.panel.height }

    private var visibleRange: ClosedRange<Int> { -layout.context...layout.context }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(visibleRange, id: \.self) { offset in
                row(at: line + offset, isCurrent: offset == 0)
            }
        }
        .modifier(TrackerFrame(bevelled: layout.showsBevel))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("LN")
                .frame(width: lineColumnWidth, alignment: .leading)
            ForEach(0..<trackCount, id: \.self) { track in
                Text("TRACK \(track + 1)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Amiga.font(min(layout.fontSize, 9 + layout.fontSize / 4)))
        .foregroundColor(Amiga.darkGrey)
        .padding(.horizontal, 3)
        .frame(height: layout.headerHeight)
    }

    // MARK: - Rows

    private func row(at lineIndex: Int, isCurrent: Bool) -> some View {
        let block = currentBlock
        let valid = block != nil && lineIndex >= 0 && lineIndex < (block?.lines ?? 0)

        // MED highlights every beat; with no better information the usual four
        // lines per beat is the sensible default.
        let onBeat = valid && lineIndex % 4 == 0

        return HStack(spacing: 0) {
            Text(valid ? String(format: "%03d", lineIndex) : "")
                .frame(width: lineColumnWidth, alignment: .leading)
                .foregroundColor(isCurrent ? Amiga.white : Amiga.darkGrey)

            ForEach(0..<trackCount, id: \.self) { track in
                cell(block: block, line: lineIndex, track: track, valid: valid, isCurrent: isCurrent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Amiga.font(layout.fontSize))
        .padding(.horizontal, 3)
        .frame(height: layout.rowHeight)
        .background(background(isCurrent: isCurrent, onBeat: onBeat))
    }

    /// One cell in OctaMED's notation: note, instrument, command, data. The
    /// three parts are drawn separately so the stage can pen them apart; at
    /// panel size they are all the same colour and read as one string.
    private func cell(block: MMDModule.Block?, line: Int, track: Int,
                      valid: Bool, isCurrent: Bool) -> some View {
        let note = (valid && block != nil) ? block!.note(line: line, track: track) : nil

        return HStack(spacing: gap) {
            Text(note.map { TrackerView.noteName($0.note) } ?? "")
                .foregroundColor(pen(.note, set: (note?.note ?? 0) > 0, isCurrent: isCurrent))
            Text(note.map { $0.instrument > 0 ? String(format: "%02X", $0.instrument) : ".." } ?? "")
                .foregroundColor(pen(.instrument, set: (note?.instrument ?? 0) > 0, isCurrent: isCurrent))
            Text(note.map(Self.commandText) ?? "")
                .foregroundColor(pen(.command, set: note.map(Self.hasCommand) ?? false, isCurrent: isCurrent))
        }
    }

    private enum Column { case note, instrument, command }

    /// Placeholders stay dim whatever the column, so a sparse pattern reads as
    /// texture rather than as data. Only a value that is actually there gets a
    /// pen of its own, and only where the text is big enough for it to help.
    private func pen(_ column: Column, set: Bool, isCurrent: Bool) -> Color {
        if isCurrent { return Amiga.white }
        // At panel size everything is one pen, exactly as OctaMED drew it.
        guard layout.tintsColumns else { return Amiga.black }
        guard set else { return Amiga.darkGrey }
        return column == .instrument ? Amiga.blue : Amiga.black
    }

    /// Roughly one character of the monospaced face, so the parts sit apart the
    /// way they would inside a single string.
    private var gap: CGFloat { (layout.fontSize * 0.6).rounded() }

    private var lineColumnWidth: CGFloat { (layout.fontSize * 2.4).rounded() }

    private func background(isCurrent: Bool, onBeat: Bool) -> Color {
        if isCurrent { return Amiga.blue }
        if onBeat { return Amiga.grey.opacity(0.55) }
        return .clear
    }

    // MARK: - Formatting

    private var currentBlock: MMDModule.Block? {
        guard let module, module.blocks.indices.contains(block) else { return nil }
        return module.blocks[block]
    }

    private var trackCount: Int {
        min(currentBlock?.tracks ?? 4, layout.maxTracks)
    }

    private static func hasCommand(_ note: MMDModule.Note) -> Bool {
        note.command != 0 || note.data != 0
    }

    private static func commandText(_ note: MMDModule.Note) -> String {
        hasCommand(note) ? String(format: "%02X%02X", note.command, note.data) : "...."
    }

    private static let noteNames = ["C-", "C#", "D-", "D#", "E-", "F-", "F#",
                                    "G-", "G#", "A-", "A#", "B-"]

    /// MED numbers notes from 1, where 1 is C-1.
    static func noteName(_ note: Int) -> String {
        guard note > 0 else { return "---" }
        let index = note - 1
        return "\(noteNames[index % 12])\(index / 12 + 1)"
    }
}

/// The panel sits in a recessed bevel; the stage draws its own surround.
private struct TrackerFrame: ViewModifier {
    let bevelled: Bool

    func body(content: Content) -> some View {
        if bevelled {
            content.amigaBevel(.recessed, fill: Amiga.lightGrey, inset: Amiga.bevel + 1)
        } else {
            content.background(Amiga.lightGrey)
        }
    }
}
