import Foundation
import ModRunnerKit
import ModRunnerSkin
import ModRunnerWindow

/// The player with a window around it, for the platforms that have no app.
///
/// Everything below this already worked on all three: the replayer, miniaudio,
/// and a skin that draws itself into a buffer. This is the loop that ties them
/// together — draw the current state, put it on screen, act on what the user
/// did — and it is deliberately small, because none of the interesting parts
/// are here. What is loaded and what a button means live in `PlayerSession`,
/// which the terminal player uses too.
enum WindowPlayer {

    static func run(_ arguments: Arguments) throws -> Int32 {
        guard !arguments.operands.isEmpty else { throw CommandError.noModules }
        guard Window.isAvailable else {
            warn("this platform has no window backend; the macOS app is the interface there,"
                 + " and `tui` is the one in a terminal")
            return 2
        }

        let session = try PlayerSession(paths: arguments.operands,
                                        showTracker: !arguments.has("--no-tracker"))
        // A window without sound is still worth showing — the tracker scrolls,
        // the meters do not.
        if let warning = session.start() { warn(warning) }

        var screen = session.screen(visibleRows: 17)
        let window = try Window.open(title: "ModRunner",
                                     width: PlayerScreenRenderer.width,
                                     height: PlayerScreenRenderer.height(for: screen))
        defer {
            window.close()
            session.finish()
        }

        var running = true
        while running {
            screen = session.screen(visibleRows: 17)
            try window.present(PlayerScreenRenderer.render(screen))

            for event in window.poll() {
                switch event {
                case .closed:
                    running = false
                case .key(let key):
                    switch key {
                    case .escape, .character("q"): running = false
                    case .space: session.playPause()
                    case .left: session.previousPosition()
                    case .right: session.nextPosition()
                    case .character("t"): session.showTracker.toggle()
                    default: break
                    }
                case .mouseDown(let x, let y):
                    // Hit testing against the rectangles the renderer reports,
                    // rather than a widget tree: the skin has no notion of a
                    // control, and for a fixed layout with nine of them it does
                    // not need one.
                    for control in PlayerScreenRenderer.controls(for: screen)
                    where control.rect.contains(x: x, y: y) {
                        let fraction = Double(x - control.rect.x) / Double(max(1, control.rect.width))
                        session.perform(control.role, at: fraction)
                        break
                    }
                default:
                    break
                }
            }

            session.advanceIfEnded()

            // Fifty frames a second is more than a chunky interface needs and
            // leaves the machine to the replayer, which is the part with a
            // deadline. Foundation's sleep rather than usleep, which Windows
            // does not have.
            Thread.sleep(forTimeInterval: 0.02)
        }
        return 0
    }
}
