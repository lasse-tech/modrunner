import Foundation
import ModRunnerKit
import ModRunnerSkin

/// A module, a playlist and a replayer, and the handful of things a user can do
/// to them.
///
/// Both interactive front ends — `window` on Linux and Windows, `tui` anywhere
/// there is a terminal — are the same player with a different way of drawing
/// it. This is the part that is the same: what is loaded, what is playing, what
/// a press of the play button means. What is left in each front end is its
/// event loop and its renderer, which is all that should differ.
final class PlayerSession {

    struct Entry {
        let url: URL
        let title: String
    }

    private(set) var entries: [Entry]
    private(set) var index = 0
    private(set) var module: MMDModule

    let replayer = Replayer()
    private let audio: AudioOutput

    /// Whether the device opened. A player with no sound is still worth
    /// showing — the tracker scrolls, the meters do not — so this is reported
    /// rather than fatal.
    private(set) var audioAvailable = false

    var showTracker: Bool

    /// 0...1, and also what the volume bar draws.
    private(set) var volume: Double = 1 {
        didSet { replayer.gain = Float(volume) }
    }

    init(paths: [String], showTracker: Bool) throws {
        guard !paths.isEmpty else { throw CommandError.noModules }
        entries = paths.map { path in
            let url = URL(fileURLWithPath: path)
            return Entry(url: url, title: url.deletingPathExtension().lastPathComponent)
        }
        self.showTracker = showTracker
        module = try ModuleLoader.load(url: entries[0].url)
        audio = AudioOutput(replayer: replayer)
        replayer.load(module: module)
    }

    /// Starts the device and playback. Returns what went wrong with the audio,
    /// if anything, for the caller to put in front of the user.
    @discardableResult
    func start() -> String? {
        var warning: String?
        do {
            try audio.start()
            audioAvailable = true
        } catch {
            warning = "no audio output: \(error.localizedDescription)"
        }
        replayer.play()
        return warning
    }

    /// Starts the replayer with no device behind it, for the callers that draw
    /// the interface rather than play it.
    func startSilently() {
        replayer.prepare(sampleRate: 44_100)
        // Live playback reports the position the listener is hearing, which is
        // a buffer or two behind what has been rendered. With nothing playing
        // there is nothing to be behind.
        replayer.setOutputLatency(seconds: 0)
        replayer.load(module: module)
        replayer.play()
    }

    /// Moves the module on by rendering it into a buffer nobody listens to.
    func advance(seconds: Double) {
        let rate = 44_100.0
        let chunk = 512
        var remaining = Int(seconds * rate)
        var left = [Float](repeating: 0, count: chunk)
        var right = [Float](repeating: 0, count: chunk)

        while remaining > 0 {
            let frames = Swift.min(chunk, remaining)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
                }
            }
            remaining -= frames
        }
    }

    func finish() {
        replayer.stop()
        audio.stop()
    }

    func snapshot() -> Replayer.Snapshot { replayer.snapshot() }

    /// The picture, filled from the module and the replayer. `visibleRows` is
    /// how many pattern lines the front end has room for.
    func screen(visibleRows: Int) -> PlayerScreen {
        var screen = PlayerScreen(module: module,
                                  snapshot: replayer.snapshot(),
                                  playlist: entries.map(\.title),
                                  currentIndex: index,
                                  visibleRows: Swift.max(1, visibleRows),
                                  showTracker: showTracker)
        screen.volume = volume
        return screen
    }

    // MARK: - What the user can do

    func playPause() {
        if replayer.snapshot().isPlaying { replayer.pause() } else { replayer.play() }
    }

    func stopPlayback() { replayer.stop() }

    func previousPosition() { replayer.previousPosition() }
    func nextPosition() { replayer.nextPosition() }

    /// Moves through the playlist, wrapping. A module that will not load is
    /// skipped rather than ending the session — a dropped drawer usually has
    /// something in it that is not a module.
    func step(module delta: Int) {
        guard entries.count > 1 || delta == 0 else { return }
        for hop in 1...Swift.max(1, entries.count) {
            let next = ((index + delta * hop) % entries.count + entries.count) % entries.count
            if let loaded = try? ModuleLoader.load(url: entries[next].url) {
                index = next
                module = loaded
                replayer.load(module: loaded)
                replayer.play()
                return
            }
        }
    }

    func seek(fraction: Double) {
        let count = module.playSequence.count
        guard count > 0 else { return }
        let target = Int((Double(count) * fraction).rounded(.down))
        replayer.seek(toSequencePosition: Swift.min(count - 1, Swift.max(0, target)))
    }

    func adjustVolume(by delta: Double) {
        volume = Swift.min(1, Swift.max(0, volume + delta))
    }

    /// Moves to the next module when this one runs out. A single module is left
    /// where it ended rather than looped.
    func advanceIfEnded() {
        guard replayer.snapshot().hasEnded, entries.count > 1 else { return }
        step(module: 1)
    }

    /// Both front ends hit-test against the rectangles their renderer reports
    /// and end up here, so a click means the same thing in a window and in a
    /// terminal.
    func perform(_ role: PlayerScreenRenderer.ControlRole, at fraction: Double = 0) {
        switch role {
        case .previousModule:   step(module: -1)
        case .previousPosition: previousPosition()
        case .playPause:        playPause()
        case .stop:             stopPlayback()
        case .nextPosition:     nextPosition()
        case .nextModule:       step(module: 1)
        case .tracker:          showTracker.toggle()
        case .songPosition:     seek(fraction: fraction)
        }
    }
}
