import AppKit
import SwiftUI
import ModRunnerKit

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
        // The keys are `Keyboard`'s, for every window in the app; the stage only
        // adds Esc to what they already do.
    }

    func dismiss() {
        guard let window else { return }
        NSApp.presentationOptions = restoreOptions ?? []
        restoreOptions = nil
        window.orderOut(nil)
        self.window = nil

        // Hand focus back to the player window rather than to whatever else
        // happens to be behind us.
        NSApp.windows.first { $0 is ModRunnerWindow }?.makeKeyAndOrderFront(nil)
    }
}
