import SwiftUI
import AppKit
import ModRunnerKit

/// A patch of view that drags the window it is in, the way a system title bar
/// does.
///
/// The skinned windows cannot use `isMovableByWindowBackground` for this. It
/// makes AppKit swallow the mouse-moved events under the whole window, and those
/// are what tooltips are built on — with it set, not one gadget in the window
/// ever showed its help.
struct WindowDragArea: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// The window title bar: close on the left, iconify, zoom and depth on the
/// right, sizing in the bottom right corner of the frame.
///
/// The positions are the ones a hand trained on 16-bit desktops reaches for.
/// The glyphs are not — they are drawn from the bar motif the app's own mark is
/// built on, a rectangle that grows, shrinks, doubles or lies down. Nothing
/// here reproduces the artwork of any particular system.
///
/// The skin hides the macOS window buttons, so these gadgets are the only
/// window controls the user has. The zoom gadget opens the full-screen stage,
/// which is what both skins map their zoom onto; the depth gadget sends the
/// window behind the others.
struct ClassicTitleBar: View {
    let title: String
    var active: Bool = true
    var onClose: (() -> Void)?
    var onMinimise: (() -> Void)?
    var onZoom: (() -> Void)?
    var onDepth: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            GadgetBox { CloseGlyph() }
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { onClose?() }
                .help(L10n.t("tooltip.close"))

            ZStack {
                BevelBox(style: .raised, fill: Classic.face)
                // The bar between the gadgets is what the window is dragged by.
                WindowDragArea()
                Text(title)
                    .font(Classic.boldFont(11))
                    .foregroundColor(active ? Classic.text : Classic.caption)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
            .frame(height: 22)

            GadgetBox { IconifyGlyph() }
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { onMinimise?() }
                .help(L10n.t("tooltip.minimise"))

            GadgetBox { ZoomGlyph() }
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { onZoom?() }
                .help(L10n.t("tooltip.zoom"))

            GadgetBox { DepthGlyph() }
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { onDepth?() }
                .help(L10n.t("tooltip.depth"))
        }
    }

    private struct GadgetBox<Content: View>: View {
        @ViewBuilder let content: Content
        var body: some View {
            ZStack {
                BevelBox(style: .raised, fill: Classic.face)
                content
            }
        }
    }
}

// MARK: - Gadget glyphs
//
// One motif throughout: the bar. Each glyph is drawn on a 14×12 grid so the
// four sit on the same baseline, and each says what the gadget does by what
// happens to the bars rather than by a symbol that has to be learned.

/// Close: three steps, 5 : 3 : 1 — a bar collapsing to nothing.
private struct CloseGlyph: View {
    var body: some View {
        GadgetCanvas { ink in
            Bar(x: 0, y: 0, w: 3, h: 12, ink)
            Bar(x: 5, y: 3, w: 3, h: 6, ink)
            Bar(x: 10, y: 5, w: 3, h: 2, ink)
        }
    }
}

/// Iconify: everything lies down on the baseline.
private struct IconifyGlyph: View {
    var body: some View {
        GadgetCanvas { ink in
            Bar(x: 0, y: 1, w: 13, h: 2, Classic.caption)
            Bar(x: 0, y: 8, w: 13, h: 3, ink)
        }
    }
}

/// Zoom: the row grows 1 : 2 : 3, the same progression the app's mark is built
/// on. Opening the stage is the window getting bigger, so the glyph is too.
private struct ZoomGlyph: View {
    var body: some View {
        GadgetCanvas { ink in
            Bar(x: 0, y: 8, w: 3, h: 3, ink)
            Bar(x: 5, y: 5, w: 3, h: 6, ink)
            Bar(x: 10, y: 0, w: 3, h: 11, ink)
        }
    }
}

/// Depth: two offset plates, the one behind gone pale.
private struct DepthGlyph: View {
    var body: some View {
        GadgetCanvas { ink in
            Bar(x: 4, y: 0, w: 9, h: 5, Classic.caption)
            Bar(x: 0, y: 6, w: 9, h: 5, ink)
        }
    }
}

/// Sizing: a corner being pulled — two rails and the step between them.
/// Deliberately not the zoom ramp, because the two would otherwise read the
/// same at this size and they do different things.
struct SizerGlyph: View {
    var body: some View {
        GadgetCanvas { ink in
            Bar(x: 2, y: 9, w: 11, h: 3, ink)
            Bar(x: 10, y: 2, w: 3, h: 10, ink)
            Bar(x: 5, y: 5, w: 3, h: 3, Classic.caption)
        }
    }
}

/// The 14×12 grid the glyphs are laid out on, so every one of them lands in the
/// same place inside its gadget.
private struct GadgetCanvas<Content: View>: View {
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            content(Classic.text)
        }
        .frame(width: 14, height: 12)
    }
}

/// One bar on the glyph grid, placed rather than offset: an offset does not
/// enlarge the stack it sits in, which used to push whole glyphs out of their
/// gadget and into the window edge.
private struct Bar: View {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    let colour: Color

    init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, _ colour: Color) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.colour = colour
    }

    var body: some View {
        Rectangle()
            .fill(colour)
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }
}

// MARK: - Controls

