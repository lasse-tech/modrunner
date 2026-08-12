import AppKit
import MediaPlayer
import ModRunnerKit

/// Play, pause and the skip keys — on the keyboard, on headphones, and on the
/// Now Playing tile in Control Centre.
///
/// This goes through `MPRemoteCommandCenter` rather than tapping the F7/F8/F9
/// keys directly. A key tap needs accessibility permission and takes the keys
/// away from whatever else is playing; the remote command centre is the
/// supported route, and it is the same one that puts the module's title on the
/// lock screen.
@MainActor
final class MediaKeys {

    static let shared = MediaKeys()

    private var model: PlayerModel { .shared }
    private var wired = false

    func start() {
        guard !wired else { return }
        wired = true

        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { [weak self] _ in
            guard let self, !self.model.snapshot.isPlaying else { return .commandFailed }
            self.model.play()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.model.snapshot.isPlaying else { return .commandFailed }
            self.model.pause()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.model.togglePlay()
            return .success
        }
        centre.stopCommand.addTarget { [weak self] _ in
            self?.model.stop()
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            self?.model.playNext()
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            self?.model.playPrevious()
            return .success
        }

        // Seeking inside a module is by song position, not by seconds, so the
        // scrubbing commands are left off rather than half-implemented.
        centre.changePlaybackPositionCommand.isEnabled = false
    }

    /// Publishes what is playing, so the keys have something to label and
    /// Control Centre has something to show.
    func update() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.module?.displayTitle ?? "ModRunner",
            MPNowPlayingInfoPropertyPlaybackRate: model.snapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.snapshot.elapsedSeconds,
        ]
        if let module = model.module, !module.annotation.isEmpty {
            info[MPMediaItemPropertyArtist] = module.annotation
                .split(separator: "\n").first.map(String.init) ?? ""
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = model.snapshot.isPlaying ? .playing : .paused
    }
}
