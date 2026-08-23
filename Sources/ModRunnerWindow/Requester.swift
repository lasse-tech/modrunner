import Foundation
#if os(Windows)
import WinSDK
#endif

/// Something to say when there is no console to say it in.
///
/// The windowed build is linked without one — that is the whole reason it is a
/// second binary — so every word `warn` writes has nowhere to go. Handed a
/// module it cannot open, it would exit in silence and look broken, which is
/// the thing the split was meant to avoid rather than to cause.
///
/// This is in the window layer rather than with the commands because it is a
/// window. A program that has to say something before it has one of its own is
/// what MessageBox has always been for; nothing is drawn here and nothing is
/// laid out, the system does both.
public enum Requester {

    /// What the requester is about, which is all the system needs in order to
    /// pick an icon for it.
    public enum Kind {
        case information, problem
    }

    /// Shows `message` and waits for it to be acknowledged.
    ///
    /// Returns false where the platform has nothing to show it with, so the
    /// caller can fall back to stderr rather than saying nothing at all. That
    /// is everywhere but Windows: X11 has no requester here, and macOS has the
    /// app.
    @discardableResult
    public static func show(_ message: String, title: String, kind: Kind = .problem) -> Bool {
        #if os(Windows)
        let body = Array(message.utf16) + [0]
        let caption = Array(title.utf16) + [0]
        let icon = kind == .problem ? MB_ICONERROR : MB_ICONINFORMATION
        body.withUnsafeBufferPointer { text in
            caption.withUnsafeBufferPointer { heading in
                _ = MessageBoxW(nil, text.baseAddress, heading.baseAddress, UINT(MB_OK | icon))
            }
        }
        return true
        #else
        return false
        #endif
    }
}
