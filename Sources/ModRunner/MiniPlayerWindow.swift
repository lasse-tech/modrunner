import AppKit
import SwiftUI
import ModRunnerKit

/// Shows and hides the mini player. While it is up the main window is put away:
/// the point of the strip is that it is the only thing ModRunner has on screen.
@MainActor
final class MiniPlayerController {

    static let shared = MiniPlayerController()

    private var window: NSWindow?
    private static let originKey = "windowOrigin.mini"

    var isPresented: Bool { window != nil }

    func toggle() {
        if isPresented { dismiss() } else { present() }
    }

    func present() {
        guard window == nil else { return }
        StageController.shared.dismiss()

        let size = NSSize(width: MiniPlayerView.width, height: MiniPlayerView.height)
        let window = ModRunnerWindow(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
        // The view paints its own ground — grey panel in the Workbench skin, a
        // rounded card in the native one — so the window itself stays clear.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // A player you keep in a corner while working is only useful if it stays
        // on top of whatever you are working in.
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(
            rootView: MiniPlayerView(model: .shared, onExpand: { [weak self] in self?.dismiss() })
                .ignoresSafeArea()
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        placeInCorner(window)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        mainWindow?.orderOut(nil)
    }

    func dismiss() {
        guard let window else { return }
        saveOrigin(of: window)
        window.orderOut(nil)
        self.window = nil

        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0 is ModRunnerWindow && $0 !== window }
    }

    // MARK: - Position

    /// Restores where the strip was last left, and otherwise puts it in the
    /// top-right corner of the screen the player is on — out of the way, which
    /// is the whole point.
    private func placeInCorner(_ window: NSWindow) {
        let screen = mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        if let stored = UserDefaults.standard.dictionary(forKey: Self.originKey),
           let x = stored["x"] as? Double, let y = stored["y"] as? Double {
            var frame = window.frame
            frame.origin = CGPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                window.setFrameOrigin(frame.origin)
                return
            }
        }

        let visible = screen.visibleFrame
        window.setFrameOrigin(CGPoint(x: visible.maxX - window.frame.width - 20,
                                      y: visible.maxY - window.frame.height - 20))
    }

    private func saveOrigin(of window: NSWindow) {
        let origin = window.frame.origin
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: Self.originKey)
    }
}
