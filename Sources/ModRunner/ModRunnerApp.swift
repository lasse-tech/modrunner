import SwiftUI
import AppKit

/// The window is built by hand rather than through a SwiftUI `Window` scene.
/// The Amiga title bar replaces the macOS one, and a scene that has its standard
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {

    // MARK: - Remembering where the window was

    /// AppKit nudges the window about while it is being set up. Saving during
    /// that would overwrite the stored position with an interim value before it
    /// has even been read back, so saving starts once the position is restored.
    private var positionRestored = false

    func windowDidMove(_ notification: Notification) {
        guard positionRestored, let window = notification.object as? NSWindow else { return }
        WindowChrome.saveOrigin(of: window, for: Skin.current)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowChrome.saveOrigin(of: window, for: Skin.current)
    }

    /// Keeps the menu's tick mark in step when the Tracks button is used.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTracker) {
            menuItem.state = AmigaSkinView.trackerVisiblePreference ? .on : .off
        }
        if menuItem.action == #selector(selectSkin(_:)),
           let raw = menuItem.representedObject as? String {
            menuItem.state = (Skin.current.rawValue == raw) ? .on : .off
        }
        if menuItem.action == #selector(selectVisualizer(_:)),
           let raw = menuItem.representedObject as? String {
            menuItem.state = (VisualizerStyle.current.rawValue == raw) ? .on : .off
        }
        return true
    }

    private var window: NSWindow?
    private var trackerMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

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
        // Start at whichever size matches the stored skin and tracker
        // preference, so the window does not visibly resize itself a moment
        // after opening.
        let size = NSSize(width: RootView.initialSize().width,
                          height: RootView.initialSize().height)
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
        // the Workbench title bar.
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
            guard let window = self?.window else { return }
            WindowChrome.apply(to: window)
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
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ModRunner",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ModRunner",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ModRunner",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let tracker = NSMenuItem(title: "Show Tracker",
                                 action: #selector(toggleTracker), keyEquivalent: "t")
        tracker.target = self
        tracker.state = AmigaSkinView.trackerVisiblePreference ? .on : .off
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

        viewMenu.addItem(.separator())

        // Visualisations continue the number-key run after the skins.
        for (index, style) in VisualizerStyle.allCases.enumerated() {
            let item = NSMenuItem(title: style.title,
                                  action: #selector(selectVisualizer(_:)),
                                  keyEquivalent: "\(Skin.allCases.count + index + 1)")
            item.target = self
            item.representedObject = style.rawValue
            item.state = (VisualizerStyle.current == style) ? .on : .off
            viewMenu.addItem(item)
        }

        viewMenuItem.submenu = viewMenu
        trackerMenuItem = tracker

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let open = NSMenuItem(title: "Open…", action: #selector(openModules), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        mainMenu.addItem(viewMenuItem)

        // A Window menu, so the standard shortcuts still work in the Workbench
        // skin, where the system window buttons are hidden.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimise",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openModules() {
        Task { @MainActor in PlayerModel.shared.openPanel() }
    }

    /// Mirrors the Tracks button. Both write the same preference, which the
    /// view observes through @AppStorage.
    @objc private func toggleTracker() {
        let visible = !AmigaSkinView.trackerVisiblePreference
        UserDefaults.standard.set(visible, forKey: "showTracker")
        trackerMenuItem?.state = visible ? .on : .off
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: Skin.storageKey)
    }

    @objc private func selectVisualizer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: VisualizerStyle.storageKey)
    }
}
