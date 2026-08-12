import Foundation

enum MMDLoadError: LocalizedError {
    case tooShort
    case unknownFormat(String)
    case unsupportedFormat(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return L10n.t("error.tooShort")
        case .unknownFormat(let id):
            return L10n.t("error.unknownFormat", id)
        case .unsupportedFormat(let id):
            return L10n.t("error.unsupportedFormat", id)
        case .corrupt(let what):
            return L10n.t("error.corrupt", what)
        }
    }
}

/// Reads MMD0 and MMD1 modules.
///
/// The spec is emphatic that every structure must be reached through the header
/// pointers rather than through hardcoded offsets, so that is what we do. Every
/// pointer is bounds-checked; a truncated module fails cleanly instead of
/// reading garbage.
struct MMDLoader {

    private let bytes: [UInt8]

    static func load(url: URL) throws -> MMDModule {
        let data = try Data(contentsOf: url)
        var module = try MMDLoader(bytes: [UInt8](data)).parse()
        if module.songName.isEmpty {
            module.songName = url.deletingPathExtension().lastPathComponent
        }
        return module
    }

    static func load(data: Data) throws -> MMDModule {
        try MMDLoader(bytes: [UInt8](data)).parse()
    }

    // MARK: - Primitive big-endian readers

    private func u8(_ offset: Int) throws -> Int {
        guard offset >= 0, offset < bytes.count else { throw MMDLoadError.corrupt("read past end of file") }
        return Int(bytes[offset])
    }

    private func i8(_ offset: Int) throws -> Int {
        Int(Int8(bitPattern: UInt8(try u8(offset))))
    }

    private func u16(_ offset: Int) throws -> Int {
        (try u8(offset) << 8) | (try u8(offset + 1))
    }

    private func i16(_ offset: Int) throws -> Int {
        Int(Int16(bitPattern: UInt16(try u16(offset))))
    }

    private func u32(_ offset: Int) throws -> Int {
        (try u16(offset) << 16) | (try u16(offset + 2))
    }

    /// Reads a NUL-terminated string, tolerating the Latin-1 text Amiga tools wrote.
    private func string(at offset: Int, maxLength: Int) -> String {
        guard offset > 0, offset < bytes.count, maxLength > 0 else { return "" }
        let end = min(offset + maxLength, bytes.count)
        var slice = [UInt8]()
        for i in offset..<end {
            if bytes[i] == 0 { break }
            slice.append(bytes[i])
        }
        guard !slice.isEmpty else { return "" }
        return String(decoding: slice, as: UTF8.self).contains("\u{FFFD}")
            ? String(slice.map { Character(UnicodeScalar($0)) })
            : String(decoding: slice, as: UTF8.self)
    }

    // MARK: - Module header

    private func parse() throws -> MMDModule {
        guard bytes.count >= 52 else { throw MMDLoadError.tooShort }

        let id = String(bytes[0..<4].map { Character(UnicodeScalar($0)) })
        switch id {
        case "MMD0", "MMD1":
            break
        case "MMD2", "MMD3":
            throw MMDLoadError.unsupportedFormat(id)
        default:
            throw MMDLoadError.unknownFormat(id)
        }

        var module = MMDModule()
        module.formatID = id
        let isMMD1 = (id == "MMD1")

        let songPtr = try u32(8)
        let blockArrPtr = try u32(16)
        let sampleArrPtr = try u32(24)
        let expDataPtr = try u32(32)

        guard songPtr > 0 else { throw MMDLoadError.corrupt("missing song structure") }

        try parseSong(at: songPtr, into: &module)
        try parseBlocks(arrayAt: blockArrPtr, count: module.blocks.count, isMMD1: isMMD1, into: &module)

        // Instrument headers were already sized by parseSong (numsamples).
        if sampleArrPtr > 0 {
            try parseInstruments(arrayAt: sampleArrPtr, into: &module)
        }
        if expDataPtr > 0 {
            try parseExpData(at: expDataPtr, into: &module)
        }

        module.numTracks = module.blocks.map(\.tracks).max() ?? 4
        return module
    }

    // MARK: - MMD0song

