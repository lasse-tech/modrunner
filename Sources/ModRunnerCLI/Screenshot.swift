import Foundation
import ModRunnerKit
import ModRunnerSkin

/// Draws the Workbench interface into a PNG without opening a window.
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

        let screen = PlayerScreen(
            module: module,
            snapshot: replayer.snapshot(),
            playlist: arguments.operands.map { URL(fileURLWithPath: $0).lastPathComponent },
            currentIndex: 0,
            showTracker: !arguments.has("--no-tracker")
        )

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
