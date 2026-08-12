import SwiftUI
import AppKit

/// Keeps the window's size and chrome in step with the content.
///
/// Two jobs. It resizes the window when the desired size changes, anchoring the
/// top-left corner — AppKit anchors a resize to the bottom-left, which would
/// make the title bar jump every time a panel is toggled. And it dresses the
/// window for the current skin: the Workbench skin draws its own title bar and
/// hides the system one, the native skin uses the real thing.
struct WindowConfigurator: NSViewRepresentable {

    let size: CGSize
    let skin: Skin

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        dress(window)
        resize(window)
    }

    private func dress(_ window: NSWindow) {
        switch skin {
        case .amiga:
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(
                calibratedRed: 0x95 / 255, green: 0x95 / 255, blue: 0x95 / 255, alpha: 1
            )
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }

        case .native:
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.styleMask.remove(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.backgroundColor = .windowBackgroundColor
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            // The window has one fixed size per skin, so zoom stays inert.
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }

    private func resize(_ window: NSWindow) {
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let current = window.frame
        guard abs(current.height - target.height) > 0.5
                || abs(current.width - target.width) > 0.5 else { return }

        let top = current.maxY
        let frame = NSRect(x: current.minX,
                           y: top - target.height,
                           width: target.width,
                           height: target.height)
        window.setFrame(frame, display: true, animate: false)
    }
}
