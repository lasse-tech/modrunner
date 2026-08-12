import XCTest
@testable import ModRunnerKit

/// Exercises the output backends as far as a machine without speakers allows.
///
/// A build server has no audio device, so none of this can assert that sound
/// came out — that check is `MODRUNNER_AUDIO_BACKEND=miniaudio` against a real
/// module on a real machine. What it can assert is that the path runs at all:
/// that the backend is compiled in, that starting it either works or fails with
/// something a person can read, and that stopping it afterwards is safe either
/// way. Without this, a backend could be broken on the platforms that depend on
/// it and CI would still be green, having only ever compiled it.
final class AudioBackendTests: XCTestCase {

    func testABackendIsAvailable() {
        XCTAssertFalse(AudioOutput.availableBackends.isEmpty,
                       "this build has no audio backend at all")
    }

    func testAppleBuildsPreferAVFoundation() throws {
        #if canImport(AVFoundation)
        XCTAssertEqual(AudioOutput.availableBackends.first, "avfoundation")
        #else
        throw XCTSkip("not an Apple platform")
        #endif
    }

    func testMiniaudioIsCompiledInEverywhere() {
        XCTAssertTrue(AudioOutput.availableBackends.contains("miniaudio"),
                      "miniaudio is what Linux and Windows play through; "
                      + "it is built on every platform so it can be tested on any of them")
    }

    /// Starting and stopping the backend Linux and Windows depend on, wherever
    /// this happens to run. A server with no device makes `start` throw, which
    /// is a pass: the failure is reported rather than crashing the process.
    func testMiniaudioStartsOrFailsCleanly() throws {
        let output = AudioOutput(replayer: Replayer(), preferring: "miniaudio")
        XCTAssertEqual(AudioOutput.activeBackend, "miniaudio")

        do {
            try output.start()
            XCTAssertTrue(output.isRunning)
        } catch {
            XCTAssertFalse(output.isRunning)
            XCTAssertFalse(error.localizedDescription.isEmpty,
                           "a device failure has to say something")
        }

        // Safe whether it started or not, and safe twice.
        output.stop()
        output.stop()
        XCTAssertFalse(output.isRunning)
    }
}
