import AppKit
import SwiftUI
import ModRunnerKit

/// Keys the stage answers to. The window turns key codes into these so the view
/// does not have to know anything about AppKit events.
enum StageKey {
    case dismiss
    case playPause
    case nextPosition
    case previousPosition
    case nextModule
    case previousModule
}

extension StageKey {
    /// The keys the stage listens for, by virtual key code.
    static func forKeyCode(_ code: UInt16) -> StageKey? {
        switch code {
        case 53, 12: return .dismiss          // esc, Q
        case 49:     return .playPause        // space
        case 123:    return .previousPosition // left
        case 124:    return .nextPosition     // right
        case 126:    return .previousModule   // up
        case 125:    return .nextModule       // down
        default:     return nil
        }
    }
}

/// A borderless window filling one screen. Deliberately not macOS's own
/// full-screen mode: the player window is a fixed size with hand-drawn chrome,
/// and letting AppKit resize it into a full-screen space fights every
/// assumption `WindowChrome` makes.
final class StageWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows and hides the stage. Owns the window, so nothing else in the app has
/// to keep track of whether it is up.
@MainActor
final class StageController {

    static let shared = StageController()

    private var window: StageWindow?
    private var restoreOptions: NSApplication.PresentationOptions?
    /// The hosting view answers key events before the window ever sees them, so
    /// the stage listens in front of the responder chain instead of behind it.
    private var keyMonitor: Any?

    var isPresented: Bool { window != nil }

    func toggle() {
        if isPresented { dismiss() } else { present() }
    }

    func present() {
        guard window == nil else { return }
        // The mini player and the stage are two answers to the same question,
        // so opening one puts the other away.
        MiniPlayerController.shared.dismiss()
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let window = StageWindow(contentRect: screen.frame,
                                 styleMask: .borderless,
                                 backing: .buffered,
                                 defer: false)
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedRed: 0x60 / 255, green: 0x60 / 255,
                                         blue: 0x60 / 255, alpha: 1)
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        window.isMovable = false

        let hosting = NSHostingView(
            rootView: StageView(model: .shared, onDismiss: { [weak self] in self?.dismiss() })
                .ignoresSafeArea()
        )
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        // The dock and menu bar have to go together; AppKit rejects hiding the
        // menu bar on its own.
        restoreOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented, let key = StageKey.forKeyCode(event.keyCode) else {
                return event
            }
            self.handle(key)
            return nil      // swallowed, so the beep does not follow
        }
    }

    func dismiss() {
        guard let window else { return }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSApp.presentationOptions = restoreOptions ?? []
        restoreOptions = nil
        window.orderOut(nil)
        self.window = nil

        // Hand focus back to the player window rather than to whatever else
        // happens to be behind us.
        NSApp.windows.first { $0 is ModRunnerWindow }?.makeKeyAndOrderFront(nil)
    }

    private func handle(_ key: StageKey) {
        let model = PlayerModel.shared
        switch key {
        case .dismiss:          dismiss()
        case .playPause:        model.togglePlay()
        case .nextPosition:     model.nextPosition()
        case .previousPosition: model.previousPosition()
        case .nextModule:       model.playNext()
        case .previousModule:   model.playPrevious()
        }
    }
}
