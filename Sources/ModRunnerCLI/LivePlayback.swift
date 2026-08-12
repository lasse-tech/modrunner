import Foundation
import ModRunnerKit

#if canImport(AVFoundation)

/// `play` needs a real output device, and over SSH without a logged-in Aqua
/// session CoreAudio usually has none. It fails with that said plainly rather
/// than pretending to play to nothing; `info`, `render` and `dump` run anywhere.
enum LivePlayback {

    static func run(paths: [String]) throws -> Int32 {
        let replayer = Replayer()
        let audio = AudioOutput(replayer: replayer)

        do {
            try audio.start()
        } catch {
            warn("no audio output: \(error.localizedDescription)")
            warn("this needs a logged-in session with an output device; use `render` instead")
            return 2
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            let module: MMDModule
            do {
                module = try ModuleLoader.load(url: url)
            } catch {
                warn("\(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            replayer.load(module: module)
            replayer.play()
            print("playing \(module.displayTitle)  (\(module.formatID), \(module.numTracks) tracks)")

            // The replayer runs on the audio thread; this one only waits for it
            // to reach the end of the sequence.
            while !replayer.snapshot().hasEnded {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            replayer.stop()
        }
        return 0
    }
}

#else

/// Off Apple's platforms there is no output backend yet, so `play` says so
/// instead of failing somewhere less obvious. Everything that renders rather
/// than sounds works exactly as it does on macOS.
enum LivePlayback {

    static func run(paths: [String]) throws -> Int32 {
        warn("play is not supported on this platform: it has no audio backend yet")
        warn("`render` writes the same audio to a WAV file and works everywhere")
        return 2
    }
}

#endif
