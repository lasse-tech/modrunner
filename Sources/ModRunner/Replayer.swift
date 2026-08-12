import Foundation

/// A Paula-style replayer for MMD0/MMD1 modules.
///
/// The design mirrors the original hardware: four (or more) voices, each holding
/// a sample pointer, a period and a volume. A tick loop drives the effects and
/// the mixer resamples each voice into the output buffer.
///
/// Timing follows OctaMED: `ticksPerLine` timing pulses per line, and a tempo
/// that converts to a ProTracker-style BPM (see `beatsPerMinute`).
final class Replayer {

    // MARK: - Tuning constants

    /// PAL Paula clock. Sample rate of a voice = clock / period.
    private static let amigaClockPAL: Double = 3_546_895.0

    /// Periods for MED notes 1...36 (C-1 ... B-3), i.e. the ProTracker table.
    private static let basePeriods: [Int] = [
        856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
        428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
        214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
    ]

    private static let sineTable: [Int] = [
          0,  24,  49,  74,  97, 120, 141, 161, 180, 197, 212, 224,
        235, 244, 250, 253, 255, 253, 250, 244, 235, 224, 212, 197,
        180, 161, 141, 120,  97,  74,  49,  24,
    ]

    // MARK: - Voice state

    private struct Voice {
        var instrument: Int = 0          // 1-based, 0 = none
        var sampleData: [Float] = []
        var loopStart: Int = 0
        var loopLength: Int = 0
        var isLooping: Bool = false

        var position: Double = 0
        var step: Double = 0
        var isActive: Bool = false

        var period: Int = 0
        var targetPeriod: Int = 0        // for tone portamento
        var portaSpeed: Int = 0
        var finetune: Int = 0

        var volume: Int = 0              // 0...64
        var trackVolume: Int = 64

        var vibratoPos: Int = 0
        var vibratoSpeed: Int = 0
        var vibratoDepth: Int = 0
        var tremoloPos: Int = 0
        var tremoloSpeed: Int = 0
        var tremoloDepth: Int = 0

        var arpeggioBase: Int = 0
        var arpeggioData: Int = 0

        var noteDelayTicks: Int = -1     // 0x0F F2/F4/F5, 0x1F level 1
        var retriggerEvery: Int = 0      // 0x0F F1/F3, 0x1F level 2
        var cutAtTick: Int = -1          // 0x18
        var loopLine: Int = 0            // 0x16
        var loopCount: Int = 0
        var pendingNote: MMDModule.Note? = nil

        /// Peak level since the last UI poll, for the VU meters.
        var meter: Float = 0
    }

    // MARK: - Public snapshot (read by the UI)

    struct Snapshot {
        var isPlaying = false
        var sequencePosition = 0
        var block = 0
        var line = 0
        /// How far playback has moved through the current line, 0...1. Lets a
        /// view scroll continuously rather than jumping a whole row at a time.
        var lineProgress = 0.0
        var lineCount = 64
        var tempo = 33
        var ticksPerLine = 6
        var beatsPerMinute = 125.0
        var channelMeters: [Float] = []
        var channelNotes: [Int] = []
        var channelInstruments: [Int] = []
        var elapsedSeconds = 0.0
        var progress = 0.0
        var hasEnded = false
    }

    // MARK: - Stored state

    private let lock = NSLock()
    private var module = MMDModule()
    private var voices: [Voice] = []

    private var sampleRate: Double = 44_100
    private var samplesUntilTick: Double = 0
    private var samplesPerTick: Double = 0

    private var tick = 0
    private var ticksPerLine = 6
    private var tempo = 33
    private var currentLine = 0
    private var sequencePosition = 0
    private var currentBlockIndex = 0

    private var pendingPositionJump: Int? = nil
    private var pendingLineBreak: Int? = nil
    private var pendingLoopLine: Int? = nil     // 0x16
    private var lineRepeatsRemaining = 0        // 0x1E
    private var songEnded = false

    private var playing = false
    private var elapsedSamples: Double = 0
    private var linesPlayed = 0

