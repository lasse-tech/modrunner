import Foundation
import ModRunnerKit
import ModRunnerSkin
import ModRunnerWindow

/// The player in a terminal.
///
/// The same three parts as `window`: draw the current state, put it up, act on
/// what the user did. Only the middle one is different, and the picture comes
/// from the same `PlayerScreen` — so a module looks like the same program
/// whether it is on a framebuffer or over ssh, which is the point of having
/// drawn the interface into an array in the first place.
enum TerminalPlayer {

    private static let hint = "SPACE play  ←→ pos  ↑↓ module  +− vol  T tracks  Q quit"

    static func run(_ arguments: Arguments) throws -> Int32 {
        let session = try PlayerSession(paths: arguments.operands,
                                        showTracker: !arguments.has("--no-tracker"))

        // A fixed number of frames written as plain text: no raw mode, no
        // escape sequences, no audio device, nothing that needs a tty. It is
        // how the suite looks at the interface, and how the picture goes into a
        // pipe.
        if let frames = arguments.int("--frames") {
            return plain(session: session,
                         frames: max(1, frames),
                         interval: arguments.double("--seconds") ?? 0.25)
        }

        guard Terminal.isInteractive else {
            warn("`tui` needs a terminal; this is a pipe or a redirect")
            warn("use `--frames 1` to write one frame as plain text, or `play` for sound alone")
            return 2
        }

        let terminal = Terminal()
        if let warning = session.start() {
            warn(warning)
            // Long enough to be read before the alternate screen swallows it.
            Thread.sleep(forTimeInterval: 1.5)
        }

        terminal.enterRawMode()
        defer {
            terminal.leaveRawMode()
            session.finish()
        }

        var running = true
        while running {
            let size = Terminal.size()
            guard size.width >= PlayerScreenTextRenderer.minimumWidth,
                  size.height >= PlayerScreenTextRenderer.minimumHeight else {
                terminal.present(tooSmall(size))
                if handle(terminal.poll(), session: session, layout: nil, screen: nil) { running = false }
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }

            let layout = PlayerScreenTextRenderer.layout(width: size.width,
                                                         height: size.height,
                                                         channels: session.module.numTracks,
                                                         playlistCount: session.entries.count,
                                                         showTracker: session.showTracker)
            var screen = session.screen(visibleRows: layout.trackerRows)
            screen.status += "  ·  \(hint)"
            terminal.present(PlayerScreenTextRenderer.render(screen, layout: layout))

            if handle(terminal.poll(), session: session, layout: layout, screen: screen) {
                running = false
            }
            session.advanceIfEnded()

            // Fifty frames a second is more than a chunky interface needs and
            // leaves the machine to the replayer, which is the part with a
            // deadline.
            Thread.sleep(forTimeInterval: 0.02)
        }
        return 0
    }

    /// Acts on a poll's worth of events; returns true when the user is done.
    private static func handle(_ events: [WindowEvent],
                               session: PlayerSession,
                               layout: PlayerScreenTextRenderer.Layout?,
                               screen: PlayerScreen?) -> Bool {
        for event in events {
            switch event {
            case .closed:
                return true
            case .key(let key):
                switch key {
                case .escape: return true
                case .space: session.playPause()
                case .left: session.previousPosition()
                case .right: session.nextPosition()
                case .up: session.step(module: -1)
                case .down: session.step(module: 1)
                case .character("q"), .character("Q"): return true
                case .character("t"), .character("T"): session.showTracker.toggle()
                case .character("p"), .character("P"): session.step(module: -1)
                case .character("n"), .character("N"): session.step(module: 1)
                case .character("s"), .character("S"): session.stopPlayback()
                case .character("+"), .character("="): session.adjustVolume(by: 0.05)
                case .character("-"), .character("_"): session.adjustVolume(by: -0.05)
                default: break
                }
            case .mouseDown(let x, let y):
                guard let layout, let screen else { break }
                for control in PlayerScreenTextRenderer.controls(for: screen, layout: layout)
                where control.rect.contains(x: x, y: y) {
                    let fraction = Double(x - control.rect.x) / Double(max(1, control.rect.width))
                    session.perform(control.role, at: fraction)
                    break
                }
            default:
                break
            }
        }
        return false
    }

    // MARK: - Without a terminal

    /// `--frames n`: the picture as text on stdout.
    ///
    /// The module is advanced by rendering it into a buffer that is thrown
    /// away rather than by waiting for a device to play it — the same thing
    /// `render` and the duration measurement do. So it needs no audio, makes no
    /// sound, takes no longer than the arithmetic, and gives the same n frames
    /// every time it is run, which is what makes it worth testing against.
    /// `--seconds` sets how much of the module passes between them.
    private static func plain(session: PlayerSession, frames: Int, interval: Double) -> Int32 {
        let size = Terminal.size()
        let layout = PlayerScreenTextRenderer.layout(width: size.width,
                                                     height: size.height,
                                                     channels: session.module.numTracks,
                                                     playlistCount: session.entries.count,
                                                     showTracker: session.showTracker)
        session.startSilently()
        defer { session.finish() }

        for frame in 0..<frames {
            if frame > 0 {
                session.advance(seconds: interval)
                print("")
            }
            let screen = session.screen(visibleRows: layout.trackerRows)
            print(PlayerScreenTextRenderer.render(screen, layout: layout).plainText)
        }
        return 0
    }

    /// Some terminals are simply too small to be this interface, and saying so
    /// is more use than a picture folded into itself.
    private static func tooSmall(_ size: (width: Int, height: Int)) -> TextCanvas {
        var canvas = TextCanvas(width: max(1, size.width), height: max(1, size.height),
                                fill: TextCell(paper: Theme.face))
        let message = "ModRunner needs \(PlayerScreenTextRenderer.minimumWidth)"
            + "×\(PlayerScreenTextRenderer.minimumHeight); this is \(size.width)×\(size.height)"
        canvas.text(message, at: 0, 0, ink: Theme.text, paper: Theme.face)
        return canvas
    }
}
