// The Library page's scan: every game under a root folder (Settings.gamesRoot, a drive or a network share such as
// /Volumes/Gaming/roms/switch), found by walking its folders. A game is what the script builds from one path:
//   - a folder of NSP / XCI / NSZ / XCZ files of one game (base, updates and DLC side by side, as the script reads them),
//   - a Switch 2 game's .nup file,
//   - a Switch 2 dump folder (exefs/main.npdm, or base/exefs/main.npdm; scripts/pack_dump.py's layout).
// The script takes one game per folder, so files of several games in one folder (a root full of loose NSPs, "Pikmin 1-2")
// are listed as one game each, marked `shared`: the converter moves a game's files into a folder of its own before it builds it.
// Nothing is opened or decrypted: title IDs come from the files' [0100…] tags, names from the file names. One directory listing
// per folder, with sizes prefetched, so a slow share costs one round trip per folder.
//
// A network share can be slow, or stop answering (a sleeping NAS, a dropped connection): each listing runs with a time limit,
// a folder that does not answer is skipped and named, and the scan stops once the share stops answering altogether, keeping
// what it found. The last scan is kept in Application Support (library.json), so the list shows at once, even with the share away.
import Foundation

struct LibraryGame: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case packages, nup, dump }
    var id: String { files.isEmpty ? path : path + "|" + files.joined(separator: "|") }
    var kind: Kind
    /// what the converter builds from: the game's folder, or the .nup file
    var path: String
    var name: String
    /// the application's title ID ("0100…" / "0400…"), when a file name carries it
    var titleID: String?
    /// shared: the game's own files, in a folder that holds other games too (they move to a folder of their own before a build)
    var files: [String] = []
    var shared = false
    var fileCount: Int
    var bytes: Int64
    var base: Bool
    var updates: Int
    var dlc: Int
    /// a Mac app built from this game, found beside its files
    var app: String?
    /// what stops the build or may surprise: no base game, DLC in a subfolder the script does not read
    var notes: [String] = []

    var folder: String { kind == .nup ? path.url.deletingLastPathComponent().path : path }
    var console: Console { kind != .packages || titleID?.hasPrefix("04") == true ? .switch2 : .switch1 }

    /// "Base game + update + 4 DLC", "Update only", "NUP container"
    var contents: String {
        switch kind {
        case .nup: return "NUP container"
        case .dump: return "Dump folder"
        case .packages:
            var parts = [base ? "Base game" : (updates > 0 ? "Update only" : dlc > 0 ? "DLC only" : "Game file")]
            if base && updates > 0 { parts.append(updates == 1 ? "update" : "\(updates) updates") }
            if dlc > 0 && (base || updates > 0) { parts.append("\(dlc) DLC") }
            return parts.joined(separator: " + ")
        }
    }
}

struct LibraryScan: Codable {
    var root: String
    var scanned: Date
    var games: [LibraryGame]
    /// folders that did not answer in time, or could not be read
    var skipped: [String] = []
    /// set when the scan ended early: the share stopped answering, or it was stopped
    var stopped: String?
    var folders = 0
}

enum GameLibrary {
    static let cacheFile = Settings.supportDir.appending(path: "library.json")
    /// how long one folder listing may take before the folder is skipped (a share waking up can take a few seconds)
    static let listTimeout: Double = 20
    /// this many folders in a row not answering: the share is gone, so stop
    static let giveUpAfter = 3
    static let maxDepth = 8

    static func loadCache() -> LibraryScan? {
        guard let d = try? Data(contentsOf: cacheFile) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(LibraryScan.self, from: d)
    }

    static func saveCache(_ s: LibraryScan) {
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(s) { try? d.write(to: cacheFile, options: .atomic) }
    }

    // MARK: file names

