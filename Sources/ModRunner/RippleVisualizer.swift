import SwiftUI
import ModRunnerKit

/// Concentric rings seen at a shallow angle, deformed by the waveform — the
/// ripple field that every second music video has had since about 2015.
///
/// Drawn from the mix rather than from a texture: each ring reads the waveform
/// at its own offset, so the rings carry the signal outwards and the field
/// moves the way the sound does. The rings nearest the middle are lifted into a
/// dome by the overall level, which is what makes it read as a wave rather than
/// as a target.
struct RippleView: View {

    let samples: [Float]
    /// Per-voice levels, used only for the overall lift of the dome.
    let levels: [Float]

    /// Rings drawn from the middle outwards.
    var rings = 22
    /// Points per ring. Enough that the deformation is a curve, few enough that
    /// a 60 Hz redraw stays cheap.
    var segments = 96

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard size.width > 1, size.height > 1 else { return }

            let centre = CGPoint(x: size.width / 2, y: size.height * 0.66)
            let lift = CGFloat(min(1, max(0, (levels.max() ?? 0) * 1.4)))

            // Back to front, so the nearer rings are drawn over the far ones.
            for index in (0..<rings).reversed() {
                let t = Double(index) / Double(max(1, rings - 1))
                context.stroke(
                    ring(at: t, centre: centre, size: size, lift: lift),
                    with: .color(colour(at: t, lift: lift)),
                    lineWidth: t < 0.35 ? 1.4 : 1.0
                )
            }
        }
        .background(Self.ground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Geometry

    private func ring(at t: Double, centre: CGPoint, size: CGSize, lift: CGFloat) -> Path {
        // The ellipse: wide, and squashed to about a third, which is the angle
        // the reference is seen from.
        let radiusX = size.width * (0.05 + 0.46 * t)
        let radiusY = radiusX * 0.36

        // The dome. Falls away quickly, so the middle rings carry it and the
        // outer ones stay flat on the "floor".
        let dome = size.height * 0.30 * lift * CGFloat(exp(-6 * t * t))

        var path = Path()
        for step in 0...segments {
            let angle = Double(step) / Double(segments) * 2 * .pi

            // Each ring reads the waveform a little further along, so a peak
            // travels outwards from one ring to the next.
            // The deformation is strongest near the middle and settles further
            // out, so the field reads as a disturbance spreading into calm
            // water rather than as noise everywhere.
            let sample = waveform(phase: t, angle: angle)
            let bulge = 1 + CGFloat(sample) * 0.20 * CGFloat(1 - 0.62 * t)

            let x = centre.x + radiusX * cos(angle) * bulge
            let y = centre.y + radiusY * sin(angle) * bulge - dome
                    // The far side of each ellipse sits slightly higher, which
                    // is what gives the field its depth.
                    - CGFloat(sin(angle)) * radiusY * 0.12

            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// The mix, indexed by ring and angle. Both wrap, so the ring closes on
    /// itself without a seam.
    private func waveform(phase: Double, angle: Double) -> Float {
        guard !samples.isEmpty else { return 0 }
        let turns = angle / (2 * .pi)
        let position = (turns + phase * 1.6).truncatingRemainder(dividingBy: 1)
        let index = Int(position * Double(samples.count)) % samples.count
        return samples[index < 0 ? index + samples.count : index]
    }

    // MARK: - Colour

    /// Deliberately not the brand ramp: this visualisation is asked to look
    /// like the deep blue-to-violet field it is named after, and orange in the
    /// middle of it reads as an error rather than as a house colour.
    private static let ground = Color(red: 0x0A / 255, green: 0x08 / 255, blue: 0x1E / 255)
    private static let near   = Color(red: 0xBF / 255, green: 0xE6 / 255, blue: 0xFF / 255)
    private static let mid    = Color(red: 0x3B / 255, green: 0x67 / 255, blue: 0xE8 / 255)
    private static let far    = Color(red: 0x7A / 255, green: 0x3B / 255, blue: 0xD6 / 255)

    private func colour(at t: Double, lift: CGFloat) -> Color {
        let base = t < 0.5
            ? blend(Self.near, Self.mid, t * 2)
            : blend(Self.mid, Self.far, (t - 0.5) * 2)
        // The outer rings fade out; a loud passage brings them back up.
        let fade = (1 - t * 0.65) * (0.55 + 0.45 * Double(lift))
        return base.opacity(max(0.12, fade))
    }

    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        let f = CGFloat(min(1, max(0, t)))
        return Color(red: Double(ca.redComponent + (cb.redComponent - ca.redComponent) * f),
                     green: Double(ca.greenComponent + (cb.greenComponent - ca.greenComponent) * f),
                     blue: Double(ca.blueComponent + (cb.blueComponent - ca.blueComponent) * f))
    }
}