    /// 0 = mono, 1 = the hard left/right split of real Amiga hardware, which is
    /// tiring on headphones. 0.45 matches what other players default to.
    var stereoSeparation: Double = 0.45
    /// Master gain applied after the module's own master volume. Kept below
    /// unity so four voices at full volume still leave headroom.
    var gain: Float = 0.5

    // MARK: - Lifecycle

    func prepare(sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        self.sampleRate = sampleRate
        recomputeTiming()
    }

    func load(module newModule: MMDModule) {
        lock.lock(); defer { lock.unlock() }
        module = newModule
        voices = (0..<max(4, newModule.numTracks)).map { index in
            var voice = Voice()
            voice.trackVolume = newModule.trackVolumes.indices.contains(index)
                ? newModule.trackVolumes[index] : 64
            return voice
        }
        tempo = newModule.defaultTempo
        ticksPerLine = newModule.ticksPerLine
        resetPositionLocked()
        recomputeTiming()
    }

    func play() {
        lock.lock(); defer { lock.unlock() }
        if songEnded { resetPositionLocked() }
        playing = true
    }

    func pause() {
        lock.lock(); defer { lock.unlock() }
        playing = false
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        playing = false
        resetPositionLocked()
        silenceVoicesLocked()
    }

    /// Jumps to a position in the play sequence.
    func seek(toSequencePosition position: Int) {
        lock.lock(); defer { lock.unlock() }
        guard !module.playSequence.isEmpty else { return }
        sequencePosition = min(max(0, position), module.playSequence.count - 1)
        currentBlockIndex = module.playSequence[sequencePosition]
        currentLine = 0
        tick = 0
        songEnded = false
        samplesUntilTick = 0
        linesPlayed = linesBefore(sequencePosition: sequencePosition)
        elapsedSamples = 0
        silenceVoicesLocked()
    }

    func nextPosition() { seek(toSequencePosition: currentPosition() + 1) }
    func previousPosition() { seek(toSequencePosition: currentPosition() - 1) }

    private func currentPosition() -> Int {
        lock.lock(); defer { lock.unlock() }
        return sequencePosition
    }

    private func resetPositionLocked() {
        sequencePosition = 0
        currentBlockIndex = module.playSequence.first ?? 0
        currentLine = 0
        tick = 0
        tempo = module.defaultTempo
        ticksPerLine = module.ticksPerLine
        samplesUntilTick = 0
        elapsedSamples = 0
        linesPlayed = 0
        songEnded = false
        pendingPositionJump = nil
        pendingLineBreak = nil
        pendingLoopLine = nil
        lineRepeatsRemaining = 0
        recomputeTiming()
    }

    private func silenceVoicesLocked() {
        for i in voices.indices {
            voices[i].isActive = false
            voices[i].volume = 0
            voices[i].meter = 0
        }
    }

    private func linesBefore(sequencePosition position: Int) -> Int {
        var total = 0
        for i in 0..<min(position, module.playSequence.count) {
            let blockIndex = module.playSequence[i]
            if module.blocks.indices.contains(blockIndex) { total += module.blocks[blockIndex].lines }
        }
        return total
    }

    // MARK: - Tempo

    /// OctaMED tempo -> BPM, following the behaviour OpenMPT documents.
    private func beatsPerMinuteLocked() -> Double {
        let t = Double(tempo)
        if module.bpmMode && !module.is8Channel {
            if tempo < 7 { return 111.5 }
            return t * Double(module.rowsPerBeat) / 4.0
        }
        if module.is8Channel && tempo > 0 {
            let table: [Double] = [179, 164, 152, 141, 131, 123, 116, 110, 104, 99]
            return table[min(tempo, 10) - 1]
        }
        if tempo > 0 && tempo <= 10 {
            return (6.0 * 1_773_447.0 / 14_500.0) / t
        }
        return t / 0.264
    }

    private func recomputeTiming() {
        let bpm = max(20.0, min(700.0, beatsPerMinuteLocked()))
        samplesPerTick = sampleRate * 2.5 / bpm
    }

    // MARK: - Rendering

