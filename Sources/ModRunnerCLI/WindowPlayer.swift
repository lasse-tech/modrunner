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
/// are here.
enum WindowPlayer {

    /// What a click on the skin means. Hit testing against the rectangles the
    /// renderer reports, rather than a widget tree: the skin has no notion of a
    /// control, and for a fixed layout with nine of them it does not need one.
    private enum Action {
        case previousModule, previousPosition, playPause, stop, nextPosition, nextModule
        case toggleTracker
        case seek(Double)
    }

    static func run(_ arguments: Arguments) throws -> Int32 {
        guard !arguments.operands.isEmpty else { throw CommandError.noModules }
        guard Window.isAvailable else {
            warn("this platform has no window backend; the macOS app is the interface there")
            return 2
        }

        var playlist: [(url: URL, title: String)] = []
        for path in arguments.operands {
            let url = URL(fileURLWithPath: path)
            playlist.append((url, url.deletingPathExtension().lastPathComponent))
        }

        var index = 0
        let replayer = Replayer()
        let audio = AudioOutput(replayer: replayer)
        var module = try ModuleLoader.load(url: playlist[0].url)
        replayer.load(module: module)

        do {
            try audio.start()
        } catch {
            // A window without sound is still worth showing — the tracker
            // scrolls, the meters do not.
            warn("no audio output: \(error.localizedDescription)")
        }
        replayer.play()

        var showTracker = !arguments.has("--no-tracker")
        var screen = PlayerScreen(module: module, snapshot: replayer.snapshot(),
                                  playlist: playlist.map(\.title), currentIndex: index,
                                  showTracker: showTracker)

        let window = try Window.open(title: "ModRunner",
                                     width: PlayerScreenRenderer.width,
                                     height: PlayerScreenRenderer.height(for: screen))
        defer { window.close() }

        var running = true
        while running {
            let snapshot = replayer.snapshot()
            screen = PlayerScreen(module: module, snapshot: snapshot,
                                  playlist: playlist.map(\.title), currentIndex: index,
                                  showTracker: showTracker)
            let canvas = PlayerScreenRenderer.render(screen)
            try window.present(canvas)

            for event in window.poll() {
                switch event {
                case .closed:
                    running = false
                case .key(let key):
                    switch key {
                    case .escape: running = false
                    case .space:
                        if snapshot.isPlaying { replayer.pause() } else { replayer.play() }
                    case .left: replayer.previousPosition()
                    case .right: replayer.nextPosition()
                    case .character("q"): running = false
                    case .character("t"): showTracker.toggle()
                    default: break
                    }
                case .mouseDown(let x, let y):
                    if let action = hit(x: x, y: y, screen: screen) {
                        switch action {
                        case .playPause:
                            if snapshot.isPlaying { replayer.pause() } else { replayer.play() }
                        case .stop: replayer.stop()
                        case .previousPosition:
                            replayer.previousPosition()
                        case .nextPosition:
                            replayer.nextPosition()
                        case .previousModule, .nextModule:
                            let step = { if case .nextModule = action { return 1 } else { return -1 } }()
                            let next = (index + step + playlist.count) % playlist.count
                            if let loaded = try? ModuleLoader.load(url: playlist[next].url) {
                                index = next
                                module = loaded
                                replayer.load(module: module)
                                replayer.play()
                            }
                        case .toggleTracker:
                            showTracker.toggle()
                        case .seek(let fraction):
                            // The slider addresses the play sequence, which is
                            // what the position field counts in.
                            let count = module.playSequence.count
                            guard count > 0 else { break }
                            let target = Int((Double(count) * fraction).rounded(.down))
                            replayer.seek(toSequencePosition: min(count - 1, max(0, target)))
                        }
                    }
                default:
                    break
                }
            }

            if replayer.snapshot().hasEnded, playlist.count > 1 {
                index = (index + 1) % playlist.count
                if let loaded = try? ModuleLoader.load(url: playlist[index].url) {
                    module = loaded
                    replayer.load(module: module)
                    replayer.play()
                }
            }

            // Fifty frames a second is more than a chunky interface needs and
            // leaves the machine to the replayer, which is the part with a
            // deadline.
            usleep(20_000)
        }

        replayer.stop()
        audio.stop()
        return 0
    }

    /// Which control, if any, is under the pointer.
    private static func hit(x: Int, y: Int, screen: PlayerScreen) -> Action? {
        for target in PlayerScreenRenderer.controls(for: screen) {
            guard x >= target.rect.x, x < target.rect.maxX,
                  y >= target.rect.y, y < target.rect.maxY else { continue }
            switch target.role {
            case .previousModule: return .previousModule
            case .previousPosition: return .previousPosition
            case .playPause: return .playPause
            case .stop: return .stop
            case .nextPosition: return .nextPosition
            case .nextModule: return .nextModule
            case .tracker: return .toggleTracker
            case .songPosition:
                let fraction = Double(x - target.rect.x) / Double(max(1, target.rect.width))
                return .seek(fraction)
            }
        }
        return nil
    }
}
