import SwiftUI
import UniformTypeIdentifiers

/// The contemporary macOS presentation: system materials and typography, SF
/// Symbols, and the ModRunner palette for anything that carries meaning.
struct NativeSkinView: View {

    static let windowWidth: CGFloat = 640
    private static let baseHeight: CGFloat = 512

    static func windowHeight(showingTracker: Bool) -> CGFloat {
        showingTracker ? baseHeight + SmoothTrackerView.height + 26 : baseHeight
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
        .frame(width: NativeSkinView.windowWidth,
               height: NativeSkinView.windowHeight(showingTracker: showTracker))
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
                Text(model.module?.displayTitle ?? "No module")
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(timeText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(positionText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var subtitle: String {
        guard let module = model.module else { return "Drop a module or a folder here" }
        var parts: [String] = []
        let annotation = module.annotation
            .split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !annotation.isEmpty, annotation != module.displayTitle { parts.append(annotation) }
        parts.append(module.formatID)
        parts.append("\(module.numTracks) tracks")
        parts.append("\(module.noteCount) notes")
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Meters and statistics

    private var meterRow: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VisualizerView(style: visualizer,
                           levels: model.snapshot.channelMeters,
                           samples: model.waveform,
                           muted: model.mutedChannels,
                           onToggleMute: { model.toggleMute(channel: $0) },
                           onSolo: { model.soloChannel($0) })

            VStack(alignment: .leading, spacing: 6) {
                stat("Position", positionText)
                stat("Block", model.module == nil ? "—" : "\(model.snapshot.block)")
                stat("Line", model.module == nil
                     ? "—" : "\(model.snapshot.line) / \(model.snapshot.lineCount)")
                stat("Tempo", "\(model.snapshot.tempo) · \(model.snapshot.ticksPerLine) TPL"
                     + String(format: " · %.0f BPM", model.snapshot.beatsPerMinute))
            }
            .font(.system(size: 11))

            Spacer(minLength: 0)

            VisualizerPicker(style: Binding(
                get: { visualizer },
                set: { visualizerName = $0.rawValue }
            ))
        }
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
                TransportButton(symbol: "backward.end.fill") { model.playPrevious() }
                TransportButton(symbol: "backward.fill") { model.previousPosition() }
                TransportButton(symbol: model.snapshot.isPlaying ? "pause.fill" : "play.fill",
                                prominent: true) { model.togglePlay() }
                TransportButton(symbol: "stop.fill") { model.stop() }
                TransportButton(symbol: "forward.fill") { model.nextPosition() }
                TransportButton(symbol: "forward.end.fill") { model.playNext() }

                Spacer(minLength: 12)

                Image(systemName: model.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: $model.volume, in: 0...1)
                    .controlSize(.small)
                    .frame(width: 92)
                    .tint(Brand.orange)
            }
        }
    }

    // MARK: - Playlist

    private var playlist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Modules")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open…") { model.openPanel() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
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
