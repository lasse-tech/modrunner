import AppKit
import ModRunnerKit

/// What a key press does to playback.
///
/// The arrows are the transport: on their own they step through the song, with
/// Shift they step through the playlist. That is the same pair of gestures the
/// buttons offer, and the same one the stage answered to back when it was the
/// only place in the app where the keyboard worked at all.
enum PlayerKey: Equatable {
    /// Play or pause, whichever the player is not doing.
    case playPause
    /// One song position back — the `<<` button.
    case rewind
    /// One song position on — the `>>` button.
    case forward
    /// The previous module in the list.
    case previousModule
    /// The next module in the list.
    case nextModule
    /// Leave the full-screen stage. Only ever acted on while it is up.
    case dismissStage

    /// The virtual key codes, as AppKit reports them.
    private enum Code {
        static let q: UInt16 = 12
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    /// Kept apart from the event so the mapping can be read — and tested —
    /// without an NSEvent to hand.
    static func forKey(code: UInt16, modifiers: NSEvent.ModifierFlags) -> PlayerKey? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        // Command belongs to the menu, and Control and Option to nobody here; a
        // shortcut that fires on any modifier combination is a shortcut that
        // fires by accident.
        guard !flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return nil }

        // Shift rather than Control for the playlist step: macOS keeps
        // Control-Left and Control-Right for itself — they move between Spaces,
        // and the system takes them before any app is asked.
        let shift = flags.contains(.shift)

        switch code {
        case Code.space:  return .playPause
        case Code.left:   return shift ? .previousModule : .rewind
        case Code.right:  return shift ? .nextModule : .forward
        // The stage has always taken the vertical arrows for the playlist, and
        // they cost nothing to keep.
        case Code.up:     return .previousModule
        case Code.down:   return .nextModule
        case Code.escape, Code.q: return .dismissStage
        default:          return nil
        }
    }
}

/// The keyboard, for the whole app rather than for one window.
///
/// A local event monitor rather than the responder chain: the SwiftUI hosting
/// view answers key events before the window ever sees them, so anything hung
/// behind it never runs. The monitor sits in front of the whole dispatch, which
/// is also what lets the keys be swallowed — an unhandled key press beeps.
@MainActor
enum Keyboard {

    private static var monitor: Any?

    static func start() {
        guard monitor == nil else { return }
        // The event itself does not cross into the actor — an NSEvent is not
        // Sendable — only the two values the mapping reads off it.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated { handle(code: code, modifiers: modifiers) }
            return handled ? nil : event     // swallowed, so the beep does not follow
        }
    }

    /// True when the key was ours and has been acted on.
    private static func handle(code: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Only our own windows. An open panel or a sheet is a window of its own
        // and is entitled to every key it is given.
        let window = NSApp.keyWindow
        guard window is ModRunnerWindow || window is StageWindow else { return false }

        guard let key = PlayerKey.forKey(code: code, modifiers: modifiers) else { return false }

        let model = PlayerModel.shared
        switch key {
        case .playPause:       model.togglePlay()
        case .rewind:          model.previousPosition()
        case .forward:         model.nextPosition()
        case .previousModule:  model.playPrevious()
        case .nextModule:      model.playNext()
        case .dismissStage:
            // Esc closes the About panel, and Q is a letter. Neither is ours
            // unless the stage is up, so both go on their way if it is not.
            guard StageController.shared.isPresented else { return false }
            StageController.shared.dismiss()
        }
        return true
    }
}
