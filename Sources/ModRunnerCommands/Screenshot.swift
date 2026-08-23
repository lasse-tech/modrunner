import Foundation
import ModRunnerKit
import ModRunnerSkin

/// Draws the classic interface into a PNG without opening a window.
///
/// This is how the portable skin is looked at on a machine that has no way to
/// show it yet, and how a build server checks that it still draws: the renderer
/// needs no display, so the picture it would put on screen can be written to a
/// file instead. When there is a window layer, it will call the same renderer
/// with the same screen description.
enum Screenshot {

    static func run(_ arguments: Arguments) throws -> Int32 {
        guard let path = arguments.operands.first else { throw CommandError.noModules }
        guard let output = arguments.string("-o", "--output") else { throw CommandError.needsOutput }

        let url = URL(fileURLWithPath: path)
        let module = try ModuleLoader.load(url: url)

        // A still of a module that has not been played yet would be all zeroes,
        // so the replayer is run offline up to the requested point and the
        // picture taken from there.
        let seconds = arguments.double("--seconds") ?? 8
        let replayer = Replayer()
        replayer.prepare(sampleRate: 44_100)
        replayer.load(module: module)
        replayer.play()

        let frames = Int(44_100 * max(0, seconds))
        if frames > 0 {
            let chunk = 4_096
            var left = [Float](repeating: 0, count: chunk)
            var right = [Float](repeating: 0, count: chunk)
            var rendered = 0
            while rendered < frames {
                let count = min(chunk, frames - rendered)
                left.withUnsafeMutableBufferPointer { leftBuffer in
                    right.withUnsafeMutableBufferPointer { rightBuffer in
                        replayer.render(left: leftBuffer.baseAddress!,
                                        right: rightBuffer.baseAddress!,
                                        frames: count)
                    }
                }
                rendered += count
            }
        }

        // Which of the three shapes to draw, and which visualisation in it.
        // The window layer has no way to hand a picture back, so this is how
        // the strip and the stage are looked at without one — and how a change
        // to either is measured rather than eyeballed.
        let layout = PlayerScreen.Layout(rawValue: arguments.string("--layout") ?? "window")
            ?? .window
        let visualisation = PlayerScreen.Visualisation(
            rawValue: arguments.string("--visualiser", "--visualizer") ?? "levels") ?? .levels

        let stageWidth = arguments.int("--width") ?? 1280
        let stageHeight = arguments.int("--height") ?? 720
        let rows: Int
        switch layout {
        case .window: rows = 17
        case .mini:   rows = 0
        case .stage:
            rows = PlayerScreenRenderer.stageTrackerRows(width: stageWidth, height: stageHeight,
                                                         tracks: module.numTracks)
        }

        var screen = PlayerScreen(
            module: module,
            snapshot: replayer.snapshot(),
            playlist: arguments.operands.map { URL(fileURLWithPath: $0).lastPathComponent },
            currentIndex: 0,
            visibleRows: rows,
            showTracker: !arguments.has("--no-tracker"),
            layout: layout,
            waveform: replayer.waveform(sampleCount: 320),
            visualisation: visualisation
        )
        screen.stageWidth = stageWidth
        screen.stageHeight = stageHeight

        // A pointer position draws the picture as it would look with the mouse
        // there: the tool tip of whatever is under it, over everything else.
        // The only way to check the help text and the hit boxes agree without
        // a window and a hand on the mouse.
        if let pointer = arguments.string("--pointer") {
            let parts = pointer.split(separator: ",").compactMap { Int($0) }
            if parts.count == 2,
               let text = PlayerScreenRenderer.help(at: parts[0], y: parts[1], in: screen) {
                screen.tooltip = PlayerScreen.Tooltip(text: text, x: parts[0], y: parts[1])
            }
        }

        let canvas = PlayerScreenRenderer.render(screen)
        let png = PNG.encode(canvas)

        if output == "-" {
            FileHandle.standardOutput.write(png)
        } else {
            let destination = URL(fileURLWithPath: output)
            do {
                try png.write(to: destination)
            } catch {
                throw CommandError.notWritable(output)
            }
            warn("wrote \(canvas.width)×\(canvas.height) to \(output)")
        }
        return 0
    }
}