/// A push button. It inverts while held, as a bevelled button always has.
struct ClassicButton: View {
    let label: String
    var width: CGFloat?
    var enabled: Bool = true
    /// Whether this button shows a setting that is currently on.
    var on: Bool = false
    /// The gadget labels are two or three characters of tracker shorthand, so
    /// the tooltip is the only place their meaning is spelled out.
    var help: String = ""
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        ZStack {
            BevelBox(style: pressed ? .recessed : .raised, fill: Classic.face)
            Text(label)
                .font(Classic.font(11))
                .foregroundColor(ink)
                .lineLimit(1)
                // The labels are set from the localised strings, and German is
                // the longer language. Shrinking a little is better than an
                // ellipsis on a two-word button.
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle())
        .help(help)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { pressed = true } }
                .onEnded { _ in
                    if enabled, pressed { action() }
                    pressed = false
                }
        )
    }

    private var ink: Color {
        guard enabled else { return Classic.caption }
        return (pressed || on) ? Classic.highlight : Classic.text
    }
}

/// A recessed field used for read-only values, the way a tracker shows one.
struct ClassicReadout: View {
    let text: String
    var alignment: Alignment = .leading
    var color: Color? = nil

    var body: some View {
        ZStack(alignment: alignment) {
            BevelBox(style: .recessed, fill: Classic.sunken)
            Text(text)
                .font(Classic.font(11))
                .foregroundColor(color ?? Classic.text)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(height: 20)
    }
}

/// A labelled pair: small caption above a recessed readout.
struct ClassicField: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(Classic.font(9))
                .foregroundColor(Classic.caption)
                .lineLimit(1)
            ClassicReadout(text: value)
        }
    }
}

/// A horizontal proportional gadget, as used for the song position. The part
/// already played is filled in, which a plain knob on a groove does not say.
struct ClassicSlider: View {
    var value: Double            // 0...1
    var knobWidth: CGFloat = 28
    var onScrub: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - 2 * Classic.bevel
            let usable = max(0, track - knobWidth)
            let clamped = CGFloat(max(0, min(1, value)))
            let x = Classic.bevel + usable * clamped
            ZStack(alignment: .topLeading) {
                BevelBox(style: .recessed, fill: Classic.sunken)
                Rectangle()
                    .fill(Classic.highlight)
                    .frame(width: max(0, x - Classic.bevel),
                           height: geo.size.height - 2 * Classic.bevel)
                    .offset(x: Classic.bevel, y: Classic.bevel)
                BevelBox(style: .raised, fill: Classic.faceLight)
                    .frame(width: knobWidth, height: geo.size.height - 2 * Classic.bevel)
                    .offset(x: x, y: Classic.bevel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard usable > 0 else { return }
                        let position = (drag.location.x - knobWidth / 2 - Classic.bevel) / usable
                        onScrub?(max(0, min(1, Double(position))))
                    }
            )
        }
        .frame(height: 16)
    }
}

/// The volume slider. Same gadget, narrower knob, and it writes back.
struct ClassicVolumeSlider: View {
    @Binding var value: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - 2 * Classic.bevel
            let knob: CGFloat = 20
            let usable = max(0, track - knob)
            let x = Classic.bevel + usable * CGFloat(max(0, min(1, value)))
            ZStack(alignment: .topLeading) {
                BevelBox(style: .recessed, fill: Classic.sunken)
                Rectangle()
                    .fill(Classic.highlight)
                    .frame(width: max(0, x - Classic.bevel),
                           height: geo.size.height - 2 * Classic.bevel)
                    .offset(x: Classic.bevel, y: Classic.bevel)
                BevelBox(style: .raised, fill: Classic.faceLight)
                    .frame(width: knob, height: geo.size.height - 2 * Classic.bevel)
                    .offset(x: x, y: Classic.bevel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard usable > 0 else { return }
                        value = max(0, min(1, Double((drag.location.x - knob / 2 - Classic.bevel) / usable)))
                    }
            )
        }
        .frame(height: 16)
    }
}

/// A segmented VU meter for one voice. Discrete on purpose: a bar that
/// quantises reads as a machine rather than as a progress view.
struct ClassicVUMeter: View {
    let label: String
    let level: Float        // 0...1
    var segments: Int = 20

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Classic.font(10))
                .foregroundColor(Classic.caption)
                .frame(width: 26, alignment: .leading)

            GeometryReader { geo in
                let lit = Int((Double(min(1, max(0, level))) * Double(segments)).rounded())
                let gap: CGFloat = 1
                let cell = (geo.size.width - 2 * Classic.bevel - CGFloat(segments - 1) * gap) / CGFloat(segments)
                ZStack(alignment: .leading) {
                    BevelBox(style: .recessed, fill: Classic.meterOff)
                    HStack(spacing: gap) {
                        ForEach(0..<segments, id: \.self) { index in
                            Rectangle()
                                .fill(index < lit
                                      ? Classic.meterCell(at: Double(index) / Double(segments))
                                      : Classic.meterOff)
                                .frame(width: max(1, cell))
                        }
                    }
                    .padding(Classic.bevel)
                }
            }
            .frame(height: 14)
        }
    }
}
