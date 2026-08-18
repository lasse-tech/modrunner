import SwiftUI
import ModRunnerKit

/// The things the View menu can do, in a form the interface can offer as
/// buttons. Everything here was reachable only by menu or shortcut before, which
/// is a poor deal for a window that is meant to be looked at rather than
/// navigated.
@MainActor
enum ViewOptions {

    static var skin: Skin {
        get { Skin.current }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Skin.storageKey) }
    }

    /// The skin the toggle would switch to.
    static var otherSkin: Skin {
        skin == .classic ? .native : .classic
    }

    static func toggleSkin() {
        skin = otherSkin
    }

    /// The colour palette. Only the classic skin is drawn from it — the native
    /// one follows the system — but the menu item is always live, so switching
    /// it while the native skin is showing does the sensible thing and takes
    /// effect the moment the classic skin comes back.
    static var palette: Palette {
        get { Palette.current }
        set { Palette.current = newValue }
    }

    static func togglePalette() {
        palette = palette.other
    }

    static var trackerVisible: Bool {
        get { SkinMetrics.trackerVisiblePreference }
        set { UserDefaults.standard.set(newValue, forKey: "showTracker") }
    }

    static func toggleTracker() {
        trackerVisible.toggle()
    }

    static func toggleFilter() {
        PlayerModel.shared.filterEnabled.toggle()
    }

    static func toggleStage() {
        StageController.shared.toggle()
    }

    static func toggleMiniPlayer() {
        MiniPlayerController.shared.toggle()
    }
}

// MARK: - Classic

/// The row of gadgets that mirrors the View menu.
///
/// One row, fixed boxes, no wrapping — the widths below are chosen so the
/// German labels fit at the window's one width. Anything longer shrinks a
/// little rather than reflowing onto a second line.
struct ClassicViewOptions: View {

    @ObservedObject var model: PlayerModel
    @AppStorage("showTracker") private var showTracker = true
    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue
    @AppStorage(Palette.storageKey) private var paletteName = Palette.incudex.rawValue

    /// Height the panel adds to the window, bevel included.
    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 5) {
            Text(L10n.t("player.view"))
                .font(Classic.font(9))
                .foregroundColor(Classic.caption)
                .fixedSize()

            ClassicButton(label: ViewOptions.otherSkin.title, width: 78,
                          help: L10n.t("tooltip.switchSkin", ViewOptions.otherSkin.title)) {
                ViewOptions.toggleSkin()
            }

            ClassicButton(label: ViewOptions.palette.other.title, width: 78,
                          help: L10n.t("tooltip.switchPalette", ViewOptions.palette.other.title)) {
                ViewOptions.togglePalette()
            }

            ClassicButton(label: L10n.t("button.tracks"), width: 62, on: showTracker,
                          help: L10n.t("tooltip.tracks")) {
                showTracker.toggle()
            }

            ClassicButton(label: L10n.t("button.filter"), width: 42, on: model.filterEnabled,
                          help: L10n.t(model.filterEnabled ? "tooltip.filterOn" : "tooltip.filterOff")) {
                model.filterEnabled.toggle()
            }

            Spacer(minLength: 4)

            ClassicButton(label: L10n.t("button.fullScreen"), width: 56,
                          help: L10n.t("menu.fullScreen")) {
                ViewOptions.toggleStage()
            }

            ClassicButton(label: L10n.t("button.miniPlayer"), width: 50,
                          help: L10n.t("menu.miniPlayer")) {
                ViewOptions.toggleMiniPlayer()
            }
        }
        .classicBevel(.raised)
    }
}

// MARK: - Native

/// The same row with SF Symbols. The two that are switches show their state by
/// filling in, the way the channel buttons and the filter LED do.
struct NativeViewOptions: View {

    @ObservedObject var model: PlayerModel
    @AppStorage("showTracker") private var showTracker = true
    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue

    var body: some View {
        HStack(spacing: 8) {
            OptionButton(symbol: "paintpalette",
                         help: L10n.t("tooltip.switchSkin", ViewOptions.otherSkin.title)) {
                ViewOptions.toggleSkin()
            }

            OptionButton(symbol: "list.bullet.rectangle",
                         on: showTracker,
                         help: L10n.t("menu.showTracker")) {
                showTracker.toggle()
            }

            OptionButton(symbol: "arrow.up.left.and.arrow.down.right",
                         help: L10n.t("menu.fullScreen")) {
                ViewOptions.toggleStage()
            }

            OptionButton(symbol: "rectangle.bottomthird.inset.filled",
                         help: L10n.t("menu.miniPlayer")) {
                ViewOptions.toggleMiniPlayer()
            }
        }
    }
}

/// A small square button, filled when what it controls is on.
private struct OptionButton: View {
    let symbol: String
    var on: Bool = false
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(on ? AnyShapeStyle(Brand.orange) : AnyShapeStyle(.quaternary))
                        .opacity(hovering ? 0.8 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
