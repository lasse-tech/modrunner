#if os(Windows)

import Foundation
import WinSDK
import ModRunnerSkin

/// A window on Win32, drawn into with GDI.
///
/// Nothing is installed for this either: `user32` and `gdi32` are part of
/// Windows, and the pixels go up with `StretchDIBits`, which has been the way
/// to put a software framebuffer on screen since Windows 3. No Direct2D, no
/// swap chain, no device loss to handle — the picture is 560 pixels wide and
/// changes fifty times a second at most.
///
/// The window procedure is a C function pointer and cannot capture anything, so
/// events land in a queue beside it. The player has exactly one window, which
/// is what makes that acceptable rather than a design to be ashamed of.
final class Win32Window: WindowBackend {

    private static var queue: [WindowEvent] = []
    private static var currentSize: (width: Int, height: Int) = (0, 0)

    private let handle: HWND
    private var closed = false
    private var pixels: [UInt32] = []

    private(set) var size: (width: Int, height: Int)

    // MARK: - Opening

    init(title: String, width: Int, height: Int) throws {
        let className = "ModRunnerWindow"
        let instance = GetModuleHandleW(nil)

        var wideClass = Array(className.utf16) + [0]
        try wideClass.withUnsafeMutableBufferPointer { classBuffer in
            var windowClass = WNDCLASSW()
            windowClass.lpfnWndProc = Win32Window.procedure
            windowClass.hInstance = instance
            windowClass.lpszClassName = UnsafePointer(classBuffer.baseAddress!)
            // IDC_ARROW is MAKEINTRESOURCE(32512), a macro Swift does not
            // import: the resource id goes in as a pointer bit pattern.
            windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32_512))

            // A class that is already registered is not an error: it is the
            // second window this process has opened.
            if RegisterClassW(&windowClass) == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
                throw WindowError.failed("RegisterClassW failed (\(GetLastError()))")
            }
        }

        // CreateWindow takes the outer size, and the canvas has to fit the
        // client area, so the frame is measured and added on.
        // The window styles come through as differently signed integers, so
        // they are widened before being combined rather than after.
        let style = DWORD(WS_OVERLAPPEDWINDOW) | DWORD(WS_VISIBLE)
        var frame = RECT(left: 0, top: 0, right: LONG(width), bottom: LONG(height))
        _ = AdjustWindowRect(&frame, DWORD(WS_OVERLAPPEDWINDOW), false)

        var wideTitle = Array(title.utf16) + [0]
        var wideClassName = Array(className.utf16) + [0]
        let created: HWND? = wideClassName.withUnsafeBufferPointer { classBuffer in
            wideTitle.withUnsafeBufferPointer { titleBuffer in
                CreateWindowExW(0, classBuffer.baseAddress, titleBuffer.baseAddress, style,
                                Int32(CW_USEDEFAULT), Int32(CW_USEDEFAULT),
                                frame.right - frame.left, frame.bottom - frame.top,
                                nil, nil, instance, nil)
            }
        }
        guard let handle = created else {
            throw WindowError.noDisplay("CreateWindowExW failed (\(GetLastError()))")
        }
        self.handle = handle
        self.size = (width, height)
        Win32Window.currentSize = (width, height)

        _ = ShowWindow(handle, SW_SHOW)
        _ = UpdateWindow(handle)
    }

    deinit {
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        _ = DestroyWindow(handle)
    }

    // MARK: - Drawing

    func present(_ canvas: Canvas) throws {
        guard !closed else { return }

        let count = canvas.width * canvas.height
        if pixels.count != count {
            pixels = [UInt32](repeating: 0, count: count)
        }
        // BI_RGB wants 0x00RRGGBB in a machine word; the canvas has red in the
        // top byte of an RGBA word, so the alpha is what has to go.
        for index in 0..<count {
            pixels[index] = (canvas.pixels[index] >> 8) & 0x00FF_FFFF
        }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(canvas.width)
        // Negative height: rows top to bottom, the way the canvas stores them.
        info.bmiHeader.biHeight = LONG(-canvas.height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)

        guard let context = GetDC(handle) else {
            throw WindowError.failed("GetDC returned nothing")
        }
        defer { _ = ReleaseDC(handle, context) }

        pixels.withUnsafeBufferPointer { buffer in
            _ = StretchDIBits(context,
                              0, 0, Int32(size.width), Int32(size.height),
                              0, 0, Int32(canvas.width), Int32(canvas.height),
                              buffer.baseAddress, &info, UINT(DIB_RGB_COLORS), DWORD(SRCCOPY))
        }
    }

    // MARK: - Events

    func poll() -> [WindowEvent] {
        guard !closed else { return [] }

        var message = MSG()
        while PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
            _ = TranslateMessage(&message)
            _ = DispatchMessageW(&message)
        }

        size = Win32Window.currentSize
        let events = Win32Window.queue
        Win32Window.queue.removeAll(keepingCapacity: true)
        return events
    }

    private static let procedure: WNDPROC = { window, message, wParam, lParam in
        switch message {
        case UINT(WM_CLOSE), UINT(WM_DESTROY):
            queue.append(.closed)
            return 0
        case UINT(WM_PAINT):
            queue.append(.exposed)
            return DefWindowProcW(window, message, wParam, lParam)
        case UINT(WM_SIZE):
            let width = Int(LOWORD(lParam)), height = Int(HIWORD(lParam))
            if width > 0, height > 0 {
                currentSize = (width, height)
                queue.append(.resized(width: width, height: height))
            }
            return 0
        case UINT(WM_LBUTTONDOWN):
            queue.append(.mouseDown(x: Int(LOWORD(lParam)), y: Int(HIWORD(lParam))))
            return 0
        case UINT(WM_LBUTTONUP):
            queue.append(.mouseUp(x: Int(LOWORD(lParam)), y: Int(HIWORD(lParam))))
            return 0
        case UINT(WM_KEYDOWN):
            if let key = Win32Window.key(for: Int32(wParam)) { queue.append(.key(key)) }
            return 0
        default:
            return DefWindowProcW(window, message, wParam, lParam)
        }
    }

    private static func key(for code: Int32) -> WindowEvent.Key? {
        switch code {
        case VK_SPACE:  return .space
        case VK_ESCAPE: return .escape
        case VK_LEFT:   return .left
        case VK_UP:     return .up
        case VK_RIGHT:  return .right
        case VK_DOWN:   return .down
        default:
            // Virtual key codes for letters and digits are their uppercase
            // ASCII; anything else is not something the player listens for.
            guard code >= 0x30, code <= 0x5A,
                  let scalar = UnicodeScalar(UInt32(code)) else { return nil }
            return .character(Character(scalar).lowercased().first!)
        }
    }
}

/// The low and high words of an LPARAM, which is how Win32 packs coordinates.
private func LOWORD(_ value: LPARAM) -> UInt16 { UInt16(truncatingIfNeeded: value) }
private func HIWORD(_ value: LPARAM) -> UInt16 { UInt16(truncatingIfNeeded: value >> 16) }

#endif
