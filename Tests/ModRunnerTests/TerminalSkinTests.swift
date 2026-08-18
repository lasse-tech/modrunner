import XCTest
@testable import ModRunnerKit
@testable import ModRunnerSkin
@testable import ModRunnerWindow

/// The terminal interface, checked without a terminal.
///
/// The same bargain as `SkinTests`: the picture is data before it is anything
/// else, so what a user will see can be asserted on a build server with no tty
/// at all — and the escape sequences and the key parsing can be driven through
/// states a real terminal will not reproduce on demand.
final class TerminalSkinTests: XCTestCase {

    private func screen(tracks: Int = 4, playlist: Int = 3, showTracker: Bool = true) -> PlayerScreen {
        var screen = PlayerScreen()
        screen.moduleTitle = "Happy Hour"
        screen.trackCount = tracks
        screen.meters = Array(repeating: 0.5, count: tracks)
        screen.playlist = (0..<playlist).map { "Module \($0)" }
        screen.currentIndex = 0
        screen.showTracker = showTracker
        screen.status = "MMD0 · 15 blocks"
        return screen
    }

    // MARK: - Layout

    /// The frame has to close on the last row whatever the terminal's height
    /// is, or the picture walks off the bottom and the shell scrolls it.
    func testEveryHeightProducesAClosedFrame() {
        for height in 16...60 {
            for showTracker in [true, false] {
                let canvas = PlayerScreenTextRenderer.render(screen(showTracker: showTracker),
                                                             width: 80, height: height)
                XCTAssertEqual(canvas.height, height, "height \(height)")
                XCTAssertEqual(canvas.cell(0, 0).character, "┌", "height \(height)")
                XCTAssertEqual(canvas.cell(79, 0).character, "┐", "height \(height)")
                XCTAssertEqual(canvas.cell(0, height - 1).character, "└", "height \(height)")
                XCTAssertEqual(canvas.cell(79, height - 1).character, "┘", "height \(height)")
            }
        }
    }

    /// Nothing may be drawn past the right-hand edge: a row wider than the
    /// terminal wraps, and one wrapped row pushes the whole picture up.
    func testNothingIsDrawnOverTheRightHandEdge() {
        for width in [48, 60, 80, 132, 200] {
            let canvas = PlayerScreenTextRenderer.render(screen(tracks: 8), width: width, height: 30)
            XCTAssertEqual(canvas.width, width)
            for y in 0..<canvas.height {
                XCTAssertEqual(canvas.line(y).count, width, "row \(y) at width \(width)")
                XCTAssertEqual(canvas.cell(width - 1, y).character == "│"
                               || canvas.cell(width - 1, y).character == "┐"
                               || canvas.cell(width - 1, y).character == "┘"
                               || canvas.cell(width - 1, y).character == "┤", true,
                               "row \(y) at width \(width) does not end on the frame")
            }
        }
    }

    /// An odd number of pattern rows is what puts the playing line exactly in
    /// the middle; an even one leaves the playhead off by half a row and the
    /// pattern looks like it is scrolling past the wrong place.
    func testTrackerRowCountIsOdd() {
        for height in 20...60 {
            let rows = PlayerScreenTextRenderer.visibleRows(width: 80, height: height,
                                                            channels: 4, playlistCount: 3,
                                                            showTracker: true)
            XCTAssertTrue(rows > 0, "height \(height) has no tracker")
            XCTAssertFalse(rows.isMultiple(of: 2), "height \(height) has \(rows) rows")
        }
    }

    /// The panels come and go with the space on offer, but the transport and
    /// the status line never do — they are how the player is worked.
    func testSmallTerminalsKeepTheTransport() {
        let canvas = PlayerScreenTextRenderer.render(screen(),
                                                     width: PlayerScreenTextRenderer.minimumWidth,
                                                     height: PlayerScreenTextRenderer.minimumHeight)
        XCTAssertTrue(canvas.plainText.contains("|<"))
        XCTAssertTrue(canvas.plainText.contains(">|"))
        XCTAssertTrue(canvas.plainText.contains("MMD0"))
    }

