import SwiftUI

/// The full-screen presentation: the pattern, as big as the display allows,
/// scrolling under a fixed playhead. Everything else is a thin strip of
/// information above and below it, and both strips fade away while the mouse is
/// still.
///
/// Like the player window, the stage comes in both skins and follows the same
/// setting, so switching skins mid-song changes the stage too.
struct StageView: View {

    @ObservedObject var model: PlayerModel
    var onDismiss: () -> Void = {}

    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    @State private var chromeVisible = true
    @State private var hideWorkItem: DispatchWorkItem?

    private var skin: Skin { Skin(rawValue: skinName) ?? .native }

    /// Margin around the pattern, so the notation does not run into the bezel.
    static let margin: CGFloat = 28

    var body: some View {
        Group {
            switch skin {
            case .amiga:
                AmigaStageView(model: model, chromeVisible: chromeVisible)
            case .native:
                NativeStageView(model: model, chromeVisible: chromeVisible)
            }
        }
        .id(language)
        .animation(.easeInOut(duration: 0.25), value: chromeVisible)
        // Any sign of life brings the strips back; the pattern itself never
        // moves, so nothing jumps when they go away again.
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        .onAppear { wakeChrome() }
        .onDisappear { hideWorkItem?.cancel() }
    }

    private func wakeChrome() {
        hideWorkItem?.cancel()
        chromeVisible = true

        let work = DispatchWorkItem { chromeVisible = false }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: - Sizing

    /// The type size is bounded twice over: wide enough modules run out of
    /// width, narrow ones would otherwise grow until only a handful of lines
    /// were left on screen. Whichever bound bites first wins.
    static func layout(for size: CGSize, tracks: Int) -> TrackerLayout {
        let tracks = max(1, min(tracks, 16))

        // A cell is "C-3 01 0A05" — twelve characters and a gap — and the line
        // number column adds about five more.
        let columns = 5.0 + Double(tracks) * 13.5
        let advance = 0.62     // width of one character, relative to its size
        let usable = Double(size.width) - 2 * margin - 4 * Double(Amiga.bevel)
        let byWidth = usable / (columns * advance)

        // Height left for the pattern once both strips have taken their share.
        let forRows = Double(size.height) - 2 * margin - chromeHeight
        // Around twenty lines is what a tracker showed, and what makes the
        // playhead read as a position in the pattern rather than as the whole of
        // it.
        let byHeight = forRows / (Double(targetRows) * rowFactor)

        let fontSize = min(byWidth, byHeight).clamped(to: 9...34)
        let rowHeight = (fontSize * rowFactor).rounded()
        let headerHeight = (fontSize * 1.1).rounded()
        let rows = max(7, Int((forRows - Double(headerHeight)) / Double(rowHeight)))

        return TrackerLayout(
            rowHeight: rowHeight,
            fontSize: fontSize,
            headerHeight: headerHeight,
            // An odd number of rows, so the playhead sits exactly in the middle.
            context: (rows - 1) / 2,
            maxTracks: tracks,
            showsBevel: false,
            tintsColumns: true
        )
    }

    /// What the native tracker needs to know, which is not a `TrackerLayout`:
    /// it measures itself in whole rows rather than in context lines.
    struct NativeLayout {
        var rowHeight: CGFloat
        var fontSize: CGFloat
        var rows: Int
        var tracks: Int
    }

    /// The same reasoning as `layout(for:tracks:)`, for the native tracker.
    static func nativeLayout(for size: CGSize, tracks: Int) -> NativeLayout {
        let tracks = max(1, min(tracks, 16))
        let columns = 5.0 + Double(tracks) * 13.5
        let usable = Double(size.width) - 2 * margin - 40
        let byWidth = usable / (columns * 0.62)

        let forRows = Double(size.height) - 2 * margin - chromeHeight
        let byHeight = forRows / (Double(targetRows) * nativeRowFactor)

        let fontSize = min(byWidth, byHeight).clamped(to: 9...30)
        let rowHeight = (fontSize * nativeRowFactor).rounded()
        var rows = max(7, Int(forRows / Double(rowHeight)))
        if rows.isMultiple(of: 2) { rows -= 1 }     // odd, so the playhead centres

        return NativeLayout(rowHeight: rowHeight, fontSize: fontSize, rows: rows, tracks: tracks)
    }

    private static let targetRows = 21
    private static let rowFactor = 1.45
    private static let nativeRowFactor = 1.55
    /// Height taken by the two strips, their spacing and the tracker's frame.
    private static let chromeHeight = 24.0 + 96.0 + 74.0
}

/// Text shown on both stages. Formatting a position is not a matter of skin.
@MainActor
enum StageText {

    static func position(_ model: PlayerModel) -> String {
        guard let module = model.module, !module.playSequence.isEmpty else { return "--/--" }
        return String(format: "%02d/%02d", model.snapshot.sequencePosition + 1, module.playSequence.count)
    }

    static func block(_ model: PlayerModel) -> String {
        model.module == nil ? "--" : String(format: "%02d", model.snapshot.block)
    }

    static func line(_ model: PlayerModel) -> String {
        model.module == nil
            ? "--" : String(format: "%02d/%02d", model.snapshot.line, model.snapshot.lineCount)
    }

