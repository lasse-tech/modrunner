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

        var canvas = Canvas(width: 64, height: 32, fill: Workbench.grey)
        canvas.fill(Rect(0, 0, 32, 32), Workbench.blue)
        canvas.set(40, 8, Workbench.salmon)
        try window.present(canvas)

        guard let readBack = window.readBack() else {
            return XCTFail("the server returned no image")
        }
        XCTAssertEqual(readBack.width, 64)
        XCTAssertEqual(readBack.pixel(10, 10), Workbench.blue, "the left half should be blue")
        XCTAssertEqual(readBack.pixel(50, 10), Workbench.grey, "the right half should be grey")
        XCTAssertEqual(readBack.pixel(40, 8), Workbench.salmon, "a single pixel went astray")
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
            var canvas = Canvas(width: 64, height: 32, fill: Workbench.blue)
            canvas.set(1, 1, Workbench.white)
            try window.present(canvas)
            _ = window.poll()
        } catch let error as WindowError {
            XCTAssertNotNil(error.errorDescription)
        }
        #else
        throw XCTSkip("not Windows")
        #endif
    }

    /// The renderer reports where it drew the controls, and the window layer
    /// hit-tests against that. If the two disagree the buttons stop working,
    /// so the report itself is worth checking: the play button has to be under
    /// the pixels that show a play button.
    func testControlsSitInsideTheWindow() {
        var screen = PlayerScreen()
        screen.playlist = ["one", "two"]
        let controls = PlayerScreenRenderer.controls(for: screen)
        let height = PlayerScreenRenderer.height(for: screen)

        XCTAssertFalse(controls.isEmpty)
        for control in controls {
            XCTAssertGreaterThanOrEqual(control.rect.x, 0)
            XCTAssertGreaterThanOrEqual(control.rect.y, 0)
            XCTAssertLessThanOrEqual(control.rect.maxX, PlayerScreenRenderer.width)
            XCTAssertLessThanOrEqual(control.rect.maxY, height, "a control is off the bottom")
        }

        // The play button is the third of the six transport buttons, and the
        // canvas under it must not be the window background — that would mean
        // the hit box and the drawing had parted company.
        let canvas = PlayerScreenRenderer.render(screen)
        guard let play = controls.first(where: {
            if case .playPause = $0.role { return true } else { return false }
        }) else { return XCTFail("no play button was reported") }
        XCTAssertEqual(canvas.pixel(play.rect.x + 1, play.rect.y + 1), Workbench.white,
                       "the play button's raised edge is not where it was said to be")
    }
}
