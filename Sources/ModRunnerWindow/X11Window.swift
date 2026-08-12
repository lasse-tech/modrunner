#if os(Linux)

import Foundation
import Glibc
import ModRunnerSkin

/// A window on X11, with Xlib opened at run time.
///
/// Nothing here is linked against and no development package is needed to
/// build it: the library is found with `dlopen` and every entry point with
/// `dlsym`. That keeps a build machine free of X11 entirely, and means a
/// machine without a display fails with a sentence rather than refusing to
/// start the program at all — which matters, since `info`, `render` and `dump`
/// have every right to work over SSH.
///
/// The structures Xlib passes back are read by offset rather than by declaring
/// them. `XEvent` is a union the size of its largest member, and its layout for
/// the members used here — type, then the pointer-aligned fields, then the
/// coordinates — has been fixed for as long as X11 has been 64-bit.
final class X11Window: WindowBackend {

    // MARK: - Xlib entry points

    private typealias OpenDisplay = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias CloseDisplay = @convention(c) (OpaquePointer?) -> Int32
    private typealias DefaultScreen = @convention(c) (OpaquePointer?) -> Int32
    private typealias RootWindow = @convention(c) (OpaquePointer?, Int32) -> UInt
    private typealias DefaultVisual = @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    private typealias DefaultDepth = @convention(c) (OpaquePointer?, Int32) -> Int32
    private typealias DefaultGC = @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    private typealias WhitePixel = @convention(c) (OpaquePointer?, Int32) -> UInt
    private typealias CreateSimpleWindow = @convention(c)
        (OpaquePointer?, UInt, Int32, Int32, UInt32, UInt32, UInt32, UInt, UInt) -> UInt
    private typealias StoreName = @convention(c) (OpaquePointer?, UInt, UnsafePointer<CChar>?) -> Int32
    private typealias SelectInput = @convention(c) (OpaquePointer?, UInt, Int) -> Int32
    private typealias MapWindow = @convention(c) (OpaquePointer?, UInt) -> Int32
    private typealias DestroyWindow = @convention(c) (OpaquePointer?, UInt) -> Int32
    private typealias CreateImage = @convention(c)
        (OpaquePointer?, OpaquePointer?, UInt32, Int32, Int32,
         UnsafeMutablePointer<CChar>?, UInt32, UInt32, Int32, Int32) -> OpaquePointer?
    private typealias PutImage = @convention(c)
        (OpaquePointer?, UInt, OpaquePointer?, OpaquePointer?,
         Int32, Int32, Int32, Int32, UInt32, UInt32) -> Int32
    private typealias GetImage = @convention(c)
        (OpaquePointer?, UInt, Int32, Int32, UInt32, UInt32, UInt, Int32) -> OpaquePointer?
    private typealias Flush = @convention(c) (OpaquePointer?) -> Int32
    private typealias Sync = @convention(c) (OpaquePointer?, Int32) -> Int32
    private typealias Pending = @convention(c) (OpaquePointer?) -> Int32
    private typealias NextEvent = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    private typealias InternAtom = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32) -> UInt
    private typealias SetWMProtocols = @convention(c)
        (OpaquePointer?, UInt, UnsafeMutablePointer<UInt>?, Int32) -> Int32
    private typealias LookupKeysym = @convention(c) (UnsafeMutableRawPointer?, Int32) -> UInt

    private let library: UnsafeMutableRawPointer
    private let openDisplay: OpenDisplay
    private let closeDisplay: CloseDisplay
    private let createImage: CreateImage
    private let putImage: PutImage
    private let getImage: GetImage
    private let flush: Flush
    private let sync: Sync
    private let pending: Pending
    private let nextEvent: NextEvent
    private let destroyWindow: DestroyWindow
    private let lookupKeysym: LookupKeysym

    // MARK: - State

    private let display: OpaquePointer
    private let window: UInt
    private let gc: OpaquePointer
    private let visual: OpaquePointer
    private let depth: UInt32
    private var deleteWindowAtom: UInt = 0
    private var closed = false

    private(set) var size: (width: Int, height: Int)

    /// The pixels as X wants them: one 32-bit word per pixel, blue in the low
    /// byte on every little-endian machine X11 runs on today.
    private var scanline: [UInt32]

    // MARK: - Opening

    init(title: String, width: Int, height: Int) throws {
        // The versioned name first: libX11.so without a suffix only exists when
        // the development package is installed, which is exactly what this
        // avoids needing.
        guard let library = dlopen("libX11.so.6", RTLD_NOW) ?? dlopen("libX11.so", RTLD_NOW) else {
            throw WindowError.noDisplay("libX11.so.6 could not be loaded"
                                        + (String(cString: dlerror() ?? UnsafeMutablePointer(mutating: "")).isEmpty
                                           ? "" : ": \(String(cString: dlerror()!))"))
        }
        self.library = library

        func symbol<T>(_ name: String, _ type: T.Type = T.self) throws -> T {
            guard let pointer = dlsym(library, name) else {
                throw WindowError.failed("Xlib has no \(name)")
            }
            return unsafeBitCast(pointer, to: type)
        }

        openDisplay = try symbol("XOpenDisplay")
        closeDisplay = try symbol("XCloseDisplay")
        createImage = try symbol("XCreateImage")
        putImage = try symbol("XPutImage")
        getImage = try symbol("XGetImage")
        flush = try symbol("XFlush")
        sync = try symbol("XSync")
        pending = try symbol("XPending")
        nextEvent = try symbol("XNextEvent")
        destroyWindow = try symbol("XDestroyWindow")
        lookupKeysym = try symbol("XLookupKeysym")

        let defaultScreen: DefaultScreen = try symbol("XDefaultScreen")
        let rootWindow: RootWindow = try symbol("XRootWindow")
        let defaultVisual: DefaultVisual = try symbol("XDefaultVisual")
        let defaultDepth: DefaultDepth = try symbol("XDefaultDepth")
        let defaultGC: DefaultGC = try symbol("XDefaultGC")
        let blackPixel: WhitePixel = try symbol("XBlackPixel")
        let createSimpleWindow: CreateSimpleWindow = try symbol("XCreateSimpleWindow")
        let storeName: StoreName = try symbol("XStoreName")
        let selectInput: SelectInput = try symbol("XSelectInput")
        let mapWindow: MapWindow = try symbol("XMapWindow")
        let internAtom: InternAtom = try symbol("XInternAtom")
        let setWMProtocols: SetWMProtocols = try symbol("XSetWMProtocols")

        guard let display = openDisplay(nil) else {
            let name = ProcessInfo.processInfo.environment["DISPLAY"] ?? "unset"
            throw WindowError.noDisplay("cannot open the display (DISPLAY is \(name))")
        }
        self.display = display

        let screen = defaultScreen(display)
        guard let visual = defaultVisual(display, screen), let gc = defaultGC(display, screen) else {
            _ = closeDisplay(display)
            throw WindowError.failed("the screen has no visual this can draw on")
        }
        self.visual = visual
        self.gc = gc
        self.depth = UInt32(defaultDepth(display, screen))
        self.size = (width, height)
        self.scanline = [UInt32](repeating: 0, count: width * height)

        window = createSimpleWindow(display, rootWindow(display, screen), 0, 0,
                                    UInt32(width), UInt32(height), 0,
                                    blackPixel(display, screen), blackPixel(display, screen))
        title.withCString { _ = storeName(display, window, $0) }

        // Exposure, keys, buttons and structure changes — nothing else, so the
        // queue does not fill with motion the player has no use for.
        let mask = Self.exposureMask | Self.keyPressMask
            | Self.buttonPressMask | Self.buttonReleaseMask | Self.structureNotifyMask
        _ = selectInput(display, window, mask)

        // Without this the window manager kills the connection when the window
        // is closed, instead of sending a message that can be handled.
        deleteWindowAtom = "WM_DELETE_WINDOW".withCString { internAtom(display, $0, 0) }
        var atom = deleteWindowAtom
        withUnsafeMutablePointer(to: &atom) { _ = setWMProtocols(display, window, $0, 1) }

        _ = mapWindow(display, window)
        _ = flush(display)
    }

    deinit {
        close()
        dlclose(library)
    }

    func close() {
        guard !closed else { return }
        closed = true
        _ = destroyWindow(display, window)
        _ = closeDisplay(display)
    }

    // MARK: - Drawing

    func present(_ canvas: Canvas) throws {
        guard !closed else { return }

        let count = canvas.width * canvas.height
        if scanline.count != count {
            scanline = [UInt32](repeating: 0, count: count)
        }
        // The canvas stores red in the high byte; X wants blue in the low byte
        // of a native-endian word, so this is a shuffle rather than a copy.
        for index in 0..<count {
            let rgba = canvas.pixels[index]
            scanline[index] = (rgba >> 8) & 0x00FF_FFFF
        }

        try scanline.withUnsafeMutableBufferPointer { buffer in
            let raw = UnsafeMutableRawPointer(buffer.baseAddress!)
                .bindMemory(to: CChar.self, capacity: count * 4)
            guard let image = createImage(display, visual, depth, Self.zPixmap, 0, raw,
                                          UInt32(canvas.width), UInt32(canvas.height),
                                          32, Int32(canvas.width * 4)) else {
                throw WindowError.failed("XCreateImage refused a \(canvas.width)×\(canvas.height) image")
            }
            _ = putImage(display, window, gc, image, 0, 0, 0, 0,
                         UInt32(canvas.width), UInt32(canvas.height))
            // XDestroyImage would free the pixel buffer with it, and the buffer
            // belongs to Swift. Releasing the header alone is what is wanted.
            free(UnsafeMutableRawPointer(image))
        }
        _ = flush(display)
    }

    /// Reads the window's pixels back off the server. Only used to prove, on a
    /// virtual framebuffer, that what was drawn actually arrived.
    func readBack() -> Canvas? {
        guard !closed else { return nil }
        _ = sync(display, 0)
        guard let image = getImage(display, window, 0, 0,
                                   UInt32(size.width), UInt32(size.height),
                                   ~0, Self.zPixmap) else { return nil }
        defer { free(UnsafeMutableRawPointer(image)) }

        // XImage: width, height, xoffset, format as 32-bit fields, then the
        // data pointer at the first pointer-aligned offset after them.
        let header = UnsafeRawPointer(image)
        guard let data = header.load(fromByteOffset: 16, as: UnsafeMutablePointer<UInt8>?.self) else {
            return nil
        }
        var canvas = Canvas(width: size.width, height: size.height)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let offset = (y * size.width + x) * 4
                canvas.set(x, y, Colour(data[offset + 2], data[offset + 1], data[offset]))
            }
        }
        return canvas
    }

    // MARK: - Events

    func poll() -> [WindowEvent] {
        guard !closed else { return [] }
        var events: [WindowEvent] = []
        var storage = [UInt8](repeating: 0, count: 256)

        while pending(display) > 0 {
            storage.withUnsafeMutableBytes { raw in
                _ = nextEvent(display, raw.baseAddress)
                let base = raw.baseAddress!
                let type = base.load(fromByteOffset: 0, as: Int32.self)

                switch type {
                case Self.expose:
                    events.append(.exposed)
                case Self.configureNotify:
                    // XConfigureEvent: width and height follow x and y.
                    let width = base.load(fromByteOffset: 72, as: Int32.self)
                    let height = base.load(fromByteOffset: 76, as: Int32.self)
                    if width > 0, height > 0 {
                        size = (Int(width), Int(height))
                        events.append(.resized(width: Int(width), height: Int(height)))
                    }
                case Self.buttonPress, Self.buttonRelease:
                    let x = base.load(fromByteOffset: 64, as: Int32.self)
                    let y = base.load(fromByteOffset: 68, as: Int32.self)
                    events.append(type == Self.buttonPress
                                  ? .mouseDown(x: Int(x), y: Int(y))
                                  : .mouseUp(x: Int(x), y: Int(y)))
                case Self.keyPress:
                    if let key = Self.key(for: lookupKeysym(base, 0)) {
                        events.append(.key(key))
                    }
                case Self.clientMessage:
                    // The atom the window manager sends sits in the first word
                    // of the message data.
                    let atom = base.load(fromByteOffset: 56, as: UInt.self)
                    if atom == deleteWindowAtom { events.append(.closed) }
                default:
                    break
                }
            }
        }
        return events
    }

    private static func key(for keysym: UInt) -> WindowEvent.Key? {
        switch keysym {
        case 0x20:   return .space
        case 0xFF1B: return .escape
        case 0xFF51: return .left
        case 0xFF52: return .up
        case 0xFF53: return .right
        case 0xFF54: return .down
        default:
            guard keysym >= 0x21, keysym <= 0x7E,
                  let scalar = UnicodeScalar(UInt32(keysym)) else { return nil }
            return .character(Character(scalar))
        }
    }

    // MARK: - Xlib constants

    private static let zPixmap: Int32 = 2

    private static let keyPressMask: Int = 1 << 0
    private static let buttonPressMask: Int = 1 << 2
    private static let buttonReleaseMask: Int = 1 << 3
    private static let exposureMask: Int = 1 << 15
    private static let structureNotifyMask: Int = 1 << 17

    private static let keyPress: Int32 = 2
    private static let buttonPress: Int32 = 4
    private static let buttonRelease: Int32 = 5
    private static let expose: Int32 = 12
    private static let configureNotify: Int32 = 22
    private static let clientMessage: Int32 = 33
}

#endif