    private func parseSong(at base: Int, into module: inout MMDModule) throws {
        // struct MMD0sample sample[63] — 8 bytes each, then the song fields.
        var instruments = [MMDModule.Instrument]()
        for i in 0..<63 {
            let s = base + i * 8
            var instr = MMDModule.Instrument()
            instr.repeatStart = (try u16(s)) * 2
            instr.repeatLength = (try u16(s + 2)) * 2
            instr.midiChannel = try u8(s + 4)
            instr.volume = min(64, try u8(s + 6))
            instr.transpose = try i8(s + 7)
            instruments.append(instr)
        }

        let numBlocks = try u16(base + 504)
        let songLen = try u16(base + 506)

        guard numBlocks <= 0xFFFF, songLen <= 256 else {
            throw MMDLoadError.corrupt("implausible block/sequence count")
        }

        var sequence = [Int]()
        for i in 0..<songLen {
            sequence.append(try u8(base + 508 + i))
        }

        module.defaultTempo = try u16(base + 764)
        module.playTranspose = try i8(base + 766)

        let flags = try u8(base + 767)
        let flags2 = try u8(base + 768)
        module.volumesAreHex = (flags & 0x10) != 0
        module.ptSliding = (flags & 0x20) != 0
        module.is8Channel = (flags & 0x40) != 0
        module.bpmMode = (flags2 & 0x20) != 0
        module.rowsPerBeat = (flags2 & 0x1F) + 1
        module.usesMixing = (flags2 & 0x80) != 0

        module.ticksPerLine = max(1, try u8(base + 769))

        var trackVolumes = [Int]()
        for i in 0..<16 { trackVolumes.append(max(1, try u8(base + 770 + i))) }
        module.trackVolumes = trackVolumes
        module.masterVolume = max(1, try u8(base + 786))

        let numSamples = try u8(base + 787)
        module.instruments = Array(instruments.prefix(max(0, min(63, numSamples))))

        // Drop sequence entries pointing at blocks that do not exist.
        module.playSequence = sequence.filter { $0 < numBlocks }
        module.blocks = Array(repeating: MMDModule.Block(), count: numBlocks)
    }

    // MARK: - Blocks

    private func parseBlocks(arrayAt tablePtr: Int, count: Int, isMMD1: Bool, into module: inout MMDModule) throws {
        guard count > 0 else { return }
        guard tablePtr > 0 else { throw MMDLoadError.corrupt("missing block table") }

        for index in 0..<count {
            let blockPtr = try u32(tablePtr + index * 4)
            guard blockPtr > 0 else { continue }

            var block = MMDModule.Block()
            let noteBase: Int
            let entrySize: Int

            if isMMD1 {
                block.tracks = try u16(blockPtr)
                block.lines = (try u16(blockPtr + 2)) + 1
                let infoPtr = try u32(blockPtr + 4)
                noteBase = blockPtr + 8
                entrySize = 4
                if infoPtr > 0 {
                    let namePtr = try u32(infoPtr + 4)
                    let nameLen = try u32(infoPtr + 8)
                    block.name = string(at: namePtr, maxLength: min(nameLen, 64))
                }
            } else {
                block.tracks = try u8(blockPtr)
                block.lines = (try u8(blockPtr + 1)) + 1
                noteBase = blockPtr + 2
                entrySize = 3
            }

            guard block.tracks > 0, block.tracks <= 64, block.lines > 0, block.lines <= 3200 else {
                throw MMDLoadError.corrupt("block \(index) has implausible dimensions")
            }

            let cellCount = block.tracks * block.lines
            guard noteBase + cellCount * entrySize <= bytes.count else {
                throw MMDLoadError.corrupt("block \(index) extends past end of file")
            }

            var notes = [MMDModule.Note]()
            notes.reserveCapacity(cellCount)
            for cell in 0..<cellCount {
                let p = noteBase + cell * entrySize
                var note = MMDModule.Note()
                if isMMD1 {
                    // xnnnnnnn xxiiiiii cccccccc dddddddd
                    note.note = Int(bytes[p]) & 0x7F
                    note.instrument = Int(bytes[p + 1]) & 0x3F
                    note.command = Int(bytes[p + 2])
                    note.data = Int(bytes[p + 3])
                } else {
                    // xynnnnnn iiiicccc dddddddd
                    let b0 = Int(bytes[p]), b1 = Int(bytes[p + 1])
                    note.note = b0 & 0x3F
                    note.instrument = ((b0 & 0x80) >> 3) | ((b0 & 0x40) >> 1) | (b1 >> 4)
                    note.command = b1 & 0x0F
                    note.data = Int(bytes[p + 2])
                }
                notes.append(note)
            }
            block.notes = notes
            module.blocks[index] = block
        }
    }

