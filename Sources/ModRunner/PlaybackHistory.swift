import Foundation

/// What the replayer was doing at a given point on the rendered-sample timeline.
struct PlaybackPosition {
    var renderedSamples: Double = 0
    var sequencePosition = 0
    var block = 0
    var line = 0
    var lineProgress = 0.0
    var lineCount = 64
    var tempo = 33
    var ticksPerLine = 6
    var elapsedSeconds = 0.0
    var linesPlayed = 0
    var channelPeaks: [Float] = []
}

/// A ring of recent playback positions, and a ring of the audio that went with
/// them.
///
/// Audio is rendered ahead of when it is heard — on this machine the output
/// device reported over 300 ms of presentation latency, which is more than two
/// pattern lines at a typical MED tempo. Reading the replayer's live state
/// would therefore show the interface running ahead of the music. Instead the
/// replayer records where it was as it renders, and the interface asks what was
/// happening one output-latency ago.
final class PlaybackHistory {

    private var positions: [PlaybackPosition]
    private var writeIndex = 0
    private var count = 0

    /// Mono mix of everything rendered, for the waveform display.
    private var audio: [Float]
    private var audioWrite = 0
    private let audioMask: Int

    /// Total frames rendered since the history was reset.
    private(set) var renderedSamples: Double = 0

    init(positionCapacity: Int = 1024, audioCapacity: Int = 1 << 16) {
        positions = Array(repeating: PlaybackPosition(), count: positionCapacity)
        audio = Array(repeating: 0, count: audioCapacity)
        audioMask = audioCapacity - 1
        precondition(audioCapacity & audioMask == 0, "audio capacity must be a power of two")
    }

    func reset() {
        writeIndex = 0
        count = 0
        renderedSamples = 0
        audioWrite = 0
        for i in audio.indices { audio[i] = 0 }
    }

    /// Records the state at the end of a rendered chunk.
    func record(_ position: PlaybackPosition) {
        var entry = position
        entry.renderedSamples = renderedSamples
        positions[writeIndex] = entry
        writeIndex = (writeIndex + 1) % positions.count
        count = min(count + 1, positions.count)
    }

    func advance(frames: Int) {
        renderedSamples += Double(frames)
    }

    /// Appends one mixed frame to the audio ring.
    @inline(__always)
    func appendAudio(_ sample: Float) {
        audio[audioWrite & audioMask] = sample
        audioWrite += 1
    }

    /// The most recent recorded position at or before `renderedSamples - delay`.
    /// Returns nil while nothing has been recorded yet.
    func position(delayedBy delaySamples: Double) -> PlaybackPosition? {
        guard count > 0 else { return nil }
        let target = renderedSamples - max(0, delaySamples)

        var best: PlaybackPosition? = nil
        // Walk backwards from the newest entry; the wanted one is usually close.
        for step in 0..<count {
            let index = (writeIndex - 1 - step + positions.count * 2) % positions.count
            let candidate = positions[index]
            if candidate.renderedSamples <= target { return candidate }
            best = candidate
        }
        // The delay reaches further back than the history goes.
        return best
    }

    /// Peak per channel over a short window ending at the delayed position, so
    /// meters read steadily instead of flickering on single chunks.
    func peaks(delayedBy delaySamples: Double, window: Double) -> [Float] {
        guard count > 0 else { return [] }
        let end = renderedSamples - max(0, delaySamples)
        let start = end - window

        var result: [Float] = []
        for step in 0..<count {
            let index = (writeIndex - 1 - step + positions.count * 2) % positions.count
            let candidate = positions[index]
            if candidate.renderedSamples > end { continue }
            if candidate.renderedSamples < start { break }
            if result.isEmpty {
                result = candidate.channelPeaks
            } else {
                for i in result.indices where i < candidate.channelPeaks.count {
                    result[i] = max(result[i], candidate.channelPeaks[i])
                }
            }
        }
        return result
    }

    /// A window of the mixed output ending one output latency ago, for the
    /// waveform view. Values are ordered oldest to newest.
    func waveform(delayedBy delaySamples: Double, count sampleCount: Int, stride: Int = 1) -> [Float] {
        guard sampleCount > 0, audioWrite > 0 else { return [] }
        let span = sampleCount * max(1, stride)
        let end = audioWrite - Int(max(0, delaySamples))
        let start = end - span
        guard end > 0 else { return [] }

        var result = [Float]()
        result.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let index = start + i * max(1, stride)
            result.append(index >= 0 && index < audioWrite ? audio[index & audioMask] : 0)
        }
        return result
    }
}
