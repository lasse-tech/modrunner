import SwiftUI
import AppKit
import ModRunnerKit

/// The classic skin's surface: bevelled panels, recessed readouts and a
/// monospaced grid, drawn in the colours `Palette` hands out.
///
/// The shapes are a 16-bit idiom. The colours are the project's own, and they
/// are dark, so the bevel runs the other way round from the beige desktops the
/// idiom came from: the lit edge is the lightest frame tone rather than white,
/// the dark edge is the deepest ground rather than black. Light still falls
/// from the top left, which is the part that has to hold for a surface to read
/// as raised.
enum Classic {

    /// The palette in force. Read on every body evaluation — cheaply, because
    /// `Palette` caches — so a change to the stored value repaints the window
    /// as soon as anything above it redraws, which is what
    /// `@AppStorage(Palette.storageKey)` in the skin roots guarantees.
    static var palette: Palette { Palette.current }

    static func color(_ role: KeyPath<Palette, PaletteColour>) -> Color {
        let (red, green, blue) = palette[keyPath: role].components
        return Color(red: red, green: green, blue: blue)
    }

    static func nsColor(_ role: KeyPath<Palette, PaletteColour>) -> NSColor {
        let (red, green, blue) = palette[keyPath: role].components
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    static var screen: Color        { color(\.screen) }
    static var face: Color          { color(\.face) }
    static var faceDark: Color      { color(\.faceDark) }
    static var faceLight: Color     { color(\.faceLight) }
    static var shine: Color         { color(\.shine) }
    static var shadow: Color        { color(\.shadow) }
    static var sunken: Color        { color(\.sunken) }
    static var text: Color          { color(\.text) }
    static var textDim: Color       { color(\.textDim) }
    static var caption: Color       { color(\.caption) }
    static var highlight: Color     { color(\.highlight) }
    static var highlightText: Color { color(\.highlightText) }
    static var accent: Color        { color(\.accent) }
    static var arc: Color           { color(\.arc) }
    static var meter: Color         { color(\.meter) }
    static var meterPeak: Color     { color(\.meterPeak) }
    static var meterOff: Color      { color(\.meterOff) }

    static func meterCell(at fraction: Double) -> Color {
        let (red, green, blue) = palette.meterCell(at: fraction).components
        return Color(red: red, green: green, blue: blue)
    }

    static let bevel = CGFloat(Palette.bevel)

    // MARK: - Font

    /// A pixel face if the user has one installed, otherwise the blockiest
    /// monospaced face macOS ships. Nothing is bundled: a bitmap face is
    /// somebody's work, and the skin does not need to carry it to read right.
    static let fontName: String? = {
        let candidates = [
            "JetBrains Mono", "JetBrainsMono-Regular",
            "IBM Plex Mono", "PxPlus IBM VGA8",
            "Menlo", "Monaco",
        ]
        let available = Set(NSFontManager.shared.availableFonts)
        let families = Set(NSFontManager.shared.availableFontFamilies)
        return candidates.first { available.contains($0) || families.contains($0) }
    }()

    static func font(_ size: CGFloat) -> Font {
        if let name = fontName { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    /// The chosen face if there is one. A pixel face has no separate bold, and
    /// asking the system for one would put two different typefaces in the same
    /// window; only the fallback is really emboldened.
    static func boldFont(_ size: CGFloat) -> Font {
        if let name = fontName, name != "Menlo", name != "Monaco" {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }
}

/// A raised or recessed bevel: a lit edge on the top and left, a dark edge on
/// the bottom and right. Recessed is the same rule with the two swapped, which
/// is why one view does both.
struct BevelBox: View {
    enum Style { case raised, recessed }

    var style: Style = .raised
    var fill: Color = Classic.face
    var width: CGFloat = Classic.bevel

    var body: some View {
        GeometryReader { geo in
            let shine = style == .raised ? Classic.shine : Classic.shadow
            let shadow = style == .raised ? Classic.shadow : Classic.shine
            ZStack(alignment: .topLeading) {
                fill
                // top
                Rectangle().fill(shine)
                    .frame(width: geo.size.width, height: width)
                // left
                Rectangle().fill(shine)
                    .frame(width: width, height: geo.size.height)
                // bottom
                Rectangle().fill(shadow)
                    .frame(width: geo.size.width, height: width)
                    .offset(y: geo.size.height - width)
                // right
                Rectangle().fill(shadow)
                    .frame(width: width, height: geo.size.height)
                    .offset(x: geo.size.width - width)
            }
        }
    }
}

extension View {
    /// Wraps the view in a bevel with the usual two-pixel inset.
    func classicBevel(_ style: BevelBox.Style = .raised,
                      fill: Color? = nil,
                      inset: CGFloat = Classic.bevel + 2) -> some View {
        self
            .padding(inset)
            .background(BevelBox(style: style, fill: fill ?? Classic.face))
    }
}
