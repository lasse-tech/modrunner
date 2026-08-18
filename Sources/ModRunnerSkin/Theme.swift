import Foundation
import ModRunnerKit

/// The classic skin's colours and the bevels drawn out of them, as bytes rather
/// than as a toolkit's colour type.
///
/// The values themselves live in `Palette`, in the engine, which is what the
/// SwiftUI app reads too — so the two interfaces cannot drift apart. They used
/// to be written out on both sides, and they did.
public enum Theme {

    /// The palette in force. Read on each access, so switching it repaints
    /// whatever is drawn next without anything having to be rebuilt.
    public static var palette: Palette { Palette.current }

    public static var screen: Colour        { colour(\.screen) }
    public static var face: Colour          { colour(\.face) }
    public static var faceDark: Colour      { colour(\.faceDark) }
    public static var faceLight: Colour     { colour(\.faceLight) }
    public static var shine: Colour         { colour(\.shine) }
    public static var shadow: Colour        { colour(\.shadow) }
    public static var sunken: Colour        { colour(\.sunken) }
    public static var text: Colour          { colour(\.text) }
    public static var textDim: Colour       { colour(\.textDim) }
    public static var caption: Colour       { colour(\.caption) }
    public static var highlight: Colour     { colour(\.highlight) }
    public static var highlightText: Colour { colour(\.highlightText) }
    public static var accent: Colour        { colour(\.accent) }
    public static var arc: Colour           { colour(\.arc) }
    public static var meter: Colour         { colour(\.meter) }
    public static var meterPeak: Colour     { colour(\.meterPeak) }
    public static var meterOff: Colour      { colour(\.meterOff) }

    public static let bevel = Palette.bevel

    public enum Style { case raised, recessed }

    public static func meterCell(at fraction: Double) -> Colour {
        Colour(palette.meterCell(at: fraction))
    }

    private static func colour(_ role: KeyPath<Palette, PaletteColour>) -> Colour {
        Colour(palette[keyPath: role])
    }

    // MARK: - Window gadgets
    //
    // One motif throughout: the bar. Each gadget says what it does by what
    // happens to the bars rather than by a symbol that has to be learned, and
    // no shape here is taken from anywhere. Positions follow the habit — close
    // on the left, iconify, zoom and depth on the right — but only the
    // positions do.

    public enum Gadget: CaseIterable, Sendable {
        case close, iconify, zoom, depth, sizer
    }

    /// One bar on the 14×12 glyph grid.
    public struct GlyphBar: Sendable {
        public let x, y, width, height: Int
        public let colour: Colour

        public init(x: Int, y: Int, width: Int, height: Int, colour: Colour) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.colour = colour
        }
    }

    public static func glyph(_ kind: Gadget) -> [GlyphBar] {
        func bar(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ colour: Colour = Theme.text) -> GlyphBar {
            GlyphBar(x: x, y: y, width: width, height: height, colour: colour)
        }

        switch kind {
        case .close:                        // three steps, 5 : 3 : 1
            return [bar(0, 0, 3, 12), bar(5, 3, 3, 6), bar(10, 5, 3, 2)]
        case .iconify:                      // everything lies down
            return [bar(0, 1, 13, 2, Theme.caption), bar(0, 8, 13, 3)]
        case .zoom:                         // the row grows, 1 : 2 : 3
            return [bar(0, 8, 3, 3), bar(5, 5, 3, 6), bar(10, 0, 3, 11)]
        case .depth:                        // two offset plates
            return [bar(4, 0, 9, 5, Theme.caption), bar(0, 6, 9, 5)]
        case .sizer:                        // a corner being pulled
            return [bar(2, 9, 11, 3), bar(10, 2, 3, 10), bar(5, 5, 3, 3, Theme.caption)]
        }
    }
}

public extension Colour {
    /// Bridges a palette entry into the canvas's own colour type.
    init(_ palette: PaletteColour) {
        self.init(palette.red, palette.green, palette.blue)
    }
}

public extension Canvas {

    /// A bevelled box: fill, then the four edges. Two pixels. Light above and
    /// to the left is what makes a surface read as raised; recessed is the same
    /// rule with the two swapped, which is why one function does both.
    ///
    /// The vertical edges are drawn last, so the top-right and bottom-left
    /// corners belong to them and both end up dark. That diagonal is what stops
    /// the box reading as a flat outline.
    mutating func bevel(_ rect: Rect,
                        _ style: Theme.Style = .raised,
                        fill colour: Colour = Theme.face,
                        width: Int = Theme.bevel) {
        let shine = style == .raised ? Theme.shine : Theme.shadow
        let shadow = style == .raised ? Theme.shadow : Theme.shine

        fill(rect, colour)
        fill(Rect(rect.x, rect.y, rect.width, width), shine)
        fill(Rect(rect.x, rect.y, width, rect.height), shine)
        fill(Rect(rect.x, rect.maxY - width, rect.width, width), shadow)
        fill(Rect(rect.maxX - width, rect.y, width, rect.height), shadow)
    }