    /// More tracks than fit is a real module on a narrow terminal, and the
    /// voices that were dropped have to be admitted to rather than vanish.
    func testTracksThatDoNotFitAreCountedOut() {
        let canvas = PlayerScreenTextRenderer.render(screen(tracks: 16), width: 60, height: 30)
        XCTAssertTrue(canvas.plainText.contains("+"), "no overflow marker for the tracks left out")
    }

    // MARK: - Drawing

    func testThePlayingLineIsHighlightedAcrossTheWholeRow() {
        var screen = self.screen()
        screen.trackerRows = [
            .init(line: 4, cells: ["C-3 01 0000", "--- .. ....", "--- .. ....", "--- .. ...."]),
            .init(line: 5, cells: ["--- .. ....", "--- .. ....", "--- .. ....", "--- .. ...."],
                  isCurrent: true)
        ]
        let layout = PlayerScreenTextRenderer.layout(width: 80, height: 30, channels: 4,
                                                     playlistCount: 3, showTracker: true)
        let canvas = PlayerScreenTextRenderer.render(screen, layout: layout)
        let row = layout.trackerRule! + 2 + 1        // rule, header, then the second row

        XCTAssertEqual(canvas.cell(2, row).paper, Theme.highlight)
        XCTAssertEqual(canvas.cell(70, row).paper, Theme.highlight, "the highlight stops short")
        XCTAssertEqual(canvas.cell(0, row).character, "│", "the highlight ran over the frame")
    }

    /// Lit and unlit meter cells are two different characters, not two
    /// different backgrounds — so the bar survives a terminal with no colour,
    /// and so a test can see it.
    func testMetersReadWithoutColour() {
        var screen = self.screen()
        screen.meters = [1, 0, 0.5, 0]
        let canvas = PlayerScreenTextRenderer.render(screen, width: 80, height: 30)
        let text = canvas.plainText
        XCTAssertTrue(text.contains("CH1 █"))
        XCTAssertTrue(text.contains("CH2 ░"))
    }

    /// The transport buttons are hit-tested against what the renderer reports,
    /// exactly as in the window — so the two cannot disagree about where the
    /// play button is.
    func testTransportControlsSitUnderTheirLabels() {
        let screen = self.screen()
        let layout = PlayerScreenTextRenderer.layout(width: 80, height: 30, channels: 4,
                                                     playlistCount: 3, showTracker: true)
        let controls = PlayerScreenTextRenderer.controls(for: screen, layout: layout)
        let canvas = PlayerScreenTextRenderer.render(screen, layout: layout)

        guard let play = controls.first(where: { $0.role == .playPause }) else {
            return XCTFail("no play button")
        }
        XCTAssertEqual(play.rect.y, layout.transportRow)
        let label = (play.rect.x..<play.rect.maxX).map { canvas.cell($0, play.rect.y).character }
        XCTAssertEqual(String(label).trimmingCharacters(in: .whitespaces), ">")

        // And the roles are in reading order, left to right.
        let transport = controls.filter { $0.role != .songPosition }
        XCTAssertEqual(transport.map(\.rect.x), transport.map(\.rect.x).sorted())
    }

    // MARK: - Keys

    private func keys(_ bytes: [UInt8], terminal: Terminal = Terminal()) -> [WindowEvent] {
        terminal.events(from: bytes)
    }

    func testArrowKeysAreParsed() {
        XCTAssertEqual(keys(Array("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D".utf8)),
                       [.key(.up), .key(.down), .key(.right), .key(.left)])
    }

    func testOrdinaryKeysAndSpace() {
        XCTAssertEqual(keys(Array("q t ".utf8)),
                       [.key(.character("q")), .key(.space), .key(.character("t")), .key(.space)])
    }

