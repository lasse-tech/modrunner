#if canImport(CMiniaudio)

import CMiniaudio
import Foundation

/// Output through miniaudio, which is what Linux and Windows play through.
///
/// miniaudio picks its backend at run time and loads the system's audio
/// library itself, so a build machine needs no ALSA or PulseAudio development
/// package and a user's machine needs whichever of them it happens to have.
///
/// The replayer renders into two separate buffers, one per side, because that
/// is how a Paula-style mixer thinks. Devices want the two interleaved, so this
/// keeps a scratch buffer per side and weaves them together on the way out.
/// Allocation happens when the device starts, never in the callback: that runs
/// on the audio thread, where malloc is a dropout waiting to happen.
final class MiniaudioSink: AudioSink {

    private let replayer: Replayer
    private var device = ma_device()
    private var deviceInitialised = false
    private(set) var isRunning = false

    private var left: UnsafeMutablePointer<Float>?
    private var right: UnsafeMutablePointer<Float>?
    private var capacity = 0

    private var debugging: Bool { AudioOutput.isDebugging }

    init(replayer: Replayer) {
        self.replayer = replayer
    }

    deinit {
        teardown()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }

        var config = ma_device_config_init(ma_device_type_playback)
        config.playback.format = ma_format_f32
        config.playback.channels = 2
        // 0 means "whatever the device runs at"; resampling the replayer's
        // output to a rate the hardware did not ask for would only add error.
        config.sampleRate = 0
        config.dataCallback = { device, output, _, frameCount in
            guard let device, let output,
                  let userData = device.pointee.pUserData else { return }
            let sink = Unmanaged<MiniaudioSink>.fromOpaque(userData).takeUnretainedValue()
            sink.render(into: output.assumingMemoryBound(to: Float.self),
                        frames: Int(frameCount))
        }
        config.pUserData = Unmanaged.passUnretained(self).toOpaque()

        guard ma_device_init(nil, &config, &device) == MA_SUCCESS else {
            throw NSError(domain: "ModRunner", code: 3, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("error.audioFormat")
            ])
        }
        deviceInitialised = true

        let sampleRate = Double(device.sampleRate)
        replayer.prepare(sampleRate: sampleRate)
        try growScratch(to: Int(device.playback.internalPeriodSizeInFrames))
        reportLatency(sampleRate: sampleRate)

        guard ma_device_start(&device) == MA_SUCCESS else {
            teardown()
            throw NSError(domain: "ModRunner", code: 4, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("error.audioFormat")
            ])
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        ma_device_stop(&device)
        isRunning = false
    }

    private func teardown() {
        if deviceInitialised {
            ma_device_uninit(&device)
            deviceInitialised = false
        }
        left?.deallocate()
        right?.deallocate()
        left = nil
        right = nil
        capacity = 0
    }

    // MARK: - Rendering

    /// Grows the per-side scratch buffers. Called before the device starts and,
    /// as a safety net, from the callback if a period ever comes in larger than
    /// the one the device promised.
    private func growScratch(to frames: Int) throws {
        guard frames > capacity else { return }
        left?.deallocate()
        right?.deallocate()
        left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        capacity = frames
    }

    private func render(into output: UnsafeMutablePointer<Float>, frames: Int) {
        if frames > capacity {
            // Should not happen — the device tells us its period size up front
            // — but a silent buffer beats writing past the end of one.
            try? growScratch(to: frames)
        }
        guard let left, let right, frames <= capacity else {
            output.update(repeating: 0, count: frames * 2)
            return
        }

        replayer.render(left: left, right: right, frames: frames)
        for frame in 0..<frames {
            output[frame * 2] = left[frame]
            output[frame * 2 + 1] = right[frame]
        }
        AudioOutput.observedRenderFrames = frames
    }

    // MARK: - Latency

    /// miniaudio does not report the device's own presentation latency, so this
    /// is what the graph can account for: the periods it keeps in flight.
    /// Undercounting here makes the display run slightly ahead of the speakers,
    /// which is the direction that reads as tight rather than sloppy.
    private func reportLatency(sampleRate: Double) {
        let rate = sampleRate > 0 ? sampleRate : 44_100
        let period = Double(device.playback.internalPeriodSizeInFrames)
        let periods = Double(device.playback.internalPeriods)
        let latency = period * periods / rate
        replayer.setOutputLatency(seconds: latency)

        if debugging {
            let backend = device.pContext.map { String(cString: ma_get_backend_name($0.pointee.backend)) }
                ?? "unknown"
            print(String(format: "AUDIO miniaudio backend=%@ rate=%.0f period=%.0f x%.0f total=%.1fms",
                         backend, rate, period, periods, latency * 1000))
            fflush(stdout)
        }
    }
}

#endif
