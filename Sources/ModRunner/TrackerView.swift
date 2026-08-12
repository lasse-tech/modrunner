import SwiftUI

/// The note data of the block being played, scrolling under a fixed playhead —
/// the view every tracker has had since the eighties.
struct TrackerView: View {

    let module: MMDModule?
    let block: Int
    let line: Int

    /// Lines shown above and below the playhead.
    static let context = 5
    static let rowHeight: CGFloat = 14
    static let headerHeight: CGFloat = 12

    /// Exact height of the panel, so the window can be sized without guessing.
    static var panelHeight: CGFloat {
        headerHeight + rowHeight * CGFloat(context * 2 + 1) + 2 * (Amiga.bevel + 1)
    }

    private var visibleRange: ClosedRange<Int> { -Self.context...Self.context }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(visibleRange, id: \.self) { offset in
                row(at: line + offset, isCurrent: offset == 0)
            }
        }
        .amigaBevel(.recessed, fill: Amiga.lightGrey, inset: Amiga.bevel + 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("LN")
                .frame(width: 26, alignment: .leading)
            ForEach(0..<trackCount, id: \.self) { track in
                Text("TRACK \(track + 1)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Amiga.font(9))
        .foregroundColor(Amiga.darkGrey)
        .padding(.horizontal, 3)
        .frame(height: Self.headerHeight)
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
                .frame(width: 26, alignment: .leading)
                .foregroundColor(isCurrent ? Amiga.white : Amiga.darkGrey)

            ForEach(0..<trackCount, id: \.self) { track in
                Text(valid ? cell(block: block!, line: lineIndex, track: track) : "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(textColor(isCurrent: isCurrent, onBeat: onBeat))
            }
        }
        .font(Amiga.font(11))
        .padding(.horizontal, 3)
        .frame(height: Self.rowHeight)
        .background(background(isCurrent: isCurrent, onBeat: onBeat))
    }

    private func textColor(isCurrent: Bool, onBeat: Bool) -> Color {
        if isCurrent { return Amiga.white }
        return Amiga.black
    }

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
        min(currentBlock?.tracks ?? 4, 8)
    }

    /// One cell in OctaMED's notation: note, instrument, command, data.
    private func cell(block: MMDModule.Block, line: Int, track: Int) -> String {
        let note = block.note(line: line, track: track)
        let name = TrackerView.noteName(note.note)
        let instrument = note.instrument > 0 ? String(format: "%02X", note.instrument) : ".."
        let command = (note.command != 0 || note.data != 0)
            ? String(format: "%02X%02X", note.command, note.data)
            : "...."
        return "\(name) \(instrument) \(command)"
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