    /// A recessed field with text in it — a value you can read but not type
    /// into, the way a tracker shows one.
    mutating func readout(_ rect: Rect, _ string: String,
                          _ colour: Colour = Theme.text,
                          background: Colour = Theme.sunken) {
        bevel(rect, .recessed, fill: background)
        let inner = rect.inset(by: Theme.bevel + 2)
        text(string, at: inner.x, inner.y + (inner.height - Font.cellHeight) / 2,
             colour, maxWidth: inner.width)
    }

    /// A captioned field: small label above, value in a recessed box below.
    mutating func field(_ rect: Rect, caption: String, value: String) {
        text(caption, at: rect.x + 2, rect.y, Theme.caption, maxWidth: rect.width - 4)
        readout(Rect(rect.x, rect.y + Font.cellHeight + 2,
                     rect.width, rect.height - Font.cellHeight - 2), value)
    }

    /// A push button: raised bevel with the label centred. `on` is for a button
    /// that shows a setting rather than performing an action.
    mutating func button(_ rect: Rect, _ label: String,
                         pressed: Bool = false, on: Bool = false) {
        bevel(rect, pressed ? .recessed : .raised)
        let textWidth = Font.width(of: label)
        text(label,
             at: rect.x + (rect.width - textWidth) / 2,
             rect.y + (rect.height - Font.cellHeight) / 2,
             (pressed || on) ? Theme.highlight : Theme.text,
             maxWidth: rect.width - 4)
    }

    /// A level meter as a row of discrete cells. Discrete on purpose: a bar
    /// that quantises reads as a machine rather than as a progress view.
    mutating func meter(_ rect: Rect, level: Float, cells: Int = 24) {
        bevel(rect, .recessed, fill: Theme.meterOff)
        let inner = rect.inset(by: Theme.bevel)
        guard cells > 0, inner.width > 0 else { return }

        let lit = Int((Float(cells) * Swift.max(0, Swift.min(1, level))).rounded())

        // Cell edges are computed from the full width rather than from a
        // rounded-down cell size, so the last one reaches the right edge
        // instead of leaving a gap that looks like a rendering fault.
        for index in 0..<cells {
            let start = inner.x + index * inner.width / cells
            let end = inner.x + (index + 1) * inner.width / cells
            guard end - start > 1 else { continue }
            let colour = index < lit
                ? Theme.meterCell(at: Double(index) / Double(cells))
                : Theme.meterOff
            fill(Rect(start, inner.y, end - start - 1, inner.height), colour)
        }
    }

    /// A slider with a draggable-looking knob at `value`. The part already
    /// played is filled in, which a bare knob on a groove does not say.
    mutating func slider(_ rect: Rect, value: Double) {
        bevel(rect, .recessed, fill: Theme.sunken)
        let inner = rect.inset(by: Theme.bevel)
        guard inner.width > 0 else { return }

        let knobWidth = Swift.max(12, inner.width / 12)
        let travel = Swift.max(0, inner.width - knobWidth)
        let position = Int(Double(travel) * Swift.max(0, Swift.min(1, value)))
        fill(Rect(inner.x, inner.y, position, inner.height), Theme.highlight)
        bevel(Rect(inner.x + position, inner.y, knobWidth, inner.height),
              .raised, fill: Theme.faceLight)
    }

    // MARK: - Window gadgets

    /// Draws a gadget: raised bevel, glyph centred on a 14×12 grid inside it.
    ///
    /// The bars are listed rather than drawn inline so the same table can be
    /// read back — and so the description of each glyph sits in one place next
    /// to the others it has to stay distinguishable from.
    mutating func gadget(_ rect: Rect, _ kind: Theme.Gadget) {
        bevel(rect, .raised)

        let originX = rect.x + (rect.width - 14) / 2
        let originY = rect.y + (rect.height - 12) / 2

        for bar in Theme.glyph(kind) {
            fill(Rect(originX + bar.x, originY + bar.y, bar.width, bar.height), bar.colour)
        }
    }
}
