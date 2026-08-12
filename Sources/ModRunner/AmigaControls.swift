import SwiftUI

/// The window title bar, with the close gadget on the left and the
/// minimise/zoom/depth gadgets on the right, as Intuition arranged them.
///
/// This skin hides the macOS window buttons, so these gadgets are the only
/// window controls the user has — they all do real work. The zoom gadget maps
/// onto the window's two sizes, which here means showing or hiding the tracker,
/// and the depth gadget sends the window behind the others, as it did on the
/// Amiga.
struct AmigaTitleBar: View {
    let title: String
    var onClose: (() -> Void)?
    var onMinimise: (() -> Void)?
    var onZoom: (() -> Void)?
    var onDepth: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            GadgetBox { CloseGlyph() }
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { onClose?() }
                .help(L10n.t("tooltip.close"))

            ZStack {
                BevelBox(style: .raised, fill: Amiga.grey)
                Text(title)
                    .font(Amiga.boldFont(11))
                    .foregroundColor(Amiga.black)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 20)

            GadgetBox { MinimiseGlyph() }
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { onMinimise?() }
                .help(L10n.t("tooltip.minimise"))

            GadgetBox { ZoomGlyph() }
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { onZoom?() }
                .help(L10n.t("tooltip.zoom"))

            GadgetBox { DepthGlyph() }
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { onDepth?() }
                .help(L10n.t("tooltip.depth"))
        }
    }

    private struct GadgetBox<Content: View>: View {
        @ViewBuilder let content: Content
        var body: some View {
            ZStack {
                BevelBox(style: .raised, fill: Amiga.grey)
                content
            }
        }
    }

    // The gadget glyphs below are deliberately generic. They read as
    // period-appropriate window controls without reproducing the specific
    // artwork of any particular system's gadgets.

    /// Close gadget: a plain open square.
    private struct CloseGlyph: View {
        var body: some View {
            Rectangle()
                .strokeBorder(Amiga.black, lineWidth: 2)
                .frame(width: 11, height: 11)
        }
    }

    /// Minimise gadget: a bar along the bottom edge.
    private struct MinimiseGlyph: View {
        var body: some View {
            VStack {
                Spacer()
                Rectangle()
                    .fill(Amiga.black)
                    .frame(width: 11, height: 3)
            }
            .frame(width: 11, height: 11)
        }
    }

    /// Zoom gadget: a small square inside a larger open one, for the two sizes.
    private struct ZoomGlyph: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Amiga.black, lineWidth: 2)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(Amiga.black)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 2)
            }
            .frame(width: 12, height: 12)
        }
    }

    /// Depth gadget: two outlined squares, offset to suggest stacked windows.
    private struct DepthGlyph: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Amiga.black, lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .offset(x: 0, y: 4)
                Rectangle()
                    .fill(Amiga.grey)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: 0)
                Rectangle()
                    .strokeBorder(Amiga.black, lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: 0)
            }
            .frame(width: 13, height: 12)
        }
    }
}

/// A push button. Intuition buttons invert to black-on-grey while held.
struct AmigaButton: View {
    let label: String
    var width: CGFloat?
    var enabled: Bool = true
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        ZStack {
            BevelBox(style: pressed ? .recessed : .raised, fill: Amiga.grey)
            Text(label)
                .font(Amiga.font(11))
                .foregroundColor(enabled ? Amiga.black : Amiga.darkGrey)
                .padding(.horizontal, 10)
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.7)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { pressed = true } }
                .onEnded { _ in
                    if enabled, pressed { action() }
                    pressed = false
                }
        )
    }
}

/// A recessed text field used for read-only values, like OctaMED's displays.
struct AmigaReadout: View {
    let text: String
    var alignment: Alignment = .leading
    var color: Color = Amiga.black

    var body: some View {
        ZStack(alignment: alignment) {
            BevelBox(style: .recessed, fill: Amiga.lightGrey)
            Text(text)
                .font(Amiga.font(11))
                .foregroundColor(color)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(height: 20)
    }
}

/// A labelled pair: small caption above a recessed readout.
struct AmigaField: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(Amiga.font(9))
                .foregroundColor(Amiga.black)
            AmigaReadout(text: value)
        }
    }
}

/// A horizontal proportional gadget, as used for the song position.
struct AmigaSlider: View {
    var value: Double            // 0...1
    var knobWidth: CGFloat = 28
    var onScrub: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - 2 * Amiga.bevel
            let usable = max(0, track - knobWidth)
            let x = Amiga.bevel + usable * CGFloat(max(0, min(1, value)))
            ZStack(alignment: .topLeading) {
                BevelBox(style: .recessed, fill: Amiga.blue)
                BevelBox(style: .raised, fill: Amiga.grey)
                    .frame(width: knobWidth, height: geo.size.height - 2 * Amiga.bevel)
                    .offset(x: x, y: Amiga.bevel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard usable > 0 else { return }
                        let position = (drag.location.x - knobWidth / 2 - Amiga.bevel) / usable
                        onScrub?(max(0, min(1, Double(position))))
                    }
            )
        }
        .frame(height: 16)
    }
}

/// A vertical volume slider with a chunky knob.
struct AmigaVolumeSlider: View {
    @Binding var value: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - 2 * Amiga.bevel
            let knob: CGFloat = 20
            let usable = max(0, track - knob)
            ZStack(alignment: .topLeading) {
                BevelBox(style: .recessed, fill: Amiga.darkGrey)
                BevelBox(style: .raised, fill: Amiga.grey)
                    .frame(width: knob, height: geo.size.height - 2 * Amiga.bevel)
                    .offset(x: Amiga.bevel + usable * CGFloat(value), y: Amiga.bevel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard usable > 0 else { return }
                        value = max(0, min(1, Double((drag.location.x - knob / 2 - Amiga.bevel) / usable)))
                    }
            )
        }
        .frame(height: 16)
    }
}

/// A segmented VU meter for one Paula voice.
struct AmigaVUMeter: View {
    let label: String
    let level: Float        // 0...1
    var segments: Int = 20

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Amiga.font(10))
                .foregroundColor(Amiga.black)
                .frame(width: 26, alignment: .leading)

            GeometryReader { geo in
                let lit = Int((Double(min(1, max(0, level))) * Double(segments)).rounded())
                let gap: CGFloat = 1
                let cell = (geo.size.width - 2 * Amiga.bevel - CGFloat(segments - 1) * gap) / CGFloat(segments)
                ZStack(alignment: .leading) {
                    BevelBox(style: .recessed, fill: Amiga.black)
                    HStack(spacing: gap) {
                        ForEach(0..<segments, id: \.self) { index in
                            Rectangle()
                                .fill(index < lit ? color(for: index) : Amiga.darkGrey.opacity(0.35))
                                .frame(width: max(1, cell))
                        }
                    }
                    .padding(Amiga.bevel)
                }
            }
            .frame(height: 14)
        }
    }

    private func color(for index: Int) -> Color {
        let fraction = Double(index) / Double(segments)
        if fraction > 0.85 { return Amiga.salmon }
        if fraction > 0.65 { return Amiga.tan }
        return Amiga.blue
    }
}
