import SwiftUI
import AppKit
import ModRunnerKit

/// The brand mark: six bars in the Fibonacci ratio 1 : 2 : 3 : 5 : 8 : 13, each
/// divided into exactly that many segments. Drawn rather than loaded, so it is
/// crisp at any size and needs no asset in the bundle.
struct FibonacciMark: View {

    var body: some View {
        Canvas { context, size in
            // Proportions taken from brand/svg/mark.svg.
            let columns = 6.0, barWidth = 112.64, barPitch = 143.36
            let segmentHeight = 43.1, segmentPitch = 59.87
            let artWidth = barPitch * (columns - 1) + barWidth      // 829.44
            let artHeight = segmentPitch * 12 + segmentHeight       // 761.5

            let scale = min(size.width / artWidth, size.height / artHeight)
            let originX = (size.width - artWidth * scale) / 2
            let originY = (size.height - artHeight * scale) / 2

            for (index, segments) in Self.segments.enumerated() {
                let x = originX + barPitch * Double(index) * scale
                for step in 0..<segments {
                    let y = originY + (artHeight - segmentHeight - segmentPitch * Double(step)) * scale
                    let rect = CGRect(x: x, y: y,
                                      width: barWidth * scale,
                                      height: segmentHeight * scale)
                    context.fill(Path(rect), with: .color(Self.colours[index]))
                }
            }
        }
        .aspectRatio(829.44 / 761.5, contentMode: .fit)
    }

    private static let segments = [1, 2, 3, 5, 8, 13]
    private static let colours = [Brand.blue, Brand.blue,
                                  Brand.salmon, Brand.salmon,
                                  Brand.orange, Brand.orange]
}

/// The palette of the About panel. Darker and quieter than the app's own
/// surfaces: it is a page about the program, not part of the instrument.
private enum About {
    static let card       = Color(red: 0x17 / 255, green: 0x13 / 255, blue: 0x0F / 255)
    static let footer     = Color(red: 0x12 / 255, green: 0x0F / 255, blue: 0x0D / 255)
    static let chip       = Color(red: 0x23 / 255, green: 0x1D / 255, blue: 0x18 / 255)
    static let chipBorder = Color(red: 0x2F / 255, green: 0x27 / 255, blue: 0x21 / 255)
    static let rule       = Color(red: 0x24 / 255, green: 0x1E / 255, blue: 0x1A / 255)
    static let text       = Brand.light
    static let muted      = Color(red: 0xA2 / 255, green: 0x98 / 255, blue: 0x92 / 255)
    static let subdued    = Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x78 / 255)
    static let dim        = Color(red: 0x6F / 255, green: 0x65 / 255, blue: 0x5F / 255)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let width: CGFloat = 640
}

/// The About panel.
struct AboutView: View {

    var onClose: () -> Void = {}
    var onLicences: () -> Void = {}

