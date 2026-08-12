import SwiftUI

// MARK: - Level meters

/// Vertical per-voice meters in the shape of the app icon: a segmented bar that
/// runs blue through salmon to orange. The fill is animated and the peak marker
/// falls away slowly, so the movement reads as level rather than as flicker.
struct ChannelMeters: View {

    let levels: [Float]
    /// Channels the listener has silenced, and the callbacks to change that.
    var muted: Set<Int> = []
    var onToggleMute: ((Int) -> Void)? = nil
    var onSolo: ((Int) -> Void)? = nil
    var barWidth: CGFloat = 14
    /// Total height including the channel numbers, so the meters occupy the
    /// same box as the other visualisations.
    var height: CGFloat = 96

    private static let labelHeight: CGFloat = 16
    private static let labelSpacing: CGFloat = 5

    @State private var peaks: [Float] = []

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                VStack(spacing: Self.labelSpacing) {
                    bar(level: CGFloat(level), peak: CGFloat(peak(at: index)))
                        .opacity(muted.contains(index) ? 0.25 : 1)
                    ChannelButton(number: index + 1,
                                  muted: muted.contains(index),
                                  width: barWidth,
                                  height: Self.labelHeight,
                                  onToggle: { onToggleMute?(index) },
                                  onSolo: { onSolo?(index) })
                }
            }
        }
        .onChange(of: levels) { new in updatePeaks(new) }
        .onAppear { peaks = levels }
    }

    private func peak(at index: Int) -> Float {
        peaks.indices.contains(index) ? peaks[index] : 0
    }

    /// Peaks jump up instantly and sink slowly, the way a real peak meter holds.
    private func updatePeaks(_ new: [Float]) {
        if peaks.count != new.count { peaks = new; return }
        for i in new.indices {
            peaks[i] = new[i] > peaks[i] ? new[i] : max(new[i], peaks[i] - 0.012)
        }
    }

    private func bar(level: CGFloat, peak: CGFloat) -> some View {
        GeometryReader { geo in
            let full = geo.size.height
            let clamped = min(1, max(0, level))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)

                // The gradient spans the whole bar and is masked to the current
                // level, so a colour always means the same loudness. Anchoring
                // it to the fill instead would squeeze the entire ramp into a
                // quiet channel and paint it orange.
                Brand.meterGradient
                    .frame(height: full)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: full * clamped)
                            .animation(.easeOut(duration: 0.07), value: clamped)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Peak marker.
                Capsule()
                    .fill(Brand.level(Double(peak)))
                    .frame(height: 2)
                    .offset(y: -max(2, full * min(1, max(0, peak)) - 1))
                    .opacity(peak > 0.02 ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: peak)
            }
            // The segment gaps of the brand mark, laid over the moving fill so
            // the fill itself can animate continuously.
            .overlay(SegmentGaps(count: 13))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(width: barWidth,
               height: max(10, height - Self.labelHeight - Self.labelSpacing))
    }
}

/// The mute switch under each meter. It has to look like a control, not like a
/// label: a numbered button that fills in when the channel is silenced.
private struct ChannelButton: View {
    let number: Int
    let muted: Bool
    let width: CGFloat
    let height: CGFloat
    let onToggle: () -> Void
    let onSolo: () -> Void

    @State private var hovering = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(muted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: width, height: height)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(muted ? AnyShapeStyle(Brand.orange) : AnyShapeStyle(.quaternary))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hovering ? Brand.orange : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onSolo() }
            .onTapGesture { onToggle() }
            .onHover { hovering = $0 }
            .help(muted
                  ? "Channel \(number) muted — click to unmute, double-click to solo"
                  : "Click to mute channel \(number), double-click to solo")
    }
}

