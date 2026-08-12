import Foundation

/// Reads ProTracker-style `.mod` files into the same model the MED loader
/// produces, so the replayer and the whole interface work unchanged.
///
/// The formats are not related — MOD is a flat, fixed layout with no pointers,
/// 31 sample slots and 64-row patterns — but they describe the same machine:
/// Paula voices playing 8-bit samples at a period. The differences that do
/// matter are the effect command meanings, which is why the module carries an
/// `effectDialect`.
public struct MODLoader {

    private let bytes: [UInt8]

    /// Tags that appear at offset 1080, and the channel count they imply.
    private static let signatures: [String: Int] = [
        "M.K.": 4, "M!K!": 4, "M&K!": 4, "N.T.": 4, "FLT4": 4,
        "4CHN": 4, "6CHN": 6, "8CHN": 8, "FLT8": 8,
        "2CHN": 2, "CD81": 8, "OKTA": 8, "OCTA": 8,
        "10CH": 10, "12CH": 12, "14CH": 14, "16CH": 16,
        "20CH": 20, "24CH": 24, "28CH": 28, "32CH": 32,
    ]

    public static func signature(in data: Data) -> String? {
        guard data.count >= 1084 else { return nil }
        let tag = String(decoding: data[1080..<1084], as: UTF8.self)
        return signatures[tag] != nil ? tag : nil
    }

    public static func load(url: URL) throws -> MMDModule {
        var module = try load(data: try Data(contentsOf: url))
        if module.songName.isEmpty {
            module.songName = url.deletingPathExtension().lastPathComponent
        }
        return module
    }

    public static func load(data: Data) throws -> MMDModule {
        try MODLoader(bytes: [UInt8](data)).parse()
    }

    // MARK: - Readers

    private func u8(_ offset: Int) throws -> Int {
        guard offset >= 0, offset < bytes.count else { throw MMDLoadError.corrupt("read past end of file") }
        return Int(bytes[offset])
    }

    private func u16(_ offset: Int) throws -> Int {
        (try u8(offset) << 8) | (try u8(offset + 1))
    }

    private func text(at offset: Int, length: Int) -> String {
        guard offset >= 0, offset + length <= bytes.count else { return "" }
        var slice = [UInt8]()
        for i in offset..<(offset + length) {
            if bytes[i] == 0 { break }
            slice.append(bytes[i])
        }
        let string = String(slice.map { Character(UnicodeScalar($0)) })
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing

    private func parse() throws -> MMDModule {
        guard bytes.count >= 1084 else { throw MMDLoadError.tooShort }

        let tag = String(bytes[1080..<1084].map { Character(UnicodeScalar($0)) })
        guard let channels = MODLoader.signatures[tag] else {
            throw MMDLoadError.unknownFormat(tag)
        }

        var module = MMDModule()
        module.formatID = tag
        module.effectDialect = .protracker
        module.songName = text(at: 0, length: 20)
        module.numTracks = channels

        // ProTracker timing: six ticks per row at 125 BPM. Expressed through the
        // BPM mode the model already has, with four rows to the beat, `tempo`
        // *is* the BPM — which is exactly what command F sets.
        module.ticksPerLine = 6
        module.defaultTempo = 125
        module.bpmMode = true
        module.rowsPerBeat = 4
        module.volumesAreHex = false
        module.masterVolume = 64
        module.trackVolumes = Array(repeating: 64, count: max(16, channels))

        // 31 sample headers of 30 bytes each, starting after the 20-byte title.
        var instruments = [MMDModule.Instrument]()
        var sampleLengths = [Int]()
        for index in 0..<31 {
            let base = 20 + index * 30
            var instrument = MMDModule.Instrument()
            instrument.name = text(at: base, length: 22)

            let length = (try u16(base + 22)) * 2
            // The low nibble is a signed 4-bit finetune.
            let rawFinetune = (try u8(base + 24)) & 0x0F
            instrument.finetune = rawFinetune > 7 ? rawFinetune - 16 : rawFinetune
            instrument.volume = min(64, try u8(base + 25))
            instrument.repeatStart = (try u16(base + 26)) * 2
            instrument.repeatLength = (try u16(base + 28)) * 2

            sampleLengths.append(length)
            instruments.append(instrument)
        }

        let songLength = try u8(950)
        guard songLength > 0, songLength <= 128 else {
            throw MMDLoadError.corrupt("implausible song length \(songLength)")
        }

        var order = [Int]()
        var highestPattern = 0
        for i in 0..<128 {
            let entry = try u8(952 + i)
            highestPattern = max(highestPattern, entry)
            if i < songLength { order.append(entry) }
        }
        let patternCount = highestPattern + 1

        // Patterns: 64 rows of `channels` notes, four bytes each.
        let patternBase = 1084
        let patternSize = 64 * channels * 4
        guard patternBase + patternCount * patternSize <= bytes.count else {
            throw MMDLoadError.corrupt("pattern data extends past end of file")
        }

        var blocks = [MMDModule.Block]()
        for pattern in 0..<patternCount {
            var block = MMDModule.Block()
            block.tracks = channels
            block.lines = 64
            var notes = [MMDModule.Note]()
            notes.reserveCapacity(64 * channels)

            for cell in 0..<(64 * channels) {
                let p = patternBase + pattern * patternSize + cell * 4
                let b0 = Int(bytes[p]), b1 = Int(bytes[p + 1])
                let b2 = Int(bytes[p + 2]), b3 = Int(bytes[p + 3])

                var note = MMDModule.Note()
                // MOD stores a period, not a note number; the model wants a note.
                let period = ((b0 & 0x0F) << 8) | b1
                note.note = MODLoader.note(forPeriod: period)
                note.instrument = (b0 & 0xF0) | (b2 >> 4)
                note.command = b2 & 0x0F
                note.data = b3
                notes.append(note)
            }
            block.notes = notes
            blocks.append(block)
        }

        module.blocks = blocks
        module.playSequence = order.filter { $0 < patternCount }

        // Sample data follows the patterns, in slot order.
        var offset = patternBase + patternCount * patternSize
        for index in 0..<31 {
            let length = sampleLengths[index]
            guard length > 0 else { continue }
            let available = min(length, max(0, bytes.count - offset))
            if available > 0 {
                var samples = [Float]()
                samples.reserveCapacity(available)
                for i in 0..<available {
                    samples.append(Float(Int8(bitPattern: bytes[offset + i])) / 128.0)
                }
                instruments[index].data = samples

                let count = samples.count
                instruments[index].repeatStart = min(instruments[index].repeatStart, count)
                instruments[index].repeatLength = min(instruments[index].repeatLength,
                                                      count - instruments[index].repeatStart)
            }
            offset += length
        }

        // Trailing empty slots carry no information; keep them so instrument
        // numbers in the patterns still line up.
        module.instruments = instruments
        return module
    }

    // MARK: - Periods

    /// ProTracker periods for notes C-1 to B-3 at finetune 0. A pattern stores
    /// the period; the replayer wants the note, and re-derives the period itself
    /// so that finetune and the effects work the same way for both formats.
    private static let periods: [Int] = [
        856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
        428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
        214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
    ]

    /// Nearest note for a stored period. Modules written with finetuned samples
    /// hold slightly shifted periods, so an exact match cannot be relied on.
    public static func note(forPeriod period: Int) -> Int {
        guard period > 0 else { return 0 }
        var bestIndex = 0
        var bestDistance = Int.max
        for (index, candidate) in periods.enumerated() {
            let distance = abs(candidate - period)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex + 1
    }
}
