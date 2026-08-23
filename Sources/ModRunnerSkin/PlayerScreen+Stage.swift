import Foundation
import ModRunnerKit

/// The player with the whole screen: the tracker at twice the size, the song
/// written across the top, and the transport along the bottom.
///
/// The same idea as the macOS stage — the app becomes the room rather than a
/// window in it — so there is no title bar and no playlist here. The way out is
/// the gadget in the top right or the Escape key, and the footer says so.
extension PlayerScreenRenderer {

    static let stageMargin = 16
    static let stageGap = 12
    static let stageHeaderHeight = 52
    static let stageFooterHeight = 70
    static let stageSliderHeight = 14
    /// The transport row. The buttons are centred in it and the visualisation
    /// fills it, so the strip is as tall as the picture wants rather than as
    /// tall as a button.
    static let stageTransportHeight = 38
    static let stageButtonHeight = 26
    static let stageButtonWidth = 40
    static let stageGadget = 22

    /// Twice the size, unless the module has too many tracks for the screen to
    /// carry them at that size — then the pattern is worth more than the size.
    static func stageScale(width: Int, tracks: Int) -> Int {
        let inner = width - stageMargin * 2 - (Theme.bevel + 2) * 2
        let needed = (4 + Swift.max(1, tracks) * 12) * Font.cellWidth * 2
        return needed <= inner ? 2 : 1
    }

    static func stageTrackerRect(width: Int, height: Int) -> Rect {
        let top = stageMargin + stageHeaderHeight + stageGap
        let bottom = height - stageMargin - stageFooterHeight - stageGap
        return Rect(stageMargin, top,
                    Swift.max(0, width - stageMargin * 2), Swift.max(0, bottom - top))
    }

    /// How many pattern lines the stage has room for. The player builds the
    /// rows, so it has to be able to ask before there is a screen to measure.
    public static func stageTrackerRows(width: Int, height: Int, tracks: Int) -> Int {
        let scale = stageScale(width: width, tracks: tracks)
        let inner = stageTrackerRect(width: width, height: height).inset(by: Theme.bevel + 2)
        let rowHeight = Font.cellHeight * scale + 4
        let listTop = inner.y + rowHeight
        return Swift.max(1, (inner.maxY - listTop) / rowHeight)
    }

    // MARK: - Where it sits

    private struct StagePanels {
        var header = Rect(0, 0, 0, 0)
        var leave = Rect(0, 0, 0, 0)
        var fields = Rect(0, 0, 0, 0)
        var title = Rect(0, 0, 0, 0)
        var tracker = Rect(0, 0, 0, 0)
        var footer = Rect(0, 0, 0, 0)
        var slider = Rect(0, 0, 0, 0)
        var transport = Rect(0, 0, 0, 0)
        var visualiser = Rect(0, 0, 0, 0)
        var hints = Rect(0, 0, 0, 0)
    }

    private static func stagePanels(for screen: PlayerScreen) -> StagePanels {
        let canvasWidth = width(for: screen)
        let canvasHeight = height(for: screen)
        var panels = StagePanels()

        panels.header = Rect(stageMargin, stageMargin,
                             canvasWidth - stageMargin * 2, stageHeaderHeight)
        let head = panels.header.inset(by: Theme.bevel + 2)
        panels.leave = Rect(head.maxX - stageGadget,
                            head.y + (head.height - stageGadget) / 2, stageGadget, stageGadget)
        // The fields take what is left over after the title has had its share,
        // so a narrow screen loses columns rather than the name of the song.
        let fieldsWidth = Swift.min(420, Swift.max(0, panels.leave.x - 8 - head.x - 160))
        panels.fields = Rect(panels.leave.x - 8 - fieldsWidth, head.y, fieldsWidth, head.height)
        panels.title = Rect(head.x, head.y, Swift.max(0, panels.fields.x - 12 - head.x), head.height)

        panels.tracker = stageTrackerRect(width: canvasWidth, height: canvasHeight)

        panels.footer = Rect(stageMargin, canvasHeight - stageMargin - stageFooterHeight,
                             canvasWidth - stageMargin * 2, stageFooterHeight)
        let foot = panels.footer.inset(by: Theme.bevel + 2)
        panels.slider = Rect(foot.x, foot.y, foot.width, stageSliderHeight)
        panels.transport = Rect(foot.x, panels.slider.maxY + 6, foot.width, stageTransportHeight)

        let buttons = 6 * (stageButtonWidth + 4)
        let hintWidth = Swift.min(Swift.max(0, panels.transport.width - buttons - 140),
                                  Font.width(of: L10n.t("stage.keys")))
        panels.hints = Rect(panels.transport.maxX - hintWidth, panels.transport.y,
                            hintWidth, panels.transport.height)
        panels.visualiser = Rect(panels.transport.x + buttons, panels.transport.y,
                                 Swift.max(0, panels.hints.x - 8 - panels.transport.x - buttons),
                                 panels.transport.height)
        return panels
    }