/// Thin horizontal gaps that turn a solid bar into a segmented one.
private struct SegmentGaps: View {
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.height / CGFloat(count)
            ForEach(1..<count, id: \.self) { index in
                Rectangle()
                    .fill(.background)
                    .frame(height: 1.5)
                    .offset(y: step * CGFloat(index))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tracker

/// The pattern data scrolling continuously past a fixed playhead. The rows move
/// by a fraction of a row per frame, driven by `Snapshot.lineProgress`, rather
/// than jumping a whole row when the line changes.
struct SmoothTrackerView: View {

    let module: MMDModule?
    let block: Int
    let line: Int
    let progress: Double

    static let rowHeight: CGFloat = 17
    static let visibleRows = 11
    static var height: CGFloat { rowHeight * CGFloat(visibleRows) }

    private var half: Int { Self.visibleRows / 2 }

    var body: some View {
        ZStack {
            // The playhead band stays put while the music moves through it.
            RoundedRectangle(cornerRadius: 5)
                .fill(Brand.orange.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Brand.orange.opacity(0.45), lineWidth: 1)
                )
                .frame(height: Self.rowHeight)

            VStack(spacing: 0) {
                // One extra row at each end so the strip never runs dry mid-scroll.
                ForEach((-half - 1)...(half + 1), id: \.self) { offset in
                    row(at: line + offset)
                }
            }
            .offset(y: -CGFloat(progress) * Self.rowHeight)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.22))
        )
    }

    private func row(at index: Int) -> some View {
        let block = currentBlock
        let valid = block != nil && index >= 0 && index < (block?.lines ?? 0)
        let onBeat = valid && index % 4 == 0
        let distance = abs(index - line)

        return HStack(spacing: 0) {
            Text(valid ? String(format: "%03d", index) : "")
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(onBeat ? .secondary : .tertiary)

            if valid, let block {
                ForEach(0..<trackCount, id: \.self) { track in
                    cellView(block: block, line: index, track: track)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        // Rows fade out towards the edges, which keeps the eye on the playhead.
        .opacity(distance <= 1 ? 1 : max(0.28, 1 - Double(distance) * 0.13))
        .background(onBeat ? Color.primary.opacity(0.05) : .clear)
    }

    private func cellView(block: MMDModule.Block, line: Int, track: Int) -> some View {
        let note = block.note(line: line, track: track)
        let hasNote = note.note > 0
        let hasCommand = note.command != 0 || note.data != 0

        return HStack(spacing: 5) {
            Text(TrackerView.noteName(note.note))
                .foregroundStyle(hasNote ? AnyShapeStyle(Brand.orange) : AnyShapeStyle(.quaternary))
            Text(note.instrument > 0 ? String(format: "%02X", note.instrument) : "··")
                .foregroundStyle(note.instrument > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            Text(hasCommand ? String(format: "%02X%02X", note.command, note.data) : "····")
                .foregroundStyle(hasCommand ? AnyShapeStyle(Brand.blue) : AnyShapeStyle(.quaternary))
        }
    }

    private var currentBlock: MMDModule.Block? {
        guard let module, module.blocks.indices.contains(block) else { return nil }
        return module.blocks[block]
    }

    private var trackCount: Int { min(currentBlock?.tracks ?? 4, 8) }
}

// MARK: - Transport

/// A round transport button using SF Symbols.
struct TransportButton: View {
    let symbol: String
    var prominent = false
    var size: CGFloat = 30
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 15 : 12, weight: .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: prominent ? size * 1.25 : size, height: prominent ? size * 1.25 : size)
                .background {
                    Circle()
                        .fill(prominent ? AnyShapeStyle(Brand.orange) : AnyShapeStyle(.quaternary))
                        .opacity(hovering ? 0.85 : 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A slim scrubber that grows a little when the pointer is over it.
struct Scrubber: View {
    let value: Double
    let onScrub: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = hovering ? 7 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: height)
                Capsule()
                    .fill(Brand.orange)
                    .frame(width: max(0, width * CGFloat(min(1, max(0, value)))), height: height)
                Circle()
                    .fill(.white)
                    .shadow(radius: 1.5)
                    .frame(width: hovering ? 12 : 0, height: hovering ? 12 : 0)
                    .offset(x: width * CGFloat(min(1, max(0, value))) - (hovering ? 6 : 0))
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: hovering)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard width > 0 else { return }
                        onScrub(min(1, max(0, Double(drag.location.x / width))))
                    }
            )
        }
        .frame(height: 14)
        .onHover { hovering = $0 }
    }
}