    // MARK: - Instruments

    private func parseInstruments(arrayAt tablePtr: Int, into module: inout MMDModule) throws {
        for index in module.instruments.indices {
            let instrPtr = try u32(tablePtr + index * 4)
            guard instrPtr > 0 else { continue }

            let length = try u32(instrPtr)
            let type = try i16(instrPtr + 4)

            // Synthetic (-1) and hybrid (-2) instruments have their own waveform
            // machinery; we leave them silent rather than playing noise.
            guard type >= 0 else { continue }

            let is16Bit = (type & 0x10) != 0
            let isStereo = (type & 0x20) != 0
            let dataStart = instrPtr + 6

            guard length > 0, dataStart + length <= bytes.count else {
                // Truncated sample: keep the header, play nothing.
                continue
            }

            var samples = [Float]()
            if is16Bit {
                let frames = length / 2
                samples.reserveCapacity(frames)
                for i in 0..<frames {
                    let value = Int16(bitPattern: UInt16(try u16(dataStart + i * 2)))
                    samples.append(Float(value) / 32768.0)
                }
            } else {
                samples.reserveCapacity(length)
                for i in 0..<length {
                    samples.append(Float(Int8(bitPattern: bytes[dataStart + i])) / 128.0)
                }
            }

            // Stereo samples are stored as two consecutive blocks; mix to mono so
            // the Paula-style channel model stays intact.
            if isStereo, samples.count >= 2 {
                let half = samples.count / 2
                var mono = [Float]()
                mono.reserveCapacity(half)
                for i in 0..<half { mono.append((samples[i] + samples[i + half]) * 0.5) }
                samples = mono
            }

            module.instruments[index].data = samples

            // Repeat values from the song header are in the sample's own units.
            let count = samples.count
            var start = module.instruments[index].repeatStart
            var repLen = module.instruments[index].repeatLength
            if is16Bit { start /= 2; repLen /= 2 }
            module.instruments[index].repeatStart = min(max(0, start), count)
            module.instruments[index].repeatLength = min(repLen, count - module.instruments[index].repeatStart)
        }
    }

    // MARK: - MMD0exp

    private func parseExpData(at base: Int, into module: inout MMDModule) throws {
        guard base + 56 <= bytes.count else { return }

        let expSmpPtr = try u32(base + 4)
        let sExtEntries = try u16(base + 8)
        let sExtEntrySize = try u16(base + 10)
        let annoPtr = try u32(base + 12)
        let annoLen = try u32(base + 16)
        let iinfoPtr = try u32(base + 20)
        let iExtEntries = try u16(base + 24)
        let iExtEntrySize = try u16(base + 26)
        let songNamePtr = try u32(base + 44)
        let songNameLen = try u32(base + 48)

        if annoPtr > 0, annoLen > 0 {
            module.annotation = string(at: annoPtr, maxLength: min(annoLen, 4096))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if songNamePtr > 0, songNameLen > 0 {
            module.songName = string(at: songNamePtr, maxLength: min(songNameLen, 256))
                .trimmingCharacters(in: .whitespaces)
        }

        // InstrExt: finetune lives here. The spec warns that entries beyond 63
        // must be ignored, and that entrsz decides which fields actually exist.
        if expSmpPtr > 0, sExtEntrySize >= 4 {
            let usable = min(min(sExtEntries, 63), module.instruments.count)
            for i in 0..<usable {
                let e = expSmpPtr + i * sExtEntrySize
                guard e + 4 <= bytes.count else { break }
                module.instruments[i].finetune = try i8(e + 3)
            }
        }

        // MMDInstrInfo: instrument names.
        if iinfoPtr > 0, iExtEntrySize > 0 {
            let usable = min(iExtEntries, module.instruments.count)
            for i in 0..<usable {
                let e = iinfoPtr + i * iExtEntrySize
                module.instruments[i].name = string(at: e, maxLength: min(iExtEntrySize, 40))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
