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
    @Published private(set) var playlist: [Entry] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var status: String = "No module loaded."
    @Published var volume: Double = 0.7 {
        didSet { replayer.gain = Float(volume) }
    }

    /// Shared instance so the app delegate can hand over files opened from the
    /// Finder or passed on the command line.
    static let shared = PlayerModel()

    private let replayer = Replayer()
    private lazy var audio = AudioOutput(replayer: replayer)
    private var timer: AnyCancellable?

    init() {
        replayer.gain = Float(volume)
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    // MARK: - Polling

    private func poll() {
        let new = replayer.snapshot()
        let wasPlaying = snapshot.isPlaying
        snapshot = new
        // Roll on to the next module when this one runs out.
        if wasPlaying, new.hasEnded, !new.isPlaying {
            playNext(autoAdvance: true)
        }
    }

    // MARK: - Loading

    func load(url: URL) {
        do {
            let loaded = try MMDLoader.load(url: url)
            module = loaded
            replayer.load(module: loaded)
            snapshot = replayer.snapshot()

            let playable = loaded.instruments.filter(\.isPlayable).count
            let midi = loaded.instruments.filter { $0.midiChannel > 0 }.count
            var parts = ["\(loaded.formatID)",
                         "\(loaded.blocks.count) blocks",
                         "\(loaded.numTracks) tracks",
                         "\(loaded.patternLines) lines",
                         "\(loaded.noteCount) notes",
                         "\(playable)/\(loaded.instruments.count) samples"]
            if midi > 0 { parts.append("\(midi) MIDI (silent)") }
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
                found.append(contentsOf: contents.filter { Self.looksLikeModule($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else if Self.looksLikeModule(url) {
                found.append(url)
            }
        }

        guard !found.isEmpty else {
            status = "No MED modules found in that drop."
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

    /// Cheap sniff: a MED module starts with MMD0-MMD3. Extensions are unreliable
    /// here because Amiga files usually have none.
    static func looksLikeModule(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let id = String(decoding: head, as: UTF8.self)
        return ["MMD0", "MMD1", "MMD2", "MMD3"].contains(id)
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
        guard module != nil else { return }
        do {
            try audio.start()
            replayer.play()
        } catch {
            status = "Audio could not start: \(error.localizedDescription)"
        }
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

    // MARK: - File panel

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose MED/OctaMED modules or a folder"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }
}
