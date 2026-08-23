import Foundation
import ModRunnerKit
import ModRunnerWindow

/// Whether there is a stderr worth writing to.
///
/// False in the windowed build, which is linked without a console — that
/// being the whole reason it is a second binary. `CLI.main` sets it once
/// before any command runs, and nothing else writes to it.
var hasConsole = true

/// Anything the commands need to say that is not the result itself goes to
/// stderr, so `modrunner render … -o -` can be piped.
///
/// Except where there is no stderr to write to. The windowed build would drop
/// all of it, and a player that is handed a module it cannot open and then
/// exits in silence looks broken — so it goes to a requester there, and back
/// to stderr where the platform has none.
func warn(_ message: String) {
    if !hasConsole, Requester.show(message, title: "ModRunner") { return }
    FileHandle.standardError.write(Data("modrunner: \(message)\n".utf8))
}

enum CommandError: LocalizedError {
    case noModules
    case needsOutput
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .noModules:    return "no module given"
        case .needsOutput:  return "render needs -o <file>, or -o - for stdout"
        case .notWritable(let path): return "cannot write to \(path)"
        }
    }
}

enum Commands {

    // MARK: - info

    /// One line per module, plus the detail underneath. Written so a collection
    /// can be swept and the exit code believed.
    static func info(_ arguments: Arguments) throws -> Int32 {
        guard !arguments.operands.isEmpty else { throw CommandError.noModules }
        let measure = !arguments.has("--no-duration")
        var failures: Int32 = 0

        for path in arguments.operands {
            let url = URL(fileURLWithPath: path)
            do {
                let module = try ModuleLoader.load(url: url)
                let playable = module.instruments.filter(\.isPlayable).count
                let midi = module.instruments.filter { $0.midiChannel > 0 }.count

                print("\(url.lastPathComponent)")
                print("  title        \(module.displayTitle)")
                print("  format       \(module.formatID)")
                print("  tracks       \(module.numTracks)")
                print("  blocks       \(module.blocks.count)")
                print("  sequence     \(module.playSequence.count)")
                print("  lines        \(module.patternLines)")
                print("  notes        \(module.noteCount)")
                print("  instruments  \(module.instruments.count) (\(playable) with samples"
                      + (midi > 0 ? ", \(midi) MIDI" : "") + ")")
                print("  tempo        \(module.defaultTempo) at \(module.ticksPerLine) ticks per line")

                if measure {
                    let (seconds, ended) = OfflineRender.duration(of: module)
                    print("  duration     \(timecode(seconds))\(ended ? "" : " (did not end; limit reached)")")
                }
            } catch {
                warn("\(url.lastPathComponent): \(error.localizedDescription)")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - render

    static func render(_ arguments: Arguments) throws -> Int32 {
        guard let path = arguments.operands.first else { throw CommandError.noModules }
        guard let output = arguments.string("-o", "--output") else { throw CommandError.needsOutput }

        let module = try ModuleLoader.load(url: URL(fileURLWithPath: path))
        let rate = arguments.double("--rate") ?? 44_100
        let seconds = arguments.double("--seconds")

        let result = OfflineRender.render(module: module,
                                          seconds: seconds,
                                          sampleRate: rate,
                                          filterEnabled: arguments.has("--filter"))
        if seconds == nil, !result.reachedEnd {
            warn("stopped at the \(Int(OfflineRender.defaultLimit / 60)) minute limit; the module did not end")
        }

        let wav = WAVWriter.data(left: result.left, right: result.right, sampleRate: Int(rate))
        if output == "-" {
            FileHandle.standardOutput.write(wav)
        } else {
            let url = URL(fileURLWithPath: output)
            do {
                try wav.write(to: url)
            } catch {
                throw CommandError.notWritable(output)
            }
            warn("wrote \(timecode(result.seconds)) to \(url.lastPathComponent)")
        }
        return 0
    }

    // MARK: - dump

    /// The pattern data as text, in OctaMED's notation — the same thing the
    /// tracker panel draws, for eyes that prefer a pager.
    static func dump(_ arguments: Arguments) throws -> Int32 {
        guard let path = arguments.operands.first else { throw CommandError.noModules }
        let module = try ModuleLoader.load(url: URL(fileURLWithPath: path))

        let wanted = arguments.int("--block")
        let blocks = wanted.map { [$0] } ?? Array(module.blocks.indices)

        for index in blocks {
            guard module.blocks.indices.contains(index) else {
                warn("no block \(index); the module has \(module.blocks.count)")
                return 1
            }
            let block = module.blocks[index]
            let tracks = block.tracks

            print("block \(index)  \(block.lines) lines  \(tracks) tracks"
                  + (block.name.isEmpty ? "" : "  \(block.name)"))
            print("LN  " + (0..<tracks).map { String(format: "TRACK %-6d", $0 + 1) }.joined(separator: " "))

            for line in 0..<block.lines {
                let cells = (0..<tracks).map { track -> String in
                    let note = block.note(line: line, track: track)
                    let name = Notation.name(of: note.note)
                    let instrument = Notation.instrument(note.instrument)
                    let command = Notation.command(note.command, note.data)
                    return "\(name) \(instrument) \(command)"
                }
                print(String(format: "%03d ", line) + cells.joined(separator: " "))
            }
            print("")
        }
        return 0
    }

    // MARK: - play

    static func play(_ arguments: Arguments) throws -> Int32 {
        guard !arguments.operands.isEmpty else { throw CommandError.noModules }
        return try LivePlayback.run(paths: arguments.operands)
    }

    // MARK: - Formatting

    static func timecode(_ seconds: Double) -> String {
        String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
