import XCTest
import SwiftUI
@testable import ModRunner

/// Renders the interface offscreen, so layout can be inspected without opening
/// a window or capturing the screen.
@MainActor
final class SnapshotTests: XCTestCase {

    private static let moduleDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples")

    /// Set MED_SNAPSHOT to a directory to write PNGs there.
    func testRenderTrackerView() throws {
        let outputDirectory = ProcessInfo.processInfo.environment["MED_SNAPSHOT"] ?? ""
        try XCTSkipIf(outputDirectory.isEmpty, "Set MED_SNAPSHOT=<dir> to write snapshots")

        let url = Self.moduleDirectory.appendingPathComponent("Happy Hour.med")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        let module = try MMDLoader.load(url: url)

        // A line with actual note data, so the columns are populated.
        let view = TrackerView(module: module, block: 0, line: 12)
            .frame(width: 552)
            .background(Amiga.grey)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not render the tracker view")
        }

        let out = URL(fileURLWithPath: outputDirectory).appendingPathComponent("tracker.png")
        try png.write(to: out)
        print("Wrote \(out.path) (\(Int(image.size.width))x\(Int(image.size.height)) pt)")

        // The panel height is what the window size is computed from, so it must
        // match or the layout will clip.
        XCTAssertEqual(image.size.height, TrackerView.panelHeight, accuracy: 1.0)
    }
}
