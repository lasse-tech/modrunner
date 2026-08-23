import Foundation
import ModRunnerKit

public extension PlayerScreen {

    /// The ways the audio can be drawn. The same three the macOS app offers,
    /// under the same names, because they are the same pictures — one of them
    /// simply happens to be painted into a framebuffer rather than by SwiftUI.
    enum Visualisation: String, CaseIterable, Sendable {
        /// Per-voice level meters.
        case levels
        /// An oscilloscope of the mixed output.
        case waveform
        /// Concentric rings deformed by the mix, seen at a shallow angle.
        case ripple

        /// The name the gadget shows, translated. The keys are the app's own,
        /// so the two interfaces call these the same thing.
        public var title: String { L10n.t("visualizer.\(rawValue)") }

        public var next: Visualisation {
            let all = Visualisation.allCases
            let index = all.firstIndex(of: self) ?? 0
            return all[(index + 1) % all.count]
        }
    }
}

/// Draws whichever visualisation is chosen, into whatever box it is given.
///
/// One box for all three, as on macOS: switching between them must not change
/// the height of the panel, or the window would jump every time.
enum VisualiserRenderer {

    static func draw(_ canvas: inout Canvas, _ screen: PlayerScreen, in rect: Rect) {
        switch screen.visualisation {
        case .levels:   levels(&canvas, screen, rect)
        case .waveform: waveform(&canvas, screen, rect)
        case .ripple:   ripple(&canvas, screen, rect)
        }
    }

    // MARK: - Levels

    private static func levels(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) {
        canvas.bevel(rect, .recessed, fill: Theme.faceDark)
        let inner = rect.inset(by: Theme.bevel + 2)
        let channels = Swift.max(1, screen.meters.count)
        let labelWidth = 4 * Font.cellWidth

        // Stacked while there is height for it, side by side when there is not.
        // The stage's strip is a couple of hundred pixels wide and thirty tall,
        // and four bars stacked in that are four grey smears — which is why the
        // app lays its stage meters out in a row too.
        guard inner.height / channels < 12 else {
            let rowHeight = inner.height / channels
            for (index, level) in screen.meters.enumerated() {
                let y = inner.y + index * rowHeight
                canvas.text("CH\(index + 1)", at: inner.x, y + (rowHeight - Font.cellHeight) / 2,
                            Theme.text)
                canvas.meter(Rect(inner.x + labelWidth, y,
                                  inner.width - labelWidth, Swift.max(5, rowHeight - 3)),
                             level: level)
            }
            return
        }

        let columnWidth = inner.width / channels
        let barHeight = Swift.min(inner.height, 14)
        for (index, level) in screen.meters.enumerated() {
            let x = inner.x + index * columnWidth
            let y = inner.y + (inner.height - barHeight) / 2
            canvas.text("\(index + 1)", at: x, y + (barHeight - Font.cellHeight) / 2, Theme.caption)
            canvas.meter(Rect(x + Font.cellWidth + 2, y,
                              Swift.max(8, columnWidth - Font.cellWidth - 8), barHeight),
                         level: level)
        }
    }

    // MARK: - Waveform

    /// An oscilloscope of the mix as it is being heard. The trace is drawn as
    /// segments rather than as a column per pixel, so a steep edge stays a line
    /// instead of breaking into dots.
    private static func waveform(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) {
        canvas.bevel(rect, .recessed, fill: Theme.screen)
        let inner = rect.inset(by: Theme.bevel + 2)
        guard inner.width > 1, inner.height > 3 else { return }

        let middle = inner.y + inner.height / 2
        canvas.fill(Rect(inner.x, middle, inner.width, 1), Theme.faceDark)

        let samples = screen.waveform
        guard samples.count > 1 else { return }

        // Module output rarely approaches full scale, so the trace carries the
        // same little gain the macOS scope does rather than sitting flat.
        let gain = 2.2
        let amplitude = Double(inner.height - 2) / 2

        func point(_ column: Int) -> (x: Int, y: Int) {
            let index = column * (samples.count - 1) / Swift.max(1, inner.width - 1)
            let value = Swift.max(-1, Swift.min(1, Double(samples[index]) * gain))
            return (inner.x + column, middle - Int((value * amplitude).rounded()))
        }

        var previous = point(0)
        for column in 1..<inner.width {
            let next = point(column)
            canvas.line(from: previous, to: next, Theme.meter)
            // A second pass one pixel down: at this size a hairline trace
            // disappears against the ground.
            canvas.line(from: (previous.x, previous.y + 1), to: (next.x, next.y + 1),
                        Theme.meterPeak)
            previous = next
        }
    }

    // MARK: - Ripple

    /// Concentric rings seen at a shallow angle, deformed by the waveform.
    ///
    /// The same construction as the app's: each ring reads the mix a little
    /// further along, so a peak travels outwards from one ring to the next, and
    /// the middle rings are lifted into a dome by the overall level.
    private static func ripple(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) {
        canvas.bevel(rect, .recessed, fill: Theme.screen)
        let inner = rect.inset(by: Theme.bevel + 2)
        guard inner.width > 8, inner.height > 8 else { return }

        let rings = 14
        let segments = 48
        let centreX = Double(inner.x) + Double(inner.width) / 2
        let centreY = Double(inner.y) + Double(inner.height) * 0.66
        let lift = Double(Swift.min(1, Swift.max(0, (screen.meters.max() ?? 0) * 1.4)))
        let samples = screen.waveform

        func sample(phase: Double, angle: Double) -> Double {
            guard !samples.isEmpty else { return 0 }
            let turns = angle / (2 * .pi)
            var position = (turns + phase * 1.6).truncatingRemainder(dividingBy: 1)
            if position < 0 { position += 1 }
            return Double(samples[Swift.min(samples.count - 1,
                                            Int(position * Double(samples.count)))])
        }

        // Back to front, so the nearer rings are drawn over the far ones.
        for ring in (0..<rings).reversed() {
            let t = Double(ring) / Double(rings - 1)
            // The rings take their width from the box and their height from
            // it too, rather than from a fixed ratio: the panel here is far
            // wider than the app's, and rings shaped from the width alone
            // would be ellipses taller than the box they sit in.
            let radiusX = Double(inner.width) * (0.05 + 0.46 * t)
            let radiusY = Double(inner.height) * (0.05 + 0.46 * t) * 0.62
            let dome = Double(inner.height) * 0.30 * lift * exp(-6 * t * t)
            let colour = Theme.meterCell(at: 1 - t * 0.85)

            var first: (x: Int, y: Int) = (0, 0)
            var previous: (x: Int, y: Int) = (0, 0)
            for step in 0...segments {
                let angle = Double(step) / Double(segments) * 2 * .pi
                let bulge = 1 + sample(phase: t, angle: angle) * 0.20 * (1 - 0.62 * t)
                let x = centreX + radiusX * cos(angle) * bulge
                let y = centreY + radiusY * sin(angle) * bulge - dome
                    - sin(angle) * radiusY * 0.12
                let point = (x: Int(x.rounded()), y: Int(y.rounded()))
                if step == 0 {
                    first = point
                } else {
                    canvas.line(from: previous, to: point, colour, clip: inner)
                }
                previous = point
            }
            canvas.line(from: previous, to: first, colour, clip: inner)
        }
    }
}
