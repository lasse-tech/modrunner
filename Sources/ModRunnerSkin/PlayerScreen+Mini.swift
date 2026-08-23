import Foundation
import ModRunnerKit

/// The strip that stays out of the way while something else has the screen.
///
/// Title, transport, one level bar, and nothing else — the same contents as the
/// macOS mini player, drawn to the same 340 points wide. Both ways back to the
/// full player are on the title bar: close and zoom, because the strip is a
/// mode rather than a second window.
extension PlayerScreenRenderer {

    static let miniMargin = 6
    static let miniGap = 5
    static let miniReadoutHeight = 18
    static let miniTransportHeight = 22
    static let miniSliderHeight = 14
    static let miniButtonWidth = 36
    static let miniTimeWidth = 5 * Font.cellWidth

    static var miniHeight: Int {
        titleBarHeight + miniMargin
            + miniReadoutHeight + miniGap
            + miniTransportHeight + miniGap
            + miniSliderHeight + miniMargin
    }

    /// Where the strip puts its three rows.
    private struct MiniPanels {
        var readout = Rect(0, 0, 0, 0)
        var transport = Rect(0, 0, 0, 0)
        var slider = Rect(0, 0, 0, 0)
    }

    private static func miniPanels() -> MiniPanels {
        var panels = MiniPanels()
        let x = miniMargin
        let contentWidth = miniWidth - miniMargin * 2
        var y = titleBarHeight + miniMargin

        panels.readout = Rect(x, y, contentWidth, miniReadoutHeight)
        y = panels.readout.maxY + miniGap
        panels.transport = Rect(x, y, contentWidth, miniTransportHeight)
        y = panels.transport.maxY + miniGap
        panels.slider = Rect(x, y, contentWidth, miniSliderHeight)
        return panels
    }

    /// The three transport buttons, laid out once for the drawing and the hit
    /// testing both.
    private static func miniButtons(in rect: Rect) -> [(role: ControlRole, rect: Rect)] {
        let roles: [ControlRole] = [.previousModule, .playPause, .nextModule]
        return roles.enumerated().map { index, role in
            (role, Rect(rect.x + index * (miniButtonWidth + miniGap), rect.y,
                        miniButtonWidth, rect.height))
        }
    }

    /// One bar for the whole mix: at this size a meter per channel would be
    /// four smears of grey.
    private static func miniMeter(in rect: Rect) -> Rect {
        let x = rect.x + 3 * (miniButtonWidth + miniGap)
        return Rect(x, rect.y + 4, Swift.max(0, rect.maxX - x - miniTimeWidth - miniGap),
                    rect.height - 8)
    }

    static func miniControls(for screen: PlayerScreen) -> [Control] {
        let panels = miniPanels()
        var controls: [Control] = []

        // Close and zoom both lead back to the full player, so neither of them
        // is a way to lose the window by accident.
        let gadget = titleBarHeight
        controls.append(Control(rect: Rect(0, 0, gadget, gadget), role: .close))
        controls.append(Control(rect: Rect(miniWidth - gadget * 3, 0, gadget, gadget),
                                role: .minimise))
        controls.append(Control(rect: Rect(miniWidth - gadget * 2, 0, gadget, gadget), role: .zoom))
        controls.append(Control(rect: Rect(miniWidth - gadget, 0, gadget, gadget), role: .depth))
        controls.append(Control(rect: Rect(0, 0, miniWidth, titleBarHeight), role: .titleBar))

        for button in miniButtons(in: panels.transport) {
            controls.append(Control(rect: button.rect, role: button.role))
        }
        controls.append(Control(rect: miniMeter(in: panels.transport), role: .visualiserPanel))
        controls.append(Control(rect: panels.slider, role: .songPosition))
        return controls
    }

    static func renderMini(_ screen: PlayerScreen) -> Canvas {
        var canvas = Canvas(width: miniWidth, height: miniHeight, fill: Theme.face)
        let panels = miniPanels()

        _ = titleBar(&canvas, screen, y: 0)
        canvas.readout(panels.readout, screen.moduleTitle)

        for button in miniButtons(in: panels.transport) {
            let label: String
            switch button.role {
            case .previousModule: label = "|<"
            case .nextModule:     label = ">|"
            default:              label = screen.isPlaying ? "||" : ">"
            }
            canvas.button(button.rect, label)
        }

        let meter = miniMeter(in: panels.transport)
        canvas.text("MIX", at: meter.x, meter.y + (meter.height - Font.cellHeight) / 2,
                    Theme.caption)
        let labelWidth = 4 * Font.cellWidth
        canvas.meter(Rect(meter.x + labelWidth, meter.y,
                          Swift.max(0, meter.width - labelWidth), meter.height),
                     level: screen.meters.max() ?? 0)

        canvas.text(screen.time,
                    at: panels.transport.maxX - Font.width(of: screen.time),
                    panels.transport.y + (panels.transport.height - Font.cellHeight) / 2,
                    Theme.text)

        canvas.slider(panels.slider, value: screen.progress)
        return canvas
    }
}
