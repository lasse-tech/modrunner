import SwiftUI
import AppKit

/// Chooses the presentation and keeps the window sized and dressed to match it.
/// Both skins observe the same `PlayerModel`, so switching between them mid-song
/// changes nothing about playback.
struct RootView: View {

    @StateObject private var model = PlayerModel.shared
    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue
    @AppStorage("showTracker") private var showTracker = true
    /// Read only so the tree is rebuilt when the language changes: the strings
    /// are fetched imperatively through `L10n`, which SwiftUI cannot observe.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    private var skin: Skin { Skin(rawValue: skinName) ?? .native }

    var body: some View {
        // Pinned to the top-left rather than centred: if the window size and the
        // content size ever disagree, the mismatch shows up as slack at the
        // edges instead of hiding the Workbench title bar off the top.
        ZStack(alignment: .topLeading) {
            Color(nsColor: skin == .amiga
                  ? NSColor(calibratedRed: 0x95 / 255, green: 0x95 / 255, blue: 0x95 / 255, alpha: 1)
                  : .windowBackgroundColor)

            switch skin {
            case .amiga:
                AmigaSkinView(model: model)
            case .native:
                NativeSkinView(model: model)
            }
        }
        .id(language)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // @AppStorage sees both in-process writes (menu, buttons, gadgets) and
        // external ones, so this is the reliable trigger for resizing the
        // window. The app delegate's notification observer is only a backstop.
        .onChange(of: skinName) { _ in applyWindowState(skinChanged: true) }
        .onChange(of: showTracker) { _ in applyWindowState() }
        .onAppear { applyWindowState() }
    }

    private func applyWindowState(skinChanged: Bool = false) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            if skinChanged {
                WindowChrome.applySkinChange(to: window)
            } else {
                WindowChrome.apply(to: window)
            }
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
