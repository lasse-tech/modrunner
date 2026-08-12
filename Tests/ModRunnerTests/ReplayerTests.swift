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

    private func moduleURL(_ name: String) -> URL {
        Self.moduleDirectory.appendingPathComponent("\(name).med")
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

    /// Writes a WAV next to the test run so playback can be checked by ear.
    func testExportWAVForListening() throws {
        let name = ProcessInfo.processInfo.environment["MED_EXPORT"] ?? ""
        try XCTSkipIf(name.isEmpty, "Set MED_EXPORT=<module name> to export a WAV")

        let url = moduleURL(name)
        try skipIfMissing(url)
        let module = try MMDLoader.load(url: url)
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