    static func time(_ model: PlayerModel) -> String {
        let seconds = Int(model.snapshot.elapsedSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func title(_ model: PlayerModel) -> String {
        model.module?.displayTitle ?? L10n.t("player.noModuleDashed")
    }

    /// The module's own first line of annotation, when it says something the
    /// title does not.
    static func annotation(_ model: PlayerModel) -> String? {
        guard let annotation = model.module?.annotation else { return nil }
        let line = annotation.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line, !line.isEmpty, line != model.module?.displayTitle else { return nil }
        return line
    }

    static func meterCount(_ model: PlayerModel) -> Int {
        min(max(4, model.snapshot.channelMeters.count), 8)
    }

    static func level(_ model: PlayerModel, channel: Int) -> Float {
        channel < model.snapshot.channelMeters.count ? model.snapshot.channelMeters[channel] : 0
    }
}

// MARK: - Workbench

/// The stage in the Workbench idiom: the pattern in a recessed bevel on a
/// Workbench screen, with drawn gadgets above and below.
struct AmigaStageView: View {

    @ObservedObject var model: PlayerModel
    var chromeVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let layout = StageView.layout(for: geo.size, tracks: model.module?.numTracks ?? 4)

            VStack(spacing: 12) {
                header
                    .opacity(chromeVisible ? 1 : 0)

                TrackerView(module: model.module,
                            block: model.snapshot.block,
                            line: model.snapshot.line,
                            layout: layout)
                    .amigaBevel(.recessed, fill: Amiga.lightGrey, inset: Amiga.bevel + 2)
                    .frame(maxHeight: .infinity)

                footer
                    .opacity(chromeVisible ? 1 : 0)
            }
            .padding(StageView.margin)
        }
        .background(Amiga.screen)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(StageText.title(model))
                    .font(Amiga.boldFont(22))
                    .foregroundColor(Amiga.white)
                    .lineLimit(1)
                if let annotation = StageText.annotation(model) {
                    Text(annotation)
                        .font(Amiga.font(12))
                        .foregroundColor(Amiga.lightGrey)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                AmigaField(caption: "POS", value: StageText.position(model))
                AmigaField(caption: "BLOCK", value: StageText.block(model))
                AmigaField(caption: "LINE", value: StageText.line(model))
                AmigaField(caption: "BPM", value: String(format: "%.0f", model.snapshot.beatsPerMinute))
                AmigaField(caption: "TIME", value: StageText.time(model))
            }
            .frame(width: 420)
            .amigaBevel(.raised)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            AmigaButton(label: model.snapshot.isPlaying ? "||" : ">", width: 44) { model.togglePlay() }
            AmigaButton(label: "<<", width: 38) { model.previousPosition() }
            AmigaButton(label: ">>", width: 38) { model.nextPosition() }

            // The meters carry a GeometryReader, so they take every point they
            // are offered. Without a ceiling they push the key hints off the
            // end of the strip.
            HStack(spacing: 8) {
                ForEach(0..<StageText.meterCount(model), id: \.self) { channel in
                    AmigaVUMeter(label: "\(channel + 1)",
                                 level: StageText.level(model, channel: channel))
                        .frame(width: 92)
                }
            }
            .frame(height: 14)

            Spacer(minLength: 8)

            Text(L10n.t("stage.keys"))
                .font(Amiga.font(11))
                .foregroundColor(Amiga.darkGrey)
                .fixedSize()
                .padding(.trailing, 4)
        }
        .amigaBevel(.raised, inset: Amiga.bevel + 4)
    }
}

// MARK: - Native

/// The stage in the contemporary idiom: the smooth-scrolling tracker on a dark
/// ground, SF Symbols for transport, and the strips floating over it.
struct NativeStageView: View {

    @ObservedObject var model: PlayerModel
    var chromeVisible: Bool

    /// Darker than the player window: on a full screen the app is the room, and
    /// system chrome colours would glow.
    private static let ground = Color(red: 0x0B / 255, green: 0x09 / 255, blue: 0x08 / 255)

    var body: some View {
        GeometryReader { geo in
            let metrics = StageView.nativeLayout(for: geo.size, tracks: model.module?.numTracks ?? 4)

            VStack(spacing: 18) {
                header
                    .opacity(chromeVisible ? 1 : 0)

                SmoothTrackerView(module: model.module,
                                  block: model.snapshot.block,
                                  line: model.snapshot.line,
                                  progress: model.snapshot.lineProgress,
                                  rowHeight: metrics.rowHeight,
                                  fontSize: metrics.fontSize,
                                  visibleRows: metrics.rows,
                                  maxTracks: metrics.tracks)
                    .frame(maxHeight: .infinity)

                footer
                    .opacity(chromeVisible ? 1 : 0)
            }
            .padding(StageView.margin)
        }
        .background(Self.ground)
        // The ground is nearly black whatever the Mac is set to, so the
        // semantic text colours have to be read against a dark appearance —
        // otherwise everything secondary turns dark-on-dark in light mode.
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(StageText.title(model))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let annotation = StageText.annotation(model) {
                    Text(annotation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 22) {
                stat(L10n.t("stat.position"), StageText.position(model))
                stat("BLOCK", StageText.block(model))
                stat("LINE", StageText.line(model))
                stat("BPM", String(format: "%.0f", model.snapshot.beatsPerMinute))
                Text(StageText.time(model))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Scrubber(value: model.snapshot.progress) { model.seek(fraction: $0) }

            HStack(spacing: 12) {
                TransportButton(symbol: "backward.fill") { model.previousPosition() }
                TransportButton(symbol: model.snapshot.isPlaying ? "pause.fill" : "play.fill",
                                prominent: true) { model.togglePlay() }
                TransportButton(symbol: "forward.fill") { model.nextPosition() }

                ChannelMeters(levels: model.snapshot.channelMeters,
                              muted: model.mutedChannels,
                              onToggleMute: { model.toggleMute(channel: $0) },
                              onSolo: { model.soloChannel($0) },
                              height: 44)
                    .padding(.leading, 10)

                Spacer(minLength: 12)

                Text(L10n.t("stage.keys"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
