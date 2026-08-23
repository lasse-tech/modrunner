import Foundation
import ModRunnerKit

public extension PlayerScreen {

    /// Fills the screen out of a module and a replayer snapshot — the one place
    /// that knows both the engine's vocabulary and the skin's.
    ///
    /// `visibleRows` is how many pattern lines the tracker panel shows, and the
    /// current line is kept in the middle of them, which is what makes the
    /// pattern scroll under a fixed playhead rather than the playhead wander.
    init(module: MMDModule?,
         snapshot: Replayer.Snapshot,
         playlist: [String] = [],
         currentIndex: Int? = nil,
         status: String = "",
         visibleRows: Int = 17,
         showTracker: Bool = true,
         layout: Layout = .window,
         waveform: [Float] = [],
         visualisation: Visualisation = .levels) {
        self.init()

        self.layout = layout
        self.waveform = waveform
        self.visualisation = visualisation
        self.showTracker = showTracker
        self.playlist = playlist
        self.currentIndex = currentIndex
        self.isPlaying = snapshot.isPlaying
        self.progress = snapshot.progress
        self.meters = snapshot.channelMeters.isEmpty ? [0, 0, 0, 0] : snapshot.channelMeters

        guard let module else {
            self.status = status
            return
        }

        windowTitle = "ModRunner — \(module.displayTitle)"
        moduleTitle = module.displayTitle
        trackCount = module.numTracks

        position = module.playSequence.isEmpty
            ? "--/--"
            : String(format: "%02d/%02d", snapshot.sequencePosition + 1, module.playSequence.count)
        block = String(format: "%02d", snapshot.block)
        line = String(format: "%02d/%02d", snapshot.line, snapshot.lineCount)
        tempo = "\(snapshot.tempo)/\(snapshot.ticksPerLine)"
        beatsPerMinute = String(format: "%.0f", snapshot.beatsPerMinute)
        let seconds = Int(snapshot.elapsedSeconds)
        time = String(format: "%d:%02d", seconds / 60, seconds % 60)

        self.status = status.isEmpty
            ? "\(module.formatID) · \(module.blocks.count) blocks · \(module.numTracks) tracks "
              + "· \(module.patternLines) lines · \(module.noteCount) notes"
            : status

        if showTracker, module.blocks.indices.contains(snapshot.block) {
            let block = module.blocks[snapshot.block]
            let half = visibleRows / 2
            trackerRows = (0..<visibleRows).map { offset in
                let line = snapshot.line - half + offset
                let inside = line >= 0 && line < block.lines
                let cells = (0..<module.numTracks).map { track -> String in
                    guard inside else { return "" }
                    let note = block.note(line: line, track: track)
                    return "\(Notation.name(of: note.note)) "
                        + "\(Notation.instrument(note.instrument)) "
                        + "\(Notation.command(note.command, note.data))"
                }
                return TrackerRow(line: inside ? line : 0,
                                  cells: cells,
                                  isCurrent: line == snapshot.line)
            }
            // Rows outside the block print no line number either.
            for index in trackerRows.indices where trackerRows[index].cells.first?.isEmpty ?? true {
                trackerRows[index].cells = []
            }
        }
    }
}