    private static let tagPattern = try! NSRegularExpression(pattern: #"\[([0-9A-Fa-f]{16})\]"#)

    /// The first [16 hex digits] tag of a file name, or a name that is only a title ID ("0100f9f00c697001.nsp").
    static func titleTag(_ name: String) -> UInt64? {
        let stem = (name as NSString).deletingPathExtension
        if stem.count == 16, let v = UInt64(stem, radix: 16) { return v }
        guard let m = tagPattern.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)), let r = Range(m.range(at: 1), in: stem) else { return nil }
        return UInt64(stem[r], radix: 16)
    }

    /// "Super Mario Odyssey [0100000000010000][v0].nsp" → "Super Mario Odyssey"; "Yoshis_Crafted_World_[01006…].nsp" → "Yoshis Crafted World";
    /// "Shadow of the Ninja Reborn [0100…][v0] (1.98 GB).nsz" → "Shadow of the Ninja Reborn". Folder names lose " [NSP]" and the like.
    static func cleanName(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "_", with: " ")
        if let i = s.firstIndex(of: "["), i != s.startIndex { s = String(s[..<i]) }
        s = s.replacingOccurrences(of: #"\s*\([\d.,]+\s*[KMGT]B\)"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: scanning

    struct Listing {
        var dirs: [URL] = []
        var packages: [(url: URL, bytes: Int64)] = []
        var nups: [(url: URL, bytes: Int64)] = []
        var apps: [String] = []
        var names: Set<String> = []
    }

    /// One folder's listing, or nil when it took longer than the time limit or failed.
    static func list(_ dir: URL, timeout: Double) -> Listing? {
        final class Box: @unchecked Sendable { var v: Listing?; var done = false }
        let box = Box(), sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.v = listNow(dir)
            sem.signal()
        }
        // a hung call on a dead share is left behind: it ends, or fails, when the share comes back or the mount times out
        return sem.wait(timeout: .now() + timeout) == .success ? box.v : nil
    }

    static func listNow(_ dir: URL) -> Listing? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        var l = Listing()
        for u in items {
            let name = u.lastPathComponent
            l.names.insert(name.lowercased())
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { continue }
            let ext = u.pathExtension.lowercased()
            if v?.isDirectory == true {
                if ext == "app" { l.apps.append(u.path); continue }
                if v?.isPackage == true || skipDir(name) { continue }
                l.dirs.append(u)
            } else if name.hasPrefix("._") {
                continue
            } else if gameExtensions.contains(ext) {
                let b = Int64(v?.fileSize ?? 0)
                if b > 0 { l.packages.append((u, b)) }   // an empty file is a download that never finished
            } else if ext == "nup" {
                l.nups.append((u, Int64(v?.fileSize ?? 0)))
            }
        }
        l.dirs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return l
    }

    /// The converter's own folders, and bundles: never games.
    static func skipDir(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasSuffix("_build") || n.hasSuffix("_survey") || n == "app-backups" || n.hasSuffix(".sparsebundle") || n.hasSuffix(".noindex") || n == "staging"
            || n == "#recycle" || n == "@eadir" || n == "$recycle.bin" || n == "system volume information"
    }

    /// Whether a listed folder is a Switch 2 dump (its code is in exefs/ or base/exefs/).
    static func isDump(_ dir: URL, _ l: Listing) -> Bool {
        let fm = FileManager.default
        if l.names.contains("exefs") && fm.fileExists(atPath: dir.path + "/exefs/main.npdm") { return true }
        if l.names.contains("base") && fm.fileExists(atPath: dir.path + "/base/exefs/main.npdm") { return true }
        return false
    }

    /// The games of one folder's game files: one, or one per title when several games share it.
    static func games(in dir: URL, packages: [(url: URL, bytes: Int64)], apps: [String]) -> [LibraryGame] {
        guard !packages.isEmpty else { return [] }
        var groups: [UInt64: [(url: URL, bytes: Int64, tid: UInt64)]] = [:]
        var untagged: [(url: URL, bytes: Int64)] = []
        for p in packages {
            if let t = titleTag(p.url.lastPathComponent) { groups[GameFiles.appOf(t), default: []].append((p.url, p.bytes, t)) }
            else { untagged.append(p) }
        }
        func make(_ files: [(url: URL, bytes: Int64, tid: UInt64?)], app: UInt64?, shared: Bool) -> LibraryGame {
            let tids = files.compactMap(\.tid)
            let base = tids.contains { $0 & 0xFFF == 0 } || files.contains { $0.tid == nil }   // an untagged file is taken as the base game, as the script does
            let updates = tids.filter { $0 & 0xFFF == 0x800 }.count
            let dlc = tids.filter { $0 & 0xFFF != 0 && $0 & 0xFFF != 0x800 }.count
            let named = files.first { $0.tid.map { $0 & 0xFFF == 0 } ?? true } ?? files[0]
            var name = cleanName(named.url.deletingPathExtension().lastPathComponent)
            if name.isEmpty || (named.tid != nil && name.count == 16 && UInt64(name, radix: 16) != nil) { name = cleanName(dir.lastPathComponent) }
            var g = LibraryGame(kind: .packages, path: dir.path, name: name, titleID: app.map { String(format: "%016llX", $0) },
                                files: shared ? files.map(\.url.lastPathComponent).sorted() : [], shared: shared,
                                fileCount: files.count, bytes: files.reduce(0) { $0 + $1.bytes }, base: base, updates: updates, dlc: dlc)
            if !shared { g.app = apps.sorted().first }
            if !base { g.notes.append(updates > 0 ? "No base game here, only an update: add the base game's NSP or XCI to build it" : "No base game here, only DLC") }
            return g
        }
        // one game: every tagged file is of one title, with at most one untagged file that can be its base game (a cartridge dump
        // with no tags), or only untagged files (the script reads their tickets)
        let taggedBase = groups.values.contains { fs in fs.contains { $0.tid & 0xFFF == 0 } }
        if groups.isEmpty || (groups.count == 1 && (untagged.isEmpty || (untagged.count == 1 && !taggedBase))) {
            var all: [(url: URL, bytes: Int64, tid: UInt64?)] = []
            for fs in groups.values { for f in fs { all.append((url: f.url, bytes: f.bytes, tid: f.tid)) } }
            for f in untagged { all.append((url: f.url, bytes: f.bytes, tid: nil)) }
            return [make(all, app: groups.keys.first, shared: false)]
        }
        var out = groups.map { app, fs in make(fs.map { (url: $0.url, bytes: $0.bytes, tid: UInt64?.some($0.tid)) }, app: app, shared: true) }
        out += untagged.map { make([(url: $0.url, bytes: $0.bytes, tid: nil)], app: nil, shared: true) }
        return out
    }

    /// Walks root, calling progress (folders read, the folder being read, the games so far) as it goes. Cancel the task to stop.
    static func scan(root: String, progress: (Int, String, [LibraryGame]) -> Void = { _, _, _ in }) -> LibraryScan {
        var result = LibraryScan(root: root, scanned: Date(), games: [])
        var stack: [(URL, Int)] = [(root.url, 0)]
        var silent = 0
        var parentHasPackages = Set<String>()
        var lastReport = Date.distantPast
        while let (dir, depth) = stack.popLast() {
            if Task.isCancelled { result.stopped = "Stopped before the end: the list may be incomplete."; break }
            if Date().timeIntervalSince(lastReport) > 0.3 { progress(result.folders, dir.path, result.games); lastReport = Date() }
            guard let l = list(dir, timeout: listTimeout) else {
                if dir.path == root { result.stopped = "\(root.tildePath) did not answer: is the drive or share connected?"; break }
                result.skipped.append(dir.path)
                silent += 1
                if silent >= giveUpAfter { result.stopped = "The share stopped answering: the list may be incomplete. Scan again once it is back."; break }
                continue
            }
            silent = 0
            result.folders += 1
            // a dump is a folder of its own: one beside game packages is something extracted from them
            if dir.path != root && !parentHasPackages.contains(dir.deletingLastPathComponent().path) && isDump(dir, l) {
                let tid = titleTag(dir.lastPathComponent).map { String(format: "%016llX", GameFiles.appOf($0)) }
                result.games.append(LibraryGame(kind: .dump, path: dir.path, name: cleanName(dir.lastPathComponent), titleID: tid, fileCount: 0, bytes: 0,
                                                base: true, updates: 0, dlc: 0, app: l.apps.sorted().first))
                continue   // a dump's own folders are its files
            }
            if !l.packages.isEmpty { parentHasPackages.insert(dir.path) }
            result.games += games(in: dir, packages: l.packages, apps: l.apps)
            for n in l.nups {
                let tid = titleTag(n.url.lastPathComponent).map { String(format: "%016llX", GameFiles.appOf($0)) }
                result.games.append(LibraryGame(kind: .nup, path: n.url.path, name: cleanName(n.url.deletingPathExtension().lastPathComponent), titleID: tid,
                                                fileCount: 1, bytes: n.bytes, base: true, updates: 0, dlc: 0, app: l.apps.sorted().first))
            }
            if depth < maxDepth { stack += l.dirs.reversed().map { ($0, depth + 1) } }
        }
        result.games = fold(result.games)
        result.scanned = Date()
        progress(result.folders, "", result.games)
        return result
    }

    /// DLC or an update in a subfolder of its base game's folder ("Cadence of Hyrule/4 DLCs"): the script reads one folder only,
    /// so it is not used; it becomes a note on the game rather than a game of its own.
    static func fold(_ games: [LibraryGame]) -> [LibraryGame] {
        var out = games
        for (i, g) in games.enumerated() where g.kind == .packages && !g.base && !g.shared {
            guard let tid = g.titleID, let p = out.firstIndex(where: { $0.titleID == tid && $0.base && g.path.hasPrefix($0.folder + "/") }) else { continue }
            let what = [g.updates > 0 ? (g.updates == 1 ? "an update" : "\(g.updates) updates") : nil, g.dlc > 0 ? "\(g.dlc) DLC" : nil].compactMap { $0 }.joined(separator: " and ")
            out[p].notes.append("\(what) in “\(g.path.lastComponent)” not used: the build reads only the game's own folder; move the files beside the base game")
            out[i].path = ""   // dropped below
        }
        return out.filter { !$0.path.isEmpty }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: tidying

    /// Moves a shared game's files into a new folder named after the game, beside them; the game's new path.
    static func moveToOwnFolder(_ g: LibraryGame) throws -> String {
        let fm = FileManager.default
        let safe = g.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
        var target = "\(g.path)/\(safe.isEmpty ? (g.titleID ?? "Game") : safe)"
        // a folder of that name with other game files in it is not this game's: take the next free name
        var n = 2
        while fm.fileExists(atPath: target) && !GameFiles.list(in: target.url).isEmpty { target = "\(g.path)/\(safe) (\(n))"; n += 1 }
        try fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        for f in g.files { try fm.moveItem(atPath: "\(g.path)/\(f)", toPath: "\(target)/\(f)") }
        return target
    }
}
