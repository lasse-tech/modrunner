import AppKit

/// Window sizing and decoration, driven from the app delegate rather than from
/// SwiftUI.
///
/// This used to be an NSViewRepresentable sitting behind the skin switch. That
/// was unreliable: switching skins rebuilt the representable, and the `window`
/// property is still nil inside `makeNSView`, so the resize silently never ran.
/// The window then kept the previous skin's size, which pushed the Workbench
/// title bar out of view. Owning the window directly removes the guesswork.
/// A window that can take focus even without a title bar.
///
/// The Workbench skin runs without `.titled`, and AppKit refuses key and main
/// status to such windows unless they say otherwise.
final class ModRunnerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum WindowChrome {

    /// Dresses the window for a skin. The Workbench skin draws its own title bar
    /// and gadgets, so the system chrome is hidden for it; the native skin uses
    /// the real thing.
    static func dress(_ window: NSWindow, for skin: Skin) {
        switch skin {
        case .amiga:
            // Dropping .titled is the point. With a titled window, AppKit's
            // NSTitlebarContainerView is layered above the content view and
            // covers the drawn Workbench title bar — titlebarAppearsTransparent
            // no longer prevents that. Without .titled there is no container at
            // all, so the drawn bar is visible and clickable. .closable and
            // .miniaturizable stay so the gadgets can still act on the window.
            window.styleMask = [.closable, .miniaturizable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(
                calibratedRed: 0x95 / 255, green: 0x95 / 255, blue: 0x95 / 255, alpha: 1
            )

        case .native:
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.styleMask.remove(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.backgroundColor = .windowBackgroundColor
            window.title = "ModRunner"
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            // Each skin has one fixed size, so zoom stays inert.
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }

    /// True when AppKit still has a title bar layered over the content.
    static func hasSystemTitlebar(_ window: NSWindow) -> Bool {
        guard let frameView = window.contentView?.superview else { return false }
        return frameView.subviews.contains {
            String(describing: type(of: $0)).contains("TitlebarContainer")
        }
    }

    /// Resizes the window, anchoring the top-left corner. AppKit anchors a
    /// resize to the bottom-left, which would make the title bar jump every
    /// time a panel is toggled or the skin changes.
    static func resize(_ window: NSWindow, to size: CGSize) {
        // frameRect(forContentRect:) is read against the *current* style mask,
        // so this has to run after dress() has settled it.
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

    /// Dress and size for the state currently stored in defaults. Deliberately
    /// does *not* touch the origin: this runs on every defaults change, and
    /// moving the window here would fight with the saved position.
    static func apply(to window: NSWindow) {
        dress(window, for: Skin.current)
        resize(window, to: RootView.initialSize())
    }

    /// As `apply`, plus the position remembered for the skin being switched to.
    static func applySkinChange(to window: NSWindow) {
        apply(to: window)
        restoreOrigin(of: window, for: Skin.current)
    }

    // MARK: - Remembered position

    /// The position is stored per skin, because the two have different sizes
    /// and a shared origin would put one of them somewhere unexpected.
    private static func originKey(for skin: Skin) -> String {
        "windowOrigin.\(skin.rawValue)"
    }

    static func saveOrigin(of window: NSWindow, for skin: Skin) {
        let origin = window.frame.origin
        UserDefaults.standard.set(["x": origin.x, "y": origin.y],
                                  forKey: originKey(for: skin))
    }

    /// Restores the stored top-left corner, if it still lands on a screen that
    /// exists — displays get unplugged, and a window off-screen is a window the
    /// user cannot reach.
    static func restoreOrigin(of window: NSWindow, for skin: Skin) {
        guard let stored = UserDefaults.standard.dictionary(forKey: originKey(for: skin)),
              let x = stored["x"] as? Double, let y = stored["y"] as? Double else {
            window.center()
            return
        }

        var frame = window.frame
        frame.origin = CGPoint(x: x, y: y)

        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if visible {
            window.setFrameOrigin(frame.origin)
        } else {
            window.center()
        }
    }
}
