import Foundation
import ModRunnerSkin

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// The terminal as a display and a keyboard, behind the same two verbs the
/// window backends answer to: put this picture up, and say what the user did.
///
/// Nothing is linked for this and nothing is vendored. A terminal is a file you
/// write escape sequences to, and the rest is `termios` on Unix and the console
/// API on Windows — both part of the system this already builds against.
public final class Terminal {

    /// How much colour the terminal admits to. Detected once, because the
    /// answer cannot change while the program runs.
    public enum ColourDepth {
        case truecolour     // 24-bit, what any terminal of the last decade has
        case indexed        // the 256-colour cube
        case none           // NO_COLOR, TERM=dumb, or a pipe

        public static func detect(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  isInteractive: Bool) -> ColourDepth {
            guard isInteractive, environment["NO_COLOR"] == nil else { return .none }
            let term = environment["TERM"] ?? ""
            guard !term.isEmpty, term != "dumb" else { return .none }

            let colourTerm = (environment["COLORTERM"] ?? "").lowercased()
            if colourTerm.contains("truecolor") || colourTerm.contains("24bit") { return .truecolour }
            if term.contains("256") || term.contains("direct") { return .truecolour }
            return .indexed
        }
    }

    public private(set) var colourDepth: ColourDepth
    private var previous: TextCanvas?
    private var raw = false

    /// What is left of a key sequence that arrived in pieces.
    private var pending: [UInt8] = []
    /// How many polls a lone escape has been sitting in the buffer. A bare Esc
    /// and the start of an arrow key are the same first byte, so the difference
    /// is only ever how long nothing followed.
    private var escapeAge = 0

    public init() {
        colourDepth = ColourDepth.detect(isInteractive: Terminal.isInteractive)
    }

    // MARK: - Is there a terminal at all

    public static var isInteractive: Bool {
        #if os(Windows)
        return _isatty(_fileno(stdout)) != 0 && _isatty(_fileno(stdin)) != 0
        #else
        return isatty(STDOUT_FILENO) == 1 && isatty(STDIN_FILENO) == 1
        #endif
    }

