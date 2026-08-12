import SwiftUI

/// Chooses the presentation and keeps the window sized and dressed to match it.
/// Both skins observe the same `PlayerModel`, so switching between them mid-song
/// changes nothing about playback.
struct RootView: View {

    @StateObject private var model = PlayerModel.shared
    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue
    @AppStorage("showTracker") private var showTracker = true

    private var skin: Skin { Skin(rawValue: skinName) ?? .native }

    var body: some View {
        Group {
            switch skin {
            case .amiga:
                AmigaSkinView(model: model)
            case .native:
                NativeSkinView(model: model)
            }
        }
        .background(WindowConfigurator(size: windowSize, skin: skin))
    }

    private var windowSize: CGSize {
        switch skin {
        case .amiga:
            return CGSize(width: AmigaSkinView.windowWidth,
                          height: AmigaSkinView.windowHeight(showingTracker: showTracker))
        case .native:
            return CGSize(width: NativeSkinView.windowWidth,
                          height: NativeSkinView.windowHeight(showingTracker: showTracker))
        }
    }

    /// The size the window should open at, before any view has been laid out.
    static func initialSize() -> CGSize {
        let tracker = AmigaSkinView.trackerVisiblePreference
        switch Skin.current {
        case .amiga:
            return CGSize(width: AmigaSkinView.windowWidth,
                          height: AmigaSkinView.windowHeight(showingTracker: tracker))
        case .native:
            return CGSize(width: NativeSkinView.windowWidth,
                          height: NativeSkinView.windowHeight(showingTracker: tracker))
        }
    }
}
