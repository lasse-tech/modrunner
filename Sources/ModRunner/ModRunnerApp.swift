import SwiftUI
import AppKit
import ModRunnerKit

/// The window is built by hand rather than through a SwiftUI `Window` scene.
/// The drawn title bar replaces the macOS one, and a scene that has its standard
/// window buttons hidden does not reliably present itself; owning the NSWindow
/// keeps the size, position and chrome fully under our control.
@main
enum ModRunnerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate, NSMenuDelegate {

    // MARK: - Remembering where the window was

    /// AppKit nudges the window about while it is being set up. Saving during
    /// that would overwrite the stored position with an interim value before it
    /// has even been read back, so saving starts once the position is restored.
    private var positionRestored = false

    func windowDidMove(_ notification: Notification) {
        guard positionRestored, let window = notification.object as? NSWindow else { return }
        WindowChrome.saveOrigin(of: window, for: Skin.current)
    }

    /// The height is the user's to choose, and it is remembered per skin. This
    /// runs when the drag ends rather than on every frame of it: saving writes a
    /// default, and the observer on that redresses the window — not something to
    /// do underneath a resize in progress.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard positionRestored, let window = notification.object as? NSWindow else { return }
        WindowChrome.saveHeight(of: window, for: Skin.current)
    }

    /// Resizes that never went through a drag — a window manager, an
    /// accessibility client, a display that changed under the window — end up
    /// here instead, and are worth keeping just the same.
    ///
    /// Not during a drag, though: saving writes a default, and the observer on
    /// that redresses the window. Both that and the save itself now stop when
    /// nothing has actually changed, which is what keeps this from recursing;
    /// staying out of a live resize keeps it from doing the work sixty times a
    /// second as well.
    func windowDidResize(_ notification: Notification) {
        guard positionRestored, let window = notification.object as? NSWindow,
              !window.inLiveResize else { return }
        WindowChrome.saveHeight(of: window, for: Skin.current)
    }

    /// The green gadget opens the stage. Each skin has exactly one width, so
    /// there is nothing to zoom to; returning false leaves the window alone.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        MainActor.assumeIsolated { StageController.shared.toggle() }
        return false
    }

    /// Belt and braces: some paths into zoom (accessibility, for one) resize
    /// the window without asking `windowShouldZoom` first. Handing back the
    /// frame it already has leaves nothing to resize.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        window.frame
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowChrome.saveOrigin(of: window, for: Skin.current)
    }

    /// Keeps the menu's tick mark in step when the Tracks button is used.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTracker) {
            menuItem.state = SkinMetrics.trackerVisiblePreference ? .on : .off
        }
        if menuItem.action == #selector(selectSkin(_:)),
           let raw = menuItem.representedObject as? String {
            menuItem.state = (Skin.current.rawValue == raw) ? .on : .off
        }
        if menuItem.action == #selector(selectPalette(_:)),
           let raw = menuItem.representedObject as? String {
            menuItem.state = (Palette.current.rawValue == raw) ? .on : .off
        }
        if menuItem.action == #selector(toggleFilter) {
            menuItem.state = UserDefaults.standard.bool(forKey: "amigaFilter") ? .on : .off
        }
        if menuItem.action == #selector(selectVisualizer(_:)),
           let raw = menuItem.representedObject as? String {
            menuItem.state = (VisualizerStyle.current.rawValue == raw) ? .on : .off
        }
        if menuItem.action == #selector(toggleStage) {
            menuItem.state = MainActor.assumeIsolated { StageController.shared.isPresented } ? .on : .off
        }
        if menuItem.action == #selector(toggleMiniPlayer) {
            menuItem.state = MainActor.assumeIsolated { MiniPlayerController.shared.isPresented } ? .on : .off
        }
        return true
    }

    private var window: NSWindow?
    private var trackerMenuItem: NSMenuItem?
    /// The language the menu bar was last built in.
    private var menuLanguage: AppLanguage = .system

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything reads a default: the classic skin's stored value and
        // two window keys were renamed with it, and a stale key read once is a
        // setting silently lost.
        DefaultsMigration.run()

        buildMenu()
        buildWindow()
        Task { @MainActor in MediaKeys.shared.start() }
        Keyboard.start()

        // Files handed over on the command line, e.g. from `open --args`.
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !paths.isEmpty {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            Task { @MainActor in
                PlayerModel.shared.add(urls: urls)
                PlayerModel.shared.play()
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Double-clicking a module in the Finder loads and plays it.
    func application(_ sender: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            PlayerModel.shared.add(urls: urls)
            PlayerModel.shared.play()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Window

    private func buildWindow() {
        // Start at whichever size matches the stored skin, tracker preference
        // and dragged height, so the window does not visibly resize itself a
        // moment after opening.
        let target = WindowChrome.targetSize()
        let size = NSSize(width: target.width, height: target.height)
        let window = ModRunnerWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "ModRunner"

        // The chrome is set per skin by WindowConfigurator; this is only the
        // state the window opens in.

        // ignoresSafeArea keeps SwiftUI from insetting the content below the
        // (transparent) macOS title bar, which would leave a grey strip above
        // the drawn title bar.
        // NSHostingView publishes Auto Layout constraints derived from the
        // SwiftUI ideal size, and those win over setContentSize — which shrank
        // the window to a stamp. Hosting it inside a plain autoresizing
        // container keeps the window at the size we ask for.
        let hosting = NSHostingView(rootView: RootView().ignoresSafeArea())
        hosting.translatesAutoresizingMaskIntoConstraints = true
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        window.contentView = container
        // Both skins are a fixed size, so macOS's own full-screen mode has
        // nothing sensible to do here — and leaving it enabled makes AppKit add
        // an "Enter Full Screen" item next to ours, which does something else
        // entirely.
        window.collectionBehavior = [.fullScreenNone]
        WindowChrome.dress(window, for: Skin.current)
        window.setContentSize(size)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        // The position is restored after the first layout pass. Restoring it
        // before that let the view's own sizing run afterwards and drag the
        // origin along with it, so the window crept away from where it was left.
        DispatchQueue.main.async {
            WindowChrome.restoreOrigin(of: window, for: Skin.current)
            self.positionRestored = true
        }

        self.window = window

        // The skin and the tracker panel both change the window's size and
        // decoration. Watching the defaults keeps that in the app delegate,
        // where the window actually lives.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            WindowChrome.apply(to: window)

            // The menu bar is built once, in the language of the moment. A
            // change of language has to rebuild it; the views follow on their
            // own, because RootView is keyed on the setting.
            if self.menuLanguage != AppLanguage.current {
                self.buildMenu()
            }
        }

        if ProcessInfo.processInfo.environment["MODRUNNER_PRINT_WINDOW_ID"] == "1" {
            print("WINDOW_ID \(window.windowNumber) frame=\(window.frame) content=\(window.contentView?.frame ?? .zero)")
            fflush(stdout)

            // Dump the chrome repeatedly, so a skin switch can be observed too.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                let mask = window.styleMask
                func shown(_ type: NSWindow.ButtonType) -> String {
                    guard let button = window.standardWindowButton(type) else { return "absent" }
                    return button.isHidden ? "hidden" : "visible"
                }
                print("""
                BUFFER frames=\(AudioOutput.observedRenderFrames)
                CHROME skin=\(Skin.current.rawValue) \
                systemTitlebar=\(WindowChrome.hasSystemTitlebar(window)) \
                origin=\(window.frame.origin) \
                titled=\(mask.contains(.titled)) \
                fullSize=\(mask.contains(.fullSizeContentView)) \
                transparent=\(window.titlebarAppearsTransparent) \
                titleVisibility=\(window.titleVisibility == .visible ? "visible" : "hidden") \
                close=\(shown(.closeButton)) min=\(shown(.miniaturizeButton)) zoom=\(shown(.zoomButton)) \
                content=\(window.contentView?.frame ?? .zero)
                """)
                fflush(stdout)
            }
        }
    }

    // MARK: - Menu

    /// A minimal menu, mostly so the standard keyboard shortcuts work.
    private func buildMenu() {
        menuLanguage = AppLanguage.current
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: L10n.t("menu.about"),
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)

        let settings = NSMenuItem(title: L10n.t("menu.settings"),
                                  action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.hide"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L10n.t("menu.quit"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: L10n.t("menu.view"))
        let tracker = NSMenuItem(title: L10n.t("menu.showTracker"),
                                 action: #selector(toggleTracker), keyEquivalent: "t")
        tracker.target = self
        tracker.state = SkinMetrics.trackerVisiblePreference ? .on : .off
        viewMenu.addItem(tracker)
        viewMenu.addItem(.separator())

        // Skin switching, one number key each.
        for (index, skin) in Skin.allCases.enumerated() {
            let item = NSMenuItem(title: skin.title,
                                  action: #selector(selectSkin(_:)),
                                  keyEquivalent: "\(index + 1)")
            item.target = self
            item.representedObject = skin.rawValue
            item.state = (Skin.current == skin) ? .on : .off
            viewMenu.addItem(item)
        }

        // The colour palettes, on the same run of number keys. Only the classic
        // skin is drawn from them, but the choice is stored either way, so it
        // is there when that skin comes back.
        for (index, palette) in Palette.allCases.enumerated() {
            let item = NSMenuItem(title: palette.title,
                                  action: #selector(selectPalette(_:)),
                                  keyEquivalent: "\(Skin.allCases.count + index + 1)")
            item.target = self
            item.representedObject = palette.rawValue
            item.state = (Palette.current == palette) ? .on : .off
            viewMenu.addItem(item)
        }

        viewMenu.addItem(.separator())

        // Visualisations continue the number-key run after the skins and the
        // palettes.
        for (index, style) in VisualizerStyle.allCases.enumerated() {
            let item = NSMenuItem(title: style.title,
                                  action: #selector(selectVisualizer(_:)),
                                  keyEquivalent: "\(Skin.allCases.count + Palette.allCases.count + index + 1)")
            item.target = self
            item.representedObject = style.rawValue
            item.state = (VisualizerStyle.current == style) ? .on : .off
            viewMenu.addItem(item)
        }

        viewMenu.addItem(.separator())
        let filter = NSMenuItem(title: L10n.t("menu.amigaFilter"),
                                action: #selector(toggleFilter), keyEquivalent: "f")
        filter.target = self
        filter.state = UserDefaults.standard.bool(forKey: "amigaFilter") ? .on : .off
        viewMenu.addItem(filter)

        viewMenu.addItem(.separator())
        let stage = NSMenuItem(title: L10n.t("menu.fullScreen"),
                               action: #selector(toggleStage), keyEquivalent: "f")
        stage.keyEquivalentModifierMask = [.command, .control]
        stage.target = self
        viewMenu.addItem(stage)

        let mini = NSMenuItem(title: L10n.t("menu.miniPlayer"),
                              action: #selector(toggleMiniPlayer), keyEquivalent: "m")
        mini.keyEquivalentModifierMask = [.command, .control]
        mini.target = self
        viewMenu.addItem(mini)

        viewMenuItem.submenu = viewMenu
        trackerMenuItem = tracker

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.t("menu.file"))
        let open = NSMenuItem(title: L10n.t("menu.open"), action: #selector(openModules), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)

        // Filled in each time the menu is opened, so it never goes stale.
        let recent = NSMenuItem(title: L10n.t("menu.recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L10n.t("menu.recent"))
        recentMenu.delegate = self
        recent.submenu = recentMenu
        recentMenu.identifier = Self.recentMenuIdentifier
        fileMenu.addItem(recent)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        mainMenu.addItem(viewMenuItem)

        // A Window menu, so the standard shortcuts still work in the classic
        // skin, where the system window buttons are hidden.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.t("menu.window"))
        windowMenu.addItem(withTitle: L10n.t("menu.minimise"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.t("menu.close"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        // AppKit inserts its own "Enter Full Screen" into whichever menu it
        // takes for the View menu, and does so lazily, so it can only be taken
        // out again just before the menu is drawn.
        viewMenu.delegate = self

        NSApplication.shared.mainMenu = mainMenu
    }

    static let recentMenuIdentifier = NSUserInterfaceItemIdentifier("recentModules")

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier == Self.recentMenuIdentifier {
            MainActor.assumeIsolated { rebuildRecentMenu(menu) }
            return
        }

        // AppKit's own full-screen item. The player window is a fixed size and
        // refuses macOS full screen, so it only sits there greyed out next to
        // the one that actually opens the stage.
        for item in menu.items where item.action == #selector(NSWindow.toggleFullScreen(_:)) {
            menu.removeItem(item)
        }
    }

    @MainActor
    private func rebuildRecentMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let entries = RecentModules.entries
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: L10n.t("menu.recent.empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(playRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            item.toolTip = entry.url.path
            // The first nine get a number, as the Finder's own list does.
            if index < 9 { item.keyEquivalent = "" }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: L10n.t("menu.recent.clear"),
                               action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func playRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @MainActor in
            PlayerModel.shared.add(urls: [url], playFirst: false)
            PlayerModel.shared.playRecorded(url: url)
        }
    }

    @objc private func clearRecent() {
        Task { @MainActor in RecentModules.clear() }
    }

    @objc private func openModules() {
        Task { @MainActor in PlayerModel.shared.openPanel() }
    }

    /// Mirrors the Tracks button. Both write the same preference, which the
    /// view observes through @AppStorage.
    @objc private func toggleTracker() {
        let visible = !SkinMetrics.trackerVisiblePreference
        UserDefaults.standard.set(visible, forKey: "showTracker")
        trackerMenuItem?.state = visible ? .on : .off
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: Skin.storageKey)
    }

    /// Through `Palette.current` rather than straight at the default: the
    /// setter is what refreshes the cached value the colours are read from, and
    /// writing round it would leave the window a frame behind.
    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let palette = Palette(rawValue: raw) else { return }
        Palette.current = palette
    }

    @objc private func toggleFilter() {
        Task { @MainActor in
            PlayerModel.shared.filterEnabled.toggle()
        }
    }

    @objc private func showAbout() {
        Task { @MainActor in AboutController.shared.present() }
    }

    @objc private func showSettings() {
        Task { @MainActor in SettingsController.shared.present() }
    }

    @objc private func toggleStage() {
        Task { @MainActor in StageController.shared.toggle() }
    }

    @objc private func toggleMiniPlayer() {
        Task { @MainActor in MiniPlayerController.shared.toggle() }
    }

    @objc private func selectVisualizer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: VisualizerStyle.storageKey)
    }
}
