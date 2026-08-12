import SwiftUI
import AppKit
import ModRunnerKit

/// The AmigaOS 3.x Workbench look: the default eight-colour palette, chunky
/// two-pixel bevels and a topaz-style monospaced face.
enum Amiga {

    // The stock Workbench 3.x palette. Pens 0-3 carry the whole interface;
    // 4-7 are the extra pens OS 3.x added for the higher-colour Workbench.
    static let grey      = Color(red: 0x95 / 255, green: 0x95 / 255, blue: 0x95 / 255) // pen 0
    static let black     = Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x00 / 255) // pen 1
    static let white     = Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255) // pen 2
    static let blue      = Color(red: 0x3B / 255, green: 0x67 / 255, blue: 0xA2 / 255) // pen 3
    static let darkGrey  = Color(red: 0x7B / 255, green: 0x7B / 255, blue: 0x7B / 255) // pen 4
    static let lightGrey = Color(red: 0xAF / 255, green: 0xAF / 255, blue: 0xAF / 255) // pen 5
    static let tan       = Color(red: 0xAA / 255, green: 0x90 / 255, blue: 0x7C / 255) // pen 6
    static let salmon    = Color(red: 0xFF / 255, green: 0xA9 / 255, blue: 0x97 / 255) // pen 7

    /// Screen background behind the window, as on a Workbench screen.
    static let screen = Color(red: 0x60 / 255, green: 0x60 / 255, blue: 0x60 / 255)

    static let bevel: CGFloat = 2

    // MARK: - Font

    /// Prefers a real Topaz if the user has one installed, otherwise falls back
    /// to the blockiest monospaced face macOS ships.
    static let fontName: String? = {
        let candidates = [
            "TopazPlus a600a1200a4000", "Topaz a600a1200a4000",
            "TopazPlus a500a1000a2000", "Topaz a500a1000a2000",
            "Topaz-8", "Topaz New", "Topaz",
            "PxPlus AmigaPC 8", "Amiga Forever",
            "Monaco",
        ]
        let available = Set(NSFontManager.shared.availableFonts)
        let families = Set(NSFontManager.shared.availableFontFamilies)
        return candidates.first { available.contains($0) || families.contains($0) }
    }()

    static func font(_ size: CGFloat) -> Font {
        if let name = fontName { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    static func boldFont(_ size: CGFloat) -> Font {
        if let name = fontName, name != "Monaco" { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: .bold, design: .monospaced)
    }
}

/// A raised or recessed bevel, drawn the way Intuition drew them: a light edge
/// on the top and left, a dark edge on the bottom and right.
struct BevelBox: View {
    enum Style { case raised, recessed }

    var style: Style = .raised
    var fill: Color = Amiga.grey
    var width: CGFloat = Amiga.bevel

    var body: some View {
        GeometryReader { geo in
            let shine = style == .raised ? Amiga.white : Amiga.black
            let shadow = style == .raised ? Amiga.black : Amiga.white
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
    func amigaBevel(_ style: BevelBox.Style = .raised,
                    fill: Color = Amiga.grey,
                    inset: CGFloat = Amiga.bevel + 2) -> some View {
        self
            .padding(inset)
            .background(BevelBox(style: style, fill: fill))
    }
}