    /// Ctrl-C reaches the program rather than the driver once the terminal is
    /// raw, so it has to mean the same thing as closing the window.
    func testControlCEndsTheSession() {
        XCTAssertEqual(keys([0x03]), [.closed])
    }

    /// The hard case: an arrow key is an escape and then more, and the Escape
    /// key is an escape and then nothing. They are only ever told apart by how
    /// long nothing followed, so a lone escape has to wait one poll and then
    /// count.
    func testALoneEscapeWaitsOnePollAndThenCounts() {
        let terminal = Terminal()
        XCTAssertEqual(terminal.events(from: [0x1B]), [], "escape fired before its sequence could arrive")
        XCTAssertEqual(terminal.events(from: []), [.key(.escape)])
    }

    func testAnArrowKeySplitAcrossTwoReadsIsStillAnArrowKey() {
        let terminal = Terminal()
        XCTAssertEqual(terminal.events(from: [0x1B]), [])
        XCTAssertEqual(terminal.events(from: [0x5B]), [])
        XCTAssertEqual(terminal.events(from: [0x43]), [.key(.right)])
    }

    /// SGR mouse reports are one-based and count the whole screen; the hit
    /// testing is zero-based and counts the same screen.
    func testMouseReportsBecomeClicks() {
        XCTAssertEqual(keys(Array("\u{1B}[<0;10;5M".utf8)), [.mouseDown(x: 9, y: 4)])
        XCTAssertEqual(keys(Array("\u{1B}[<0;10;5m".utf8)), [], "a release is not a click")
    }

    // MARK: - Colour

    func testColourDepthFollowsTheEnvironment() {
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "xterm-256color"],
                                                    isInteractive: true), .truecolour)
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "xterm",
                                                                 "COLORTERM": "truecolor"],
                                                    isInteractive: true), .truecolour)
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "xterm"],
                                                    isInteractive: true), .indexed)
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "dumb"],
                                                    isInteractive: true), .none)
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "xterm-256color",
                                                                 "NO_COLOR": "1"],
                                                    isInteractive: true), .none)
        XCTAssertEqual(Terminal.ColourDepth.detect(environment: ["TERM": "xterm-256color"],
                                                    isInteractive: false), .none)
    }

    func testIndexedColoursLandInTheRightPartOfTheCube() {
        XCTAssertEqual(Terminal.indexed(Colour(0, 0, 0)), 16)
        XCTAssertEqual(Terminal.indexed(Colour(255, 255, 255)), 231)
        // The greys go to the ramp at the end rather than into the cube.
        XCTAssertGreaterThan(Terminal.indexed(Colour(128, 128, 128)), 231)
        XCTAssertEqual(Terminal.indexed(Colour(255, 0, 0)), 196)
    }

    /// Only the rows that changed are written. At fifty frames a second the
    /// difference is not an optimisation, it is whether the picture flickers.
    func testOnlyChangedRowsAreRedrawn() {
        let terminal = Terminal()
        var first = PlayerScreenTextRenderer.render(screen(), width: 80, height: 30)
        _ = terminal.frame(first)

        XCTAssertEqual(terminal.frame(first).filter { $0 == "\u{1B}" }.count, 1,
                       "an unchanged picture was redrawn")

        first.set(4, 4, TextCell(character: "X"))
        let second = terminal.frame(first)
        XCTAssertTrue(second.contains("\u{1B}[5;1H"), "the changed row was not addressed")
        XCTAssertFalse(second.contains("\u{1B}[6;1H"), "an unchanged row was redrawn")
    }

    /// A resize cannot be patched into the old picture — the whole screen has
    /// to be cleared first, or the remains of the wider frame stay on it.
    func testResizingClearsTheScreen() {
        let terminal = Terminal()
        _ = terminal.frame(PlayerScreenTextRenderer.render(screen(), width: 80, height: 30))
        let resized = terminal.frame(PlayerScreenTextRenderer.render(screen(), width: 60, height: 24))
        XCTAssertTrue(resized.contains("\u{1B}[2J"))
    }
}
