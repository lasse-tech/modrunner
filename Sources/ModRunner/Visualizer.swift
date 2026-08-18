import SwiftUI
import ModRunnerKit

/// The ways the audio can be drawn. Adding another one means adding a case, a
/// title, and a branch in `VisualizerView` — nothing else in the app needs to
/// know about it.
enum VisualizerStyle: String, CaseIterable, Identifiable {
    /// Per-voice segmented bars, in the shape of the app icon.
    case bars
    /// An oscilloscope of the mixed output.
    case waveform
    /// Concentric rings deformed by the mix, seen at a shallow angle.
    case ripple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return L10n.t("visualizer.levels")
        case .waveform: return L10n.t("visualizer.waveform")
        case .ripple: return L10n.t("visualizer.ripple")
        }
    }

    var symbol: String {
        switch self {
        case .bars: return "chart.bar.fill"
        case .waveform: return "waveform"
        case .ripple: return "circle.circle"
        }
    }

    static let storageKey = "visualizer"

    static var current: VisualizerStyle {
        VisualizerStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .bars
    }
}

/// Draws whichever visualisation is selected, at a fixed height so the window
/// size does not change when switching.
struct VisualizerView: View {

    let style: VisualizerStyle
    let levels: [Float]
    let samples: [Float]
    var muted: Set<Int> = []
    var onToggleMute: ((Int) -> Void)?
    var onSolo: ((Int) -> Void)?

    /// Every visualisation occupies exactly this box — the same box, drawn on
    /// the same ground. If they differed, switching between them would shift
    /// everything around them in the window.
    static let height: CGFloat = 96
    static let width: CGFloat = 240

    /// Inset of the meters from the edge of the box, so the bars sit on the
    /// ground the other two draw on rather than against its rim.
    private static let inset: CGFloat = 8

    var body: some View {
        Group {
            switch style {
            case .bars:
                // No fixed bar width: the meters spread across the same box the
                // trace and the rings fill, so all three read as one panel that
                // changes its contents.
                ChannelMeters(levels: levels, muted: muted,
                              onToggleMute: onToggleMute, onSolo: onSolo,
                              barWidth: nil,
                              height: Self.height - 2 * Self.inset)
                    .padding(Self.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.22)))
            case .waveform:
                WaveformView(samples: samples)
            case .ripple:
                RippleView(samples: samples, levels: levels)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .bottom)
    }
}

/// An oscilloscope of the mixed output, as it is being heard.
struct WaveformView: View {

    let samples: [Float]
    /// Vertical scale. Module output rarely approaches full scale, so a little
    /// gain keeps the trace readable without clipping it against the frame.
    var gain: CGFloat = 2.2

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let mid = height / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.22))

                // Zero line.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addLine(to: CGPoint(x: width, y: mid))
                }
                .stroke(.quaternary, lineWidth: 1)

                if samples.count > 1 {
                    let trace = path(in: CGSize(width: width, height: height))

                    // A soft wash under the trace, then the trace itself.
                    trace
                        .stroke(Brand.orange.opacity(0.25), lineWidth: 5)
                        .blur(radius: 3)
                    trace
                        .stroke(
                            LinearGradient(colors: [Brand.blue, Brand.orange, Brand.blue],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                        )
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func path(in size: CGSize) -> Path {
        Path { path in
            let mid = size.height / 2
            let step = size.width / CGFloat(samples.count - 1)
            for (index, sample) in samples.enumerated() {
                let value = CGFloat(sample) * gain
                let y = mid - max(-1, min(1, value)) * (mid - 2)
                let point = CGPoint(x: CGFloat(index) * step, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}

/// A small segmented picker for the visualisation, styled to match the skin.
struct VisualizerPicker: View {
    @Binding var style: VisualizerStyle

    var body: some View {
        Picker("", selection: $style) {
            ForEach(VisualizerStyle.allCases) { option in
                Image(systemName: option.symbol)
                    .help(option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 88)
        // A segmented control only shows the per-segment help while the pointer
        // rests on that segment; this one covers the control as a whole.
        .help(L10n.t("tooltip.visualizer"))
    }
}
