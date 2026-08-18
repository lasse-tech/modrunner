import AppKit
import ModRunnerKit

/// Window sizing and decoration, driven from the app delegate rather than from
/// SwiftUI.
///
/// This used to be an NSViewRepresentable sitting behind the skin switch. That
/// was unreliable: switching skins rebuilt the representable, and the `window`
/// property is still nil inside `makeNSView`, so the resize silently never ran.
/// The window then kept the previous skin's size, which pushed the drawn
/// title bar out of view. Owning the window directly removes the guesswork.
/// A window that can take focus even without a title bar.
///
/// The classic skin runs without `.titled`, and AppKit refuses key and main
/// status to such windows unless they say otherwise.
final class ModRunnerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum WindowChrome {

    /// Dresses the window for a skin. The classic skin draws its own title bar
    /// and gadgets, so the system chrome is hidden for it; the native skin uses
    /// the real thing.
    static func dress(_ window: NSWindow, for skin: Skin) {
        // Assigning a style mask is not free: AppKit rebuilds the frame view and
        // moves the window. This runs on every defaults change, so it only sets
        // what is not already set.
        func setMask(_ mask: NSWindow.StyleMask) {
            guard window.styleMask != mask else { return }
            window.styleMask = mask
        }

        switch skin {
        case .classic:
            // Dropping .titled is the point. With a titled window, AppKit's
            // NSTitlebarContainerView is layered above the content view and
            // covers the drawn title bar — titlebarAppearsTransparent no longer
            // prevents that. Without .titled there is no container at all, so
            // the drawn bar is visible and clickable. .closable and
            // .miniaturizable stay so the gadgets can still act on the window.
            setMask([.closable, .miniaturizable, .resizable, .fullSizeContentView])
            // Not movable by its background: that would swallow the mouse-moved
            // events every gadget's tooltip depends on. The drawn title bar
            // carries a `WindowDragArea` instead, which is where the window is
            // meant to be dragged from anyway.
            window.isMovableByWindowBackground = false
            // From `Palette`, not a literal. The frame and the content have to
            // agree, and when this was written out separately they stopped.
            window.backgroundColor = Classic.nsColor(\.face)

        case .native:
            // .resizable does two jobs: it keeps the green gadget live, which
            // AppKit disables outright on a window that cannot be resized, and
            // it is what lets the height be dragged. The width stays pinned
            // below, and `windowShouldZoom` turns the click into the
            // full-screen stage.
            setMask([.titled, .closable, .miniaturizable, .resizable])
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.isMovableByWindowBackground = false
            window.backgroundColor = .windowBackgroundColor
            window.title = "ModRunner"
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            // Zoom stays inert: the width is fixed and the height is the
            // user's, so there is nothing to zoom to.
            // The green gadget opens the full-screen player, through the
            // delegate's `windowShouldZoom`. Replacing the button's own
            // target/action does nothing — AppKit's title bar widget does not
            // go through them.
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isEnabled = true
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
    static func resize(_ window: NSWindow, to size: CGSize, minHeight: CGFloat) {
        // The width is pinned: the layout is drawn for one width and nothing in
        // it stretches sideways. The height is the user's, between the shortest
        // the module list will tolerate and whatever the screen allows.
        defer {
            window.contentMinSize = CGSize(width: size.width, height: minHeight)
            window.contentMaxSize = CGSize(width: size.width, height: .greatestFiniteMagnitude)
        }

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
        resize(window, to: targetSize(), minHeight: RootView.minimumHeight())
    }

    // MARK: - Remembered height

    /// The size to give the window: the layout's own, plus however much taller
    /// the user has dragged it.
    ///
    /// The extra is stored rather than the height itself, so showing or hiding
    /// the tracker still adds or removes exactly the tracker's height and the
    /// user's own slack survives it.
    static func targetSize() -> CGSize {
        let ideal = RootView.initialSize()
        let height = max(RootView.minimumHeight(),
                         ideal.height + extraHeight(for: Skin.current))
        return CGSize(width: ideal.width, height: height)
    }

    private static func heightKey(for skin: Skin) -> String {
        "windowExtraHeight.\(skin.rawValue)"
    }

    private static func extraHeight(for skin: Skin) -> CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: heightKey(for: skin)))
    }

    /// Records how much taller than the layout the window has been dragged.
    static func saveHeight(of window: NSWindow, for skin: Skin) {
        guard let content = window.contentView else { return }
        let extra = Double(content.frame.height - RootView.initialSize().height)
        // Writing is what wakes the observer that redresses the window, so an
        // unchanged value is worth not writing.
        guard abs(extra - Double(extraHeight(for: skin))) > 0.5 else { return }
        UserDefaults.standard.set(extra, forKey: heightKey(for: skin))
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
