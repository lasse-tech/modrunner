import XCTest
@testable import ModRunner

/// These tests render the modules offline so playback can be checked without
/// an audio device: parsing, tempo, channel activity and overall level.
final class ReplayerTests: XCTestCase {

    /// The example modules that ship with the repository, located relative to
    /// this source file so the tests run anywhere, CI included.
    private static let moduleDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ModRunnerTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("Examples")

    private static let expected: [String: (blocks: Int, sequence: Int, instruments: Int)] = [
        "Happy Hour":    (15, 27, 14),
        "Magic Noises":  (12, 22, 10),
        "Take it slow":  (15, 33,  9),
        "Terminator II": (20, 32, 13),
    ]

    /// Examples carry a `.med` or `.mod` extension; accept a bare name or a
    /// full file name.
    private func moduleURL(_ name: String) -> URL {
        let direct = Self.moduleDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        for ext in ["med", "mod"] {
            let candidate = Self.moduleDirectory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return Self.moduleDirectory.appendingPathComponent("\(name).med")
    }

    private func skipIfMissing(_ url: URL) throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "Module not present: \(url.lastPathComponent)")
    }

    // MARK: - Loading

    func testLoadsAllModules() throws {
        for (name, expect) in Self.expected {
            let url = moduleURL(name)
            try skipIfMissing(url)

            let module = try MMDLoader.load(url: url)
            XCTAssertEqual(module.formatID, "MMD0", "\(name) format")
            XCTAssertEqual(module.blocks.count, expect.blocks, "\(name) block count")
            XCTAssertEqual(module.playSequence.count, expect.sequence, "\(name) sequence length")
            XCTAssertEqual(module.instruments.count, expect.instruments, "\(name) instrument count")
            XCTAssertEqual(module.numTracks, 4, "\(name) track count")
            XCTAssertEqual(module.ticksPerLine, 6, "\(name) ticks per line")
            XCTAssertEqual(module.defaultTempo, 33, "\(name) tempo")
            XCTAssertTrue(module.volumesAreHex, "\(name) should use hex volumes")

            for (index, instrument) in module.instruments.enumerated() where instrument.midiChannel == 0 {
                XCTAssertFalse(instrument.data.isEmpty, "\(name) instrument \(index) has no sample data")
            }
        }
    }

    func testAnnotationIsRead() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)
        XCTAssertTrue(module.annotation.contains("Shayne Ghoosman"), "annotation was: \(module.annotation)")
    }

    func testRejectsNonModule() {
        let junk = Data("not a module at all, really".utf8)
        XCTAssertThrowsError(try MMDLoader.load(data: junk))
    }

    func testRejectsTruncatedModule() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let full = try Data(contentsOf: url)
        // Keep the header but cut the body: the loader must fail, not read garbage.
        let truncated = full.prefix(2048)
        XCTAssertThrowsError(try MMDLoader.load(data: truncated))
    }

    // MARK: - Tempo

    func testTempoConversion() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)

        // deftempo 33 in non-BPM mode is the classic 125 BPM.
        XCTAssertEqual(replayer.snapshot().beatsPerMinute, 125.0, accuracy: 0.5)
    }

    // MARK: - Offline rendering

    /// Renders `seconds` of audio and returns the interleaved stereo frames.
    private func render(module: MMDModule, seconds: Double, sampleRate: Double = 44_100) -> (left: [Float], right: [Float]) {
        let replayer = Replayer()
        replayer.prepare(sampleRate: sampleRate)
        replayer.load(module: module)
        replayer.play()

        let total = Int(seconds * sampleRate)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        let chunk = 512

        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var offset = 0
                while offset < total {
                    let frames = min(chunk, total - offset)
                    replayer.render(left: l.baseAddress! + offset,
                                    right: r.baseAddress! + offset,
                                    frames: frames)
                    offset += frames
                }
            }
        }
        return (left, right)
    }

    func testRendersAudibleAudio() throws {
        for name in Self.expected.keys.sorted() {
            let url = moduleURL(name)
            try skipIfMissing(url)
            let module = try MMDLoader.load(url: url)
            let (left, right) = render(module: module, seconds: 20)

            let peak = zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 0
            let rms = (zip(left, right).reduce(0.0) { $0 + Double($1.0 * $1.0 + $1.1 * $1.1) } / Double(left.count * 2)).squareRoot()

            XCTAssertGreaterThan(peak, 0.05, "\(name) is essentially silent (peak \(peak))")
            XCTAssertLessThanOrEqual(peak, 1.0, "\(name) exceeds full scale (peak \(peak))")
            XCTAssertGreaterThan(rms, 0.005, "\(name) has almost no signal (rms \(rms))")

            // No stretch longer than two seconds should be completely silent.
            let window = Int(44_100 * 2)
            var longestSilence = 0, run = 0
            for i in 0..<left.count {
                if abs(left[i]) < 1e-5 && abs(right[i]) < 1e-5 {
                    run += 1
                    longestSilence = max(longestSilence, run)
                } else {
                    run = 0
                }
            }
            XCTAssertLessThan(longestSilence, window, "\(name) has a \(Double(longestSilence) / 44_100)s silent gap")
        }
    }

    func testAllFourChannelsAreUsed() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.play()

        var everActive = [Bool](repeating: false, count: 4)
        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)

        for _ in 0..<(44_100 / 512 * 30) {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 512)
                }
            }
            let snap = replayer.snapshot()
            for channel in 0..<min(4, snap.channelMeters.count) where snap.channelMeters[channel] > 0.001 {
                everActive[channel] = true
            }
        }

        for channel in 0..<4 {
            XCTAssertTrue(everActive[channel], "channel \(channel + 1) never produced sound")
        }
    }

    /// Audio is rendered ahead of when it is heard, so the interface must read
    /// the position one output latency in the past. Without this the display
    /// runs ahead of the music — at the 313 ms this machine's output device
    /// reports, that is more than two pattern lines.
    func testDisplayLagsRenderingByTheOutputLatency() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)

        func elapsedAfterRendering(latency: Double) -> Double {
            let replayer = Replayer()
            replayer.prepare(sampleRate: 44_100)
            replayer.load(module: module)
            replayer.setOutputLatency(seconds: latency)
            replayer.play()

            var left = [Float](repeating: 0, count: 512)
            var right = [Float](repeating: 0, count: 512)
            for _ in 0..<(44_100 / 512 * 10) {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 512)
                    }
                }
            }
            return replayer.snapshot().elapsedSeconds
        }

        let live = elapsedAfterRendering(latency: 0)
        let delayed = elapsedAfterRendering(latency: 1.0)

        XCTAssertEqual(live - delayed, 1.0, accuracy: 0.1,
                       "a one second output latency must move the display one second back")
        XCTAssertGreaterThan(delayed, 0, "the delayed position should still be usable")
    }

    /// Changing the output device can change the hardware sample rate with it.
    /// The latency is held in seconds for that reason — as a sample count it
    /// would quietly come to mean something else after the switch.
    func testLatencySurvivesASampleRateChange() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.setOutputLatency(seconds: 0.25)
        XCTAssertEqual(replayer.snapshot().outputLatency, 0.25, accuracy: 0.001)

        // As if the user had moved from a 44.1 kHz device to a 48 kHz one.
        replayer.prepare(sampleRate: 48_000)
        XCTAssertEqual(replayer.snapshot().outputLatency, 0.25, accuracy: 0.001,
                       "latency must still mean a quarter of a second at the new rate")

        // And the delayed readout must still be a quarter second behind.
        replayer.play()
        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)
        for _ in 0..<(48_000 / 512 * 5) {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 512)
                }
            }
        }
        let snap = replayer.snapshot()
        XCTAssertEqual(snap.elapsedSeconds, 5.0 - 0.25, accuracy: 0.15)
    }

    /// The limiter must be continuous. An earlier version returned 1.0 for an
    /// input of exactly 1.0 and 0.5 for 1.001, so every peak that crossed full
    /// scale was slammed to half amplitude — a loud crackle at high volume, and
    /// invisible at the default gain because nothing reached full scale.
    func testSoftClipIsContinuousAndBounded() {
        let replayer = Replayer()
        var previous = replayer.softClipForTesting(-3.0)

        var value: Float = -3.0
        while value <= 3.0 {
            let clipped = replayer.softClipForTesting(value)
            XCTAssertLessThanOrEqual(abs(clipped), 1.0, "limiter exceeded full scale at \(value)")
            XCTAssertGreaterThanOrEqual(clipped, previous - 0.001, "limiter is not monotonic at \(value)")
            XCTAssertLessThan(abs(clipped - previous), 0.02,
                              "limiter jumps at \(value): \(previous) -> \(clipped)")
            previous = clipped
            value += 0.001
        }

        // Untouched well below the threshold, and symmetric.
        XCTAssertEqual(replayer.softClipForTesting(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(replayer.softClipForTesting(-0.5), -0.5, accuracy: 0.0001)
        XCTAssertEqual(replayer.softClipForTesting(2.0), -replayer.softClipForTesting(-2.0), accuracy: 0.0001)
    }

    /// The interpolation must wrap around the loop rather than reading off the
    /// ends, or every pass round the loop puts a step into the signal.
    func testLoopedSampleHasNoSeamDiscontinuity() throws {
        // A pure sine whose loop is a whole number of cycles: a correct loop is
        // seamless, so any step at the seam is the interpolator's doing.
        var module = MMDModule()
        module.numTracks = 4
        module.ticksPerLine = 6
        module.defaultTempo = 33
        module.trackVolumes = Array(repeating: 64, count: 16)

        let cycles = 8, period = 64
        let length = cycles * period
        var instrument = MMDModule.Instrument()
        instrument.data = (0..<length).map { sinf(Float($0) / Float(period) * 2 * .pi) }
        instrument.volume = 64
        instrument.repeatStart = 0
        instrument.repeatLength = length
        module.instruments = [instrument]
        XCTAssertTrue(instrument.isLooping)

        var block = MMDModule.Block()
        block.tracks = 4
        block.lines = 64
        var notes = [MMDModule.Note](repeating: MMDModule.Note(), count: 4 * 64)
        notes[0] = MMDModule.Note(note: 13, instrument: 1, command: 0, data: 0)
        block.notes = notes
        module.blocks = [block]
        module.playSequence = [0]

        let (left, _) = render(module: module, seconds: 3)

        // The loop is many passes long at this rate; a seam glitch shows up as a
        // sample-to-sample jump far larger than the sine's own slope.
        var largestStep: Float = 0
        var previous = left[0]
        for i in 1..<left.count {
            largestStep = max(largestStep, abs(left[i] - previous))
            previous = left[i]
        }
        let peak = left.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.01, "the test tone did not play")
        XCTAssertLessThan(largestStep, peak * 0.35,
                          "step of \(largestStep) against a peak of \(peak) — the loop seam clicks")
    }

    /// At the top of the volume slider the mix must still fit in the available
    /// scale. Voices are summed, so without headroom four of them reach twice
    /// full scale and the limiter compresses a few per cent of every sample
    /// continuously — heard as a crunch rather than as music.
    func testFullVolumeDoesNotOverdriveTheMix() throws {
        for name in ["Happy Hour", "Terminator II"] {
            let url = moduleURL(name)
            try skipIfMissing(url)
            let module = try ModuleLoader.load(url: url)

            let replayer = Replayer()
            replayer.prepare(sampleRate: 44_100)
            replayer.load(module: module)
            replayer.gain = 1.0
            replayer.play()

            let total = 44_100 * 30
            var left = [Float](repeating: 0, count: total)
            var right = [Float](repeating: 0, count: total)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    var offset = 0
                    while offset < total {
                        let frames = min(512, total - offset)
                        replayer.render(left: l.baseAddress! + offset,
                                        right: r.baseAddress! + offset, frames: frames)
                        offset += frames
                    }
                }
            }

            let peak = zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 0
            XCTAssertLessThanOrEqual(peak, 1.0, "\(name) exceeds full scale at maximum volume")

            let limited = zip(left, right).reduce(0) { count, pair in
                count + ((abs(pair.0) > 0.75 || abs(pair.1) > 0.75) ? 1 : 0)
            }
            let fraction = Double(limited) / Double(total)
            XCTAssertLessThan(fraction, 0.005,
                              "\(name): the limiter is shaping \(fraction * 100)% of samples")
        }
    }

    /// A one-shot sample that ends on a large value must not be cut off there.
    /// Several samples in these modules end near -0.7 of full scale, and
    /// dropping the voice at that point steps the output straight to zero — a
    /// click on every single note.
    func testSampleEndDoesNotClick() throws {
        var module = MMDModule()
        module.numTracks = 4
        module.ticksPerLine = 6
        module.defaultTempo = 33
        module.trackVolumes = Array(repeating: 64, count: 16)

        // A steady tone that stops abruptly at a large negative value, which is
        // the shape that gave the click.
        var instrument = MMDModule.Instrument()
        let length = 512
        instrument.data = (0..<length).map { _ in Float(-92) / 128.0 }
        instrument.volume = 64
        instrument.repeatStart = 0
        instrument.repeatLength = 2      // ProTracker's "no loop"
        module.instruments = [instrument]
        XCTAssertFalse(instrument.isLooping)

        var block = MMDModule.Block()
        block.tracks = 4
        block.lines = 64
        var notes = [MMDModule.Note](repeating: MMDModule.Note(), count: 4 * 64)
        notes[0] = MMDModule.Note(note: 13, instrument: 1, command: 0, data: 0)
        block.notes = notes
        module.blocks = [block]
        module.playSequence = [0]

        let (left, _) = render(module: module, seconds: 1)

        var largestStep: Float = 0
        var previous = left[0]
        for i in 1..<left.count {
            largestStep = max(largestStep, abs(left[i] - previous))
            previous = left[i]
        }
        let peak = left.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.05, "the test tone did not play")
        XCTAssertLessThan(largestStep, peak * 0.1,
                          "step of \(largestStep) against a peak of \(peak) — the sample end clicks")
    }

    func testWaveformFollowsTheDelayedOutput() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.setOutputLatency(seconds: 0.05)
        replayer.play()

        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)
        for _ in 0..<(44_100 / 512 * 5) {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 512)
                }
            }
        }

        let wave = replayer.waveform(sampleCount: 256, stride: 4)
        XCTAssertEqual(wave.count, 256)
        XCTAssertTrue(wave.contains { $0 != 0 }, "the waveform window should carry signal")
        XCTAssertTrue(wave.allSatisfy { abs($0) <= 1.0 }, "waveform samples must stay in range")
    }

    // MARK: - ProTracker modules

    /// A minimal but valid M.K. module, built in code. The real MOD used during
    /// development is somebody else's music and is not redistributable, so the
    /// loader needs a fixture that can live in the repository and run in CI.
    private func syntheticMOD(channels: Int = 4, patterns: Int = 2, orderLength: Int = 3) -> Data {
        var data = Data(count: 1084)

        func put(_ bytes: [UInt8], at offset: Int) {
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }

        put(Array("test module".utf8), at: 0)

        // One 32-byte sample in slot 1, volume 64, looping.
        let sampleWords = 16
        put([UInt8(sampleWords >> 8), UInt8(sampleWords & 0xFF)], at: 20 + 22)
        put([0], at: 20 + 24)                 // finetune 0
        put([64], at: 20 + 25)                // volume
        put([0, 0], at: 20 + 26)              // repeat start
        put([0, UInt8(sampleWords)], at: 20 + 28)
        put(Array("saw".utf8), at: 20)

        put([UInt8(orderLength)], at: 950)
        put([0], at: 951)
        for i in 0..<orderLength { put([UInt8(i % patterns)], at: 952 + i) }
        put(Array("M.K.".utf8), at: 1080)

        // Patterns: a C-2 (period 428) on channel 0 every fourth row, with a
        // set-volume command so the effect path is exercised too.
        var pattern = Data(count: patterns * 64 * channels * 4)
        for p in 0..<patterns {
            for row in 0..<64 where row % 4 == 0 {
                let offset = ((p * 64 + row) * channels) * 4
                let period = 428
                pattern[offset] = UInt8((1 & 0xF0) | UInt8(period >> 8))
                pattern[offset + 1] = UInt8(period & 0xFF)
                pattern[offset + 2] = UInt8((1 << 4) | 0x0C)   // instrument 1, command C
                pattern[offset + 3] = 64                        // volume 64
            }
        }
        data.append(pattern)

        // A sawtooth, so the render is unmistakably non-silent.
        var sample = Data(count: sampleWords * 2)
        for i in 0..<(sampleWords * 2) {
            sample[i] = UInt8(bitPattern: Int8(truncatingIfNeeded: -128 + i * 8))
        }
        data.append(sample)
        return data
    }

    func testLoadsSyntheticProTrackerModule() throws {
        let module = try ModuleLoader.load(data: syntheticMOD())

        XCTAssertEqual(module.formatID, "M.K.")
        XCTAssertEqual(module.effectDialect, .protracker)
        XCTAssertEqual(module.numTracks, 4)
        XCTAssertEqual(module.blocks.count, 2)
        XCTAssertEqual(module.playSequence, [0, 1, 0])
        XCTAssertEqual(module.instruments.count, 31)
        XCTAssertEqual(module.songName, "test module")
        XCTAssertEqual(module.instruments[0].data.count, 32)
        XCTAssertEqual(module.instruments[0].volume, 64)

        // Period 428 is C-2, which MED numbers as note 13.
        XCTAssertEqual(module.blocks[0].note(line: 0, track: 0).note, 13)
        XCTAssertEqual(module.blocks[0].note(line: 0, track: 0).instrument, 1)
        XCTAssertEqual(module.blocks[0].note(line: 0, track: 0).command, 0x0C)
        XCTAssertEqual(module.blocks[0].note(line: 1, track: 0).note, 0)
    }

    func testSyntheticProTrackerModuleRenders() throws {
        let module = try ModuleLoader.load(data: syntheticMOD())
        let (left, right) = render(module: module, seconds: 4)
        let peak = zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.01, "the synthetic module produced no sound")
    }

    func testRejectsTruncatedProTrackerModule() {
        let truncated = syntheticMOD().prefix(1200)
        XCTAssertThrowsError(try ModuleLoader.load(data: truncated))
    }

    func testLoadsProTrackerModule() throws {
        let url = Self.moduleDirectory.appendingPathComponent("12th Warrior.mod")
        try skipIfMissing(url)

        let module = try ModuleLoader.load(url: url)
        XCTAssertEqual(module.formatID, "M.K.")
        XCTAssertEqual(module.effectDialect, .protracker)
        XCTAssertEqual(module.numTracks, 4)
        XCTAssertEqual(module.blocks.count, 23, "highest pattern in the order + 1")
        XCTAssertEqual(module.playSequence.count, 30)
        XCTAssertEqual(module.instruments.count, 31, "MOD always has 31 slots")
        XCTAssertEqual(module.instruments.filter(\.isPlayable).count, 12)
        XCTAssertEqual(module.songName, "12th warrior")
        XCTAssertTrue(module.blocks.allSatisfy { $0.lines == 64 }, "MOD patterns are 64 rows")

        // ProTracker timing expressed through the BPM mode: 6 ticks at 125 BPM.
        XCTAssertEqual(module.ticksPerLine, 6)
        XCTAssertEqual(module.defaultTempo, 125)
        XCTAssertTrue(module.bpmMode)
    }

    func testProTrackerTempoIsOneTwentyFive() throws {
        let url = Self.moduleDirectory.appendingPathComponent("12th Warrior.mod")
        try skipIfMissing(url)
        let module = try ModuleLoader.load(url: url)

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        XCTAssertEqual(replayer.snapshot().beatsPerMinute, 125.0, accuracy: 0.5)
    }

    func testProTrackerPeriodsMapToNotes() {
        // The three octaves of the ProTracker table, at both ends.
        XCTAssertEqual(MODLoader.note(forPeriod: 856), 1)    // C-1
        XCTAssertEqual(MODLoader.note(forPeriod: 428), 13)   // C-2
        XCTAssertEqual(MODLoader.note(forPeriod: 113), 36)   // B-3
        XCTAssertEqual(MODLoader.note(forPeriod: 0), 0)      // no note
        // A finetuned period should still land on the nearest note.
        XCTAssertEqual(MODLoader.note(forPeriod: 855), 1)
        XCTAssertEqual(MODLoader.note(forPeriod: 430), 13)
    }

    func testProTrackerModuleRendersAudibleAudio() throws {
        let url = Self.moduleDirectory.appendingPathComponent("12th Warrior.mod")
        try skipIfMissing(url)
        let module = try ModuleLoader.load(url: url)
        let (left, right) = render(module: module, seconds: 30)

        let peak = zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.05, "the MOD is essentially silent")
        XCTAssertLessThanOrEqual(peak, 1.0)

        var longestSilence = 0, run = 0
        for i in 0..<left.count {
            if abs(left[i]) < 1e-5 && abs(right[i]) < 1e-5 {
                run += 1
                longestSilence = max(longestSilence, run)
            } else {
                run = 0
            }
        }
        XCTAssertLessThan(longestSilence, Int(44_100 * 2),
                          "gap of \(Double(longestSilence) / 44_100)s")
    }

    func testRejectsFileThatIsNeitherFormat() {
        var junk = Data(repeating: 0x41, count: 2000)
        junk.replaceSubrange(1080..<1084, with: Data("ZZZZ".utf8))
        XCTAssertThrowsError(try ModuleLoader.load(data: junk))
    }

    func testPlaybackAdvancesThroughSequence() throws {
        let url = moduleURL("Happy Hour")
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)
        _ = render(module: module, seconds: 0)   // warm up

        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.play()

        var left = [Float](repeating: 0, count: 4410)
        var right = [Float](repeating: 0, count: 4410)
        // 30 seconds should be well past the first block (7.7s each).
        for _ in 0..<300 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 4410)
                }
            }
        }

        let snap = replayer.snapshot()
        XCTAssertGreaterThan(snap.sequencePosition, 2, "playback did not advance through the sequence")
        XCTAssertGreaterThan(snap.progress, 0.05)
        XCTAssertTrue(snap.isPlaying)
    }

    /// Reports which channels actually produce sound, per ten second window.
    func testChannelActivity() throws {
        let path = ProcessInfo.processInfo.environment["MED_CHANNELS"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set MED_CHANNELS=<module path>")

        let module = try ModuleLoader.load(url: URL(fileURLWithPath: path))
        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.play()

        var left = [Float](repeating: 0, count: 4410)
        var right = [Float](repeating: 0, count: 4410)
        var window = [Float](repeating: 0, count: 8)
        for tenth in 0..<1600 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 4410)
                }
            }
            let snap = replayer.snapshot()
            for i in 0..<min(window.count, snap.channelMeters.count) {
                window[i] = max(window[i], snap.channelMeters[i])
            }
            if tenth % 100 == 99 {
                let marks = window.prefix(module.numTracks).map { $0 > 0.001 ? "#" : "." }
                print(String(format: "CH t=%3ds pos=%2d %@",
                             (tenth + 1) / 10, snap.sequencePosition, marks.joined()))
                window = [Float](repeating: 0, count: 8)
            }
        }
    }

    /// Renders loop-handling variants of one module, to find out which reading
    /// of the repeat fields matches a reference player.
    func testExportLoopVariants() throws {
        let path = ProcessInfo.processInfo.environment["MED_LOOPTEST"] ?? ""
        let outDir = ProcessInfo.processInfo.environment["MED_BATCH_OUT"] ?? ""
        try XCTSkipIf(path.isEmpty || outDir.isEmpty, "Set MED_LOOPTEST and MED_BATCH_OUT")

        let base = try ModuleLoader.load(url: URL(fileURLWithPath: path))
        let seconds = Double(ProcessInfo.processInfo.environment["MED_SECONDS"] ?? "180") ?? 180
        let directory = URL(fileURLWithPath: outDir)

        var variants: [String: MMDModule] = ["asis": base]

        // No loop at all.
        var noLoop = base
        for i in noLoop.instruments.indices { noLoop.instruments[i].repeatLength = 0 }
        variants["noloop"] = noLoop

        // Loop the whole sample.
        var fullLoop = base
        for i in fullLoop.instruments.indices where fullLoop.instruments[i].isLooping {
            fullLoop.instruments[i].repeatStart = 0
            fullLoop.instruments[i].repeatLength = fullLoop.instruments[i].data.count
        }
        variants["fullloop"] = fullLoop

        // Repeat fields taken as bytes rather than words, i.e. not doubled.
        var halved = base
        for i in halved.instruments.indices where halved.instruments[i].isLooping {
            halved.instruments[i].repeatStart /= 2
            halved.instruments[i].repeatLength /= 2
        }
        variants["halved"] = halved

        for (name, module) in variants {
            let (l, r) = render(module: module, seconds: seconds)
            try WAVWriter.write(left: l, right: r, sampleRate: 44_100,
                                to: directory.appendingPathComponent("var_\(name).wav"))
            print("VARIANT \(name) written")
        }
    }

    /// Dumps a checksum of every loaded sample, to compare the loader's idea of
    /// where the sample data lives against an independent extraction.
    func testDumpSampleChecksums() throws {
        let path = ProcessInfo.processInfo.environment["MED_DUMPSAMPLES"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set MED_DUMPSAMPLES=<module path>")

        let module = try ModuleLoader.load(url: URL(fileURLWithPath: path))
        for (index, instrument) in module.instruments.enumerated() where !instrument.data.isEmpty {
            // Back to the stored bytes, so the checksum can be compared directly.
            var sum = 0
            for value in instrument.data {
                sum = (sum + Int(value * 128.0) & 0xFF) & 0xFFFFFF
            }
            print(String(format: "SAMPLE %2d len=%6d sum=%08X first=%4d last=%4d vol=%2d ft=%2d rep=%6d replen=%6d",
                         index + 1, instrument.data.count, sum,
                         Int(instrument.data.first! * 128), Int(instrument.data.last! * 128),
                         instrument.volume, instrument.finetune,
                         instrument.repeatStart, instrument.repeatLength))
        }
    }

    /// Traces playback position over time. Set MED_TRACE to a module path.
    func testTracePlayback() throws {
        let path = ProcessInfo.processInfo.environment["MED_TRACE"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set MED_TRACE=<module path>")

        let module = try ModuleLoader.load(url: URL(fileURLWithPath: path))
        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.play()

        var left = [Float](repeating: 0, count: 4410)
        var right = [Float](repeating: 0, count: 4410)
        var lastPosition = -1
        for tenth in 0..<2000 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: 4410)
                }
            }
            let peak = zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 0
            let snap = replayer.snapshot()
            if snap.sequencePosition != lastPosition || !snap.isPlaying {
                print(String(format: "TRACE t=%.1fs pos=%d/%d block=%d line=%d tpl=%d tempo=%d peak=%.3f playing=%@ ended=%@",
                             Double(tenth) / 10.0, snap.sequencePosition,
                             module.playSequence.count, snap.block, snap.line,
                             snap.ticksPerLine, snap.tempo, peak,
                             snap.isPlaying ? "yes" : "NO", snap.hasEnded ? "YES" : "no"))
                lastPosition = snap.sequencePosition
            }
            if !snap.isPlaying { break }
        }
    }

    /// Renders every module in a directory, for batch comparison against a
    /// reference player. Set MED_BATCH_DIR and MED_BATCH_OUT.
    func testExportBatch() throws {
        let input = ProcessInfo.processInfo.environment["MED_BATCH_DIR"] ?? ""
        let output = ProcessInfo.processInfo.environment["MED_BATCH_OUT"] ?? ""
        try XCTSkipIf(input.isEmpty || output.isEmpty,
                      "Set MED_BATCH_DIR and MED_BATCH_OUT to render a directory")

        let outputDirectory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)

        let files = try FileManager.default
            .contentsOfDirectory(at: URL(fileURLWithPath: input),
                                 includingPropertiesForKeys: nil,
                                 options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in files {
            guard ModuleLoader.looksLikeModule(file) else { continue }
            let module: MMDModule
            do {
                module = try ModuleLoader.load(url: file)
            } catch {
                print("BATCH FAIL \(file.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            let seconds = Double(ProcessInfo.processInfo.environment["MED_SECONDS"] ?? "0") ?? 0
            let duration = seconds > 0 ? seconds : 240
            let (left, right) = render(module: module, seconds: duration)

            let name = file.deletingPathExtension().lastPathComponent
            let out = outputDirectory.appendingPathComponent("\(name).wav")
            try WAVWriter.write(left: left, right: right, sampleRate: 44_100, to: out)
            print("BATCH OK \(file.lastPathComponent) -> \(out.lastPathComponent) "
                  + "[\(module.formatID), \(module.numTracks)ch, "
                  + "\(module.blocks.count) patterns, \(module.playSequence.count) positions]")
        }
    }

    /// Writes a WAV next to the test run so playback can be checked by ear.
    func testExportWAVForListening() throws {
        let name = ProcessInfo.processInfo.environment["MED_EXPORT"] ?? ""
        try XCTSkipIf(name.isEmpty, "Set MED_EXPORT=<module name> to export a WAV")

        let url = moduleURL(name)
        try skipIfMissing(url)
        let module = try ModuleLoader.load(url: url)
        let seconds = Double(ProcessInfo.processInfo.environment["MED_SECONDS"] ?? "30") ?? 30
        let (left, right) = render(module: module, seconds: seconds)

        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MED_OUT"] ?? "/tmp/med-export.wav")
        try WAVWriter.write(left: left, right: right, sampleRate: 44_100, to: out)
        print("Wrote \(out.path)")
    }
}

/// Minimal 16-bit stereo WAV writer, used only by the export test.
enum WAVWriter {
    static func write(left: [Float], right: [Float], sampleRate: Int, to url: URL) throws {
        precondition(left.count == right.count)
        let frames = left.count
        let byteRate = sampleRate * 2 * 2
        let dataSize = frames * 2 * 2

        var out = Data()
        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func le32(_ v: Int) { for i in 0..<4 { out.append(UInt8((v >> (8 * i)) & 0xFF)) } }
        func le16(_ v: Int) { for i in 0..<2 { out.append(UInt8((v >> (8 * i)) & 0xFF)) } }

        ascii("RIFF"); le32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); le32(16); le16(1); le16(2)
        le32(sampleRate); le32(byteRate); le16(4); le16(16)
        ascii("data"); le32(dataSize)

        for i in 0..<frames {
            for value in [left[i], right[i]] {
                let clamped = max(-1.0, min(1.0, value))
                le16(Int(Int16(clamped * 32767)))
            }
        }
        try out.write(to: url)
    }
}
