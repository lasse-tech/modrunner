import SwiftUI
import UniformTypeIdentifiers
import ModRunnerKit

/// The classic skin: one fixed-width window of bevelled panels, drawn in the
/// project's own colours rather than in the beige the idiom came from.
struct ClassicSkinView: View {

    @ObservedObject var model: PlayerModel
    @State private var isDropTarget = false
    @AppStorage("showTracker") private var showTracker = true

    /// Not read directly — it is here so a change of palette invalidates this
    /// view and every colour below it is looked up again. `Classic` reads the
    /// stored value on each body evaluation, so nothing else has to know.
    @AppStorage(Palette.storageKey) private var paletteName = Palette.ember.rawValue

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(
                title: titleBarText,
                onClose: { keyWindow?.performClose(nil) },
                onMinimise: { keyWindow?.miniaturize(nil) },
                // The zoom gadget opens the full-screen stage, so both skins
                // reach it the same way: green gadget in the native window,
                // zoom gadget here. The tracker panel is the Tracks button.
                onZoom: { ViewOptions.toggleStage() },
                onDepth: { keyWindow?.orderBack(nil) }
            )

            VStack(spacing: 8) {
                songPanel
                statusPanel
                if showTracker {
                    TrackerView(module: model.module,
                                block: model.snapshot.block,
                                line: model.snapshot.line)
                }
                metersPanel
                positionPanel
                transportPanel
                ClassicViewOptions(model: model)
                playlistPanel
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(Classic.face)
        }
        .background(Classic.face)
        .overlay(alignment: .bottomTrailing) {
            // The sizing gadget sits in the frame's bottom right corner, where
            // the window is dragged taller. AppKit does the dragging; this is
            // the part that says so.
            ZStack {
                BevelBox(style: .raised, fill: Classic.face)
                SizerGlyph()
            }
            .frame(width: 26, height: 22)
            .allowsHitTesting(false)
        }
        .overlay {
            if isDropTarget {
                Rectangle()
                    .strokeBorder(Classic.highlight, lineWidth: 3)
                    .background(Classic.highlight.opacity(0.14))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            model.handleDrop(providers)
            return true
        }
        // Window sizing and chrome are handled centrally by RootView. The height
        // is the window's, and the module list absorbs whatever it turns out to
        // be.
        .frame(minWidth: SkinMetrics.windowWidth,
               maxWidth: SkinMetrics.windowWidth,
               maxHeight: .infinity,
               alignment: .top)
    }

