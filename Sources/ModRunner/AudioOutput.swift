import AVFoundation

/// Pulls audio from the replayer on the render thread, and keeps the replayer
/// told how far ahead of the speakers it is running.
///
/// Output latency is a property of the device, not of the app: on this machine
/// wired output reports a few milliseconds while Bluetooth reported over
/// 300 ms, which is more than two pattern lines. Since the user can change
/// device mid-song, the engine's configuration is watched and the latency —
/// and, if the hardware rate changed with it, the whole graph — is rebuilt.
final class AudioOutput {

    private let engine = AVAudioEngine()
    private let replayer: Replayer
    private var sourceNode: AVAudioSourceNode?
    private var configurationObserver: NSObjectProtocol?
    private var currentSampleRate: Double = 0
    private(set) var isRunning = false

    /// Frames requested by the last render call, for the latency diagnostic.
    nonisolated(unsafe) static var observedRenderFrames = 0

    private var debugging: Bool {
        ProcessInfo.processInfo.environment["MODRUNNER_AUDIO_DEBUG"] == "1"
    }

    init(replayer: Replayer) {
        self.replayer = replayer
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else {
            // Latency can change without the graph being rebuilt — a Bluetooth
            // codec switch, for one — so refresh it whenever playback starts.
            reportLatency()
            return
        }

        try buildGraph()
        observeConfigurationChanges()
        isRunning = true

        // A real device switch cannot be triggered from a test without taking
        // over the user's audio output, so this exercises the same path.
        if ProcessInfo.processInfo.environment["MODRUNNER_SIMULATE_DEVICE_CHANGE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange,
                                                object: self.engine)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        teardownNode()
        isRunning = false
    }

    // MARK: - Graph

    private func buildGraph() throws {
        let output = engine.outputNode
        let sampleRate = output.inputFormat(forBus: 0).sampleRate > 0
            ? output.inputFormat(forBus: 0).sampleRate
            : 44_100

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw NSError(domain: "ModRunner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.t("error.audioFormat")])
        }

        replayer.prepare(sampleRate: sampleRate)
        currentSampleRate = sampleRate

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
            AudioOutput.observedRenderFrames = frames
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node

        engine.prepare()
        try engine.start()
        reportLatency()
    }

    private func teardownNode() {
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
    }

    // MARK: - Latency

    /// Device latency plus the render buffer that is always in flight.
    private func reportLatency() {
        let output = engine.outputNode
        let rate = currentSampleRate > 0 ? currentSampleRate : 44_100
        let bufferLatency = Double(output.auAudioUnit.maximumFramesToRender) / rate
        let latency = output.presentationLatency + bufferLatency
        replayer.setOutputLatency(seconds: latency)

        if debugging {
            print(String(format: "AUDIO rate=%.0f presentationLatency=%.1fms buffer=%.1fms total=%.1fms",
                         rate, output.presentationLatency * 1000,
                         bufferLatency * 1000, latency * 1000))
            fflush(stdout)
        }
    }

    // MARK: - Device changes

    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    /// The engine stops its graph when the hardware changes underneath it, so
    /// this has to put it back together rather than only re-reading the latency.
    private func handleConfigurationChange() {
        guard isRunning else { return }

        let newRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        if debugging {
            print(String(format: "AUDIO configuration changed: %.0f Hz -> %.0f Hz",
                         currentSampleRate, newRate))
            fflush(stdout)
        }

        // A different hardware rate needs a source node in the new format; the
        // node's format is fixed once it is created.
        if newRate > 0, abs(newRate - currentSampleRate) > 1 {
            engine.stop()
            teardownNode()
            do {
                try buildGraph()
            } catch {
                isRunning = false
                if debugging {
                    print("AUDIO could not rebuild the graph: \(error.localizedDescription)")
                    fflush(stdout)
                }
            }
            return
        }

        // Same rate: the graph survives, it just needs restarting, and the new
        // device almost certainly has a different latency.
        if !engine.isRunning {
            try? engine.start()
        }
        reportLatency()
    }
}
