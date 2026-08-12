import Foundation

/// What the engine needs from an output device: somewhere to push the frames
/// the replayer produces, and an honest answer about how far ahead of the
/// speakers it is running.
///
/// The replayer itself never sees this. It renders into two float buffers and
/// is told a latency; whether those buffers reach CoreAudio, ALSA, PulseAudio,
/// PipeWire or WASAPI is a detail of whichever backend was picked.
protocol AudioSink: AnyObject {
    func start() throws
    func stop()
    var isRunning: Bool { get }
}

/// The output device, whichever one this build and this machine ended up with.
///
/// Apple's platforms default to AVFoundation: it handles device switching and
/// reports presentation latency without being asked, and it has years of this
/// project's tuning behind it. Everywhere else the frames go through
/// miniaudio, which finds whatever the system offers at run time — ALSA,
/// PulseAudio, PipeWire or JACK on Linux, WASAPI on Windows — without a single
/// development package having to be installed to build this.
///
/// `MODRUNNER_AUDIO_BACKEND` overrides the choice, mostly so the miniaudio path
/// can be exercised on a Mac rather than only on the machines that depend on it.
public final class AudioOutput {

    private let sink: AudioSink

    /// Frames requested by the last render call, for the latency diagnostic.
    public nonisolated(unsafe) static var observedRenderFrames = 0

    static var isDebugging: Bool {
        ProcessInfo.processInfo.environment["MODRUNNER_AUDIO_DEBUG"] == "1"
    }

    /// Which backend this build can offer, in the order they are preferred.
    public static var availableBackends: [String] {
        var names: [String] = []
        #if canImport(AVFoundation)
        names.append("avfoundation")
        #endif
        #if canImport(CMiniaudio)
        names.append("miniaudio")
        #endif
        return names
    }

    public private(set) static var activeBackend = "none"

    public init(replayer: Replayer) {
        let requested = ProcessInfo.processInfo.environment["MODRUNNER_AUDIO_BACKEND"]?.lowercased()

        #if canImport(CMiniaudio)
        if requested == "miniaudio" {
            sink = MiniaudioSink(replayer: replayer)
            AudioOutput.activeBackend = "miniaudio"
            return
        }
        #endif

        #if canImport(AVFoundation)
        sink = AVFoundationSink(replayer: replayer)
        AudioOutput.activeBackend = "avfoundation"
        #elseif canImport(CMiniaudio)
        sink = MiniaudioSink(replayer: replayer)
        AudioOutput.activeBackend = "miniaudio"
        #else
        sink = SilentSink()
        AudioOutput.activeBackend = "none"
        #endif
    }

    public func start() throws { try sink.start() }
    public func stop() { sink.stop() }
    var isRunning: Bool { sink.isRunning }
}

/// For a build with no backend at all. It refuses rather than pretending to
/// play, so `play` fails with something a person can act on.
final class SilentSink: AudioSink {

    private(set) var isRunning = false

    func start() throws {
        throw NSError(domain: "ModRunner", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "this build has no audio backend"
        ])
    }

    func stop() {}
}
