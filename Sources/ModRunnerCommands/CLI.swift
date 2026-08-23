import Foundation
import ModRunnerKit
import ModRunnerWindow

/// Argument dispatch, shared by the two executables that wrap it.
///
/// There are two on Windows because the subsystem is a property of the linked
/// image rather than something a program can decide at run time: a console
/// binary always gets a console, and a windowed one never does. `modrunner` is
/// the console build, so `info` and `render` can be read and piped; `modrunnerw`
/// is the same program linked for the window, so opening a module does not drag
/// a terminal along behind it. The split is the one `python.exe` and
/// `pythonw.exe` have had for years, for the same reason.
///
/// Elsewhere there is only `modrunner`, which is why this lives in a library
/// rather than in either executable: neither of them is the real one.
public enum CLI {

    static let usage = """
    modrunner — MED / OctaMED and ProTracker modules on the command line

    usage:
      modrunner info   <module>...                 format, size and duration
      modrunner render <module> -o <file>          render to a 16-bit stereo WAV
      modrunner dump   <module> [--block N]        pattern data as text
      modrunner play   <module>...                 play through the audio device
      modrunner screenshot <module> -o <file.png>  draw the classic interface
      modrunner window [module]...                 the classic player in a window

    options:
      -o, --output <file>   where render writes; - writes the WAV to stdout
      --seconds <n>         render only the first n seconds
      --rate <n>            sample rate, default 44100
      --filter              render through the Amiga output filter
      --block <n>           dump one block instead of all of them
      --no-tracker          leave the tracker panel out of the screenshot
      --no-duration         skip the duration measurement in info, which renders
                            the module to find out

    Exit codes: 0 success, 1 a module failed to load, 2 no audio device.
    """

    /// What `--help` says where there is no console to print the usage to.
    ///
    /// Not `usage` in a requester: its columns are aligned with spaces and a
    /// requester draws in a proportional face, so it would arrive as a ragged
    /// block. The build that can lay it out properly is one letter away.
    static let usageWithoutConsole = """
    modrunnerw is the player, linked without a console behind it.

    The commands and their options are in the console build:

        modrunner --help
    """

    static let commands: Set<String> = ["info", "render", "dump", "play", "screenshot", "window"]

    /// Runs the command named on the command line and exits.
    ///
    /// - Parameter defaultCommand: what to do when nothing is named. The console
    ///   build has none and prints its usage. The windowed build opens the
    ///   player: it has no console to print to, and double-clicking a program
    ///   should show something rather than exit in silence.
    /// - Parameter hasConsole: whether there is a stderr worth writing to.
    ///   False in the windowed build, where everything that would have gone
    ///   there goes to a requester instead. Without this the second binary
    ///   would cause the fault it exists to avoid: a module that fails to load
    ///   would take the player down without a word about why.
    public static func main(defaultCommand: String? = nil,
                            hasConsole console: Bool = true) -> Never {
        // Read by `warn`, which is what every command says anything through.
        hasConsole = console
        var raw = Array(CommandLine.arguments.dropFirst())

        if raw.isEmpty, let defaultCommand {
            raw = [defaultCommand]
        }

        if raw.isEmpty || raw.contains("-h") || raw.contains("--help") {
            let status = raw.isEmpty ? Int32(1) : 0
            if !hasConsole,
               Requester.show(usageWithoutConsole, title: "ModRunner", kind: .information) {
                exit(status)
            }
            print(usage)
            exit(status)
        }

        do {
            let arguments = try Arguments(raw, commands: commands)
            let status: Int32
            switch arguments.command {
            case "info":   status = try Commands.info(arguments)
            case "render": status = try Commands.render(arguments)
            case "dump":   status = try Commands.dump(arguments)
            case "play":   status = try Commands.play(arguments)
            case "screenshot": status = try Screenshot.run(arguments)
            case "window": status = try WindowPlayer.run(arguments)
            default:       status = 1        // unreachable: the parser checks the set
            }
            exit(status)
        } catch let error as Arguments.ParseError {
            warn(error.localizedDescription)
            // Only where it can be acted on. In the windowed build this would
            // be a second requester to dismiss, naming a command there is no
            // prompt in front of to type it at.
            if hasConsole { warn("run `modrunner --help` for the commands") }
            exit(1)
        } catch {
            warn(error.localizedDescription)
            exit(1)
        }
    }
}
