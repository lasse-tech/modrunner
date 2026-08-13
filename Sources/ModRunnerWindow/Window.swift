import Foundation
import ModRunnerSkin

/// What a window has to be able to do for the player: show a canvas, and say
/// what the user did to it. Nothing else — no widgets, no layout, no drawing.
/// The skin already produced the picture; this puts it on a screen.
public protocol WindowBackend: AnyObject {
    func present(_ canvas: Canvas) throws
    func poll() -> [WindowEvent]
    func close()
    var size: (width: Int, height: Int) { get }

    /// Follows the canvas when it changes shape, so that a pixel of the picture
    /// stays a pixel of the window. The skin has two heights — with the tracker
    /// and without — and the hit testing works in canvas coordinates, so a
    /// window that kept the old size would put the buttons somewhere other than
    /// where they are drawn.
    func resize(width: Int, height: Int)

    /// What the Workbench title bar's gadgets act on. The skin draws them and
    /// hides the system chrome, so these are the only window controls there
    /// are; a backend that cannot do one of them does nothing, which is better
    /// than the player having to ask what platform it is on.
    func minimise()
    func sendToBack()

    /// Starts a title bar drag. Called when a click lands on the drawn bar
    /// rather than on a gadget, because without system chrome nothing else
    /// would move the window.
    func beginDrag()

    /// Asks the user for modules to add. The system's own chooser, not a drawn
    /// one — the macOS app opens an NSOpenPanel for this, and a file requester
    /// people already know how to drive beats a hand-made one that only looks
    /// like 1992. Both run modal, so the picture stops until they close.
    /// `startingAt` is where to open: the drawer the current module came from,
    /// so the chooser lands next to the music instead of at the top of the
    /// machine.
    func chooseFiles(startingAt: URL?) -> [URL]
    func chooseDrawer(startingAt: URL?) -> URL?
}

/// The window controls are optional: X11 has no implementation yet, and a
/// backend that ignores them leaves the player exactly as it was rather than
/// failing to build.
extension WindowBackend {
    public func resize(width: Int, height: Int) {}
    public func minimise() {}
    public func sendToBack() {}
    public func beginDrag() {}
    public func chooseFiles(startingAt: URL?) -> [URL] { [] }
    public func chooseDrawer(startingAt: URL?) -> URL? { nil }
}

public enum WindowEvent: Equatable {
    case closed
    case exposed
    case resized(width: Int, height: Int)
    case mouseDown(x: Int, y: Int)
    case mouseUp(x: Int, y: Int)
    /// The right button and the pointer, which together are the whole of the
    /// Intuition menu: press to raise the strip, move to pick, release to
    /// choose. A backend that never sends them simply has no menu.
    case rightMouseDown(x: Int, y: Int)
    case rightMouseUp(x: Int, y: Int)
    case mouseMoved(x: Int, y: Int)
    case key(Key)

    public enum Key: Equatable {
        case space
        case escape
        case left
        case right
        case up
        case down
        case character(Character)
    }
}

public enum WindowError: LocalizedError {
    case noBackend
    case noDisplay(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noBackend:
            return "this build has no window backend"
        case .noDisplay(let detail):
            return "no display: \(detail)"
        case .failed(let detail):
            return detail
        }
    }
}

public enum Window {

    /// Opens whatever this platform has. The window layer is loaded at run
    /// time, not linked: a machine with no X11 gets an error it can act on
    /// rather than a binary that would not start.
    public static func open(title: String, width: Int, height: Int) throws -> WindowBackend {
        #if os(Linux)
        return try X11Window(title: title, width: width, height: height)
        #elseif os(Windows)
        return try Win32Window(title: title, width: width, height: height)
        #else
        throw WindowError.noBackend
        #endif
    }

    public static var isAvailable: Bool {
        #if os(Linux) || os(Windows)
        return true
        #else
        return false
        #endif
    }
}
