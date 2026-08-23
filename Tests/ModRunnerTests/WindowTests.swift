import XCTest
@testable import ModRunnerSkin
@testable import ModRunnerWindow

/// The window layer, on whichever platform is running the suite.
///
/// The X11 case is the one that matters: Xlib is opened by name at run time and
/// its structures are read by byte offset, so nothing about it is checked by
/// the compiler. CI runs this against a virtual framebuffer, opens a real
/// window, draws into it and reads the pixels back off the X server — which is
/// the only way to know that the offsets are right.
final class WindowTests: XCTestCase {

    func testAvailabilityMatchesThePlatform() {
        #if os(Linux) || os(Windows)
        XCTAssertTrue(Window.isAvailable)
        #else
        XCTAssertFalse(Window.isAvailable, "macOS has an app; the window layer is for the others")
        #endif
    }

    func testMacOSSaysSoRatherThanPretending() throws {
        #if os(macOS)
        XCTAssertThrowsError(try Window.open(title: "t", width: 64, height: 64)) { error in
            guard case .noBackend? = error as? WindowError else {
                return XCTFail("expected noBackend, got \(error)")
            }
        }
        #else
        throw XCTSkip("not macOS")
        #endif
    }

    /// Opens a window, paints a known pattern and asks the X server what it
    /// actually holds. A wrong byte offset in the event or image structures
    /// shows up here as the wrong colour rather than as a crash months later.
    func testX11ShowsWhatWasDrawn() throws {
        #if os(Linux)
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil else {
            throw XCTSkip("no DISPLAY; run under xvfb-run to exercise this")
        }

        let window = try X11Window(title: "ModRunner test", width: 64, height: 32)
        defer { window.close() }

        var canvas = Canvas(width: 64, height: 32, fill: Theme.face)
        canvas.fill(Rect(0, 0, 32, 32), Theme.highlight)
        canvas.set(40, 8, Theme.accent)
        try window.present(canvas)

        guard let readBack = window.readBack() else {
            return XCTFail("the server returned no image")
        }
        XCTAssertEqual(readBack.width, 64)
        XCTAssertEqual(readBack.pixel(10, 10), Theme.highlight, "the left half is not the highlight colour")
        XCTAssertEqual(readBack.pixel(50, 10), Theme.face, "the right half is not the panel face")
        XCTAssertEqual(readBack.pixel(40, 8), Theme.accent, "a single pixel went astray")
        #else
        throw XCTSkip("not Linux")
        #endif
    }

    func testX11PollsWithoutBlocking() throws {
        #if os(Linux)
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil else {
            throw XCTSkip("no DISPLAY; run under xvfb-run to exercise this")
        }
        let window = try X11Window(title: "ModRunner test", width: 32, height: 32)
        defer { window.close() }

        // Nothing has happened to the window, so this has to come straight
        // back. XNextEvent would sit there for ever, which is why the queue is
        // checked with XPending first.
        _ = window.poll()
        #else
        throw XCTSkip("not Linux")
        #endif
    }

    /// Windows build servers run without an interactive desktop, so a window
    /// may not open at all. Either answer is fine; a crash is not.
    func testWin32OpensOrRefuses() throws {
        #if os(Windows)
        do {
            let window = try Window.open(title: "ModRunner test", width: 64, height: 32)
            defer { window.close() }
            var canvas = Canvas(width: 64, height: 32, fill: Theme.highlight)
            canvas.set(1, 1, Theme.shine)
            try window.present(canvas)
            _ = window.poll()
        } catch let error as WindowError {
            XCTAssertNotNil(error.errorDescription)
        }
        #else
        throw XCTSkip("not Windows")
        #endif
    }

    /// Every gadget in the VIEW row has to be reported as a control.
    ///
    /// LED and Load were drawn by the renderer and absent from the hit testing,
    /// because each carried its own copy of the layout and only one of them was
    /// ever updated. They looked like buttons and did nothing. Both now come
    /// from `viewGadgets`, and this is what keeps them from parting again.
    ///
    /// The expected set is read out of `viewGadgets` rather than written down
    /// here, so a gadget added there is covered by this without being named a
    /// second time — which is the same drift, one layer up.
    func testEveryViewGadgetIsClickable() {
        var screen = PlayerScreen()
        screen.playlist = ["one"]

        // Only to enumerate them: which gadgets there are and what they are
        // called does not depend on the rectangle, and the real one belongs to
        // a layout that is private to the renderer.
        let gadgets = PlayerScreenRenderer.viewGadgets(for: screen, in: Rect(0, 0, 544, 30))
        XCTAssertFalse(gadgets.isEmpty, "the VIEW row is drawn with gadgets in it")

        let canvas = PlayerScreenRenderer.render(screen)
        let controls = PlayerScreenRenderer.controls(for: screen)
        for gadget in gadgets {
            guard let control = controls.first(where: { $0.role == gadget.role }) else {
                XCTFail("\(gadget.label) is drawn in the VIEW row but cannot be clicked")
                continue
            }
            // And reported where it was drawn: the raised edge of a button,
            // not the panel behind it.
            XCTAssertEqual(canvas.pixel(control.rect.x + 1, control.rect.y + 1), Theme.shine,
                           "\(gadget.label) is reported somewhere other than where it is drawn")
        }
    }

