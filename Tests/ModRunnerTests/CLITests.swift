import XCTest
@testable import ModRunnerKit

/// Runs the built `modrunner` binary over the example modules.
///
/// Deliberately end to end rather than calling the command functions directly:
/// argument parsing, exit codes and what lands on stdout are the whole point of
/// a command-line tool, and none of them are exercised by calling a function.
final class CLITests: XCTestCase {

    private static let moduleDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples")

    private static let examples = ["Happy Hour", "Magic Noises", "Take it slow", "Terminator II"]

    /// Where the built `modrunner` is.
    ///
    /// On Apple's platforms it sits next to the test bundle. Elsewhere
    /// `Bundle(for:)` does not point into the build directory at all, and this
    /// suite used to skip itself in silence on Linux and Windows — which looks
    /// exactly like passing. The build directory relative to this file is the
    /// answer everywhere; `MODRUNNER_BINARY` overrides it for a build that
    /// puts its products somewhere else.
    private func binary() throws -> URL {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["MODRUNNER_BINARY"] {
            candidates.append(URL(fileURLWithPath: override))
        }

        #if os(Windows)
        let name = "modrunner.exe"
        #else
        let name = "modrunner"
        #endif

        candidates.append(Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(name))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for configuration in ["debug", "release"] {
            candidates.append(root
                .appendingPathComponent(".build")
                .appendingPathComponent(configuration)
                .appendingPathComponent(name))
        }

        guard let url = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw XCTSkip("modrunner has not been built; looked in "
                          + candidates.map(\.path).joined(separator: ", "))
        }
        return url
    }

    @discardableResult
    private func run(_ arguments: [String],
                     environment extra: [String: String] = [:]) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = try binary()
        process.arguments = arguments
        if !extra.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
        }

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Read before waiting: a full pipe buffer would deadlock the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus,
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self))
    }

    private func example(_ name: String) throws -> String {
        let url = Self.moduleDirectory.appendingPathComponent("\(name).med")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "Module not present: \(url.lastPathComponent)")
        return url.path
    }

    // MARK: - info

    func testInfoReadsEveryExample() throws {
        for name in Self.examples {
            let result = try run(["info", "--no-duration", try example(name)])
            XCTAssertEqual(result.status, 0, "\(name): \(result.err)")
            XCTAssertTrue(result.out.contains("format       MMD0"), "\(name) format line missing")
            XCTAssertTrue(result.out.contains("tracks       4"), "\(name) track line missing")
            XCTAssertTrue(result.out.contains(name), "\(name) title missing from:\n\(result.out)")
        }
    }

    /// The duration is measured by rendering, so it is worth one module rather
    /// than four — and worth checking against the figure the README quotes.
    func testInfoMeasuresDuration() throws {
        let result = try run(["info", try example("Happy Hour")])
        XCTAssertEqual(result.status, 0, result.err)

        let line = try XCTUnwrap(result.out.split(separator: "\n")
            .first { $0.contains("duration") }, "no duration line in:\n\(result.out)")
        XCTAssertTrue(line.contains("3:27"), "expected about 3:27, got: \(line)")
    }

    func testInfoFailsOnSomethingElse() throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-module.bin")
        try Data("not a module at all, really".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }

        let result = try run(["info", junk.path])
        XCTAssertEqual(result.status, 1, "a module that will not load has to be an error")
        XCTAssertTrue(result.err.contains("Not a MED module"), "error was: \(result.err)")
    }

    // MARK: - render

    func testRenderWritesPlayableAudio() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("modrunner-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try run(["render", try example("Happy Hour"), "--seconds", "2", "-o", output.path])
        XCTAssertEqual(result.status, 0, result.err)

        let data = try Data(contentsOf: output)
        // 44-byte header, then two seconds of 16-bit stereo at 44100.
        XCTAssertEqual(data.count, 44 + 2 * 44_100 * 4, accuracy: 8)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(data[8..<12], Data("WAVE".utf8))

        // Not silence: the header alone would satisfy the size check.
        let samples = data.dropFirst(44)
        XCTAssertTrue(samples.contains { $0 != 0 }, "the render is all zeroes")
    }

    func testRenderToStdoutIsAWAV() throws {
        let result = try run(["render", try example("Happy Hour"), "--seconds", "1", "-o", "-"])
        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertTrue(result.out.hasPrefix("RIFF"), "stdout did not start with a WAV header")
    }

    // MARK: - dump

    func testDumpWritesNotation() throws {
        let result = try run(["dump", try example("Happy Hour"), "--block", "0"])
        XCTAssertEqual(result.status, 0, result.err)

        // Not split(separator: "\n"): Windows ends its lines differently, and
        // a test that only counts line feeds reports one enormous line there.
        let lines = result.out.split(whereSeparator: \.isNewline)
        XCTAssertTrue(lines.first?.hasPrefix("block 0") ?? false, "first line was: \(lines.first ?? "")")
        XCTAssertTrue(result.out.contains("TRACK 1"))
        // 64 lines of pattern, a header, a column header and a blank line.
        XCTAssertGreaterThanOrEqual(lines.count, 66,
                                    "output was \(result.out.count) characters: "
                                    + String(result.out.prefix(200)).debugDescription)
    }

    func testDumpRejectsABlockThatIsNotThere() throws {
        let result = try run(["dump", try example("Happy Hour"), "--block", "999"])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.err.contains("no block 999"), "error was: \(result.err)")
    }

    // MARK: - tui

    /// `--frames` is the terminal interface with no terminal: it renders the
    /// module rather than playing it, so it needs no device, makes no sound and
    /// draws the same picture every time — which is the only reason a suite can
    /// look at an interactive program at all.
    func testTerminalPlayerDrawsAFrame() throws {
        let result = try run(["tui", try example("Happy Hour"), "--frames", "1"],
                             environment: ["COLUMNS": "80", "LINES": "30"])
        XCTAssertEqual(result.status, 0, result.err)

        let lines = result.out.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 30, "a frame is as tall as the terminal")
        XCTAssertTrue(lines.first?.hasPrefix("┌") ?? false, "first line was: \(lines.first ?? "")")
        XCTAssertTrue(lines.last?.hasPrefix("└") ?? false, "last line was: \(lines.last ?? "")")
        XCTAssertTrue(result.out.contains("Happy Hour"))
        XCTAssertTrue(result.out.contains("TRACKER"))
        XCTAssertTrue(result.out.contains("CH1"), "no level meters")
        // The tracker draws the pattern, in the same notation `dump` uses.
        XCTAssertTrue(result.out.contains("A#2 01"), "no note data in:\n\(result.out)")
    }

    /// Frames apart in time have to be apart in the picture, or the flipbook is
    /// one drawing repeated and the clock in it means nothing.
    func testTerminalPlayerAdvancesBetweenFrames() throws {
        let result = try run(["tui", try example("Happy Hour"), "--frames", "2", "--seconds", "2"],
                             environment: ["COLUMNS": "80", "LINES": "30"])
        XCTAssertEqual(result.status, 0, result.err)

        let frames = result.out.components(separatedBy: "\n\n")
        XCTAssertEqual(frames.count, 2, "expected two frames")
        XCTAssertTrue(frames[0].contains("0:00"), "the first frame is not at the start")
        XCTAssertTrue(frames[1].contains("0:02"), "the second frame did not move on")
    }

    func testTerminalPlayerWithoutATerminalSaysSo() throws {
        // stdout is a pipe here, which is exactly the case being tested.
        let result = try run(["tui", try example("Happy Hour")])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.err.contains("needs a terminal"), "error was: \(result.err)")
        XCTAssertTrue(result.err.contains("--frames"), "the way out was not offered: \(result.err)")
    }

    func testTerminalPlayerNeedsAModule() throws {
        let result = try run(["tui"])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.err.contains("no module given"), "error was: \(result.err)")
    }

    // MARK: - Usage

    func testUnknownCommandIsAnError() throws {
        let result = try run(["frobnicate"])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.err.contains("unknown command"), "error was: \(result.err)")
    }

    func testHelpSucceeds() throws {
        let result = try run(["--help"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.out.contains("modrunner info"))
        XCTAssertTrue(result.out.contains("modrunner tui"))
    }
}

private func XCTAssertEqual(_ lhs: Int, _ rhs: Int, accuracy: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(abs(lhs - rhs) <= accuracy, "\(lhs) is not within \(accuracy) of \(rhs)",
                  file: file, line: line)
}
