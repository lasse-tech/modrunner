import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Glue between the replayer and the interface.
@MainActor
final class PlayerModel: ObservableObject {

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        var title: String
    }

    @Published private(set) var module: MMDModule?
    @Published private(set) var snapshot = Replayer.Snapshot()
    /// A window of the mixed output as it is being heard, for the waveform view.
    @Published private(set) var waveform: [Float] = []
    @Published private(set) var playlist: [Entry] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var status: String = L10n.t("status.noModuleLoaded")
    @Published var volume: Double = 0.85 {
        didSet { replayer.gain = Float(volume) }
    }

    /// Channels the listener has silenced, for picking a track out of the mix.
    @Published private(set) var mutedChannels = Set<Int>()

    /// The Amiga output filter. Stored, so the choice survives a restart.
    @Published var filterEnabled: Bool = UserDefaults.standard.bool(forKey: "amigaFilter") {
        didSet {
            UserDefaults.standard.set(filterEnabled, forKey: "amigaFilter")
            replayer.filterEnabled = filterEnabled
        }
    }

    func toggleMute(channel: Int) {
        if mutedChannels.contains(channel) {
            mutedChannels.remove(channel)
            replayer.setMuted(false, channel: channel)
        } else {
            mutedChannels.insert(channel)
            replayer.setMuted(true, channel: channel)
        }
    }

    /// Silences everything except one channel, or clears a solo already set.
    func soloChannel(_ channel: Int) {
        let others = Set(0..<max(4, module?.numTracks ?? 4)).subtracting([channel])
        if mutedChannels == others {
            mutedChannels.removeAll()
        } else {
            mutedChannels = others
        }
        for i in 0..<max(4, module?.numTracks ?? 4) {
            replayer.setMuted(mutedChannels.contains(i), channel: i)
        }
    }

    /// Shared instance so the app delegate can hand over files opened from the
    /// Finder or passed on the command line.
    static let shared = PlayerModel()

    private let replayer = Replayer()
    private lazy var audio = AudioOutput(replayer: replayer)
    private var timer: AnyCancellable?

    init() {
        replayer.gain = Float(volume)
        replayer.filterEnabled = UserDefaults.standard.bool(forKey: "amigaFilter")
        timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    // MARK: - Polling

    private func poll() {
        let (new, wave) = replayer.uiState(waveformSamples: 320)
        let wasPlaying = snapshot.isPlaying
        snapshot = new
        waveform = wave
        // Roll on to the next module when this one runs out.
        if wasPlaying, new.hasEnded, !new.isPlaying {
            playNext(autoAdvance: true)
        }
    }

    // MARK: - Loading

    func load(url: URL) {
        do {
            let loaded = try ModuleLoader.load(url: url)
            module = loaded
            replayer.load(module: loaded)
            snapshot = replayer.snapshot()

            let playable = loaded.instruments.filter(\.isPlayable).count
            let midi = loaded.instruments.filter { $0.midiChannel > 0 }.count
            var parts = [loaded.formatID,
                         L10n.t("status.blocks", loaded.blocks.count),
                         L10n.t("status.tracks", loaded.numTracks),
                         L10n.t("status.lines", loaded.patternLines),
                         L10n.t("status.notes", loaded.noteCount),
                         L10n.t("status.samples", playable, loaded.instruments.count)]
            if midi > 0 { parts.append(L10n.t("status.midiSilent", midi)) }
            status = parts.joined(separator: " · ")
        } catch {
            module = nil
            status = error.localizedDescription
        }
    }

    /// Adds files and, for a directory, every MED module inside it.
    func add(urls: [URL], playFirst: Bool = true) {
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                found.append(contentsOf: contents.filter { Self.looksLikeModule($0) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else if Self.looksLikeModule(url) {
                found.append(url)
            }
        }

        guard !found.isEmpty else {
            status = L10n.t("status.noModulesFound")
            return
        }

        let wasEmpty = playlist.isEmpty
        for url in found where !playlist.contains(where: { $0.url == url }) {
            playlist.append(Entry(url: url, title: url.lastPathComponent))
        }

        if playFirst, wasEmpty || currentIndex == nil,
           let index = playlist.firstIndex(where: { $0.url == found[0] }) {
            select(index: index, autoplay: false)
        }
    }

    /// Extensions are unreliable here — Amiga files usually have none — so the
    /// decision is made on content.
    static func looksLikeModule(_ url: URL) -> Bool {
        ModuleLoader.looksLikeModule(url)
    }

    func select(index: Int, autoplay: Bool = true) {
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        load(url: playlist[index].url)
        if let module, !module.songName.isEmpty {
            playlist[index].title = module.displayTitle
        }
        if autoplay { play() }
    }

    // MARK: - Transport

    func play() {
        guard let module else { return }
        do {
            try audio.start()
            replayer.play()

            // Recorded on play rather than on load: dropping a folder loads
            // many modules and only one of them is listened to.
            if let index = currentIndex, playlist.indices.contains(index) {
                RecentModules.record(url: playlist[index].url, title: module.displayTitle)
            }
        } catch {
            status = L10n.t("status.audioFailed", error.localizedDescription)
        }
    }

    /// Plays a module the playlist already knows about — how the recently
    /// played menu gets back to one.
    func playRecorded(url: URL) {
        guard let index = playlist.firstIndex(where: { $0.url == url }) else { return }
        select(index: index, autoplay: true)
    }

    func pause() { replayer.pause() }

    func togglePlay() {
        if snapshot.isPlaying { pause() } else { play() }
    }

    func stop() { replayer.stop() }

    func nextPosition() { replayer.nextPosition() }
    func previousPosition() { replayer.previousPosition() }

    func seek(fraction: Double) {
        guard let module, !module.playSequence.isEmpty else { return }
        let position = Int((Double(module.playSequence.count - 1) * fraction).rounded())
        replayer.seek(toSequencePosition: position)
    }

    func playNext(autoAdvance: Bool = false) {
        guard let index = currentIndex, playlist.indices.contains(index + 1) else {
            if autoAdvance { replayer.stop() }
            return
        }
        select(index: index + 1, autoplay: true)
    }

    func playPrevious() {
        guard let index = currentIndex, index > 0 else { return }
        select(index: index - 1, autoplay: true)
    }

    // MARK: - Drag and drop

    /// Resolves dropped items to file URLs and adds them to the playlist.
    func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "de.incudex.modrunner.drop")
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { queue.sync { urls.append(url) } }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.add(urls: urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
    }

    // MARK: - File panel

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = L10n.t("panel.chooseModules")
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }
}
