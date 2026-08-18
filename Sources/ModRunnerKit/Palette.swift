import Foundation

/// One colour, as bytes. Deliberately not a `Color` or an `NSColor`: this file
/// is the one place the interface colours are written down, and it has to be
/// readable from the SwiftUI app, from the pixel renderer and from a test with
/// no window server attached.
public struct PaletteColour: Sendable, Equatable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From `0xRRGGBB`, which is how the design tokens are written down.
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    /// The three components as 0...1, for toolkits that want them that way.
    public var components: (Double, Double, Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    }
}

/// The colours the classic skin is drawn from.
///
/// The skin's *shapes* are a 16-bit idiom — two-pixel bevels, light above and
/// to the left, recessed readouts, a monospaced grid. Its *colours* are not:
/// they come from the design tokens of the two sibling projects, and both of
/// those are dark. That inverts the bevel: the shine is no longer white but the
/// lightest frame tone, and the shadow is the deepest ground. The rule itself is
/// unchanged, which is what keeps the surfaces legible.
///
/// Every colour in the interface comes from here. It used to be written out
/// four times — twice as literals in window code — and the two halves drifted.
public enum Palette: String, CaseIterable, Sendable {

    /// incudex: ember on slate. The default, and the closest to the ModRunner
    /// brand orange.
    case incudex

    /// lasse-web: cyan and magenta on near-black. Higher contrast, colder.
    case lasse

    /// What the menu calls it. Both are proper names, so neither is
    /// translated.
    public var title: String {
        switch self {
        case .incudex: return "incudex"
        case .lasse: return "lasse-web"
        }
    }

    public static let storageKey = "palette"

    /// Where the choice is stored. Injectable so a test can point it at a suite
    /// of its own rather than at the settings of whoever is running it.
    public nonisolated(unsafe) static var store: UserDefaults = .standard {
        didSet { cached = nil }
    }

    /// The last value read, so a render pass does not go to `UserDefaults` once
    /// per colour.
    ///
    /// It matters: the tracker asks for a colour per note column, so a full
    /// stage is over a thousand lookups a frame. Every path that writes the
    /// choice goes through `current`'s setter, which refreshes this; the
    /// notification below is the backstop for a write from outside the process,
    /// such as `defaults write`.
    private nonisolated(unsafe) static var cached: Palette?
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    /// The palette the app last ran with.
    public static var current: Palette {
        get {
            if let cached { return cached }
            observeExternalWrites()
            let value = Palette(rawValue: store.string(forKey: storageKey) ?? "") ?? .incudex
            cached = value
            return value
        }
        set {
            cached = newValue
            store.set(newValue.rawValue, forKey: storageKey)
        }
    }

    private static func observeExternalWrites() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { _ in cached = nil }
    }

    /// The other one, which is what a toggle switches to.
    public var other: Palette {
        self == .incudex ? .lasse : .incudex
    }

    // MARK: - The roles
    //
    // Eight pens carried the whole of a 16-bit desktop, and the roles below are
    // the same eight jobs plus the handful a colour interface can afford: a
    // separate caption grey, a dedicated meter ramp, a second accent.

    /// Behind the window — the desktop the window sits on.
    public var screen: PaletteColour { pick(0x0C0F14, 0x08090F) }

    /// The face of every panel, button and title bar.
    public var face: PaletteColour { pick(0x1D242F, 0x12141F) }

    /// One step down from the face, for surfaces that recede.
    public var faceDark: PaletteColour { pick(0x161B24, 0x0B0D15) }

    /// One step up from the face, for knobs and anything held above it.
    public var faceLight: PaletteColour { pick(0x252E3B, 0x1F2333) }

    /// The lit edge of a raised bevel: top and left.
    public var shine: PaletteColour { pick(0x3A4757, 0x2B3040) }

    /// The dark edge of a raised bevel: bottom and right.
    public var shadow: PaletteColour { pick(0x0A0D12, 0x05060A) }

    /// The ground of a recessed readout — the deepest surface in the window.
    public var sunken: PaletteColour { pick(0x0F131A, 0x0A0C14) }

    /// Body text and glyph ink.
    public var text: PaletteColour { pick(0xEEF1F5, 0xE7ECF5) }

    /// Values that are present but not the point.
    public var textDim: PaletteColour { pick(0xA3ADBB, 0xA9B4C7) }

    /// Small capitals above a field, and anything switched off.
    public var caption: PaletteColour { pick(0x6C7787, 0x6F7C92) }

    /// Selection, the playing line, the filled part of a slider.
    public var highlight: PaletteColour { pick(0xF97D4E, 0x2EE6FF) }

    /// Text on top of `highlight`.
    public var highlightText: PaletteColour { pick(0x0A0D12, 0x08090F) }

    /// The second accent, for state that is worth noticing but not selected.
    public var accent: PaletteColour { pick(0xE0A83D, 0xFF3DBD) }

    /// A cool counterpart to `highlight`: instrument numbers, quiet levels.
    public var arc: PaletteColour { pick(0x4FA6E8, 0x6FA8DC) }

    /// A lit meter cell.
    public var meter: PaletteColour { pick(0xF97D4E, 0x9BD40A) }

    /// The top of the meter, where a voice is close to clipping.
    public var meterPeak: PaletteColour { pick(0xE5624A, 0xFF3DBD) }

    /// An unlit meter cell.
    public var meterOff: PaletteColour { pick(0x131923, 0x0E1018) }

    /// How many pixels a bevel is. Two, as it always was — one reads as a
    /// hairline, three as a frame.
    public static let bevel = 2

    private func pick(_ incudexHex: UInt32, _ lasseHex: UInt32) -> PaletteColour {
        PaletteColour(hex: self == .incudex ? incudexHex : lasseHex)
    }

    /// The meter ramp: cool at the bottom, hot at the top. `fraction` is where
    /// the cell sits in the meter, not how loud the voice is.
    public func meterCell(at fraction: Double) -> PaletteColour {
        if fraction > 0.85 { return meterPeak }
        if fraction > 0.62 { return accent }
        return meter
    }
}
