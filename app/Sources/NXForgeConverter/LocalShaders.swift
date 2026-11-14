// A game's bundled pipeline archive, kept on this Mac's own disk.
//
// A built game carries its compiled pipelines in Contents/Resources/pso (<GPU>.mtl4a and the prewarm files). Metal maps
// such a file when it is on the Mac's internal disk: its pages are clean, outside the game's memory footprint, and the
// open takes a fraction of a second. From any other volume (an external drive, whatever its format, or a disk image on
// one) Metal reads the whole file into the game's memory for the whole run: Ocarina of Time's 4.4 GB archive adds
// 4.4 GB to the footprint and 4 to 10 s to every start (measured on an M4 Pro, macOS 27.2; nxnative's
// docs/reference/memory.md has the same finding). The player's launcher only sets DM_PSO_BUNDLE when nothing has, so
// NXForge copies the folder to ~/Library/Caches/NXForge/pso once and starts the game with DM_PSO_BUNDLE on the copy.
// The copy is made again when the app's folder changes (a rebuild), is left out when the disk would be left short,
// and goes with the game: a copy whose app is gone from a connected drive is removed.
import Foundation

enum LocalShaders {
    static var root: URL { Disk.cacheDir.url.appending(path: "pso") }
    /// free space the internal disk keeps after a copy
    static let keepFree: Int64 = 10 << 30

    /// What a copy would be made from: nil for an app without a pipeline archive, or one already on the home folder's volume
    struct Source: Equatable {
        var folder: URL
        /// "<name>\t<bytes>\t<modified, whole seconds>" per file, sorted: a rebuild changes it
        var stamp: String
        var bytes: Int64
    }

    static func source(app: String, home: String = NSHomeDirectory()) -> Source? {
        let folder = app.url.appending(path: "Contents/Resources/pso").resolvingSymlinksInPath()
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path), names.contains(where: { $0.hasSuffix(".mtl4a") }) else { return nil }
        if sameVolume(folder.path, home) { return nil }
        return read(folder)
    }

    /// A pso folder's files as a Source, wherever it is
    static func read(_ folder: URL) -> Source? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }
        var lines: [String] = [], bytes: Int64 = 0
        for n in names.sorted() where !n.hasPrefix(".") {
            guard let a = try? fm.attributesOfItem(atPath: folder.appending(path: n).path), a[.type] as? FileAttributeType == .typeRegular else { continue }
            let size = (a[.size] as? NSNumber)?.int64Value ?? 0
            lines.append("\(n)\t\(size)\t\(Int((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0))")
            bytes += size
        }
        return Source(folder: folder, stamp: lines.joined(separator: "\n"), bytes: bytes)
    }

    static func sameVolume(_ a: String, _ b: String) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let x = try? a.url.resourceValues(forKeys: key).volumeIdentifier, let y = try? b.url.resourceValues(forKeys: key).volumeIdentifier else { return false }
        return x.isEqual(y)
    }

    /// The copy's folder for an app: its name, with a short hash of its path so two apps of one name keep apart
    static func folder(app: String, root: URL = root) -> URL {
        let path = app.url.standardizedFileURL.path
        var h: UInt64 = 0xcbf29ce484222325   // FNV-1a: only a folder name, nothing to protect
        for b in path.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let name = app.url.deletingPathExtension().lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
        return root.appending(path: "\(name.isEmpty ? "game" : name) \(String(h, radix: 16))")
    }

    /// The copy, when it is whole and of the app as it is now
    static func ready(app: String, source: Source, root: URL = root) -> URL? {
        let dir = folder(app: app, root: root)
        guard let t = try? String(contentsOf: dir.appending(path: "copy.txt"), encoding: .utf8), t == note(app: app, source: source) else { return nil }
        return dir.appending(path: "pso")
    }

    static func note(app: String, source: Source) -> String { "app\t\(app.url.standardizedFileURL.path)\n\(source.stamp)\n" }

    enum Outcome: Equatable { case ready(URL), noRoom(needed: Int64, free: Int64), failed(String) }

    /// Make the copy (a few seconds for a few GB, once per build of the game). copy.txt is written last, so a copy that was cut off is made again.
    static func copy(app: String, source: Source, root: URL = root, free: Int64? = Disk.free(NSHomeDirectory())) -> Outcome {
        let fm = FileManager.default, dir = folder(app: app, root: root), dest = dir.appending(path: "pso")
        let had = size(dir)
        if let free, free + had - source.bytes < keepFree { return .noRoom(needed: source.bytes, free: free) }
        try? fm.removeItem(at: dir)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for line in source.stamp.split(separator: "\n") {
                guard let n = line.split(separator: "\t").first.map(String.init) else { continue }
                try fm.copyItem(at: source.folder.appending(path: n), to: dest.appending(path: n))
            }
            // the stamp is taken again: a rebuild that replaced the folder during the copy must not pass for whole
            guard read(source.folder)?.stamp == source.stamp else { try? fm.removeItem(at: dir); return .failed("the game's files changed during the copy") }
            try note(app: app, source: source).write(to: dir.appending(path: "copy.txt"), atomically: true, encoding: .utf8)
        } catch {
            try? fm.removeItem(at: dir)
            return .failed(error.localizedDescription)
        }
        return .ready(dest)
    }

    static func size(_ dir: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var n: Int64 = 0
        for case let f as URL in e { n += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return n
    }

    /// Remove the copies whose app is gone. An app on a drive that is not connected is not gone: its copy stays.
    @discardableResult
    static func removeOrphans(root: URL = root, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
        let fm = FileManager.default
        var gone: [String] = []
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where d.hasDirectoryPath {
            let first = (try? String(contentsOf: d.appending(path: "copy.txt"), encoding: .utf8))?.split(separator: "\n").first.map(String.init)
            guard let first, first.hasPrefix("app\t") else { continue }   // no note: a copy being made, or cut off (the next Play makes it again)
            let app = String(first.dropFirst(4))
            if exists(app) || !exists(volume(of: app)) { continue }
            try? fm.removeItem(at: d)
            gone.append(app)
        }
        return gone
    }

    /// "/Volumes/<name>" of a path on another drive, "/" otherwise
    static func volume(of path: String) -> String {
        let c = path.split(separator: "/")
        return c.count >= 2 && c[0] == "Volumes" ? "/Volumes/\(c[1])" : "/"
    }
}
