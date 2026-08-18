// The keyboard lives in the app target, which only exists on macOS.
#if os(macOS)
import XCTest
import AppKit
@testable import ModRunnerApp

/// The transport keys. The mapping is the whole of the feature — everything
/// after it is a call on the model — so it is worth pinning down, particularly
/// the modifier rules, which are the part a later change is most likely to get
/// wrong.
final class KeyboardTests: XCTestCase {

    private enum Key {
        static let q: UInt16 = 12
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    private func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> PlayerKey? {
        PlayerKey.forKey(code: code, modifiers: modifiers)
    }

    func testBareKeysAreTheTransport() {
        XCTAssertEqual(key(Key.space), .playPause)
        XCTAssertEqual(key(Key.left), .rewind)
        XCTAssertEqual(key(Key.right), .forward)
    }

    /// Shift rather than Control, which macOS keeps for switching Spaces: an
    /// app never sees Control-Left or Control-Right while that is on.
    func testShiftArrowsStepThroughThePlaylist() {
        XCTAssertEqual(key(Key.left, .shift), .previousModule)
        XCTAssertEqual(key(Key.right, .shift), .nextModule)
    }

    func testVerticalArrowsAlsoStepThroughThePlaylist() {
        XCTAssertEqual(key(Key.up), .previousModule)
        XCTAssertEqual(key(Key.down), .nextModule)
    }

    func testEscapeAndQLeaveTheStage() {
        XCTAssertEqual(key(Key.escape), .dismissStage)
        XCTAssertEqual(key(Key.q), .dismissStage)
    }

    /// Command belongs to the menu: Cmd-Q has to quit rather than leave the
    /// stage, and Cmd-← has to reach whatever else wants it.
    /// Command belongs to the menu, and Control and Option to nobody here.
    func testTheOtherModifiersAreLeftAlone() {
        XCTAssertNil(key(Key.q, .command))
        XCTAssertNil(key(Key.left, .command))
        XCTAssertNil(key(Key.space, .command))
        XCTAssertNil(key(Key.left, .control))
        XCTAssertNil(key(Key.right, .option))
        XCTAssertNil(key(Key.left, [.shift, .control]))
    }

    /// Shift only means anything on the horizontal arrows.
    func testShiftDoesNothingToTheOtherKeys() {
        XCTAssertEqual(key(Key.space, .shift), .playPause)
        XCTAssertEqual(key(Key.up, .shift), .previousModule)
        XCTAssertEqual(key(Key.escape, .shift), .dismissStage)
    }

    func testCapsLockDoesNotChangeTheMeaning() {
        XCTAssertEqual(key(Key.left, [.shift, .capsLock]), .previousModule)
    }

    func testUnknownKeysAreNotOurs() {
        XCTAssertNil(key(0))        // A
        XCTAssertNil(key(36))       // Return
    }
}
#endif