    /// Fills interleaved-free stereo buffers. Called from the audio thread.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        lock.lock(); defer { lock.unlock() }

        for i in 0..<frames { left[i] = 0; right[i] = 0 }

        guard playing, !voices.isEmpty else { return }

        var offset = 0
        while offset < frames {
            if samplesUntilTick <= 0 {
                processTick()
                samplesUntilTick += samplesPerTick
                if songEnded {
                    playing = false
                    silenceVoicesLocked()
                    return
                }
            }
            let chunk = min(frames - offset, max(1, Int(samplesUntilTick.rounded(.up))))
            mix(left: left + offset, right: right + offset, frames: chunk)
            samplesUntilTick -= Double(chunk)
            elapsedSamples += Double(chunk)
            offset += chunk
        }
    }

    private func mix(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let masterScale = Float(module.masterVolume) / 64.0 * gain
        // Amiga hardware panning: voices 0 and 3 left, 1 and 2 right.
        let separation = Float(max(0, min(1, stereoSeparation)))
        let near = 0.5 + 0.5 * separation
        let far = 0.5 - 0.5 * separation

        for index in voices.indices {
            guard voices[index].isActive, !voices[index].sampleData.isEmpty else { continue }

            let isLeft = (index % 4 == 0 || index % 4 == 3)
            let gainL = isLeft ? near : far
            let gainR = isLeft ? far : near

            let voiceVolume = Float(voices[index].volume) / 64.0
                * Float(voices[index].trackVolume) / 64.0
                * masterScale
            var peak: Float = 0

            voices[index].sampleData.withUnsafeBufferPointer { samples in
                var position = voices[index].position
                let step = voices[index].step
                let count = samples.count
                let loopStart = voices[index].loopStart
                let loopEnd = voices[index].loopStart + voices[index].loopLength
                let looping = voices[index].isLooping && loopEnd > loopStart

                var frame = 0
                while frame < frames {
                    if position >= Double(count) || (looping && position >= Double(loopEnd)) {
                        if looping {
                            let span = Double(loopEnd - loopStart)
                            position = Double(loopStart) + (position - Double(loopEnd)).truncatingRemainder(dividingBy: span)
                        } else {
                            voices[index].isActive = false
                            break
                        }
                    }

                    // Catmull-Rom interpolation. Linear resampling adds audible
                    // aliasing on these short 8-bit samples; the cubic curve is
                    // much closer to what a real Paula plus its output filter
                    // produced, and to what other players do.
                    let i0 = Int(position)
                    guard i0 >= 0, i0 < count else { voices[index].isActive = false; break }
                    let frac = Float(position - Double(i0))

                    func sample(at index: Int) -> Float {
                        var i = index
                        if i < 0 { i = looping ? loopEnd + i : 0 }
                        if i >= count { i = looping ? loopStart + (i - loopEnd) : count - 1 }
                        return (i >= 0 && i < count) ? samples[i] : 0
                    }

                    let p0 = sample(at: i0 - 1)
                    let p1 = samples[i0]
                    let p2 = sample(at: i0 + 1)
                    let p3 = sample(at: i0 + 2)
                    let a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
                    let b = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
                    let c = -0.5 * p0 + 0.5 * p2
                    let value = (((a * frac + b) * frac + c) * frac + p1) * voiceVolume

                    left[frame] += value * gainL
                    right[frame] += value * gainR
                    let magnitude = abs(value)
                    if magnitude > peak { peak = magnitude }

                    position += step
                    frame += 1
                }
                voices[index].position = position
            }

            if peak > voices[index].meter { voices[index].meter = peak }
        }

        // Soft clip so loud modules distort gracefully rather than wrapping.
        for i in 0..<frames {
            left[i] = softClip(left[i])
            right[i] = softClip(right[i])
        }
    }

    private func softClip(_ x: Float) -> Float {
        if x > 1.0 || x < -1.0 { return x > 0 ? 1.0 - 1.0 / (1.0 + x) : -(1.0 - 1.0 / (1.0 - x)) }
        return x
    }

    // MARK: - Tick processing

    private func processTick() {
        if tick == 0 {
            processLine()
        }
        processEffects()

        tick += 1
        if tick >= ticksPerLine {
            tick = 0
            advanceLine()
        }
    }

    private func advanceLine() {
        // 0x1E replays the current line's commands a number of times before
        // playback moves on.
        if lineRepeatsRemaining > 0 {
            lineRepeatsRemaining -= 1
            return
        }

        linesPlayed += 1

        // 0x16 jumps back to the marked loop line within the same block.
        if let loopLine = pendingLoopLine {
            pendingLoopLine = nil
            currentLine = min(loopLine, max(0, currentBlockLines() - 1))
            return
        }

        if let jump = pendingPositionJump {
            pendingPositionJump = nil
            let breakLine = pendingLineBreak ?? 0
            pendingLineBreak = nil
            guard jump < module.playSequence.count else { songEnded = true; return }
            sequencePosition = jump
            currentBlockIndex = module.playSequence[sequencePosition]
            currentLine = min(breakLine, currentBlockLines() - 1)
            linesPlayed = linesBefore(sequencePosition: sequencePosition) + currentLine
            return
        }

        if let breakLine = pendingLineBreak {
            pendingLineBreak = nil
            advanceSequence(startingAt: breakLine)
            return
        }

        currentLine += 1
        if currentLine >= currentBlockLines() {
            advanceSequence(startingAt: 0)
        }
    }

    private func advanceSequence(startingAt line: Int) {
        sequencePosition += 1
        if sequencePosition >= module.playSequence.count {
            songEnded = true
            sequencePosition = max(0, module.playSequence.count - 1)
            return
        }
        currentBlockIndex = module.playSequence[sequencePosition]
        currentLine = min(line, max(0, currentBlockLines() - 1))
        linesPlayed = linesBefore(sequencePosition: sequencePosition) + currentLine
    }

    private func currentBlockLines() -> Int {
        module.blocks.indices.contains(currentBlockIndex) ? module.blocks[currentBlockIndex].lines : 64
    }

    private func processLine() {
        guard module.blocks.indices.contains(currentBlockIndex) else { return }
        let block = module.blocks[currentBlockIndex]

        for track in 0..<min(block.tracks, voices.count) {
            let note = block.note(line: currentLine, track: track)
            startNote(note, on: track)
        }
    }

    private func startNote(_ note: MMDModule.Note, on track: Int) {
        var voice = voices[track]

        voice.arpeggioData = 0
        voice.noteDelayTicks = -1
        voice.retriggerEvery = 0
        voice.cutAtTick = -1
        voice.pendingNote = nil

        // Note delay and retrigger. The manual defines the 0x0F Fx shorthands
        // in terms of 0x1F: 0FF1 = 1F03, 0FF2 = 1F30, 0FF3 = 1F02. The delays
        // are fractions of a line, so they follow the current TPL rather than
        // a fixed tick count.
        var delay = 0
        var retrigger = 0

        switch note.command {
        case 0x0F:
            switch note.data {
            case 0xF1: retrigger = 3
            case 0xF3: retrigger = 2
            case 0xF2: delay = max(1, ticksPerLine / 2)
            case 0xF4: delay = max(1, ticksPerLine / 3)
            case 0xF5: delay = max(1, 2 * ticksPerLine / 3)
            default: break
            }
        case 0x1F:
            delay = note.data >> 4
            retrigger = note.data & 0x0F
        default:
            break
        }

        voice.retriggerEvery = retrigger

        if delay > 0 {
            voice.noteDelayTicks = delay
            voice.pendingNote = note
            voices[track] = voice
            applyLineEffect(note, on: track, triggeredNote: false)
            return
        }

        voices[track] = voice
        triggerNote(note, on: track)
        applyLineEffect(note, on: track, triggeredNote: note.note > 0)
    }

    private func triggerNote(_ note: MMDModule.Note, on track: Int) {
        var voice = voices[track]

        if note.instrument > 0, note.instrument <= module.instruments.count {
            let instrument = module.instruments[note.instrument - 1]
            voice.instrument = note.instrument
            voice.volume = instrument.volume
            voice.finetune = instrument.finetune
            if instrument.isPlayable {
                voice.sampleData = instrument.data
                voice.loopStart = instrument.repeatStart
                voice.loopLength = instrument.repeatLength
                voice.isLooping = instrument.isLooping
            } else {
                voice.sampleData = []
                voice.isActive = false
            }
        }

        // 0x15 overrides the instrument finetune for this note, so it has to be
        // applied before the period is worked out.
        if note.command == 0x15 {
            voice.finetune = Int(Int8(bitPattern: UInt8(note.data)))
        }

        if note.note > 0 {
            let instrument = voice.instrument > 0 && voice.instrument <= module.instruments.count
                ? module.instruments[voice.instrument - 1] : nil
            let transposed = note.note + (instrument?.transpose ?? 0) + module.playTranspose
            let period = periodFor(note: transposed, finetune: voice.finetune)

            // 0FFD sets the pitch of the note already sounding without
            // replaying it, which avoids the click on looped samples.
            let setPitchOnly = (note.command == 0x0F && note.data == 0xFD)

            // Tone portamento retargets instead of restarting the sample.
            if note.command == 0x03 || note.command == 0x05 {
                voice.targetPeriod = period
                if note.command == 0x03, note.data > 0 { voice.portaSpeed = note.data }
            } else if setPitchOnly {
                voice.period = period
                voice.targetPeriod = period
            } else {
                voice.period = period
                voice.targetPeriod = period
                voice.position = 0
                voice.vibratoPos = 0
                voice.tremoloPos = 0
                voice.isActive = !voice.sampleData.isEmpty

                // 0x19 starts the sample part-way in, in steps of 256 bytes.
                if note.command == 0x19, note.data > 0 {
                    let offset = note.data * 256
                    voice.position = offset < voice.sampleData.count ? Double(offset) : 0
                }
            }
            voice.arpeggioBase = period
        }

        voices[track] = voice
        updateStep(track)
    }

    private func periodFor(note: Int, finetune: Int) -> Int {
        // Notes outside the three ProTracker octaves are reached by halving or
        // doubling; MED itself allows note numbers up to 0x7F.
        let index = note - 1
        guard index >= 0 else { return Replayer.basePeriods[0] }

        var octaveShift = 0
        var tableIndex = index
        while tableIndex >= Replayer.basePeriods.count { tableIndex -= 12; octaveShift += 1 }
        while tableIndex < 0 { tableIndex += 12; octaveShift -= 1 }

        var period = Double(Replayer.basePeriods[tableIndex])
        period /= pow(2.0, Double(octaveShift))
        if finetune != 0 {
            period *= pow(2.0, -Double(finetune) / 96.0)
        }
        return max(28, min(8192, Int(period.rounded())))
    }

    private func updateStep(_ track: Int) {
        let period = max(28, voices[track].period)
        let frequency = Replayer.amigaClockPAL / Double(period)
        voices[track].step = frequency / sampleRate
    }

    // MARK: - Effects

    /// Effects that take place once, on the line itself (tick 0).
    private func applyLineEffect(_ note: MMDModule.Note, on track: Int, triggeredNote: Bool) {
        var voice = voices[track]
        let param = note.data
        let hi = param >> 4
        let lo = param & 0x0F

        switch note.command {
        case 0x00:
            voice.arpeggioData = param

        case 0x03:
            if param > 0 { voice.portaSpeed = param }

        case 0x04, 0x06:
            if note.command == 0x04 {
                if hi > 0 { voice.vibratoSpeed = hi }
                // MED vibrato is twice as deep as ProTracker's.
                if lo > 0 { voice.vibratoDepth = min(15, lo * 2) }
            }

        case 0x07:
            if hi > 0 { voice.tremoloSpeed = hi }
            if lo > 0 { voice.tremoloDepth = lo }

        case 0x09:
            // Set secondary tempo (timing pulses per line).
            if param > 0 && param <= 0x20 { ticksPerLine = param }

        case 0x0B:
            pendingPositionJump = param

        case 0x0C:
            // Volumes are hex or decimal depending on FLAG_VOLHEX. In hex mode
            // the range $80-$C0 does something different: it overwrites the
            // instrument's *default* volume rather than this note's.
            if module.volumesAreHex, param >= 0x80, param <= 0xC0 {
                if voice.instrument > 0, voice.instrument <= module.instruments.count {
                    module.instruments[voice.instrument - 1].volume = param - 0x80
                }
            } else {
                let value = module.volumesAreHex ? param : (hi * 10 + lo)
                voice.volume = min(64, max(0, value))
            }

        case 0x11:
            // Slide pitch up once: acts on the first tick only.
            voice.period = max(28, voice.period - param)

        case 0x12:
            voice.period = min(8192, voice.period + param)

        case 0x14:
            // ProTracker vibrato: half the depth of command 0x04.
            if hi > 0 { voice.vibratoSpeed = hi }
            if lo > 0 { voice.vibratoDepth = lo }

        case 0x16:
            // Repeat lines. Level 00 marks the start, a non-zero level repeats.
            if param == 0 {
                voice.loopLine = currentLine
            } else if voice.loopCount == 0 {
                voice.loopCount = param
                pendingLoopLine = voice.loopLine
            } else {
                voice.loopCount -= 1
                if voice.loopCount > 0 { pendingLoopLine = voice.loopLine }
            }

        case 0x18:
            // Cut note: only meaningful while the level is below TPL.
            if param < ticksPerLine { voice.cutAtTick = param }

        case 0x1A:
            voice.volume = min(64, voice.volume + param)

        case 0x1B:
            voice.volume = max(0, voice.volume - param)

        case 0x1D:
            // Jump to the next sequence entry, starting at the given line.
            pendingLineBreak = param

        case 0x1E:
            if param > 0, lineRepeatsRemaining == 0 { lineRepeatsRemaining = param }

        case 0x0F:
            switch param {
            case 0x00:
                pendingLineBreak = 0
            case 0xFF:
                voice.volume = 0
                voice.isActive = false
            case 0xFE:
                songEnded = true
            case 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF8, 0xF9, 0xFA, 0xFB, 0xFD:
                break   // handled elsewhere, or not applicable to sample playback
            default:
                if param >= 0x01 && param <= 0xF0 {
                    tempo = param
                    recomputeTiming()
                }
            }

        default:
            break
        }

        voices[track] = voice
        if triggeredNote { updateStep(track) }
    }

    /// Effects that run every tick.
    private func processEffects() {
        for track in voices.indices {
            guard module.blocks.indices.contains(currentBlockIndex) else { continue }
            let block = module.blocks[currentBlockIndex]
            guard track < block.tracks else { continue }
            let note = block.note(line: currentLine, track: track)

            var voice = voices[track]
            let param = note.data
            let hi = param >> 4
            let lo = param & 0x0F
            var periodChanged = false

            // Delayed note (0x0F F2)
            if voice.noteDelayTicks >= 0 {
                voice.noteDelayTicks -= 1
                if voice.noteDelayTicks < 0, let pending = voice.pendingNote {
                    voice.pendingNote = nil
                    voices[track] = voice
                    triggerNote(pending, on: track)
                    continue
                }
                voices[track] = voice
                continue
            }

            // Retrigger (0x0F F1 / F3)
            if voice.retriggerEvery > 0, tick > 0, tick % voice.retriggerEvery == 0 {
                voice.position = 0
                voice.isActive = !voice.sampleData.isEmpty
            }

            switch note.command {
            case 0x00:
                if voice.arpeggioData != 0 {
                    let offsets = [0, hi, lo]
                    let semitones = offsets[tick % 3]
                    voice.period = semitones == 0
                        ? voice.arpeggioBase
                        : Int(Double(voice.arpeggioBase) / pow(2.0, Double(semitones) / 12.0))
                    periodChanged = true
                }

            // The manual contrasts 01/02 with 11/12, which "only change the
            // pitch on the first tick of each line" — so these run on every
            // tick, tick 0 included.
            case 0x01:
                voice.period = max(28, voice.period - param); periodChanged = true

            case 0x02:
                voice.period = min(8192, voice.period + param); periodChanged = true

            case 0x03, 0x05:
                if tick > 0, voice.targetPeriod > 0, voice.portaSpeed > 0 {
                    if voice.period < voice.targetPeriod {
                        voice.period = min(voice.targetPeriod, voice.period + voice.portaSpeed)
                    } else if voice.period > voice.targetPeriod {
                        voice.period = max(voice.targetPeriod, voice.period - voice.portaSpeed)
                    }
                    periodChanged = true
                }
                if note.command == 0x05 {
                    applyVolumeSlide(&voice, hi: hi, lo: lo)
                }

            case 0x04, 0x06, 0x14:
                if tick > 0 {
                    voice.vibratoPos = (voice.vibratoPos + voice.vibratoSpeed) & 0x3F
                    let sine = Replayer.sineTable[voice.vibratoPos & 0x1F]
                    var delta = sine * voice.vibratoDepth / 128
                    if voice.vibratoPos >= 32 { delta = -delta }
                    voice.period = max(28, min(8192, voice.arpeggioBase + delta))
                    periodChanged = true
                }
                if note.command == 0x06 {
                    applyVolumeSlide(&voice, hi: hi, lo: lo)
                }

            case 0x07:
                if tick > 0 {
                    voice.tremoloPos = (voice.tremoloPos + voice.tremoloSpeed) & 0x3F
                    let sine = Replayer.sineTable[voice.tremoloPos & 0x1F]
                    var delta = sine * voice.tremoloDepth / 64
                    if voice.tremoloPos >= 32 { delta = -delta }
                    voice.volume = max(0, min(64, voice.volume + delta))
                }

            // "The volume is changed every tick — so if the TPL slider were 6, a
            // decrease value of 1 would lower the volume by 6." That only adds
            // up if tick 0 counts too, unlike ProTracker.
            case 0x0A, 0x0D:
                applyVolumeSlide(&voice, hi: hi, lo: lo)

            default:
                break
            }

            // 0x18 cuts the note on the given tick.
            if voice.cutAtTick >= 0, tick == voice.cutAtTick {
                voice.volume = 0
            }

            voices[track] = voice
            if periodChanged { updateStep(track) }
        }
    }

    private func applyVolumeSlide(_ voice: inout Voice, hi: Int, lo: Int) {
        if hi > 0 {
            voice.volume = min(64, voice.volume + hi)
        } else if lo > 0 {
            voice.volume = max(0, voice.volume - lo)
        }
    }

    // MARK: - UI snapshot

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }

        var snap = Snapshot()
        snap.isPlaying = playing
        snap.sequencePosition = sequencePosition
        snap.block = currentBlockIndex
        snap.line = currentLine
        snap.lineCount = currentBlockLines()
        snap.tempo = tempo
        snap.ticksPerLine = ticksPerLine
        snap.beatsPerMinute = beatsPerMinuteLocked()
        snap.elapsedSeconds = elapsedSamples / sampleRate
        snap.hasEnded = songEnded

        let total = module.totalLines
        snap.progress = total > 0 ? min(1.0, Double(linesPlayed) / Double(total)) : 0

        // Position within the current line: whole ticks plus the fraction of the
        // tick already rendered.
        if ticksPerLine > 0, samplesPerTick > 0 {
            let withinTick = 1.0 - max(0, min(1, samplesUntilTick / samplesPerTick))
            snap.lineProgress = min(1, max(0, (Double(tick) + withinTick) / Double(ticksPerLine)))
        }

        snap.channelMeters = voices.map(\.meter)
        snap.channelInstruments = voices.map(\.instrument)
        snap.channelNotes = voices.map { $0.isActive ? $0.period : 0 }

        // Meters decay once read, so the UI shows a falling peak. Tuned for the
        // 60 Hz polling rate the interface uses.
        for i in voices.indices { voices[i].meter *= 0.75 }

        return snap
    }
}