    /// The renderer reports where it drew the controls, and the window layer
    /// hit-tests against that. If the two disagree the buttons stop working,
    /// so the report itself is worth checking: the play button has to be under
    /// the pixels that show a play button.
    func testControlsSitInsideTheWindow() {
        // All three shapes: the strip and the stage have their own widths, and
        // a control reported outside the canvas is a button drawn where nobody
        // can reach it.
        for layout in PlayerScreen.Layout.allCases {
            var screen = PlayerScreen()
            screen.playlist = ["one", "two"]
            screen.layout = layout
            screen.stageWidth = 1280
            screen.stageHeight = 720

            let controls = PlayerScreenRenderer.controls(for: screen)
            let width = PlayerScreenRenderer.width(for: screen)
            let height = PlayerScreenRenderer.height(for: screen)
            let canvas = PlayerScreenRenderer.render(screen)
            XCTAssertEqual(canvas.width, width, "\(layout) draws a canvas of another width")
            XCTAssertEqual(canvas.height, height, "\(layout) draws a canvas of another height")

            XCTAssertFalse(controls.isEmpty)
            for control in controls {
                XCTAssertGreaterThanOrEqual(control.rect.x, 0)
                XCTAssertGreaterThanOrEqual(control.rect.y, 0)
                XCTAssertLessThanOrEqual(control.rect.maxX, width, "\(layout): off the right")
                XCTAssertLessThanOrEqual(control.rect.maxY, height, "\(layout): off the bottom")
            }
        }

        // The play button is the third of the six transport buttons, and the
        // canvas under it must not be the window background — that would mean
        // the hit box and the drawing had parted company.
        var screen = PlayerScreen()
        screen.playlist = ["one", "two"]
        let controls = PlayerScreenRenderer.controls(for: screen)
        let canvas = PlayerScreenRenderer.render(screen)
        guard let play = controls.first(where: {
            if case .playPause = $0.role { return true } else { return false }
        }) else { return XCTFail("no play button was reported") }
        XCTAssertEqual(canvas.pixel(play.rect.x + 1, play.rect.y + 1), Theme.shine,
                       "the play button's raised edge is not where it was said to be")
    }

    /// The menu is a drag from the title strip down into the items, and the
    /// only thing standing between a press and the right action is that the
    /// rectangles agree with the drawing. They are checked here rather than
    /// through a window, because a menu is the same shape on every platform.
    func testMenuDropsItsItemsInsideTheCanvas() {
        var screen = PlayerScreen()
        screen.playlist = ["one"]
        let headings = PlayerScreenRenderer.menu(for: screen)
        XCTAssertFalse(headings.isEmpty)

        for index in headings.indices {
            let box = PlayerScreenRenderer.menuBox(forHeading: index, in: screen)
            XCTAssertGreaterThanOrEqual(box.x, 0, "a menu hangs off the left edge")
            XCTAssertLessThanOrEqual(box.maxX, PlayerScreenRenderer.width,
                                     "a menu hangs off the right edge")
            XCTAssertEqual(PlayerScreenRenderer.menuEntryRects(forHeading: index, in: screen).count,
                           headings[index].entries.count)
        }
    }

    /// Crossing a title opens it, moving into an item picks it, and letting go
    /// of the items leaves the title open — the pointer is still under a held
    /// button, so closing everything would be the one thing it cannot mean.
    func testMenuTrackingFollowsThePointer() {
        var screen = PlayerScreen()
        screen.playlist = ["one"]

        let title = PlayerScreenRenderer.menuHeadingRects(for: screen)[1]
        let opened = PlayerScreenRenderer.menuSelection(at: title.x + 2, y: 2,
                                                        current: .init(), in: screen)
        XCTAssertEqual(opened.heading, 1)
        XCTAssertNil(opened.entry, "a title on its own picks nothing")

        let second = PlayerScreenRenderer.menuEntryRects(forHeading: 1, in: screen)[1]
        let picked = PlayerScreenRenderer.menuSelection(at: second.x + 2, y: second.y + 2,
                                                        current: opened, in: screen)
        XCTAssertEqual(picked.heading, 1)
        XCTAssertEqual(picked.entry, 1)

        let wandered = PlayerScreenRenderer.menuSelection(at: PlayerScreenRenderer.width - 1,
                                                          y: second.maxY + 200,
                                                          current: picked, in: screen)
        XCTAssertEqual(wandered.heading, 1, "the open menu should stay open")
        XCTAssertNil(wandered.entry, "nothing is under the pointer any more")
    }

    /// The tick is the only thing that says whether the tracker is showing, so
    /// it has to follow the screen rather than being drawn once and forgotten.
    func testMenuTickFollowsTheTrackerSetting() {
        var screen = PlayerScreen()
        screen.showTracker = true
        var entry = PlayerScreenRenderer.menu(for: screen)
            .flatMap(\.entries).first { if case .showTracker = $0.role { return true } else { return false } }
        XCTAssertEqual(entry?.checked, true)

        screen.showTracker = false
        entry = PlayerScreenRenderer.menu(for: screen)
            .flatMap(\.entries).first { if case .showTracker = $0.role { return true } else { return false } }
        XCTAssertEqual(entry?.checked, false)
    }
}
