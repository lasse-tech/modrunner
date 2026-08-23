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
        case toggleTracker, toggleFilter
        case seek(Double)
        case setVolume(Double)
        /// A line of the playlist, which is how a module is chosen.
        case play(Int)
        // The title bar. Zoom is not here: on the Amiga it switched between the
        // window's two sizes, and the two sizes this window has are with the
        // tracker and without, so it is the same action as the Tracks button.
        case closeWindow, minimise, sendToBack, beginDrag
        case openFiles, openDrawer, showAbout, dismissAbout
        /// The three shapes the player has, and the way back to the middle one.
        case toggleMini, toggleFullScreen, leaveLayout
        case cycleVisualisation, setVisualisation(PlayerScreen.Visualisation)
    }

    /// How long the pointer has to sit still before its tool tip comes up, in
    /// frames of the fifty-a-second loop below.
    private static let tooltipDelay = 20

    static func run(_ arguments: Arguments) throws -> Int32 {
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

        // Nothing has to be loaded for the window to go up. The skin already
        // draws the empty player — it says "no module" and leaves the fields
        // dashed — and Project > Open Files fills it, so an empty playlist is
        // a state to open in rather than a reason to refuse. A module named on
        // the command line still has to load: being handed a file and silently
        // showing an empty window would be worse than saying so.
        var module: MMDModule?
        if let first = playlist.first {
            let loaded = try ModuleLoader.load(url: first.url)
            module = loaded
            replayer.load(module: loaded)
        }

        do {
            try audio.start()
        } catch {
            // A window without sound is still worth showing — the tracker
            // scrolls, the meters do not.
            warn("no audio output: \(error.localizedDescription)")
        }
        if module != nil { replayer.play() }

        var showTracker = !arguments.has("--no-tracker")
        var layout = PlayerScreen.Layout.window
        var visualisation = PlayerScreen.Visualisation.levels
        /// The size the stage got when the window took the screen. Nil in the
        /// other two layouts, and the only thing that says whether the backend
        /// actually managed it.
        var stage: (width: Int, height: Int)?

        var screen = PlayerScreen(module: module, snapshot: replayer.snapshot(),
                                  playlist: playlist.map(\.title),
                                  currentIndex: playlist.isEmpty ? nil : index,
                                  showTracker: showTracker)

        let window = try Window.open(title: "ModRunner",
                                     width: PlayerScreenRenderer.width(for: screen),
                                     height: PlayerScreenRenderer.height(for: screen))
        defer { window.close() }

        var running = true
        // The menu is a drag: raised on the right button, tracked while it is
        // held, acted on when it comes up. Nil the rest of the time.
        var menu: PlayerScreen.MenuSelection?
        var showAbout = false

        // Where the pointer is, how long it has been there, and whether it has
        // been clicked since it last moved — between them, whether a tool tip
        // is owed.
        var pointer: (x: Int, y: Int)?
        var hoverTicks = 0
        var tipSuppressed = false

        /// Something to say that the module cannot say for itself, shown in the
        /// status line for a couple of seconds. Only used when a gadget cannot
        /// do what it offers, which beats a button that does nothing at all.
        var notice: (text: String, ticks: Int)?

        /// Where a chooser should open: beside the module being played, or
        /// nowhere in particular when there is none.
        func currentDrawer() -> URL? {
            guard playlist.indices.contains(index) else { return nil }
            return playlist[index].url.deletingLastPathComponent()
        }

        /// Switches to an entry and starts it. A file that will not load is
        /// passed over rather than fatal: the playlist is whatever the user
        /// pointed at, and one bad file in it should not take the window down.
        func show(_ position: Int) {
            guard playlist.indices.contains(position),
                  let loaded = try? ModuleLoader.load(url: playlist[position].url) else { return }
            index = position
            module = loaded
            replayer.load(module: loaded)
            replayer.play()
        }

        /// Adds what the chooser handed back, skipping anything already listed.
        /// Nothing starts playing: the macOS app appends too, and having Open
        /// interrupt the music would be a surprise rather than a convenience.
        func add(_ urls: [URL]) {
            for url in ModuleLoader.modules(in: urls)
            where !playlist.contains(where: { $0.url == url }) {
                playlist.append((url, url.deletingPathExtension().lastPathComponent))
            }
        }

        /// Gives the screen back before changing shape. Called from everything
        /// that leaves the stage, so the window cannot be left covering the
        /// display in a layout that no longer fills it.
        func leaveStage() {
            guard stage != nil else { return }
            _ = window.setFullScreen(false)
            stage = nil
        }

        /// A layout change makes every rectangle on screen a different one, so
        /// whatever the pointer was over it is not over it any more.
        func changed(to next: PlayerScreen.Layout) {
            layout = next
            pointer = nil
            hoverTicks = 0
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
                guard !playlist.isEmpty else { break }
                let step = { if case .nextModule = action { return 1 } else { return -1 } }()
                show((index + step + playlist.count) % playlist.count)
            case .play(let position): show(position)
            case .toggleTracker: showTracker.toggle()
            // The Amiga low-pass, switched by the power LED on the machine
            // itself. The replayer applies it as it mixes, so it takes
            // effect on the next buffer rather than needing a reload.
            case .toggleFilter: replayer.filterEnabled.toggle()
            case .closeWindow: running = false
            case .minimise: window.minimise()
            case .sendToBack: window.sendToBack()
            case .beginDrag: window.beginDrag()
            case .openFiles:
                let wasEmpty = playlist.isEmpty
                add(window.chooseFiles(startingAt: currentDrawer()))
                // Opening into an empty player starts playing, because there is
                // nothing to interrupt. With a module already up, Open only
                // appends, the way the macOS app does.
                if wasEmpty { show(0) }
            case .openDrawer:
                let wasEmpty = playlist.isEmpty
                if let drawer = window.chooseDrawer(startingAt: currentDrawer()) { add([drawer]) }
                if wasEmpty { show(0) }
            case .showAbout:
                // The requester is a page of text and the strip is a hundred
                // pixels tall, so asking who wrote this comes back to the
                // player first rather than being shown a box with its middle
                // cut out.
                if layout == .mini { leaveStage(); changed(to: .window) }
                showAbout = true
            case .dismissAbout: showAbout = false
            case .cycleVisualisation: visualisation = visualisation.next
            case .setVisualisation(let choice): visualisation = choice
            case .toggleMini:
                leaveStage()
                changed(to: layout == .mini ? .window : .mini)
            case .toggleFullScreen:
                if layout == .stage {
                    leaveStage()
                    changed(to: .window)
                } else if let size = window.setFullScreen(true) {
                    stage = size
                    changed(to: .stage)
                } else {
                    // X11 has no implementation of this yet. Saying so is the
                    // whole difference between a gadget that cannot and a
                    // gadget that is broken.
                    notice = ("this window backend has no full screen", 150)
                }
            case .leaveLayout:
                leaveStage()
                changed(to: .window)
            case .setVolume(let fraction):
                replayer.gain = Float(Swift.min(1, Swift.max(0, fraction)))
            case .seek(let fraction):
                // The slider addresses the play sequence, which is what the
                // position field counts in.
                guard let module else { break }
                let count = module.playSequence.count
                guard count > 0 else { break }
                let target = Int((Double(count) * fraction).rounded(.down))
                replayer.seek(toSequencePosition: min(count - 1, max(0, target)))
            }
        }

        while running {
            // The stage is drawn to whatever the window actually got, not to
            // what it asked for. On a display with a scaling factor those are
            // different numbers, and drawing to the wrong one puts the picture
            // up at the wrong size with its bottom off the screen.
            if layout == .stage, window.size.width > 0, window.size.height > 0 {
                stage = window.size
            }

            // The scope and the ripple read the mix; the meters do not, and the
            // audio thread holds the same lock the waveform is copied under.
            let snapshot: Replayer.Snapshot
            var wave: [Float] = []
            if visualisation == .levels {
                snapshot = replayer.snapshot()
            } else {
                (snapshot, wave) = replayer.uiState(waveformSamples: 320)
            }

            let rows: Int
            switch layout {
            case .window: rows = 17
            case .mini:   rows = 0
            case .stage:
                rows = PlayerScreenRenderer.stageTrackerRows(width: stage?.width ?? 0,
                                                             height: stage?.height ?? 0,
                                                             tracks: module?.numTracks ?? 4)
            }

            screen = PlayerScreen(module: module, snapshot: snapshot,
                                  playlist: playlist.map(\.title),
                                  currentIndex: playlist.isEmpty ? nil : index,
                                  status: notice?.text ?? "",
                                  visibleRows: rows,
                                  showTracker: showTracker,
                                  layout: layout,
                                  waveform: wave,
                                  visualisation: visualisation)
            if let stage {
                screen.stageWidth = stage.width
                screen.stageHeight = stage.height
            }
            screen.filterEnabled = replayer.filterEnabled
            screen.volume = Double(replayer.gain)
            screen.menu = menu
            screen.showAbout = showAbout

            // A tool tip waits for the pointer to settle, and the menu owns the
            // pointer while it is up.
            if let pointer, menu == nil, !tipSuppressed {
                hoverTicks += 1
                if hoverTicks >= tooltipDelay,
                   let text = PlayerScreenRenderer.help(at: pointer.x, y: pointer.y, in: screen) {
                    screen.tooltip = PlayerScreen.Tooltip(text: text, x: pointer.x, y: pointer.y)
                }
            }

            let canvas = PlayerScreenRenderer.render(screen)
            // Showing or hiding the tracker changes the canvas height, and so
            // does switching layout; the hit testing works in canvas
            // coordinates. A window that kept the old size would scale the
            // picture and leave every button somewhere other than where it is.
            if window.size.width != canvas.width || window.size.height != canvas.height {
                window.resize(width: canvas.width, height: canvas.height)
            }
            try window.present(canvas)

            for event in window.poll() {
                switch event {
                case .closed:
                    running = false
                case .key(let key):
                    tipSuppressed = true
                    switch key {
                    // A requester takes the escape first: it is what the key
                    // most obviously means while one is up. After that it is
                    // the way out of the stage and the strip, which is what the
                    // stage's own footer says it is.
                    case .escape:
                        if showAbout { showAbout = false }
                        else if layout != .window { perform(.leaveLayout) }
                        else { running = false }
                    case .space:
                        if snapshot.isPlaying { replayer.pause() } else { replayer.play() }
                    case .left: replayer.previousPosition()
                    case .right: replayer.nextPosition()
                    case .character("q"): running = false
                    case .character("t"): showTracker.toggle()
                    default: break
                    }
                case .mouseDown(let x, let y):
                    tipSuppressed = true
                    // Not while the menu is up: the right button owns the
                    // pointer until it is let go.
                    if menu == nil, let action = hit(x: x, y: y, screen: screen) {
                        perform(action)
                    }
                case .rightMouseDown(let x, let y):
                    // No menu over a requester, for the same reason the buttons
                    // underneath it are out of reach.
                    guard !showAbout else { break }
                    tipSuppressed = true
                    menu = PlayerScreenRenderer.menuSelection(at: x, y: y,
                                                              current: .init(), in: screen)
                case .mouseMoved(let x, let y):
                    if pointer?.x != x || pointer?.y != y {
                        pointer = (x, y)
                        hoverTicks = 0
                        tipSuppressed = false
                    }
                    if let current = menu {
                        menu = PlayerScreenRenderer.menuSelection(at: x, y: y,
                                                                  current: current, in: screen)
                    }
                case .mouseExited:
                    pointer = nil
                    hoverTicks = 0
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
                show((index + 1) % playlist.count)
            }

            if var held = notice {
                held.ticks -= 1
                notice = held.ticks > 0 ? held : nil
            }

            // Fifty frames a second is more than a chunky interface needs and
            // leaves the machine to the replayer, which is the part with a
            // deadline. Foundation's sleep rather than usleep, which Windows
            // does not have.
            Thread.sleep(forTimeInterval: 0.02)
        }

        leaveStage()
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
        case .fullScreen: return .toggleFullScreen
        case .miniPlayer: return .toggleMini
        case .visualisation(let choice): return .setVisualisation(choice)
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
            case .tracker: return .toggleTracker
            case .filter: return .toggleFilter
            case .openFiles: return .openFiles
            case .visualiser, .visualiserPanel: return .cycleVisualisation
            case .miniPlayer: return .toggleMini
            case .fullScreen: return .toggleFullScreen
            case .playlistEntry(let index): return .play(index)
            case .dismissAbout: return .dismissAbout
            // In the strip, both of these are the way back to the player: the
            // mini player is a mode, not a second window to be closed.
            case .close: return screen.layout == .mini ? .leaveLayout : .closeWindow
            case .zoom: return screen.layout == .mini ? .leaveLayout : .toggleTracker
            case .minimise: return .minimise
            case .depth: return .sendToBack
            case .titleBar: return .beginDrag
            case .songPosition:
                let fraction = Double(x - target.rect.x) / Double(max(1, target.rect.width))
                return .seek(fraction)
            case .volume:
                let fraction = Double(x - target.rect.x) / Double(max(1, target.rect.width))
                return .setVolume(fraction)
            }
        }
        return nil
    }
}
