import Foundation

/// The About requester.
///
/// An Amiga program answered "who wrote this?" with a bevelled box in the
/// middle of the window and a single gadget to make it go away, and nothing
/// under it could be touched until it did. That last part is not decoration:
/// `controls(for:)` returns this box's OK gadget and nothing else while it is
/// up, so the modality is a property of the layout rather than a flag some
/// event handler has to remember to check.
///
/// The words are the ones the macOS About panel shows, wrapped by hand to a
/// font that is eight pixels wide and does not wrap itself.
extension PlayerScreenRenderer {

    static let aboutLineHeight = 10
    static let aboutButtonHeight = 20

    /// Leading spaces are the indent; there is no other styling in an 8×8 face.
    static let aboutText: [String] = [
        "ModRunner",
        "",
        "A player for MED / OctaMED and ProTracker modules —",
        "the Amiga tracker formats of the late eighties and",
        "early nineties.",
        "",
        "FORMATS",
        "  OctaMED     .med, played in full",
        "  ProTracker  .mod, same replayer",
        "  .med in MMD0 and MMD1; MMD2 and MMD3 are",
        "  detected and reported, not played",
        "",
        "BUILT ON THE WORK OF",
        "  Teijo Kinnunen",
        "    MED, OctaMED and the format specification",
        "  Ed Wiles / RBF Software",
        "    The OctaMED SoundStudio manual",
        "  The OpenMPT developers",
        "    Their MED loader, used to cross-check the",
        "    tempo conversion",
        "  Claudio Matsuoka, Hipolito Carraro Jr",
        "    libxmp, the reference renderer",
        "",
        "© 2026 incūdex, Lars Gossard",
        "Apache License 2.0"
    ]

    public static func aboutBox(for screen: PlayerScreen) -> Rect {
        let widest = aboutText.map { Font.width(of: $0) }.max() ?? 0
        let boxWidth = widest + 32
        let boxHeight = aboutText.count * aboutLineHeight + aboutButtonHeight + 28
        let canvasHeight = height(for: screen)
        return Rect(Swift.max(0, (width - boxWidth) / 2),
                    Swift.max(0, (canvasHeight - boxHeight) / 2),
                    Swift.min(boxWidth, width), Swift.min(boxHeight, canvasHeight))
    }

    public static func aboutButton(for screen: PlayerScreen) -> Rect {
        let box = aboutBox(for: screen)
        let buttonWidth = 64
        return Rect(box.x + (box.width - buttonWidth) / 2,
                    box.maxY - Theme.bevel - 6 - aboutButtonHeight,
                    buttonWidth, aboutButtonHeight)
    }

    static func about(_ canvas: inout Canvas, _ screen: PlayerScreen) {
        let box = aboutBox(for: screen)
        canvas.bevel(box, .raised)

        var y = box.y + Theme.bevel + 8
        for line in aboutText {
            canvas.text(line, at: box.x + 14, y, Theme.text,
                        maxWidth: box.width - 28)
            y += aboutLineHeight
        }
        canvas.button(aboutButton(for: screen), "OK")
    }
}
