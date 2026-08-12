import SwiftUI

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
        skin == .amiga ? .native : .amiga
    }

    static func toggleSkin() {
        skin = otherSkin
    }

    static var trackerVisible: Bool {
        get { AmigaSkinView.trackerVisiblePreference }
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

// MARK: - Workbench

/// The row of gadgets that mirrors the View menu, in Intuition's idiom.
struct AmigaViewOptions: View {

    @ObservedObject var model: PlayerModel
    @AppStorage("showTracker") private var showTracker = true
    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue

    /// Height the panel adds to the window, bevel included.
    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.t("player.view"))
                .font(Amiga.font(9))
                .foregroundColor(Amiga.black)

            AmigaButton(label: ViewOptions.otherSkin.title, width: 96) {
                ViewOptions.toggleSkin()
            }

            AmigaButton(label: L10n.t("button.tracks"), width: 62) {
                showTracker.toggle()
            }

            AmigaButton(label: L10n.t("button.filter"), width: 46) {
                model.filterEnabled.toggle()
            }

            Spacer(minLength: 4)

            AmigaButton(label: L10n.t("button.fullScreen"), width: 62) {
                ViewOptions.toggleStage()
            }

            AmigaButton(label: L10n.t("button.miniPlayer"), width: 52) {
                ViewOptions.toggleMiniPlayer()
            }
        }
        .amigaBevel(.raised)
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