    private static func stageButton(_ index: Int, in row: Rect) -> Rect {
        Rect(row.x + index * (stageButtonWidth + 4),
             row.y + (row.height - stageButtonHeight) / 2, stageButtonWidth, stageButtonHeight)
    }

    static func stageControls(for screen: PlayerScreen) -> [Control] {
        let panels = stagePanels(for: screen)
        var controls: [Control] = []

        controls.append(Control(rect: panels.leave, role: .fullScreen))
        let roles: [ControlRole] = [.previousModule, .previousPosition, .playPause,
                                    .stop, .nextPosition, .nextModule]
        for (index, role) in roles.enumerated() {
            controls.append(Control(rect: stageButton(index, in: panels.transport), role: role))
        }
        controls.append(Control(rect: panels.visualiser, role: .visualiserPanel))
        controls.append(Control(rect: panels.slider, role: .songPosition))
        return controls
    }

    // MARK: - Drawing it

    static func renderStage(_ screen: PlayerScreen) -> Canvas {
        var canvas = Canvas(width: width(for: screen), height: height(for: screen),
                            fill: Theme.screen)
        let panels = stagePanels(for: screen)

        stageHeader(&canvas, screen, panels)
        stageTracker(&canvas, screen, panels.tracker)
        stageFooter(&canvas, screen, panels)
        return canvas
    }

    private static func stageHeader(_ canvas: inout Canvas, _ screen: PlayerScreen,
                                    _ panels: StagePanels) {
        canvas.bevel(panels.header, .raised)

        canvas.text(screen.moduleTitle, at: panels.title.x,
                    panels.title.y + (panels.title.height - Font.cellHeight * 2) / 2,
                    Theme.text, scale: 2, maxWidth: panels.title.width)

        let fields = [("POS", screen.position), ("BLOCK", screen.block), ("LINE", screen.line),
                      ("BPM", screen.beatsPerMinute), ("TIME", screen.time)]
        if panels.fields.width > 0 {
            let fieldWidth = (panels.fields.width - (fields.count - 1) * 4) / fields.count
            for (index, field) in fields.enumerated() {
                canvas.field(Rect(panels.fields.x + index * (fieldWidth + 4),
                                  panels.fields.y + 4, fieldWidth, panels.fields.height - 8),
                             caption: field.0, value: field.1)
            }
        }
        canvas.gadget(panels.leave, .zoom)
    }

    private static func stageTracker(_ canvas: inout Canvas, _ screen: PlayerScreen, _ rect: Rect) {
        canvas.bevel(rect, .recessed, fill: Theme.sunken)
        let inner = rect.inset(by: Theme.bevel + 2)
        let scale = stageScale(width: width(for: screen), tracks: screen.trackCount)
        let cell = Font.cellWidth * scale
        let rowHeight = Font.cellHeight * scale + 4

        let lineColumn = 4 * cell
        let trackWidth = screen.trackCount > 0
            ? (inner.width - lineColumn) / screen.trackCount : inner.width

        canvas.text("LN", at: inner.x, inner.y, Theme.caption, scale: scale)
        for track in 0..<screen.trackCount {
            canvas.text("TRACK \(track + 1)", at: inner.x + lineColumn + track * trackWidth,
                        inner.y, Theme.caption, scale: scale, maxWidth: trackWidth - 4)
        }

        var y = inner.y + rowHeight
        for row in screen.trackerRows {
            guard y + rowHeight <= inner.maxY + rowHeight else { break }
            if row.isCurrent {
                canvas.fill(Rect(rect.x + Theme.bevel, y - 2,
                                 rect.width - Theme.bevel * 2, rowHeight), Theme.highlight)
            }
            let ink = row.isCurrent ? Theme.highlightText : Theme.text
            if !row.cells.isEmpty {
                canvas.text(String(format: "%03d", row.line), at: inner.x, y,
                            row.isCurrent ? Theme.highlightText : Theme.caption, scale: scale)
            }
            for (track, cellText) in row.cells.enumerated() where track < screen.trackCount {
                canvas.text(cellText, at: inner.x + lineColumn + track * trackWidth, y, ink,
                            scale: scale, maxWidth: trackWidth - 4)
            }
            y += rowHeight
        }
    }

    private static func stageFooter(_ canvas: inout Canvas, _ screen: PlayerScreen,
                                    _ panels: StagePanels) {
        canvas.bevel(panels.footer, .raised)
        canvas.slider(panels.slider, value: screen.progress)

        let labels = ["|<", "<<", screen.isPlaying ? "||" : ">", "[]", ">>", ">|"]
        for (index, label) in labels.enumerated() {
            canvas.button(stageButton(index, in: panels.transport), label)
        }

        if panels.visualiser.width > 40 {
            VisualiserRenderer.draw(&canvas, screen, in: panels.visualiser)
        }
        if panels.hints.width > 0 {
            canvas.text(L10n.t("stage.keys"), at: panels.hints.x,
                        panels.hints.y + (panels.hints.height - Font.cellHeight) / 2,
                        Theme.caption, maxWidth: panels.hints.width)
        }
    }
}
