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
        var canvas = Canvas(width: 8, height: 8, fill: Workbench.black)
        canvas.fill(Rect(-10, -10, 4, 4), Workbench.white)
        canvas.fill(Rect(6, 6, 100, 100), Workbench.white)
        canvas.set(-1, -1, Workbench.blue)
        canvas.set(1_000, 1_000, Workbench.blue)

        XCTAssertEqual(canvas.pixel(0, 0), Workbench.black)
        XCTAssertEqual(canvas.pixel(7, 7), Workbench.white)
    }

    /// Intuition's rule: light on top and left, dark on bottom and right, and
    /// the other way round for a recess. Getting this backwards is the single
    /// most visible way to draw a Workbench interface wrong.
    func testBevelsFaceTheRightWay() {
        var canvas = Canvas(width: 20, height: 20)
        canvas.bevel(Rect(0, 0, 20, 20), .raised)
        XCTAssertEqual(canvas.pixel(10, 0), Workbench.white)
        XCTAssertEqual(canvas.pixel(0, 10), Workbench.white)
        XCTAssertEqual(canvas.pixel(10, 19), Workbench.black)
        XCTAssertEqual(canvas.pixel(19, 10), Workbench.black)

        canvas.bevel(Rect(0, 0, 20, 20), .recessed)
        XCTAssertEqual(canvas.pixel(10, 0), Workbench.black)
        XCTAssertEqual(canvas.pixel(10, 19), Workbench.white)
    }

    func testMeterFillsToTheRightEdge() {
        var canvas = Canvas(width: 100, height: 12)
        canvas.meter(Rect(0, 0, 100, 12), level: 1)
        // Every cell lit means the far end is lit too, not left over as
        // background because the cell width did not divide evenly.
        XCTAssertEqual(canvas.pixel(96, 6), Workbench.blue)
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
        var canvas = Canvas(width: 40, height: 16, fill: Workbench.grey)
        canvas.text("I", at: 0, 0, Workbench.black)
        // The I is a five-pixel bar across the top row of its cell.
        XCTAssertEqual(canvas.pixel(1, 0), Workbench.black)
        XCTAssertEqual(canvas.pixel(0, 0), Workbench.grey)
        // Nothing spills into the next cell.
        XCTAssertEqual(canvas.pixel(8, 0), Workbench.grey)
    }

    func testTextIsClippedToItsWidth() {
        var canvas = Canvas(width: 64, height: 16, fill: Workbench.grey)
        canvas.text("IIIIIIII", at: 0, 0, Workbench.black, maxWidth: 16)
        XCTAssertEqual(canvas.pixel(1, 0), Workbench.black)
        XCTAssertEqual(canvas.pixel(17, 0), Workbench.grey, "text ran past its width")
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
        try writeIfAsked(canvas, "workbench.png")

        XCTAssertEqual(canvas.width, PlayerScreenRenderer.width)
        XCTAssertGreaterThan(canvas.height, 400)

        // The title bar is the Workbench blue, and the window is not blank.
        XCTAssertEqual(canvas.pixel(280, 10), Workbench.blue)
        let distinct = Set(canvas.pixels)
        XCTAssertGreaterThan(distinct.count, 4, "the window rendered as a flat fill")
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
        try writeIfAsked(canvas, "workbench-empty.png")
        XCTAssertEqual(canvas.width, PlayerScreenRenderer.width)
    }

    // MARK: - PNG

    func testPNGHasTheRightSignatureAndChunks() {
        var canvas = Canvas(width: 4, height: 4, fill: Workbench.salmon)
        canvas.set(1, 1, Workbench.black)
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
