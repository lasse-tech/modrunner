import SwiftUI
import UniformTypeIdentifiers

struct AmigaSkinView: View {

    /// The window is a fixed size, as Amiga tool windows were, but it has two
    /// sizes: with and without the tracker panel.
    static let windowWidth: CGFloat = 560
    private static let baseHeight: CGFloat = 486 + AmigaViewOptions.height

    static func windowHeight(showingTracker: Bool) -> CGFloat {
        showingTracker ? baseHeight + TrackerView.panelHeight + 8 : baseHeight
    }

    /// Whether the tracker panel was visible when the app last ran.
    static var trackerVisiblePreference: Bool {
        UserDefaults.standard.object(forKey: "showTracker") as? Bool ?? true
    }

    @ObservedObject var model: PlayerModel
    @State private var isDropTarget = false
    @AppStorage("showTracker") private var showTracker = true

    var body: some View {
        VStack(spacing: 0) {
            AmigaTitleBar(
                title: titleBarText,
                onClose: { keyWindow?.performClose(nil) },
                onMinimise: { keyWindow?.miniaturize(nil) },
                // The Amiga zoom gadget flipped between two window sizes; ours
                // are "with tracker" and "without".
                onZoom: { showTracker.toggle() },
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
                AmigaViewOptions(model: model)
                playlistPanel
            }
            .padding(8)
            .background(Amiga.grey)
        }
        .background(Amiga.grey)
        .overlay {
            if isDropTarget {
                Rectangle()
                    .strokeBorder(Amiga.white, lineWidth: 3)
                    .background(Amiga.blue.opacity(0.18))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            model.handleDrop(providers)
            return true
        }
        // Window sizing and chrome are handled centrally by RootView.
        .frame(width: AmigaSkinView.windowWidth,
               height: AmigaSkinView.windowHeight(showingTracker: showTracker),
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
            AmigaReadout(text: model.module?.displayTitle ?? L10n.t("player.noModuleDashed"))

            if let annotation = model.module?.annotation, !annotation.isEmpty {
                ScrollView {
                    Text(annotation)
                        .font(Amiga.font(10))
                        .foregroundColor(Amiga.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .frame(height: 34)
                .amigaBevel(.recessed, fill: Amiga.lightGrey, inset: Amiga.bevel + 1)
            }
        }
        .amigaBevel(.raised)
    }

    private var statusPanel: some View {
        HStack(spacing: 6) {
            AmigaField(caption: "POS", value: positionText)
            AmigaField(caption: "BLOCK", value: blockText)
            AmigaField(caption: "LINE", value: lineText)
            AmigaField(caption: "TEMPO", value: "\(model.snapshot.tempo)/\(model.snapshot.ticksPerLine)")
            AmigaField(caption: "BPM", value: String(format: "%.0f", model.snapshot.beatsPerMinute))
            AmigaField(caption: "TIME", value: timeText)
        }
        .amigaBevel(.raised)
    }

    private var metersPanel: some View {
        VStack(spacing: 4) {
            ForEach(0..<max(4, model.snapshot.channelMeters.count), id: \.self) { channel in
                AmigaVUMeter(
                    label: "CH\(channel + 1)",
                    level: channel < model.snapshot.channelMeters.count
                        ? model.snapshot.channelMeters[channel] : 0
                )
            }
        }
        .amigaBevel(.recessed, fill: Amiga.grey)
    }

    private var positionPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("player.songPosition"))
                .font(Amiga.font(9))
                .foregroundColor(Amiga.black)
            AmigaSlider(value: model.snapshot.progress) { fraction in
                model.seek(fraction: fraction)
            }
        }
        .amigaBevel(.raised)
    }

    private var transportPanel: some View {
        HStack(spacing: 6) {
            AmigaButton(label: "|<", width: 38) { model.playPrevious() }
            AmigaButton(label: "<<", width: 38) { model.previousPosition() }
            AmigaButton(label: model.snapshot.isPlaying ? "||" : ">", width: 44) { model.togglePlay() }
            AmigaButton(label: "[]", width: 38) { model.stop() }
            AmigaButton(label: ">>", width: 38) { model.nextPosition() }
            AmigaButton(label: ">|", width: 38) { model.playNext() }

            Spacer(minLength: 4)

            Text(L10n.t("player.volume"))
                .font(Amiga.font(9))
                .foregroundColor(Amiga.black)
            AmigaVolumeSlider(value: $model.volume)
                .frame(width: 90)

            AmigaButton(label: L10n.t("button.tracks"), width: 66) { showTracker.toggle() }
            AmigaButton(label: L10n.t("button.load"), width: 62) { model.openPanel() }
        }
        .amigaBevel(.raised)
    }

    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("player.modulesDrop"))
                .font(Amiga.font(9))
                .foregroundColor(Amiga.black)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.playlist.enumerated()), id: \.element.id) { index, entry in
                        let selected = (model.currentIndex == index)
                        Text(entry.title)
                            .font(Amiga.font(11))
                            .foregroundColor(selected ? Amiga.white : Amiga.black)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Amiga.blue : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(index: index) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .amigaBevel(.recessed, fill: Amiga.lightGrey, inset: Amiga.bevel + 1)

            AmigaReadout(text: model.status, color: Amiga.black)
        }
        .amigaBevel(.raised)
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
