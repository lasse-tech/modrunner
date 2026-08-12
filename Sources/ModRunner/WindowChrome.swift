import AppKit

/// Window sizing and decoration, driven from the app delegate rather than from
/// SwiftUI.
///
/// This used to be an NSViewRepresentable sitting behind the skin switch. That
/// was unreliable: switching skins rebuilt the representable, and the `window`
/// property is still nil inside `makeNSView`, so the resize silently never ran.
/// The window then kept the previous skin's size, which pushed the Workbench
/// title bar out of view. Owning the window directly removes the guesswork.
enum WindowChrome {

    /// Dresses the window for a skin. The Workbench skin draws its own title bar
    /// and gadgets, so the system chrome is hidden for it; the native skin uses
    /// the real thing.
    static func dress(_ window: NSWindow, for skin: Skin) {
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
            // Each skin has one fixed size, so zoom stays inert.
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }

    /// Resizes the window, anchoring the top-left corner. AppKit anchors a
    /// resize to the bottom-left, which would make the title bar jump every
    /// time a panel is toggled or the skin changes.
    static func resize(_ window: NSWindow, to size: CGSize) {
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let current = window.frame
        guard abs(current.height - target.height) > 0.5
                || abs(current.width - target.width) > 0.5 else { return }

        let top = current.maxY
        window.setFrame(NSRect(x: current.minX,
                               y: top - target.height,
                               width: target.width,
                               height: target.height),
                        display: true, animate: false)
    }

    /// Applies both, for the skin and panel state currently stored in defaults.
    static func apply(to window: NSWindow) {
        let skin = Skin.current
        dress(window, for: skin)
        resize(window, to: RootView.initialSize())
    }
}
