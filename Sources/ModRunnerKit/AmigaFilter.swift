import Foundation

/// The Amiga's output filter.
///
/// An A500 put two low-pass stages between Paula and the audio sockets: a fixed
/// single-pole RC network at roughly 4.9 kHz, and a switchable two-pole
/// Butterworth around 3.3 kHz — the one wired to the power LED, which is why
/// people called it the LED filter. Modules were written and mixed through
/// them, so a lot of period music was never meant to be heard with its top end
/// intact.
///
/// This is off by default. Other players do not apply it either, so leaving it
/// off keeps playback comparable with them; switching it on is closer to what
/// the machine actually sounded like.
public struct AmigaFilter {

    /// The fixed RC stage every A500 had.
    private var fixed = OnePole()
    /// The switchable stage, as two cascaded one-pole sections.
    private var ledA = OnePole()
    private var ledB = OnePole()

    private var sampleRate: Double = 44_100

    /// Whether the switchable stage is engaged.
    public var ledEnabled = false

    mutating func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        fixed.setCutoff(4_900, sampleRate: sampleRate)
        ledA.setCutoff(3_275, sampleRate: sampleRate)
        ledB.setCutoff(3_275, sampleRate: sampleRate)
        reset()
    }

    mutating func reset() {
        fixed.reset()
        ledA.reset()
        ledB.reset()
    }

    @inline(__always)
    mutating func process(_ input: Float) -> Float {
        var value = fixed.process(input)
        if ledEnabled {
            value = ledB.process(ledA.process(value))
        }
        return value
    }

    /// One-pole low-pass: y += a * (x - y).
    private struct OnePole {
        private var state: Float = 0
        private var a: Float = 1

        mutating func setCutoff(_ hertz: Double, sampleRate: Double) {
            let rc = 1.0 / (2.0 * Double.pi * hertz)
            let dt = 1.0 / sampleRate
            a = Float(dt / (rc + dt))
        }

        mutating func reset() { state = 0 }

        @inline(__always)
        mutating func process(_ input: Float) -> Float {
            state += a * (input - state)
            return state
        }
    }
}
