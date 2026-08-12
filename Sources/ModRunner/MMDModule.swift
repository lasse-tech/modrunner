import Foundation

/// In-memory representation of a MED/OctaMED module.
///
/// Field names follow Teijo Kinnunen's specification (docs/MMD_FileFormat.txt)
/// so the loader can be read side by side with the document.
struct MMDModule {

    struct Instrument {
        var name: String = ""
        /// 8-bit signed sample data, already converted to -1.0...1.0.
        var data: [Float] = []
        /// Repeat start in samples (the file stores it shifted right one bit).
        var repeatStart: Int = 0
        /// Repeat length in samples. <= 2 means "no loop" (ProTracker convention).
        var repeatLength: Int = 0
        var volume: Int = 64          // svol, 0...64
        var transpose: Int = 0        // strans, semitones
        var finetune: Int = 0         // InstrExt.finetune, -8...+7
        var midiChannel: Int = 0      // non-zero => MIDI instrument, we cannot play it

        var isLooping: Bool { repeatLength > 2 && repeatStart + repeatLength <= data.count }
        var isPlayable: Bool { !data.isEmpty }
    }

    struct Note {
        var note: Int = 0        // 0 = none, 1 = C-1
        var instrument: Int = 0  // 0 = none, else 1-based index
        var command: Int = 0
        var data: Int = 0

        var isEmpty: Bool { note == 0 && instrument == 0 && command == 0 && data == 0 }
    }

    struct Block {
        var name: String = ""
        var tracks: Int = 4
        var lines: Int = 64
        /// Row-major: `notes[line * tracks + track]`.
        var notes: [Note] = []

        func note(line: Int, track: Int) -> Note {
            guard line >= 0, line < lines, track >= 0, track < tracks else { return Note() }
            return notes[line * tracks + track]
        }
    }

    // Header
    var formatID: String = "MMD0"

    // Song
    var songName: String = ""
    var annotation: String = ""
    var numTracks: Int = 4
    var blocks: [Block] = []
    var playSequence: [Int] = []
    var instruments: [Instrument] = []
    var trackVolumes: [Int] = Array(repeating: 64, count: 16)
    var masterVolume: Int = 64

    // Timing
    var defaultTempo: Int = 33
    var ticksPerLine: Int = 6      // tempo2 / "secondary tempo"
    var playTranspose: Int = 0

    // Flags (see FLAG_* in the spec)
    var volumesAreHex: Bool = false   // FLAG_VOLHEX  0x10
    var ptSliding: Bool = false       // FLAG_STSLIDE 0x20
    var is8Channel: Bool = false      // FLAG_8CHANNEL 0x40
    var bpmMode: Bool = false         // FLAG2_BPM    0x20
    var rowsPerBeat: Int = 4          // FLAG2_BMASK  0x1F, +1
    var usesMixing: Bool = false      // FLAG2_MIX    0x80

    /// Number of notes actually written across every block — a fair measure of
    /// how much was put into the song.
    var noteCount: Int {
        blocks.reduce(0) { total, block in
            total + block.notes.reduce(0) { $0 + ($1.note > 0 ? 1 : 0) }
        }
    }

    /// Number of lines of pattern data, counting each block once.
    var patternLines: Int {
        blocks.reduce(0) { $0 + $1.lines }
    }

    /// Total number of lines the play sequence walks through, for the progress bar.
    var totalLines: Int {
        playSequence.reduce(0) { sum, blockIndex in
            sum + (blocks.indices.contains(blockIndex) ? blocks[blockIndex].lines : 0)
        }
    }

    /// Display title: song name, else annotation's first line, else "untitled".
    var displayTitle: String {
        if !songName.isEmpty { return songName }
        let firstLine = annotation.split(separator: "\n").first.map(String.init) ?? ""
        if !firstLine.isEmpty { return firstLine.trimmingCharacters(in: .whitespaces) }
        return "untitled"
    }
}
