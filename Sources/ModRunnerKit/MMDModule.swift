import Foundation

/// Which set of effect command meanings a module uses.
///
/// The numbers collide: `0x0D` is a volume slide in MED but a pattern break in
/// ProTracker, and `0x0F` sets MED's tempo slider where ProTracker sets speed or
/// BPM. Commands `0x00`–`0x07` largely agree.
public enum EffectDialect {
    case med
    case protracker
}

/// In-memory representation of a module.
///
/// Field names follow Teijo Kinnunen's MED specification
/// (docs/MMD_FileFormat.txt) so the loader can be read side by side with the
/// document. ProTracker modules are loaded into the same shape, since both
/// describe Paula voices playing 8-bit samples at a period.
public struct MMDModule {

    public struct Instrument {
        public var name: String = ""
        /// 8-bit signed sample data, already converted to -1.0...1.0.
        public var data: [Float] = []
        /// Repeat start in samples (the file stores it shifted right one bit).
        public var repeatStart: Int = 0
        /// Repeat length in samples. <= 2 means "no loop" (ProTracker convention).
        public var repeatLength: Int = 0
        public var volume: Int = 64          // svol, 0...64
        public var transpose: Int = 0        // strans, semitones
        public var finetune: Int = 0         // InstrExt.finetune, -8...+7
        public var midiChannel: Int = 0      // non-zero => MIDI instrument, we cannot play it

        public var isLooping: Bool { repeatLength > 2 && repeatStart + repeatLength <= data.count }
        public var isPlayable: Bool { !data.isEmpty }
    }

    public struct Note {
        public var note: Int = 0        // 0 = none, 1 = C-1
        public var instrument: Int = 0  // 0 = none, else 1-based index
        public var command: Int = 0
        public var data: Int = 0

        public var isEmpty: Bool { note == 0 && instrument == 0 && command == 0 && data == 0 }
    }

    public struct Block {
        public var name: String = ""
        public var tracks: Int = 4
        public var lines: Int = 64
        /// Row-major: `notes[line * tracks + track]`.
        public var notes: [Note] = []

        public func note(line: Int, track: Int) -> Note {
            guard line >= 0, line < lines, track >= 0, track < tracks else { return Note() }
            return notes[line * tracks + track]
        }
    }

    // Header
    public var formatID: String = "MMD0"
    public var effectDialect: EffectDialect = .med

    // Song
    public var songName: String = ""
    public var annotation: String = ""
    public var numTracks: Int = 4
    public var blocks: [Block] = []
    public var playSequence: [Int] = []
    public var instruments: [Instrument] = []
    public var trackVolumes: [Int] = Array(repeating: 64, count: 16)
    public var masterVolume: Int = 64

    // Timing
    public var defaultTempo: Int = 33
    public var ticksPerLine: Int = 6      // tempo2 / "secondary tempo"
    public var playTranspose: Int = 0

    // Flags (see FLAG_* in the spec)
    public var volumesAreHex: Bool = false   // FLAG_VOLHEX  0x10
    public var ptSliding: Bool = false       // FLAG_STSLIDE 0x20
    public var is8Channel: Bool = false      // FLAG_8CHANNEL 0x40
    public var bpmMode: Bool = false         // FLAG2_BPM    0x20
    public var rowsPerBeat: Int = 4          // FLAG2_BMASK  0x1F, +1
    public var usesMixing: Bool = false      // FLAG2_MIX    0x80

    /// Number of notes actually written across every block — a fair measure of
    /// how much was put into the song.
    public var noteCount: Int {
        blocks.reduce(0) { total, block in
            total + block.notes.reduce(0) { $0 + ($1.note > 0 ? 1 : 0) }
        }
    }

    /// Number of lines of pattern data, counting each block once.
    public var patternLines: Int {
        blocks.reduce(0) { $0 + $1.lines }
    }

    /// Total number of lines the play sequence walks through, for the progress bar.
    public var totalLines: Int {
        playSequence.reduce(0) { sum, blockIndex in
            sum + (blocks.indices.contains(blockIndex) ? blocks[blockIndex].lines : 0)
        }
    }

    /// Display title: song name, else annotation's first line, else "untitled".
    public var displayTitle: String {
        if !songName.isEmpty { return songName }
        let firstLine = annotation.split(separator: "\n").first.map(String.init) ?? ""
        if !firstLine.isEmpty { return firstLine.trimmingCharacters(in: .whitespaces) }
        return "untitled"
    }
}
