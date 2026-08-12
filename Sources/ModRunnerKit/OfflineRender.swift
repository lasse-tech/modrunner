import Foundation

/// Rendering a module without an audio device.
///
/// `Replayer.render` was always able to do this — the test suite has rendered
/// through it from the start — but the only caller was the audio callback. This
/// is the entry point everything else uses: the command line, the export test,
/// and anything that wants to measure a module rather than hear it.
public enum OfflineRender {

    /// Frames handed to the replayer at a time. The same order of magnitude as
    /// a real audio callback, so effects that depend on buffer boundaries
    /// behave as they do live.
    private static let chunk = 512

    /// A module that never ends — one whose sequence loops without an end
    /// marker — would otherwise render until the disk fills.
    public static let defaultLimit: Double = 15 * 60

    public struct Result {
        public var left: [Float]
        public var right: [Float]
        public var sampleRate: Double
        /// True when the module reached its end rather than the time limit.
        public var reachedEnd: Bool

        public var seconds: Double { Double(left.count) / sampleRate }
    }

    /// Renders `seconds` of audio, or the whole module when `seconds` is nil.
    public static func render(module: MMDModule,
                              seconds: Double? = nil,
                              sampleRate: Double = 44_100,
                              filterEnabled: Bool = false,
                              limit: Double = defaultLimit) -> Result {
        let replayer = Replayer()
        replayer.prepare(sampleRate: sampleRate)
        replayer.filterEnabled = filterEnabled
        // The display offset is a live-playback concern; offline it would shift
        // the reported position against the samples actually written.
        replayer.setOutputLatency(seconds: 0)
        replayer.load(module: module)
        replayer.play()

        let cap = Int((seconds ?? limit) * sampleRate)
        var left: [Float] = [], right: [Float] = []
        left.reserveCapacity(cap)
        right.reserveCapacity(cap)

        var chunkLeft = [Float](repeating: 0, count: chunk)
        var chunkRight = [Float](repeating: 0, count: chunk)
        var reachedEnd = false

        while left.count < cap {
            let frames = min(chunk, cap - left.count)
            chunkLeft.withUnsafeMutableBufferPointer { l in
                chunkRight.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
                }
            }
            left.append(contentsOf: chunkLeft[0..<frames])
            right.append(contentsOf: chunkRight[0..<frames])

            // Only an open-ended render stops early; asking for a fixed length
            // means the caller wants that length, silence included.
            if seconds == nil, replayer.snapshot().hasEnded {
                reachedEnd = true
                break
            }
        }

        return Result(left: left, right: right, sampleRate: sampleRate, reachedEnd: reachedEnd)
    }

    /// How long the module plays, by rendering it and throwing the audio away.
    /// There is no shortcut: tempo changes, pattern breaks and position jumps
    /// mean the length is a property of the playroutine, not of the file.
    public static func duration(of module: MMDModule,
                                sampleRate: Double = 44_100,
                                limit: Double = defaultLimit) -> (seconds: Double, reachedEnd: Bool) {
        let replayer = Replayer()
        replayer.prepare(sampleRate: sampleRate)
        replayer.setOutputLatency(seconds: 0)
        replayer.load(module: module)
        replayer.play()

        var scratchLeft = [Float](repeating: 0, count: chunk)
        var scratchRight = [Float](repeating: 0, count: chunk)
        let cap = Int(limit * sampleRate)
        var rendered = 0

        while rendered < cap {
            scratchLeft.withUnsafeMutableBufferPointer { l in
                scratchRight.withUnsafeMutableBufferPointer { r in
                    replayer.render(left: l.baseAddress!, right: r.baseAddress!, frames: chunk)
                }
            }
            rendered += chunk
            if replayer.snapshot().hasEnded {
                return (Double(rendered) / sampleRate, true)
            }
        }
        return (Double(rendered) / sampleRate, false)
    }
}
