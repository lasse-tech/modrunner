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
    /// Where the pointer and the window were when a title bar drag began.
    private static var drag: (cursor: POINT, origin: POINT)?

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

        // No system title bar. The skin draws a Workbench one with its own
        // gadgets, and two title bars on one window is one too many — the same
        // choice the macOS app makes by dropping `.titled`. A popup has no
        // frame either, so the window rectangle *is* the client rectangle and
        // there is nothing to measure and add on. WS_EX_APPWINDOW keeps the
        // taskbar button, without which the minimise gadget would be a one-way
        // door.
        //
        // WS_SYSMENU draws nothing without WS_CAPTION, but it is what keeps
        // Alt+Space and the taskbar button's right-click menu working: hiding
        // the title bar should cost the Workbench look-alike its decoration,
        // not the ways out of the window that every Windows user expects.
        // WS_MINIMIZEBOX goes with it so that menu's Minimise is not greyed.
        //
        // WS_POPUP has its top bit set, which the SDK hands over as a negative
        // Int32; the bit pattern is what CreateWindowEx wants either way.
        let style = DWORD(bitPattern: Int32(truncatingIfNeeded: WS_POPUP))
            | DWORD(WS_VISIBLE) | DWORD(WS_SYSMENU) | DWORD(WS_MINIMIZEBOX)

        // A popup gets no placement worth having from CW_USEDEFAULT, and the
        // window is as tall as the skin makes it — on a scaled display that can
        // be more than the room above the taskbar. Centring inside the work
        // area and clamping to its top left keeps the status line on screen.
        var work = RECT(left: 0, top: 0, right: 0, bottom: 0)
        withUnsafeMutablePointer(to: &work) {
            _ = SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, UnsafeMutableRawPointer($0), 0)
        }
        let originX = Swift.max(work.left, work.left + ((work.right - work.left) - LONG(width)) / 2)
        let originY = Swift.max(work.top, work.top + ((work.bottom - work.top) - LONG(height)) / 2)

        let wideTitle = Array(title.utf16) + [0]
        let wideClassName = Array(className.utf16) + [0]
        let created: HWND? = wideClassName.withUnsafeBufferPointer { classBuffer in
            wideTitle.withUnsafeBufferPointer { titleBuffer in
                CreateWindowExW(DWORD(WS_EX_APPWINDOW),
                                classBuffer.baseAddress, titleBuffer.baseAddress, style,
                                originX, originY, Int32(width), Int32(height),
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
        // A popup is not activated the way an overlapped window is, and without
        // the keyboard the player would be down to the mouse.
        _ = SetForegroundWindow(handle)
    }

    // MARK: - Window controls

    /// The window follows the canvas rather than scaling it. With no frame the
    /// window rectangle is the client rectangle, so the new size goes straight
    /// in — and because this is now the only thing that ever changes the size,
    /// client and canvas cannot drift apart.
    func resize(width: Int, height: Int) {
        guard !closed, width > 0, height > 0 else { return }
        _ = SetWindowPos(handle, nil, 0, 0, Int32(width), Int32(height),
                         UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        size = (width, height)
        Win32Window.currentSize = (width, height)
    }

    func minimise() {
        guard !closed else { return }
        _ = ShowWindow(handle, SW_MINIMIZE)
    }

    func sendToBack() {
        guard !closed else { return }
        // HWND_BOTTOM is (HWND)1 — a value dressed as a handle, which Swift
        // will not import as a constant.
        _ = SetWindowPos(handle, HWND(bitPattern: 1), 0, 0, 0, 0,
                         UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
    }

    /// Moves the window with the pointer until the button comes up.
    ///
    /// Deliberately not `WM_NCLBUTTONDOWN` with `HTCAPTION`, which is the usual
    /// trick: that hands control to a modal loop inside `DefWindowProcW`, and
    /// since the messages are only pumped from `poll()`, the player would stop
    /// drawing for as long as the window is being dragged. Tracking it here
    /// costs a dozen lines and the picture keeps running.
    func beginDrag() {
        guard !closed else { return }
        var cursor = POINT()
        _ = GetCursorPos(&cursor)
        var frame = RECT(left: 0, top: 0, right: 0, bottom: 0)
        _ = GetWindowRect(handle, &frame)
        Win32Window.drag = (cursor: cursor, origin: POINT(x: frame.left, y: frame.top))
        _ = SetCapture(handle)
    }

    deinit {
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        _ = DestroyWindow(handle)
    }

    // MARK: - Choosing modules

    /// The common dialog, with no type filter to speak of: Amiga files rarely
    /// carry an extension and `ModuleLoader` decides on content anyway, so
    /// filtering by name would hide exactly the files this player is for.
    func chooseFiles(startingAt drawer: URL?) -> [URL] {
        guard !closed else { return [] }
        // OFN_ALLOWMULTISELECT answers with a NUL-separated run — the directory
        // first, then each name — except when one file is picked, where the
        // whole path arrives on its own. Room for a long multiple selection.
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let filter = Array("All files\0*.*\0Modules\0*.med;*.mod\0\0".utf16)
        let start = Array((drawer?.path ?? "").utf16) + [0]
        var chosen: [URL] = []

        buffer.withUnsafeMutableBufferPointer { file in
            filter.withUnsafeBufferPointer { pattern in
                start.withUnsafeBufferPointer { initial in
                    var open = OPENFILENAMEW()
                    open.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
                    open.hwndOwner = handle
                    open.lpstrFile = file.baseAddress
                    open.nMaxFile = DWORD(file.count)
                    open.lpstrFilter = pattern.baseAddress
                    open.nFilterIndex = 1
                    if drawer != nil { open.lpstrInitialDir = initial.baseAddress }
                    open.Flags = DWORD(OFN_EXPLORER | OFN_ALLOWMULTISELECT
                        | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_HIDEREADONLY)
                    guard GetOpenFileNameW(&open) else { return }
                    chosen = Win32Window.paths(from: file)
                }
            }
        }
        return chosen
    }

    /// A drawer. The classic browser rather than the newer one, which would
    /// oblige the process to initialise COM for the sake of a nicer dialog.
    ///
    /// `startingAt` is ignored here, and the browser opens at the top of the
    /// machine. A `BFFM_SETSELECTIONW` from a `BFFM_INITIALIZED` callback is
    /// the documented way to place it, and it was tried and had no visible
    /// effect in the classic dialog; rather than leave a line in that cannot
    /// be shown to do anything, the parameter goes unused until someone can
    /// make it work — likely with `BIF_NEWDIALOGSTYLE`, which wants COM
    /// initialised in the process.
    func chooseDrawer(startingAt drawer: URL?) -> URL? {
        guard !closed else { return nil }
        var title = Array("Choose a drawer of modules".utf16) + [0]
        var picked: URL?

        title.withUnsafeMutableBufferPointer { caption in
            var browse = BROWSEINFOW()
            browse.hwndOwner = handle
            browse.lpszTitle = UnsafePointer(caption.baseAddress)
            browse.ulFlags = UINT(BIF_RETURNONLYFSDIRS)
            guard let list = SHBrowseForFolderW(&browse) else { return }
            defer { CoTaskMemFree(list) }

            var path = [WCHAR](repeating: 0, count: Int(MAX_PATH))
            guard SHGetPathFromIDListW(list, &path) else { return }
            let text = String(decoding: path.prefix { $0 != 0 }, as: UTF16.self)
            if !text.isEmpty { picked = URL(fileURLWithPath: text) }
        }
        return picked
    }

    private static func paths(from buffer: UnsafeMutableBufferPointer<WCHAR>) -> [URL] {
        var parts: [String] = []
        var start = 0
        while start < buffer.count, buffer[start] != 0 {
            var end = start
            while end < buffer.count, buffer[end] != 0 { end += 1 }
            parts.append(String(decoding: buffer[start..<end], as: UTF16.self))
            start = end + 1
        }
        guard let directory = parts.first else { return [] }
        guard parts.count > 1 else { return [URL(fileURLWithPath: directory)] }
        let base = URL(fileURLWithPath: directory)
        return parts.dropFirst().map { base.appendingPathComponent($0) }
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
            queue.append(.mouseDown(x: mouseX(lParam), y: mouseY(lParam)))
            return 0
        case UINT(WM_MOUSEMOVE):
            // Screen coordinates rather than lParam: the window is moving under
            // the pointer, so anything relative to it chases its own tail.
            if let drag = drag {
                var now = POINT()
                _ = GetCursorPos(&now)
                _ = SetWindowPos(window, nil,
                                 drag.origin.x + (now.x - drag.cursor.x),
                                 drag.origin.y + (now.y - drag.cursor.y),
                                 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
            }
            // The player can act on one position per frame, so a fast pointer
            // replaces its own last report rather than filling the queue.
            if let last = queue.last, case .mouseMoved = last { queue.removeLast() }
            queue.append(.mouseMoved(x: mouseX(lParam), y: mouseY(lParam)))
            return 0
        case UINT(WM_LBUTTONUP):
            if drag != nil {
                drag = nil
                _ = ReleaseCapture()
            }
            queue.append(.mouseUp(x: mouseX(lParam), y: mouseY(lParam)))
            return 0
        case UINT(WM_RBUTTONDOWN):
            // Captured for the same reason the menu needs it: the pointer will
            // leave the window while an item is being chosen near its edge.
            _ = SetCapture(window)
            queue.append(.rightMouseDown(x: mouseX(lParam), y: mouseY(lParam)))
            return 0
        case UINT(WM_RBUTTONUP):
            _ = ReleaseCapture()
            queue.append(.rightMouseUp(x: mouseX(lParam), y: mouseY(lParam)))
            return 0
        case UINT(WM_CAPTURECHANGED):
            // Capture can be taken away — by a system dialog, by Alt-Tab. The
            // drag has to end with it or the window would follow the pointer
            // around with no button held.
            drag = nil
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

/// Pointer coordinates are the same two words read as *signed*: with the mouse
/// captured — dragging the title bar, choosing a menu item — the pointer goes
/// outside the window, and read unsigned a few pixels left of the edge would
/// arrive as sixty-five thousand.
private func mouseX(_ value: LPARAM) -> Int { Int(Int16(bitPattern: LOWORD(value))) }
private func mouseY(_ value: LPARAM) -> Int { Int(Int16(bitPattern: HIWORD(value))) }

#endif
