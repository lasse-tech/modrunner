import XCTest
import SwiftUI
@testable import ModRunner
@testable import ModRunnerKit

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

    /// The full-screen stage, at a common display size. The pattern has to fill
    /// the height: if the type size or row count is miscomputed the tracker box
    /// ends up a stripe in the middle of an empty screen.
    func testRenderStage() throws {
        let directory = try outputDirectory()

        let model = PlayerModel.shared
        model.load(url: Self.moduleDirectory.appendingPathComponent("Happy Hour.med"))

        let view = AmigaStageView(model: model, chromeVisible: true).frame(width: 1440, height: 900)
        let size = try write(view, to: directory.appendingPathComponent("stage.png"))
        XCTAssertEqual(size.width, 1440, accuracy: 1.0)
    }

    /// The stage's pattern mid-block, where there is data above the playhead as
    /// well as below it.
    func testRenderStageTracker() throws {
        let directory = try outputDirectory()
        let module = try loadExample()

        let layout = StageView.layout(for: CGSize(width: 1440, height: 900), tracks: module.numTracks)
        let view = TrackerView(module: module, block: 0, line: 30, layout: layout)
            .frame(width: 1440 - 56)
            .background(Amiga.screen)

        try write(view, to: directory.appendingPathComponent("stage-tracker.png"))

        // The playhead has to sit in the middle: equal context above and below.
        XCTAssertGreaterThanOrEqual(layout.context, 7)
        XCTAssertLessThanOrEqual(layout.fontSize, 34)
    }

    /// The mini player in both skins, at the fixed size its window is opened
    /// with — the window is not resized when the skin changes, so both have to
    /// fit the same box.
    func testRenderMiniPlayer() throws {
        let directory = try outputDirectory()

        let model = PlayerModel.shared
        model.load(url: Self.moduleDirectory.appendingPathComponent("Happy Hour.med"))

        for skin in Skin.allCases {
            let view = (skin == .amiga
                        ? AnyView(AmigaMiniPlayerView(model: model))
                        : AnyView(NativeMiniPlayerView(model: model)))
                .frame(width: MiniPlayerView.width, height: MiniPlayerView.height)
                .background(Amiga.screen)

            let size = try write(view, to: directory.appendingPathComponent("mini-\(skin.rawValue).png"))
            XCTAssertEqual(size.width, MiniPlayerView.width, accuracy: 1.0)
            XCTAssertEqual(size.height, MiniPlayerView.height, accuracy: 1.0)
        }
    }

    /// The native stage. The Workbench one is covered by `testRenderStage`.
    func testRenderNativeStage() throws {
        let directory = try outputDirectory()

        let model = PlayerModel.shared
        model.load(url: Self.moduleDirectory.appendingPathComponent("Happy Hour.med"))

        let view = NativeStageView(model: model, chromeVisible: true)
            .frame(width: 1440, height: 900)
        let size = try write(view, to: directory.appendingPathComponent("stage-native.png"))
        XCTAssertEqual(size.width, 1440, accuracy: 1.0)
    }

    /// The About panel, in both languages: German is the longer of the two and
    /// is where the fixed 640-point width gets tested.
    func testRenderAbout() throws {
        let directory = try outputDirectory()

        for language in [AppLanguage.english, .german] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            let size = try write(AboutView(),
                                 to: directory.appendingPathComponent("about-\(language.rawValue).png"))
            XCTAssertEqual(size.width, 640, accuracy: 1.0)
        }
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
    }

    func testRenderWaveform() throws {
        let directory = try outputDirectory()

        // A recognisable trace: two summed sines, as a module's mix would be.
        let samples = (0..<320).map { i -> Float in
            let t = Double(i) / 320
            return Float(0.32 * sin(t * .pi * 12) + 0.14 * sin(t * .pi * 43))
        }

        let view = WaveformView(samples: samples)
            .frame(width: 250, height: VisualizerView.height)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))

        try write(view, to: directory.appendingPathComponent("waveform-native.png"))
    }

    /// The ripple field, at panel size and again large, since it is meant to
    /// carry a whole screen as well as a corner of the window.
    func testRenderRipple() throws {
        let directory = try outputDirectory()

        // Two summed sines: a recognisable trace with a slow and a fast part.
        let samples = (0..<320).map { i -> Float in
            let t = Double(i) / 320
            return Float(0.55 * sin(t * .pi * 4) + 0.25 * sin(t * .pi * 17))
        }
        let levels: [Float] = [0.82, 0.44, 0.63, 0.7]

        try write(RippleView(samples: samples, levels: levels)
                    .frame(width: VisualizerView.width, height: VisualizerView.height),
                  to: directory.appendingPathComponent("ripple-panel.png"))

        try write(RippleView(samples: samples, levels: levels)
                    .frame(width: 900, height: 380),
                  to: directory.appendingPathComponent("ripple-large.png"))
    }

    func testRenderNativeMeters() throws {
        let directory = try outputDirectory()

        let view = ChannelMeters(levels: [0.82, 0.44, 0.13, 0.66])
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))

        try write(view, to: directory.appendingPathComponent("meters-native.png"))
    }
}
