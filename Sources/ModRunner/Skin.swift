import SwiftUI

/// The two presentations of the player. They share the model and the replayer
/// completely; only the view layer differs.
enum Skin: String, CaseIterable, Identifiable {
    /// A re-creation in the AmigaOS 3.x Workbench idiom.
    case amiga
    /// A contemporary macOS interface, using the ModRunner brand.
    case native

    var id: String { rawValue }

    var title: String {
        switch self {
        // "Workbench" is the name of the thing it imitates, in any language.
        case .amiga: return "Workbench"
        case .native: return L10n.t("skin.native")
        }
    }

    static let storageKey = "skin"

    /// The skin the app last ran with.
    static var current: Skin {
        Skin(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .native
    }
}

/// The ModRunner palette, taken from `brand/README.txt`.
enum Brand {
    static let orange = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x35 / 255)
    static let salmon = Color(red: 0xFF / 255, green: 0xA9 / 255, blue: 0x97 / 255)
    static let blue   = Color(red: 0x3B / 255, green: 0x67 / 255, blue: 0xA2 / 255)
    static let dark   = Color(red: 0x17 / 255, green: 0x13 / 255, blue: 0x0F / 255)
    static let light  = Color(red: 0xED / 255, green: 0xE6 / 255, blue: 0xE0 / 255)

    /// The level ramp the app icon uses: quiet is blue, loud is orange.
    static func level(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.28: return blue
        case ..<0.62: return salmon
        default: return orange
        }
    }

    static let meterGradient = LinearGradient(
        stops: [
            .init(color: blue, location: 0.0),
            .init(color: blue, location: 0.26),
            .init(color: salmon, location: 0.34),
            .init(color: salmon, location: 0.58),
            .init(color: orange, location: 0.66),
            .init(color: orange, location: 1.0),
        ],
        startPoint: .bottom, endPoint: .top
    )
}
