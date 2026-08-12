import AVFoundation

/// Pulls audio from the replayer on the render thread.
final class AudioOutput {

    private let engine = AVAudioEngine()
    private let replayer: Replayer
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    init(replayer: Replayer) {
        self.replayer = replayer
    }

    func start() throws {
        guard !isRunning else { return }

        let output = engine.outputNode
        let outputFormat = output.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw NSError(domain: "ModRunner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the audio format."])
        }

        replayer.prepare(sampleRate: sampleRate)

        let replayer = self.replayer
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            guard buffers.count >= 2,
                  let leftData = buffers[0].mData,
                  let rightData = buffers[1].mData else {
                for buffer in buffers {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = rightData.assumingMemoryBound(to: Float.self)
            replayer.render(left: left, right: right, frames: frames)
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isRunning = false
    }
}
