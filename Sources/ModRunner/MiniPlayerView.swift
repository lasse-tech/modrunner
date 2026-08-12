import SwiftUI
import AppKit
import ModRunnerKit

/// The opposite end of the stage: a strip that stays out of the way while
/// something else has the screen. Title, transport, level, and nothing else.
/// Both skins are drawn to the same box, so switching one for the other does
/// not resize the window under the pointer.
struct MiniPlayerView: View {

    @ObservedObject var model: PlayerModel
    var onExpand: () -> Void = {}

    @AppStorage(Skin.storageKey) private var skinName = Skin.native.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    static let width: CGFloat = 340
    static let height: CGFloat = 92

    private var skin: Skin { Skin(rawValue: skinName) ?? .native }

    var body: some View {
        Group {
            switch skin {
            case .amiga:  AmigaMiniPlayerView(model: model, onExpand: onExpand)
            case .native: NativeMiniPlayerView(model: model, onExpand: onExpand)
            }
        }
        .id(language)
        .frame(width: Self.width, height: Self.height)
    }
}

/// The loudest channel, so a single busy voice still moves the bar.
@MainActor
private func mixLevel(_ model: PlayerModel) -> Float {
    model.snapshot.channelMeters.max() ?? 0
}

// MARK: - Workbench

struct AmigaMiniPlayerView: View {

    @ObservedObject var model: PlayerModel
    var onExpand: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Close and zoom both lead back to the full player: the strip is a
            // mode, not a second document window.
            AmigaTitleBar(
                title: "ModRunner",
                onClose: { MiniPlayerController.shared.dismiss() },
                onMinimise: { NSApplication.shared.keyWindow?.miniaturize(nil) },
                onZoom: { onExpand() },
                onDepth: { NSApplication.shared.keyWindow?.orderBack(nil) }
            )

            VStack(spacing: 5) {
                AmigaReadout(text: StageText.title(model))
                    .frame(height: 18)

                HStack(spacing: 5) {
                    // Narrower than the main window's, but not so narrow that
                    // the labels have to be truncated.
                    AmigaButton(label: "|<", width: 34) { model.playPrevious() }
                    AmigaButton(label: model.snapshot.isPlaying ? "||" : ">", width: 38) { model.togglePlay() }
                    AmigaButton(label: ">|", width: 34) { model.playNext() }

                    // One bar for the whole mix: at this size a meter per
                    // channel would be four smears of grey.
                    AmigaVUMeter(label: "MIX", level: mixLevel(model))

                    Text(StageText.time(model))
                        .font(Amiga.font(10))
                        .foregroundColor(Amiga.black)
                        .frame(width: 34, alignment: .trailing)
                }

                AmigaSlider(value: model.snapshot.progress, knobWidth: 18) { fraction in
                    model.seek(fraction: fraction)
                }
            }
            .padding(6)
        }
        .background(Amiga.grey)
    }
}

// MARK: - Native

struct NativeMiniPlayerView: View {

    @ObservedObject var model: PlayerModel
    var onExpand: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(StageText.title(model))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(StageText.time(model))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                // The window has no title bar of its own, so the way back to
                // the full player lives here.
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("tooltip.expand"))

                Button { MiniPlayerController.shared.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("tooltip.close"))
            }

            HStack(spacing: 8) {
                TransportButton(symbol: "backward.end.fill", size: 22) { model.playPrevious() }
                TransportButton(symbol: model.snapshot.isPlaying ? "pause.fill" : "play.fill",
                                prominent: true, size: 22) { model.togglePlay() }
                TransportButton(symbol: "forward.end.fill", size: 22) { model.playNext() }

                MixBar(level: mixLevel(model))
                    .frame(height: 6)
            }

            Scrubber(value: model.snapshot.progress) { model.seek(fraction: $0) }
        }
        .padding(10)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A single horizontal bar for the whole mix, in the meter's own ramp.
private struct MixBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * CGFloat(min(1, max(0, level)))
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Brand.level(Double(level)))
                    .frame(width: width)
                    .animation(.easeOut(duration: 0.07), value: width)
            }
        }
    }
}
