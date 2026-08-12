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
}

public enum WindowEvent: Equatable {
    case closed
    case exposed
    case resized(width: Int, height: Int)
    case mouseDown(x: Int, y: Int)
    case mouseUp(x: Int, y: Int)
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