    /// The skin hides the system window buttons, so the drawn gadgets act on
    /// the window directly.
    private var keyWindow: NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
    }

    private var titleBarText: String {
        guard let module = model.module else { return "ModRunner" }
        return "ModRunner — \(module.displayTitle)"
    }

    // MARK: - Panels

    private var songPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClassicReadout(text: model.module?.displayTitle ?? L10n.t("player.noModuleDashed"))

            if let annotation = model.module?.annotation, !annotation.isEmpty {
                ScrollView {
                    Text(annotation)
                        .font(Classic.font(10))
                        .foregroundColor(Classic.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .frame(height: 34)
                .classicBevel(.recessed, fill: Classic.sunken, inset: Classic.bevel + 1)
            }
        }
        .classicBevel(.raised)
    }

    /// The captions stay in tracker notation in every language — POS, BLOCK,
    /// LINE, TEMPO, BPM. That is a decision the localisation files already
    /// record, and TIME belongs to the same strip.
    private var statusPanel: some View {
        HStack(spacing: 6) {
            ClassicField(caption: "POS", value: positionText)
            ClassicField(caption: "BLOCK", value: blockText)
            ClassicField(caption: "LINE", value: lineText)
            ClassicField(caption: "TEMPO",
                         value: "\(model.snapshot.tempo)/\(model.snapshot.ticksPerLine)")
            ClassicField(caption: "BPM",
                         value: String(format: "%.0f", model.snapshot.beatsPerMinute))
            ClassicField(caption: "TIME", value: timeText)
        }
        .classicBevel(.raised)
    }

    private var metersPanel: some View {
        VStack(spacing: 4) {
            ForEach(0..<max(4, model.snapshot.channelMeters.count), id: \.self) { channel in
                ClassicVUMeter(
                    label: "CH\(channel + 1)",
                    level: channel < model.snapshot.channelMeters.count
                        ? model.snapshot.channelMeters[channel] : 0
                )
            }
        }
        .classicBevel(.recessed, fill: Classic.faceDark)
    }

    private var positionPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("player.songPosition"))
                .font(Classic.font(9))
                .foregroundColor(Classic.caption)
            ClassicSlider(value: model.snapshot.progress) { fraction in
                model.seek(fraction: fraction)
            }
        }
        .classicBevel(.raised)
    }

    /// One row, and it stays one row. The buttons are fixed boxes and the
    /// labels never wrap: a transport that reflows onto a second line loses
    /// the thing that makes it readable at a glance.
    private var transportPanel: some View {
        HStack(spacing: 5) {
            ClassicButton(label: "|<", width: 38,
                          help: L10n.t("tooltip.playPrevious")) { model.playPrevious() }
            ClassicButton(label: "<<", width: 38,
                          help: L10n.t("tooltip.previousBlock")) { model.previousPosition() }
            ClassicButton(label: model.snapshot.isPlaying ? "||" : ">", width: 38,
                          help: L10n.t(model.snapshot.isPlaying ? "tooltip.pause" : "tooltip.play")) {
                model.togglePlay()
            }
            ClassicButton(label: "[]", width: 38, help: L10n.t("tooltip.stop")) { model.stop() }
            ClassicButton(label: ">>", width: 38,
                          help: L10n.t("tooltip.nextBlock")) { model.nextPosition() }
            ClassicButton(label: ">|", width: 38,
                          help: L10n.t("tooltip.playNext")) { model.playNext() }

            Spacer(minLength: 4)

            // Fixed size: the caption is one word, and letting it wrap breaks it
            // across two lines inside a 22-point strip.
            Text(L10n.t("player.volume"))
                .font(Classic.font(9))
                .foregroundColor(Classic.caption)
                .fixedSize()
            ClassicVolumeSlider(value: $model.volume)
                .frame(width: 80)

            ClassicButton(label: L10n.t("button.tracks"), width: 66, on: showTracker,
                          help: L10n.t("tooltip.tracks")) { showTracker.toggle() }
            ClassicButton(label: L10n.t("button.load"), width: 66,
                          help: L10n.t("tooltip.open")) { model.openPanel() }
        }
        .classicBevel(.raised)
    }

    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("player.modulesDrop"))
                .font(Classic.font(9))
                .foregroundColor(Classic.caption)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.playlist.enumerated()), id: \.element.id) { index, entry in
                        let selected = (model.currentIndex == index)
                        Text(entry.title)
                            .font(Classic.font(11))
                            .foregroundColor(selected ? Classic.highlightText : Classic.textDim)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Classic.highlight : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(index: index) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .classicBevel(.recessed, fill: Classic.sunken, inset: Classic.bevel + 1)

            ClassicReadout(text: model.status, color: Classic.textDim)
        }
        .classicBevel(.raised)
    }

    // MARK: - Formatting

    private var positionText: String {
        guard let module = model.module, !module.playSequence.isEmpty else { return "--/--" }
        return String(format: "%02d/%02d", model.snapshot.sequencePosition + 1, module.playSequence.count)
    }

    private var blockText: String {
        model.module == nil ? "--" : String(format: "%02d", model.snapshot.block)
    }

    private var lineText: String {
        model.module == nil ? "--" : String(format: "%02d/%02d", model.snapshot.line, model.snapshot.lineCount)
    }

    private var timeText: String {
        let seconds = Int(model.snapshot.elapsedSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
