import Foundation

/// The AmigaOS 3.x Workbench palette and the bevels drawn out of it.
///
/// The same eight pens the macOS skin uses, as bytes rather than as `Color`,
/// so the two interfaces cannot drift apart on colour. Intuition drew a raised
/// box with a light top and left and a dark bottom and right; recessed is the
/// same rule with the two swapped, which is why one function does both.
public enum Workbench {

    public static let grey      = Colour(0x95, 0x95, 0x95)  // pen 0
    public static let black     = Colour(0x00, 0x00, 0x00)  // pen 1
    public static let white     = Colour(0xFF, 0xFF, 0xFF)  // pen 2
    public static let blue      = Colour(0x3B, 0x67, 0xA2)  // pen 3
    public static let darkGrey  = Colour(0x7B, 0x7B, 0x7B)  // pen 4
    public static let lightGrey = Colour(0xAF, 0xAF, 0xAF)  // pen 5
    public static let tan       = Colour(0xAA, 0x90, 0x7C)  // pen 6
    public static let salmon    = Colour(0xFF, 0xA9, 0x97)  // pen 7

    /// The screen behind the window.
    public static let screen = Colour(0x60, 0x60, 0x60)

    public static let bevel = 2

    public enum Style { case raised, recessed }
}

public extension Canvas {

    /// A bevelled box: fill, then the two edges. Two pixels, as Intuition drew
    /// them, with the corners belonging to the horizontal edges.
    mutating func bevel(_ rect: Rect,
                        _ style: Workbench.Style = .raised,
                        fill colour: Colour = Workbench.grey,
                        width: Int = Workbench.bevel) {
        let shine = style == .raised ? Workbench.white : Workbench.black
        let shadow = style == .raised ? Workbench.black : Workbench.white

        fill(rect, colour)
        fill(Rect(rect.x, rect.y, rect.width, width), shine)
        fill(Rect(rect.x, rect.y, width, rect.height), shine)
        fill(Rect(rect.x, rect.maxY - width, rect.width, width), shadow)
        fill(Rect(rect.maxX - width, rect.y, width, rect.height), shadow)
    }

    /// A recessed field with text in it — the Amiga way of showing a value you
    /// cannot type into.
    mutating func readout(_ rect: Rect, _ string: String,
                          _ colour: Colour = Workbench.black,
                          background: Colour = Workbench.lightGrey) {
        bevel(rect, .recessed, fill: background)
        let inner = rect.inset(by: Workbench.bevel + 2)
        text(string, at: inner.x, inner.y + (inner.height - Font.cellHeight) / 2,
             colour, maxWidth: inner.width)
    }

    /// A captioned field: small label above, value in a recessed box below.
    mutating func field(_ rect: Rect, caption: String, value: String) {
        text(caption, at: rect.x + 2, rect.y, Workbench.black, maxWidth: rect.width - 4)
        readout(Rect(rect.x, rect.y + Font.cellHeight + 2,
                     rect.width, rect.height - Font.cellHeight - 2), value)
    }

    /// A push button: raised bevel with the label centred.
    mutating func button(_ rect: Rect, _ label: String, pressed: Bool = false) {
        bevel(rect, pressed ? .recessed : .raised)
        let textWidth = Font.width(of: label)
        text(label,
             at: rect.x + (rect.width - textWidth) / 2,
             rect.y + (rect.height - Font.cellHeight) / 2,
             Workbench.black, maxWidth: rect.width - 4)
    }

    /// A level meter as a row of discrete cells. Discrete on purpose: Paula had
    /// no smooth anything, and a bar that quantises reads as a machine rather
    /// than as a progress view.
    mutating func meter(_ rect: Rect, level: Float, cells: Int = 24) {
        bevel(rect, .recessed, fill: Workbench.black)
        let inner = rect.inset(by: Workbench.bevel)
        guard cells > 0, inner.width > 0 else { return }

        let lit = Int((Float(cells) * Swift.max(0, Swift.min(1, level))).rounded())

        // Cell edges are computed from the full width rather than from a
        // rounded-down cell size, so the last one reaches the right edge
        // instead of leaving a gap that looks like a rendering fault.
        for index in 0..<cells {
            let start = inner.x + index * inner.width / cells
            let end = inner.x + (index + 1) * inner.width / cells
            guard end - start > 1 else { continue }
            fill(Rect(start, inner.y, end - start - 1, inner.height),
                 index < lit ? Workbench.blue : Workbench.darkGrey)
        }
    }

    /// A slider with a draggable-looking knob at `value`.
    mutating func slider(_ rect: Rect, value: Double) {
        bevel(rect, .recessed, fill: Workbench.darkGrey)
        let inner = rect.inset(by: Workbench.bevel)
        guard inner.width > 0 else { return }

        let knobWidth = Swift.max(12, inner.width / 12)
        let travel = Swift.max(0, inner.width - knobWidth)
        let position = Int(Double(travel) * Swift.max(0, Swift.min(1, value)))
        fill(Rect(inner.x, inner.y, position, inner.height), Workbench.blue)
        bevel(Rect(inner.x + position, inner.y, knobWidth, inner.height), .raised)
    }
}
