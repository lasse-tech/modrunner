import Foundation
import ModRunnerKit

let usage = """
modrunner — MED / OctaMED and ProTracker modules on the command line

usage:
  modrunner info   <module>...                 format, size and duration
  modrunner render <module> -o <file>          render to a 16-bit stereo WAV
  modrunner dump   <module> [--block N]        pattern data as text
  modrunner play   <module>...                 play through the audio device
  modrunner screenshot <module> -o <file.png>  draw the Workbench interface
  modrunner window <module>...                 the Workbench player in a window

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

let commands: Set<String> = ["info", "render", "dump", "play", "screenshot", "window"]
let raw = Array(CommandLine.arguments.dropFirst())

if raw.isEmpty || raw.contains("-h") || raw.contains("--help") {
    print(usage)
    exit(raw.isEmpty ? 1 : 0)
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
    warn("run `modrunner --help` for the commands")
    exit(1)
} catch {
    warn(error.localizedDescription)
    exit(1)
}