    /// Read so the panel is rebuilt when the language changes: the window is
    /// reused, and L10n is fetched imperatively where SwiftUI cannot see it.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            masthead
            dashedRule
            columns
            credits
            footer
        }
        .frame(width: About.width)
        .background(About.card)
        .foregroundStyle(About.text)
        .id(language)
    }

    // MARK: - Masthead

    /// The panel has no title bar; the masthead above the rule is what it is
    /// dragged by, so the drag area sits under it and nothing in it takes a
    /// click of its own.
    private var masthead: some View {
        ZStack {
            WindowDragArea()
            mastheadContent.allowsHitTesting(false)
        }
    }

    private var mastheadContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                FibonacciMark()
                    .frame(width: 80, height: 80)
                    .padding(.bottom, -10)

                // "Space Grotesk" is the brand face and is not on every Mac;
                // the system face at the same weight and tracking carries the
                // lockup well enough.
                (Text("Mod").foregroundColor(About.text)
                 + Text("Runner").foregroundColor(Brand.orange))
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.6)
            }

            Text(L10n.t("about.tagline"))
                .font(.system(size: 13))
                .foregroundStyle(About.muted)
                .lineSpacing(3)
                // Without this the text is offered a single line and truncates
                // rather than wrapping inside its 400 points.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400, alignment: .leading)
                .padding(.top, 18)

            HStack(spacing: 8) {
                chip(L10n.t("about.chip.unreleased"), highlighted: true)
                chip("macOS 13+")
                chip("SWIFT 6.0")
                chip(L10n.t("about.chip.noDependencies"))
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            FibonacciMark()
                .frame(width: 420, height: 420)
                .opacity(0.09)
                .offset(x: 96, y: -40)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private func chip(_ text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(About.mono(10))
            .tracking(0.8)
            .foregroundStyle(highlighted ? About.text : About.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(About.chip))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(About.chipBorder, lineWidth: 1))
    }

    /// The orange dashes that run under the masthead, as on the brand sheet.
    private var dashedRule: some View {
        GeometryReader { geo in
            Path { path in
                var x = 0.0
                while x < geo.size.width {
                    path.addRect(CGRect(x: x, y: 0, width: 10, height: 6))
                    x += 14
                }
            }
            .fill(Brand.orange)
        }
        .frame(height: 6)
    }

    // MARK: - Formats and accuracy

    private var columns: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(L10n.t("about.formats"))
            VStack(alignment: .leading, spacing: 9) {
                format(L10n.t("about.formats.octamed.prefix"), ".med",
                       L10n.t("about.formats.octamed.suffix"))
                format(L10n.t("about.formats.protracker.prefix"), ".mod",
                       L10n.t("about.formats.protracker.suffix"))
                Text(L10n.t("about.formats.note"))
                    .font(.system(size: 13))
                    .foregroundStyle(About.subdued)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(About.mono(10))
            .tracking(1.6)
            .foregroundStyle(About.dim)
    }

    /// A format line, with the file extension set in the monospaced face.
    private func format(_ prefix: String, _ extension: String, _ suffix: String) -> some View {
        (Text(prefix + " ")
         + Text(`extension`).font(About.mono(12))
         + Text(suffix))
            .font(.system(size: 13))
            .foregroundStyle(About.text)
            .lineSpacing(2)
    }

    // MARK: - Credits

    private var credits: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(L10n.t("about.credits"))

            // Two by two, as on the sheet. Names are names in any language;
            // only what each is credited for is translated.
            Grid(alignment: .topLeading, horizontalSpacing: 32, verticalSpacing: 12) {
                GridRow {
                    credit("Teijo Kinnunen", L10n.t("about.credit.kinnunen"))
                    credit("Ed Wiles / RBF Software", L10n.t("about.credit.wiles"))
                }
                GridRow {
                    credit(L10n.t("about.credit.openmpt.name"), L10n.t("about.credit.openmpt"))
                    credit("Claudio Matsuoka, Hipolito Carraro Jr", L10n.t("about.credit.libxmp"))
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 32)
        .overlay(alignment: .top) {
            Rectangle().fill(About.rule).frame(height: 1).padding(.horizontal, 40)
        }
        .padding(.top, 26)
    }

    private func credit(_ name: String, _ role: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
            Text(role)
                .font(.system(size: 13))
                .foregroundStyle(About.subdued)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("© 2026 incūdex, Lars Gossard")
                Text("Apache License 2.0")
            }
            .font(About.mono(11))
            .foregroundStyle(About.dim)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onLicences) {
                    Text(L10n.t("about.button.licences"))
                        .font(.system(size: 13))
                        .foregroundStyle(About.muted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(About.chipBorder, lineWidth: 1))
                }
                .help(L10n.t("tooltip.licences"))

                Button(action: onClose) {
                    Text(L10n.t("about.button.close"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(About.card)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.orange))
                }
                // Esc, because the panel is a dialog and has no title bar of
                // its own to close from.
                .keyboardShortcut(.cancelAction)
                .help(L10n.t("tooltip.aboutClose"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .background(About.footer)
        .overlay(alignment: .top) {
            Rectangle().fill(About.rule).frame(height: 1)
        }
    }
}

/// One About window, reused.
@MainActor
final class AboutController {

    static let shared = AboutController()

    private var window: NSWindow?

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = AboutView(
            onClose: { [weak self] in self?.dismiss() },
            onLicences: { Self.openLicences() }
        )

        // ignoresSafeArea, or SwiftUI insets the panel below the (hidden) title
        // bar and leaves an empty band above the mark. The height is then
        // measured at the panel's own width, so the text has wrapped before
        // anything asks how tall it is.
        let hosting = NSHostingView(rootView: view.ignoresSafeArea())
        hosting.frame.size = NSSize(width: About.width, height: 10)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame.size = NSSize(width: About.width, height: hosting.fittingSize.height)

        // Borderless rather than a titled window with its chrome hidden: a title
        // bar would add its own height to the frame and leave a strip of empty
        // window below the footer.
        let window = ModRunnerWindow(contentRect: NSRect(origin: .zero, size: hosting.frame.size),
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
        window.backgroundColor = NSColor(calibratedRed: 0x17 / 255, green: 0x13 / 255,
                                         blue: 0x0F / 255, alpha: 1)
        // Dragged by its masthead, not by its background: a window that moves by
        // its background swallows the mouse-moved events, and the two buttons in
        // the footer would never show their help.
        window.isMovableByWindowBackground = false
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    /// The notices as published, rather than a copy that may or may not sit
    /// next to the running app.
    private static let noticesURL = URL(
        string: "https://github.com/lasse-tech/modrunner/blob/main/THIRD-PARTY-NOTICES.md")

    private static func openLicences() {
        guard let noticesURL else { return }
        NSWorkspace.shared.open(noticesURL)
    }
}
