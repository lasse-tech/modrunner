import SwiftUI
import AppKit
import ModRunnerKit

/// Settings are deliberately system-native rather than skinned: Cmd-, is a
/// macOS habit, and a skinned dialog would be the one place the
/// imitation gets in the way of the person using it.
struct SettingsView: View {

    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage(Palette.storageKey) private var palette = Palette.incudex.rawValue

    static let width: CGFloat = 420
    static let height: CGFloat = 268

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("settings.title"))
                .font(.system(size: 15, weight: .semibold))

            Picker(L10n.t("settings.language"), selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .help(L10n.t("settings.languageNote"))

            Text(L10n.t("settings.languageNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // The palette only shows in the classic skin, which the note below
            // says rather than leaving the control to look broken when the
            // native skin is on.
            Picker(L10n.t("settings.palette"), selection: paletteChoice) {
                ForEach(Palette.allCases, id: \.rawValue) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            Text(L10n.t("settings.paletteNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        // Everything here is drawn in the language being chosen, so the whole
        // pane is rebuilt when the choice changes.
        .id(language)
    }

    /// Reads through `@AppStorage` so the radio group follows a change made in
    /// the menu, but writes through `Palette.current` so the setter can refresh
    /// the value the colours are actually read from. Writing straight to the
    /// default would leave the window painted in the previous palette until
    /// something else made it redraw.
    private var paletteChoice: Binding<String> {
        Binding(get: { palette },
                set: { Palette.current = Palette(rawValue: $0) ?? .incudex })
    }
}

/// One settings window, reused. AppKit has no scene to lean on here, so it is
/// opened by hand like the other auxiliary windows.
@MainActor
final class SettingsController {

    static let shared = SettingsController()

    private var window: NSWindow?

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero,
                                size: CGSize(width: SettingsView.width, height: SettingsView.height)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("settings.title")
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
