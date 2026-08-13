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
        // The title bar. Zoom is not here: on the Amiga it switched between the
        // window's two sizes, and the two sizes this window has are with the
        // tracker and without, so it is the same action as the Tracks button.
        case closeWindow, minimise, sendToBack, beginDrag
        case openFiles, openDrawer, showAbout, dismissAbout
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
        // The menu is a drag: raised on the right button, tracked while it is
        // held, acted on when it comes up. Nil the rest of the time.
        var menu: PlayerScreen.MenuSelection?
        var showAbout = false

        /// Adds what the chooser handed back, skipping anything already listed.
        /// Nothing starts playing: the macOS app appends too, and having Open
        /// interrupt the music would be a surprise rather than a convenience.
        func add(_ urls: [URL]) {
            for url in ModuleLoader.modules(in: urls)
            where !playlist.contains(where: { $0.url == url }) {
                playlist.append((url, url.deletingPathExtension().lastPathComponent))
            }
        }

        // One place where an action happens, because two things ask for them
        // now — the buttons on the skin and the menu over it.
        func perform(_ action: Action) {
            switch action {
            case .playPause:
                if replayer.snapshot().isPlaying { replayer.pause() } else { replayer.play() }
            case .stop: replayer.stop()
            case .previousPosition: replayer.previousPosition()
            case .nextPosition: replayer.nextPosition()
            case .previousModule, .nextModule:
                let step = { if case .nextModule = action { return 1 } else { return -1 } }()
                let next = (index + step + playlist.count) % playlist.count
                if let loaded = try? ModuleLoader.load(url: playlist[next].url) {
                    index = next
                    module = loaded
                    replayer.load(module: module)
                    replayer.play()
                }
            case .toggleTracker: showTracker.toggle()
            case .closeWindow: running = false
            case .minimise: window.minimise()
            case .sendToBack: window.sendToBack()
            case .beginDrag: window.beginDrag()
            case .openFiles:
                add(window.chooseFiles(startingAt: playlist[index].url.deletingLastPathComponent()))
            case .openDrawer:
                let here = playlist[index].url.deletingLastPathComponent()
                if let drawer = window.chooseDrawer(startingAt: here) { add([drawer]) }
            case .showAbout: showAbout = true
            case .dismissAbout: showAbout = false
            case .seek(let fraction):
                // The slider addresses the play sequence, which is what the
                // position field counts in.
                let count = module.playSequence.count
                guard count > 0 else { break }
                let target = Int((Double(count) * fraction).rounded(.down))
                replayer.seek(toSequencePosition: min(count - 1, max(0, target)))
            }
        }

        while running {
            let snapshot = replayer.snapshot()
            screen = PlayerScreen(module: module, snapshot: snapshot,
                                  playlist: playlist.map(\.title), currentIndex: index,
                                  showTracker: showTracker)
            screen.menu = menu
            screen.showAbout = showAbout
            let canvas = PlayerScreenRenderer.render(screen)
            // Showing or hiding the tracker changes the canvas height, and the
            // hit testing works in canvas coordinates. A window that kept the
            // old size would scale the picture and leave every button somewhere
            // other than where it is drawn.
            if window.size.width != canvas.width || window.size.height != canvas.height {
                window.resize(width: canvas.width, height: canvas.height)
            }
            try window.present(canvas)

            for event in window.poll() {
                switch event {
                case .closed:
                    running = false
                case .key(let key):
                    switch key {
                    // A requester takes the escape first: it is what the key
                    // most obviously means while one is up.
                    case .escape:
                        if showAbout { showAbout = false } else { running = false }
                    case .space:
                        if snapshot.isPlaying { replayer.pause() } else { replayer.play() }
                    case .left: replayer.previousPosition()
                    case .right: replayer.nextPosition()
                    case .character("q"): running = false
                    case .character("t"): showTracker.toggle()
                    default: break
                    }
                case .mouseDown(let x, let y):
                    // Not while the menu is up: the right button owns the
                    // pointer until it is let go.
                    if menu == nil, let action = hit(x: x, y: y, screen: screen) {
                        perform(action)
                    }
                case .rightMouseDown(let x, let y):
                    // No menu over a requester, for the same reason the buttons
                    // underneath it are out of reach.
                    guard !showAbout else { break }
                    menu = PlayerScreenRenderer.menuSelection(at: x, y: y,
                                                              current: .init(), in: screen)
                case .mouseMoved(let x, let y):
                    if let current = menu {
                        menu = PlayerScreenRenderer.menuSelection(at: x, y: y,
                                                                  current: current, in: screen)
                    }
                case .rightMouseUp(let x, let y):
                    // Taken down before the action runs, not after: Open puts a
                    // modal dialog on screen, and the last thing drawn behind
                    // it should not be a menu that is no longer open.
                    let held = menu
                    menu = nil
                    if let held {
                        let chosen = PlayerScreenRenderer.menuSelection(at: x, y: y,
                                                                        current: held, in: screen)
                        if let heading = chosen.heading, let entry = chosen.entry {
                            let role = PlayerScreenRenderer.menu(for: screen)[heading].entries[entry].role
                            perform(action(for: role))
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
            // deadline. Foundation's sleep rather than usleep, which Windows
            // does not have.
            Thread.sleep(forTimeInterval: 0.02)
        }

        replayer.stop()
        audio.stop()
        return 0
    }

    /// What a menu item does. Nothing the skin's own buttons cannot also do —
    /// which is the point: the menu is a second road to the same places, the
    /// way an Amiga program gave you both.
    private static func action(for role: MenuRole) -> Action {
        switch role {
        case .playPause: return .playPause
        case .stop: return .stop
        case .previousPosition: return .previousPosition
        case .nextPosition: return .nextPosition
        case .previousModule: return .previousModule
        case .nextModule: return .nextModule
        case .showTracker: return .toggleTracker
        case .minimise: return .minimise
        case .sendToBack: return .sendToBack
        case .quit: return .closeWindow
        case .openFiles: return .openFiles
        case .openDrawer: return .openDrawer
        case .about: return .showAbout
        }
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
            case .tracker, .zoom: return .toggleTracker
            case .dismissAbout: return .dismissAbout
            case .close: return .closeWindow
            case .minimise: return .minimise
            case .depth: return .sendToBack
            case .titleBar: return .beginDrag
            case .songPosition:
                let fraction = Double(x - target.rect.x) / Double(max(1, target.rect.width))
                return .seek(fraction)
            }
        }
        return nil
    }
}
