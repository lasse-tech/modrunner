import SwiftUI
import AppKit
import ModRunnerKit

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
    /// Same reason: a change of palette has to repaint the classic skin, and
    /// the colours are read imperatively through `Classic`.
    @AppStorage(Palette.storageKey) private var paletteName = Palette.incudex.rawValue

    private var skin: Skin { Skin(rawValue: skinName) ?? .native }

    var body: some View {
        // Pinned to the top-left rather than centred: if the window size and the
        // content size ever disagree, the mismatch shows up as slack at the
        // edges instead of hiding the drawn title bar off the top.
        ZStack(alignment: .topLeading) {
            // The ground behind the content, for the moment between a resize
            // and the relayout. It comes from `Palette` like everything else —
            // this used to be a literal, and it stayed grey when the rest of
            // the skin was recoloured.
            Color(nsColor: skin == .classic
                  ? Classic.nsColor(\.face)
                  : .windowBackgroundColor)

            switch skin {
            case .classic:
                ClassicSkinView(model: model)
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
        // The window's own background colour is set on the NSWindow, not in
        // SwiftUI, so a palette change has to go back through the chrome or the
        // frame keeps the previous palette's ground.
        .onChange(of: paletteName) { _ in applyWindowState() }
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

    /// The size the layout asks for, before any view has been laid out and
    /// before whatever height the user has dragged the window to.
    static func initialSize() -> CGSize {
        let tracker = SkinMetrics.trackerVisiblePreference
        switch Skin.current {
        case .classic:
            return CGSize(width: SkinMetrics.windowWidth,
                          height: SkinMetrics.windowHeight(showingTracker: tracker))
        case .native:
            return CGSize(width: NativeSkinView.windowWidth,
                          height: NativeSkinView.windowHeight(showingTracker: tracker))
        }
    }

    /// The shortest the window may be made. Everything above the module list is
    /// laid out at a fixed height, so this is where dragging stops.
    static func minimumHeight() -> CGFloat {
        let tracker = SkinMetrics.trackerVisiblePreference
        switch Skin.current {
        case .classic: return SkinMetrics.minimumHeight(showingTracker: tracker)
        case .native: return NativeSkinView.minimumHeight(showingTracker: tracker)
        }
    }
}