    /// The size of the terminal, or a sensible page when there is none —
    /// `COLUMNS` and `LINES` first, since that is how a pipe is told.
    public static func size() -> (width: Int, height: Int) {
        let environment = ProcessInfo.processInfo.environment
        if let columns = environment["COLUMNS"].flatMap(Int.init),
           let lines = environment["LINES"].flatMap(Int.init),
           columns > 0, lines > 0 {
            return (columns, lines)
        }

        #if os(Windows)
        var info = CONSOLE_SCREEN_BUFFER_INFO()
        if let handle = GetStdHandle(STD_OUTPUT_HANDLE),
           handle != INVALID_HANDLE_VALUE,
           GetConsoleScreenBufferInfo(handle, &info) == true {
            let width = Int(info.srWindow.Right - info.srWindow.Left) + 1
            let height = Int(info.srWindow.Bottom - info.srWindow.Top) + 1
            if width > 1, height > 1 { return (width, height) }
        }
        #else
        var window = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &window) == 0,
           window.ws_col > 1, window.ws_row > 1 {
            return (Int(window.ws_col), Int(window.ws_row))
        }
        #endif
        return (100, 30)
    }

    // MARK: - Raw mode

    /// Takes the terminal over: no line buffering, no echo, the alternate
    /// screen, no cursor, and mouse reports.
    ///
    /// Every one of those has to be undone or the shell the user comes back to
    /// is unusable — so the undo is registered with the signals as well as with
    /// the caller, and `stty sane` is never the user's problem to work out.
    public func enterRawMode() {
        guard Terminal.isInteractive, !raw else { return }

        #if os(Windows)
        Terminal.savedInputMode = 0
        Terminal.savedOutputMode = 0
        if let input = GetStdHandle(STD_INPUT_HANDLE) {
            var mode: DWORD = 0
            _ = GetConsoleMode(input, &mode)
            Terminal.savedInputMode = mode
            var wanted = mode
            wanted &= ~DWORD(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT)
            wanted |= DWORD(ENABLE_WINDOW_INPUT)
            _ = SetConsoleMode(input, wanted)
        }
        if let output = GetStdHandle(STD_OUTPUT_HANDLE) {
            var mode: DWORD = 0
            _ = GetConsoleMode(output, &mode)
            Terminal.savedOutputMode = mode
            _ = SetConsoleMode(output, mode | DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING))
        }
        // The picture is box-drawing characters and blocks, so the console has
        // to be told the bytes coming at it are UTF-8.
        Terminal.savedOutputCodePage = GetConsoleOutputCP()
        _ = SetConsoleOutputCP(UINT(CP_UTF8))
        #else
        var settings = termios()
        tcgetattr(STDIN_FILENO, &settings)
        Terminal.savedSettings = settings
        Terminal.settingsSaved = true

        var rawSettings = settings
        cfmakeraw(&rawSettings)
        // A read that returns nothing rather than waiting: the loop has a frame
        // to draw whether or not a key was pressed.
        withUnsafeMutablePointer(to: &rawSettings.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { control in
                control[Int(VMIN)] = 0
                control[Int(VTIME)] = 0
            }
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &rawSettings)

        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number) { received in
                Terminal.emergencyRestore()
                _exit(128 + received)
            }
        }
        #endif

        raw = true
        Terminal.decorated = true
        emit("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1006h\u{1B}[2J")
    }

    /// Puts everything back. Safe to call twice, and called from the signal
    /// handler as well as from the player's `defer`.
    public func leaveRawMode() {
        guard raw else { return }
        raw = false
        Terminal.emergencyRestore()
        previous = nil
    }

    #if !os(Windows)
    private nonisolated(unsafe) static var savedSettings = termios()
    private nonisolated(unsafe) static var settingsSaved = false
    #else
    private nonisolated(unsafe) static var savedInputMode: DWORD = 0
    private nonisolated(unsafe) static var savedOutputMode: DWORD = 0
    private nonisolated(unsafe) static var savedOutputCodePage: UINT = 0
    #endif
    private nonisolated(unsafe) static var decorated = false

    /// Only the calls that are safe to make from a signal handler: writing
    /// bytes, and handing the terminal settings back.
    public static func emergencyRestore() {
        if decorated {
            decorated = false
            let reset = "\u{1B}[?1006l\u{1B}[?1000l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l"
            #if os(Windows)
            _ = reset.withCString { _write(_fileno(stdout), $0, UInt32(strlen($0))) }
            #else
            _ = reset.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
            #endif
        }
        #if os(Windows)
        if savedInputMode != 0, let input = GetStdHandle(STD_INPUT_HANDLE) {
            _ = SetConsoleMode(input, savedInputMode)
        }
        if savedOutputMode != 0, let output = GetStdHandle(STD_OUTPUT_HANDLE) {
            _ = SetConsoleMode(output, savedOutputMode)
        }
        if savedOutputCodePage != 0 { _ = SetConsoleOutputCP(savedOutputCodePage) }
        #else
        if settingsSaved {
            tcsetattr(STDIN_FILENO, TCSANOW, &savedSettings)
        }
        #endif
    }

    // MARK: - Drawing

    /// Puts a picture on the terminal, writing only the rows that changed.
    ///
    /// At fifty frames a second a full repaint is both a lot of bytes and a
    /// visible flicker over ssh; in a player at rest the only rows that move
    /// are the tracker, the meters and the clock.
    public func present(_ canvas: TextCanvas) {
        emit(frame(canvas))
    }

    /// The escape sequences for one frame, and the picture it now believes is
    /// on screen. Split out from `present` so it can be checked without a
    /// terminal to write to.
    public func frame(_ canvas: TextCanvas) -> String {
        var output = ""
        let unchanged = previous.map { $0.width == canvas.width && $0.height == canvas.height } ?? false
        if !unchanged {
            output += "\u{1B}[2J"
        }

        for y in 0..<canvas.height {
            if unchanged, let previous, rowsMatch(previous, canvas, y) { continue }
            output += "\u{1B}[\(y + 1);1H"
            output += encode(row: y, of: canvas)
        }
        output += "\u{1B}[0m"

        previous = canvas
        return output
    }

    private func rowsMatch(_ old: TextCanvas, _ new: TextCanvas, _ y: Int) -> Bool {
        for x in 0..<new.width where old.cell(x, y) != new.cell(x, y) { return false }
        return true
    }

    /// One row, with runs of the same two colours written as a single escape.
    private func encode(row y: Int, of canvas: TextCanvas) -> String {
        var output = ""
        var ink: Colour?
        var paper: Colour?

        for x in 0..<canvas.width {
            let cell = canvas.cell(x, y)
            if cell.ink != ink || cell.paper != paper {
                output += style(ink: cell.ink, paper: cell.paper)
                ink = cell.ink
                paper = cell.paper
            }
            output.append(cell.character)
        }
        return output
    }

    private func style(ink: Colour, paper: Colour) -> String {
        switch colourDepth {
        case .truecolour:
            return "\u{1B}[0;38;2;\(ink.red);\(ink.green);\(ink.blue)"
                + ";48;2;\(paper.red);\(paper.green);\(paper.blue)m"
        case .indexed:
            return "\u{1B}[0;38;5;\(Terminal.indexed(ink));48;5;\(Terminal.indexed(paper))m"
        case .none:
            // With no colour left, the only thing that can still say "this row
            // is the one playing" is reversing it.
            return paper == Theme.face || paper == Theme.sunken ? "\u{1B}[0m" : "\u{1B}[0;7m"
        }
    }

    /// An RGB colour as an xterm-256 index: the 6×6×6 cube, or the grey ramp
    /// when the three components are close enough to be a grey.
    public static func indexed(_ colour: Colour) -> Int {
        let red = Int(colour.red), green = Int(colour.green), blue = Int(colour.blue)
        if abs(red - green) < 10, abs(green - blue) < 10 {
            let level = (red + green + blue) / 3
            if level < 8 { return 16 }
            if level > 248 { return 231 }
            return 232 + (level - 8) * 24 / 240
        }
        func step(_ value: Int) -> Int { value < 48 ? 0 : (value < 114 ? 1 : (value - 35) / 40) }
        return 16 + 36 * step(red) + 6 * step(green) + step(blue)
    }

    private func emit(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    // MARK: - Input

    /// What the user did since the last call, in the same vocabulary the window
    /// backends use — so the two players share the code that acts on it.
    public func poll() -> [WindowEvent] {
        #if os(Windows)
        return pollConsole()
        #else
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        return events(from: count > 0 ? Array(buffer[0..<count]) : [])
        #endif
    }

    /// The same parse, over bytes the caller supplies. `poll` is this with a
    /// `read` in front of it, and this is what a test can drive: escape
    /// sequences arriving in pieces are the whole difficulty, and they are
    /// impossible to provoke reliably through a real terminal.
    public func events(from bytes: [UInt8]) -> [WindowEvent] {
        pending.append(contentsOf: bytes)
        return parse()
    }

    /// Turns the bytes in the buffer into events, leaving anything that is only
    /// half a sequence for the next poll.
    private func parse() -> [WindowEvent] {
        var events: [WindowEvent] = []

        while !pending.isEmpty {
            let byte = pending[0]

            if byte == 0x1B {
                if pending.count == 1 {
                    // Either the Escape key, or an arrow whose second byte has
                    // not arrived yet. One frame of patience tells them apart.
                    escapeAge += 1
                    if escapeAge > 1 {
                        pending.removeFirst()
                        escapeAge = 0
                        events.append(.key(.escape))
                    }
                    return events
                }
                escapeAge = 0
                guard consumeEscape(&events) else { return events }
                continue
            }

            pending.removeFirst()
            switch byte {
            case 0x03, 0x04:                        // Ctrl-C, Ctrl-D
                events.append(.closed)
            case 0x0D, 0x0A:
                events.append(.key(.character("\n")))
            case 0x20:
                events.append(.key(.space))
            case 0x21...0x7E:
                events.append(.key(.character(Character(UnicodeScalar(byte)))))
            default:
                break                               // control bytes with no meaning here
            }
        }
        return events
    }

    /// True when a whole sequence was taken off the front of the buffer, false
    /// when it is still arriving and should be waited on.
    private func consumeEscape(_ events: inout [WindowEvent]) -> Bool {
        guard pending.count >= 2 else { return false }
        guard pending[1] == 0x5B || pending[1] == 0x4F else {   // '[' or 'O'
            pending.removeFirst()
            events.append(.key(.escape))
            return true
        }
        guard pending.count >= 3 else { return false }

        // A mouse report: ESC [ < button ; column ; row M or m.
        if pending[1] == 0x5B, pending[2] == 0x3C {
            guard let terminator = pending.firstIndex(where: { $0 == 0x4D || $0 == 0x6D }) else { return false }
            let body = String(decoding: pending[3..<terminator], as: UTF8.self)
            let pressed = pending[terminator] == 0x4D
            pending.removeFirst(terminator + 1)

            let parts = body.split(separator: ";").compactMap { Int($0) }
            if pressed, parts.count == 3, parts[0] & 0b11 == 0 {
                // The report is one-based and counts the whole screen.
                events.append(.mouseDown(x: parts[1] - 1, y: parts[2] - 1))
            }
            return true
        }

        let final = pending[2]
        pending.removeFirst(3)
        switch final {
        case 0x41: events.append(.key(.up))
        case 0x42: events.append(.key(.down))
        case 0x43: events.append(.key(.right))
        case 0x44: events.append(.key(.left))
        default: break                              // Home, End, F-keys: not used
        }
        return true
    }

    #if os(Windows)
    /// Windows has no escape sequences to parse: the console hands over key
    /// records, and the virtual key codes are the arrows directly.
    private func pollConsole() -> [WindowEvent] {
        guard let input = GetStdHandle(STD_INPUT_HANDLE), input != INVALID_HANDLE_VALUE else { return [] }
        var events: [WindowEvent] = []

        while true {
            var waiting: DWORD = 0
            guard GetNumberOfConsoleInputEvents(input, &waiting) == true, waiting > 0 else { break }

            var record = INPUT_RECORD()
            var read: DWORD = 0
            guard ReadConsoleInputW(input, &record, 1, &read) == true, read == 1 else { break }
            guard Int32(record.EventType) == KEY_EVENT,
                  record.Event.KeyEvent.bKeyDown == true else { continue }

            let key = record.Event.KeyEvent
            switch Int32(key.wVirtualKeyCode) {
            case VK_ESCAPE: events.append(.key(.escape))
            case VK_LEFT:   events.append(.key(.left))
            case VK_RIGHT:  events.append(.key(.right))
            case VK_UP:     events.append(.key(.up))
            case VK_DOWN:   events.append(.key(.down))
            case VK_SPACE:  events.append(.key(.space))
            default:
                let character = key.uChar.UnicodeChar
                if character >= 0x21, let scalar = UnicodeScalar(character) {
                    events.append(.key(.character(Character(scalar))))
                }
            }
        }
        return events
    }
    #endif
}
