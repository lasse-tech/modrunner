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

    private func outputDirectory() throws -> URL {
        let path = ProcessInfo.processInfo.environment["MED_SNAPSHOT"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set MED_SNAPSHOT=<dir> to write snapshots")
        return URL(fileURLWithPath: path)
    }

    private func loadExample() throws -> MMDModule {
        let url = Self.moduleDirectory.appendingPathComponent("Happy Hour.med")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        return try MMDLoader.load(url: url)
    }

    @discardableResult
    private func write<V: View>(_ view: V, to url: URL) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("ImageRenderer produced no image")
        }
        try png.write(to: url)
        return image.size
    }

    func testRenderWorkbenchTracker() throws {
        let directory = try outputDirectory()
        let module = try loadExample()

        let view = TrackerView(module: module, block: 0, line: 12)
            .frame(width: 552)
            .background(Amiga.grey)

        let size = try write(view, to: directory.appendingPathComponent("tracker-workbench.png"))
        XCTAssertEqual(size.height, TrackerView.panelHeight, accuracy: 1.0,
                       "panel height must match what the window size is computed from")
    }

    func testRenderNativeTracker() throws {
        let directory = try outputDirectory()
        let module = try loadExample()

        // Mid-scroll, to check the continuous offset rather than a resting row.
        let view = SmoothTrackerView(module: module, block: 0, line: 12, progress: 0.45)
            .frame(width: 604)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

        let size = try write(view, to: directory.appendingPathComponent("tracker-native.png"))
        XCTAssertEqual(size.height, SmoothTrackerView.height + 16, accuracy: 1.0)
    }

    /// The Workbench skin draws its own title bar and gadgets, because the
    /// system chrome is hidden for it. If that bar goes missing the window has
    /// no controls at all, so it is worth asserting.
    func testRenderWorkbenchSkin() throws {
        let directory = try outputDirectory()
        let module = try loadExample()

        let model = PlayerModel.shared
        model.load(url: Self.moduleDirectory.appendingPathComponent("Happy Hour.med"))
        XCTAssertEqual(model.module?.displayTitle, module.displayTitle)

        let size = try write(AmigaSkinView(model: model),
                             to: directory.appendingPathComponent("skin-workbench.png"))
        XCTAssertEqual(size.width, AmigaSkinView.windowWidth, accuracy: 1.0)
    }

    func testRenderNativeSkin() throws {
        let directory = try outputDirectory()

        let model = PlayerModel.shared
        model.load(url: Self.moduleDirectory.appendingPathComponent("Happy Hour.med"))

        let size = try write(NativeSkinView(model: model),
                             to: directory.appendingPathComponent("skin-native.png"))
        XCTAssertEqual(size.width, NativeSkinView.windowWidth, accuracy: 1.0)
    }

    func testRenderNativeMeters() throws {
        let directory = try outputDirectory()

        let view = ChannelMeters(levels: [0.82, 0.44, 0.13, 0.66])
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))

        try write(view, to: directory.appendingPathComponent("meters-native.png"))
    }
}
