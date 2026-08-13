import Foundation

/// Works out which format a file is and hands it to the right loader.
///
/// Amiga files rarely carry an extension, so the decision is made on content:
/// MED modules announce themselves in the first four bytes, ProTracker modules
/// with a tag at offset 1080.
public enum ModuleLoader {

    public static func load(url: URL) throws -> MMDModule {
        let data = try Data(contentsOf: url)
        var module = try load(data: data)
        if module.songName.isEmpty {
            module.songName = url.deletingPathExtension().lastPathComponent
        }
        return module
    }

    public static func load(data: Data) throws -> MMDModule {
        if data.count >= 4 {
            let id = String(decoding: data[0..<4], as: UTF8.self)
            if ["MMD0", "MMD1", "MMD2", "MMD3"].contains(id) {
                return try MMDLoader.load(data: data)
            }
        }
        if MODLoader.signature(in: data) != nil {
            return try MODLoader.load(data: data)
        }

        // Neither matched. Report against whichever is the better guess: a
        // four-byte MMD-looking id gets the MED loader's message.
        if data.count >= 4 {
            let id = String(decoding: data[0..<4], as: UTF8.self)
            throw MMDLoadError.unknownFormat(id)
        }
        throw MMDLoadError.tooShort
    }

    /// Sifts a mixed list of files and drawers down to the modules in it.
    ///
    /// A drawer contributes the modules directly inside it, in name order —
    /// not what is below that, because a music collection is a drawer of
    /// modules and a source tree is not, and one level is the difference. What
    /// is a module is decided by `looksLikeModule`, which reads the first bytes
    /// rather than the name: Amiga files mostly have no extension to go on.
    public static func modules(in urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path,
                                                 isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])) ?? []
                found.append(contentsOf: contents.filter(looksLikeModule)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else if looksLikeModule(url) {
                found.append(url)
            }
        }
        return found
    }

    /// Cheap sniff for the playlist, without reading the whole file.
    public static func looksLikeModule(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let id = String(decoding: head, as: UTF8.self)
        if ["MMD0", "MMD1", "MMD2", "MMD3"].contains(id) { return true }

        // ProTracker's tag sits at 1080, so a short file cannot be one.
        guard (try? handle.seek(toOffset: 1080)) != nil,
              let tag = try? handle.read(upToCount: 4), tag.count == 4 else { return false }
        var probe = Data(count: 1080)
        probe.append(tag)
        return MODLoader.signature(in: probe) != nil
    }
}
