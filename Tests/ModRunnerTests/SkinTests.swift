import XCTest
@testable import ModRunnerKit
@testable import ModRunnerSkin

/// The portable skin, checked without a display of any kind.
///
/// This is the whole point of drawing the interface into an array of pixels:
/// what a Linux or Windows user will see can be asserted on a build server with
/// no window system at all, down to individual pixels. Set `MED_SKIN_PNG` to a
/// directory to also write the pictures out and look at them.
final class SkinTests: XCTestCase {

    private func writeIfAsked(_ canvas: Canvas, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["MED_SKIN_PNG"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try PNG.write(canvas, to: url.appendingPathComponent(name))
    }

    // MARK: - Canvas

    func testDrawingClipsRatherThanCrashing() {
        var canvas = Canvas(width: 8, height: 8, fill: Theme.shadow)
        canvas.fill(Rect(-10, -10, 4, 4), Theme.shine)
        canvas.fill(Rect(6, 6, 100, 100), Theme.shine)
        canvas.set(-1, -1, Theme.highlight)
        canvas.set(1_000, 1_000, Theme.highlight)

        XCTAssertEqual(canvas.pixel(0, 0), Theme.shadow)
        XCTAssertEqual(canvas.pixel(7, 7), Theme.shine)
    }

    /// Light on top and left, dark on bottom and right, and the other way
    /// round for a recess. Getting this backwards is the single most visible
    /// way to draw a bevelled interface wrong — and on a dark palette, where
    /// the "light" edge is only the lightest frame tone, it is also the
    /// easiest to get backwards without noticing.
    func testBevelsFaceTheRightWay() {
        var canvas = Canvas(width: 20, height: 20)
        canvas.bevel(Rect(0, 0, 20, 20), .raised)
        XCTAssertEqual(canvas.pixel(10, 0), Theme.shine)
        XCTAssertEqual(canvas.pixel(0, 10), Theme.shine)
        XCTAssertEqual(canvas.pixel(10, 19), Theme.shadow)
        XCTAssertEqual(canvas.pixel(19, 10), Theme.shadow)

        canvas.bevel(Rect(0, 0, 20, 20), .recessed)
        XCTAssertEqual(canvas.pixel(10, 0), Theme.shadow)
        XCTAssertEqual(canvas.pixel(10, 19), Theme.shine)
    }

    func testMeterFillsToTheRightEdge() {
        var canvas = Canvas(width: 100, height: 12)
        canvas.meter(Rect(0, 0, 100, 12), level: 1)
        // Every cell lit means the far end is lit too, not left over as
        // background because the cell width did not divide evenly. The last
        // cells are at the top of the ramp, so this is the peak colour rather
        // than the body of the meter.
        XCTAssertEqual(canvas.pixel(96, 6), Theme.meterPeak)
    }

    func testMeterLeavesUnlitCellsAlone() {
        var canvas = Canvas(width: 100, height: 12)
        canvas.meter(Rect(0, 0, 100, 12), level: 0)
        XCTAssertEqual(canvas.pixel(96, 6), Theme.meterOff)
    }

    // MARK: - Font

    func testEveryPrintableCharacterHasAGlyph() {
        for value in 32...126 {
            let character = Character(UnicodeScalar(value)!)
            let glyph = Font.glyph(for: character)
            XCTAssertEqual(glyph.count, 8, "\(character) has the wrong glyph height")
            if character != " " {
                XCTAssertTrue(glyph.contains { $0 != 0 }, "\(character) is blank")
            }
        }
    }

    func testGermanTextHasItsUmlauts() {
        for character in "ÄÖÜäöüß" {
            let glyph = Font.glyph(for: character)
            XCTAssertTrue(glyph.contains { $0 != 0 }, "\(character) is blank")
        }
    }

    func testTextLandsWhereItIsPut() {
        var canvas = Canvas(width: 40, height: 16, fill: Theme.face)
        canvas.text("I", at: 0, 0, Theme.shadow)
        // The I is a five-pixel bar across the top row of its cell.
        XCTAssertEqual(canvas.pixel(1, 0), Theme.shadow)
        XCTAssertEqual(canvas.pixel(0, 0), Theme.face)
        // Nothing spills into the next cell.
        XCTAssertEqual(canvas.pixel(8, 0), Theme.face)
    }

    func testTextIsClippedToItsWidth() {
        var canvas = Canvas(width: 64, height: 16, fill: Theme.face)
        canvas.text("IIIIIIII", at: 0, 0, Theme.shadow, maxWidth: 16)
        XCTAssertEqual(canvas.pixel(1, 0), Theme.shadow)
        XCTAssertEqual(canvas.pixel(17, 0), Theme.face, "text ran past its width")
    }

    // MARK: - The window

    func testRendersAWholeWindowFromAModule() throws {
        let module = try ModuleLoader.load(url: Self.example)
        var snapshot = Replayer.Snapshot()
        snapshot.isPlaying = true
        snapshot.block = 0
        snapshot.line = 8
        snapshot.lineCount = 64
        snapshot.channelMeters = [0.8, 0.4, 0.6, 0.2]
        snapshot.progress = 0.25
        snapshot.elapsedSeconds = 63

        let screen = PlayerScreen(module: module, snapshot: snapshot,
                                  playlist: ["Happy Hour.med", "Magic Noises.med"],
                                  currentIndex: 0)
        let canvas = PlayerScreenRenderer.render(screen)
        try writeIfAsked(canvas, "classic.png")

        XCTAssertEqual(canvas.width, PlayerScreenRenderer.width)
        XCTAssertGreaterThan(canvas.height, 400)

        // The title bar is the panel face — it is a surface, not a coloured
        // band — and the window is not blank.
        XCTAssertEqual(canvas.pixel(280, 10), Theme.face)
        let distinct = Set(canvas.pixels)
        XCTAssertGreaterThan(distinct.count, 4, "the window rendered as a flat fill")

        // The playing line is the one place the highlight belongs.
        XCTAssertTrue(canvas.pixels.contains(Theme.highlight.rgba),
                      "nothing in the window was highlighted")
    }

    func testTrackerPanelCanBeLeftOut() throws {
        let module = try ModuleLoader.load(url: Self.example)
        let snapshot = Replayer.Snapshot()

        let withTracker = PlayerScreen(module: module, snapshot: snapshot)
        let without = PlayerScreen(module: module, snapshot: snapshot, showTracker: false)

        XCTAssertGreaterThan(PlayerScreenRenderer.height(for: withTracker),
                             PlayerScreenRenderer.height(for: without))
    }

    func testAWindowWithNoModuleStillDraws() throws {
        let canvas = PlayerScreenRenderer.render(PlayerScreen())
        try writeIfAsked(canvas, "classic-empty.png")
        XCTAssertEqual(canvas.width, PlayerScreenRenderer.width)
    }

    // MARK: - Palette

    /// The colours are written down once, in the engine, and both interfaces
    /// read them from there. They used to be written out four times, and the
    /// copies drifted — the window frame stayed grey after the panels were
    /// recoloured. If this ever fails, somebody has put a literal back.
    func testBothPalettesDifferAndBothAreDark() {
        for palette in Palette.allCases {
            XCTAssertNotEqual(palette.face, palette.other.face,
                              "\(palette.rawValue) and \(palette.other.rawValue) share a face colour")
            // Dark means the shine is the lightest *frame* tone, not white:
            // the bevel is inverted, and a shine at full brightness would be
            // the old palette leaking back in.
            XCTAssertLessThan(Int(palette.shine.red), 0xC0)
            XCTAssertGreaterThan(Int(palette.shine.red), Int(palette.shadow.red),
                                 "the lit edge is not lighter than the dark one")
            XCTAssertGreaterThan(Int(palette.text.red), Int(palette.face.red),
                                 "text would not read on the panel face")
        }
    }

    func testSwitchingPaletteChangesWhatIsDrawn() {
        // A store of its own: the palette is a real setting, and a suite that
        // crashes halfway through should not leave the developer's app in the
        // other colours.
        let suite = "de.modrunner.tests.palette"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        Palette.store = UserDefaults(suiteName: suite)!
        defer {
            Palette.store = .standard
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }

        Palette.current = .ember
        let ember = PlayerScreenRenderer.render(PlayerScreen())
        Palette.current = .neon
        let neon = PlayerScreenRenderer.render(PlayerScreen())

        XCTAssertEqual(ember.width, neon.width, "the palette changed the layout")
        XCTAssertNotEqual(ember.pixels, neon.pixels, "the palette had no effect")
    }

    // MARK: - Gadgets

    /// Each of the five is drawn, sits inside its box, and is distinguishable
    /// from the others. A gadget that renders as a plain bevel is a gadget the
    /// user cannot tell apart from its neighbour.
    func testEveryGadgetDrawsSomethingOfItsOwn() {
        var pictures: [[UInt32]] = []
        for kind in Theme.Gadget.allCases {
            var canvas = Canvas(width: 26, height: 22, fill: Theme.screen)
            canvas.gadget(Rect(0, 0, 26, 22), kind)
            XCTAssertTrue(canvas.pixels.contains(Theme.text.rgba), "\(kind) drew no ink")
            // Nothing outside the gadget: the glyphs are placed on a 14x12
            // grid inside the box, and an off-by-one used to push whole ones
            // into the window edge.
            XCTAssertEqual(canvas.pixel(25, 21), Theme.shadow, "\(kind) overran its box")
            pictures.append(canvas.pixels)
        }
        XCTAssertEqual(Set(pictures.map { $0.hashValue }).count, pictures.count,
                       "two gadgets drew the same picture")
    }

    // MARK: - PNG

    func testPNGHasTheRightSignatureAndChunks() {
        var canvas = Canvas(width: 4, height: 4, fill: Theme.accent)
        canvas.set(1, 1, Theme.shadow)
        let data = PNG.encode(canvas)

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertTrue(contains(data, "IHDR"))
        XCTAssertTrue(contains(data, "IDAT"))
        XCTAssertTrue(contains(data, "IEND"))
        // 4×4 RGBA with a filter byte per row, in one stored deflate block.
        XCTAssertGreaterThan(data.count, 4 * 4 * 4)
    }

    private func contains(_ data: Data, _ marker: String) -> Bool {
        data.range(of: Data(marker.utf8)) != nil
    }

    private static let example: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples/Happy Hour.med")
}
