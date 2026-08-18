import SwiftUI
import UniformTypeIdentifiers
import ModRunnerKit

/// The contemporary macOS presentation: system materials and typography, SF
/// Symbols, and the ModRunner palette for anything that carries meaning.
struct NativeSkinView: View {

    static let windowWidth: CGFloat = 640
    private static let baseHeight: CGFloat = 512 + 30

    /// The height the window opens at, before the user has dragged it.
    static func windowHeight(showingTracker: Bool) -> CGFloat {
        showingTracker ? baseHeight + SmoothTrackerView.height + 26 : baseHeight
    }

    /// One row of the module list: the title, its padding, and the gap to the
    /// next row.
    private static let playlistRow: CGFloat = 24
    /// How tall the list is at the height the window opens at.
    private static let playlistHeight: CGFloat = 220
    /// The shortest list worth keeping: three entries, whole. Below that the
    /// list stops being a list, and it scrolls anyway.
    private static let playlistFloor: CGFloat = 3 * playlistRow + 8

    /// How far the window can be dragged shorter than its opening height.
    /// Everything above the module list is laid out at a fixed height, so the
    /// whole allowance comes out of the list.
    static let playlistFlex: CGFloat = playlistHeight - playlistFloor

    static func minimumHeight(showingTracker: Bool) -> CGFloat {
        windowHeight(showingTracker: showingTracker) - playlistFlex
    }

    @ObservedObject var model: PlayerModel
    @AppStorage("showTracker") private var showTracker = true
    @AppStorage(VisualizerStyle.storageKey) private var visualizerName = VisualizerStyle.bars.rawValue
    @State private var isDropTarget = false

    private var visualizer: VisualizerStyle {
        VisualizerStyle(rawValue: visualizerName) ?? .bars
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if showTracker {
                SmoothTrackerView(module: model.module,
                                  block: model.snapshot.block,
                                  line: model.snapshot.line,
                                  progress: model.snapshot.lineProgress)
                    .transition(.opacity)
            }
            meterRow
            transport
            playlist
        }
        .padding(18)
        // The width is the layout's; the height is the window's, and whatever it
        // is, the module list takes up the slack.
        .frame(minWidth: NativeSkinView.windowWidth,
               maxWidth: NativeSkinView.windowWidth,
               maxHeight: .infinity,
               alignment: .top)
        .background(.background)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Brand.orange, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            model.handleDrop(providers)
            return true
        }
        .animation(.easeInOut(duration: 0.2), value: showTracker)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.module?.displayTitle ?? L10n.t("player.noModule"))
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(timeText)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(positionText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                NativeViewOptions(model: model)
            }
        }
    }

    private var subtitle: String {
        guard let module = model.module else { return L10n.t("player.dropHint") }
        var parts: [String] = []
        let annotation = module.annotation
            .split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !annotation.isEmpty, annotation != module.displayTitle { parts.append(annotation) }
        parts.append(module.formatID)
        parts.append(L10n.t("status.tracks", module.numTracks))
        parts.append(L10n.t("status.notes", module.noteCount))
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Meters and statistics

    /// The readings on the left, the visualisation and its picker on the right,
    /// all hung from one line: the row is exactly as tall as the visualiser's
    /// box, and everything in it is aligned to the top of that box.
    private var meterRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                stat(L10n.t("stat.position"), positionText)
                stat(L10n.t("stat.block"), model.module == nil ? "—" : "\(model.snapshot.block)")
                stat(L10n.t("stat.line"), model.module == nil
                     ? "—" : "\(model.snapshot.line) / \(model.snapshot.lineCount)")
                stat(L10n.t("stat.tempo"), "\(model.snapshot.tempo) · \(model.snapshot.ticksPerLine) TPL"
                     + String(format: " · %.0f BPM", model.snapshot.beatsPerMinute))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VisualizerView(style: visualizer,
                           levels: model.snapshot.channelMeters,
                           samples: model.waveform,
                           muted: model.mutedChannels,
                           onToggleMute: { model.toggleMute(channel: $0) },
                           onSolo: { model.soloChannel($0) })

            VisualizerPicker(style: Binding(
                get: { visualizer },
                set: { visualizerName = $0.rawValue }
            ))
        }
        .frame(height: VisualizerView.height)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .monospacedDigit()
        }
    }

    // MARK: - Transport

    private var transport: some View {
        VStack(spacing: 12) {
            Scrubber(value: model.snapshot.progress) { model.seek(fraction: $0) }

            HStack(spacing: 10) {
                TransportButton(symbol: "backward.end.fill",
                                help: L10n.t("tooltip.playPrevious")) { model.playPrevious() }
                TransportButton(symbol: "backward.fill",
                                help: L10n.t("tooltip.previousBlock")) { model.previousPosition() }
                TransportButton(symbol: model.snapshot.isPlaying ? "pause.fill" : "play.fill",
                                prominent: true,
                                help: L10n.t(model.snapshot.isPlaying ? "tooltip.pause" : "tooltip.play")) {
                    model.togglePlay()
                }
                TransportButton(symbol: "stop.fill", help: L10n.t("tooltip.stop")) { model.stop() }
                TransportButton(symbol: "forward.fill",
                                help: L10n.t("tooltip.nextBlock")) { model.nextPosition() }
                TransportButton(symbol: "forward.end.fill",
                                help: L10n.t("tooltip.playNext")) { model.playNext() }

                Spacer(minLength: 12)

                Image(systemName: model.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: $model.volume, in: 0...1)
                    .controlSize(.small)
                    .frame(width: 92)
                    .tint(Brand.orange)

                // The Amiga output filter, off by default.
                Button {
                    model.filterEnabled.toggle()
                } label: {
                    Text("LED")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.filterEnabled
                                         ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: 30, height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(model.filterEnabled
                                      ? AnyShapeStyle(Brand.orange) : AnyShapeStyle(.quaternary))
                        }
                }
                .buttonStyle(.plain)
                .help(model.filterEnabled
                      ? L10n.t("tooltip.filterOn")
                      : L10n.t("tooltip.filterOff"))
            }
        }
    }

    // MARK: - Playlist

    private var playlist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("player.modules"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("button.open")) { model.openPanel() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .help(L10n.t("tooltip.open"))
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.playlist.enumerated()), id: \.element.id) { index, entry in
                        let selected = (model.currentIndex == index)
                        HStack(spacing: 8) {
                            Image(systemName: selected && model.snapshot.isPlaying
                                  ? "speaker.wave.2.fill" : "music.note")
                                .font(.system(size: 10))
                                .foregroundStyle(selected ? AnyShapeStyle(Brand.orange)
                                                          : AnyShapeStyle(.tertiary))
                                .frame(width: 14)
                            Text(entry.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Brand.orange.opacity(0.16) : .clear)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(index: index) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5))
            }

            Text(model.status)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Formatting

    private var positionText: String {
        guard let module = model.module, !module.playSequence.isEmpty else { return "—" }
        return "\(model.snapshot.sequencePosition + 1) / \(module.playSequence.count)"
    }

    private var timeText: String {
        let seconds = Int(model.snapshot.elapsedSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
