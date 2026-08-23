import Foundation
import ModRunnerKit

/// What each gadget is for, in words.
///
/// The macOS app hangs a `.help` on every button it draws, and the same
/// sentences are wanted here — same keys, same translations, so a gadget cannot
/// be called one thing on one platform and another on the other. There is no
/// toolkit under this skin to hold a tool tip, so the text comes out of the
/// same table the hit testing does and the window layer decides when to show
/// it.
extension PlayerScreenRenderer {

    static let tooltipHeight = Font.cellHeight + 8

    /// The help text for a control, or nil for the ones that are not gadgets —
    /// the title bar is dragged rather than pressed, and a box hovering over it
    /// the whole time would be noise.
    public static func help(for role: ControlRole, in screen: PlayerScreen) -> String? {
        switch role {
        case .previousModule:   return L10n.t("tooltip.playPrevious")
        case .previousPosition: return L10n.t("tooltip.previousBlock")
        case .playPause:        return L10n.t(screen.isPlaying ? "tooltip.pause" : "tooltip.play")
        case .stop:             return L10n.t("tooltip.stop")
        case .nextPosition:     return L10n.t("tooltip.nextBlock")
        case .nextModule:       return L10n.t("tooltip.playNext")
        case .tracker:          return L10n.t("tooltip.tracks")
        case .songPosition:     return L10n.t("tooltip.songPosition")
        case .volume:           return L10n.t("tooltip.volume")
        case .filter:
            return L10n.t(screen.filterEnabled ? "tooltip.filterOn" : "tooltip.filterOff")
        case .openFiles:        return L10n.t("tooltip.open")
        case .visualiser, .visualiserPanel: return L10n.t("tooltip.visualizer")
        case .miniPlayer:
            return L10n.t(screen.layout == .mini ? "tooltip.expand" : "menu.miniPlayer")
        case .fullScreen:
            return L10n.t(screen.layout == .stage ? "tooltip.expand" : "menu.fullScreen")
        case .close:
            // In the strip, close is a way back to the player rather than out
            // of it, and it should not promise otherwise.
            return L10n.t(screen.layout == .mini ? "tooltip.expand" : "tooltip.close")
        case .minimise:         return L10n.t("tooltip.minimise")
        case .zoom:
            return L10n.t(screen.layout == .mini ? "tooltip.expand" : "tooltip.zoom")
        case .depth:            return L10n.t("tooltip.depth")
        case .dismissAbout:     return L10n.t("tooltip.aboutClose")
        case .titleBar:         return nil
        case .playlistEntry(let index):
            guard screen.playlist.indices.contains(index) else { return nil }
            // Not `L10n.t(_:_:)`: the formatted variant goes through
            // `String(format:)`, and the substitution is wanted on every
            // platform this window runs on, not only where Foundation bridges
            // a Swift string into a C variadic.
            return L10n.t("tooltip.playlistEntry")
                .replacingOccurrences(of: "%@", with: screen.playlist[index])
        }
    }

    /// The help text for whatever is under the pointer.
    public static func help(at x: Int, y: Int, in screen: PlayerScreen) -> String? {
        for target in controls(for: screen)
        where x >= target.rect.x && x < target.rect.maxX
            && y >= target.rect.y && y < target.rect.maxY {
            return help(for: target.role, in: screen)
        }
        return nil
    }

    /// Where the box goes: below and to the right of the pointer, the way every
    /// tool tip since 1995 has, and pushed back onto the canvas when that would
    /// put it over the edge.
    public static func tooltipBox(for tip: PlayerScreen.Tooltip, in screen: PlayerScreen) -> Rect {
        let boxWidth = Font.width(of: tip.text) + 12
        let canvasWidth = width(for: screen)
        let canvasHeight = height(for: screen)
        let x = Swift.max(0, Swift.min(tip.x + 12, canvasWidth - boxWidth))
        var y = tip.y + 18
        if y + tooltipHeight > canvasHeight { y = Swift.max(0, tip.y - tooltipHeight - 4) }
        return Rect(x, y, Swift.min(boxWidth, canvasWidth), tooltipHeight)
    }

    static func drawTooltip(_ canvas: inout Canvas, _ screen: PlayerScreen) {
        guard let tip = screen.tooltip, !tip.text.isEmpty else { return }
        let box = tooltipBox(for: tip, in: screen)
        canvas.bevel(box, .raised, fill: Theme.faceLight)
        canvas.text(tip.text, at: box.x + 6, box.y + (box.height - Font.cellHeight) / 2,
                    Theme.text, maxWidth: box.width - 12)
    }
}
