// Storage's Forgotten items: big files NXForge did not make a place for, found where they hide. On 2026-11-21 a 23 GB update
// NSP sat in ~/Downloads/.switch-staging, a hidden folder Finder does not show, and the Mac's disk ran out during builds.
// Looked for: in Downloads (hidden folders too) any game package or unfinished download of 256 MB or more; the holding folders
// `nxforge clean` moves worktrees and build caches into (deleted for good after a day); and the temporary files a stopped
// build left in ~/Library/Caches/NXForge/scratch. Only what is safe to lose can be deleted here: an unfinished download, a
// package whose copy (same name and size) is in the games folder, a held item, stopped-build scratch. A package found only
// in Downloads is shown, with where it is, and left to the user.
import Foundation

enum Forgotten {
    /// The smallest file worth a row.
    static let minBytes: Int64 = 256 << 20
    static let partial: Set<String> = ["download", "crdownload", "part", "partial"]
    static var packages: Set<String> { gameExtensions.union(["nup"]) }

    static var downloads: String { NSHomeDirectory() + "/Downloads" }
    /// `nxforge clean`'s holding folder on the home folder's volume (scripts/nxforge.py held_root); other volumes keep theirs
    /// in .nxforge-held at their top.
    static var heldHome: String { Disk.cacheDir + "/held" }
    static var scratch: String { Disk.cacheDir + "/scratch" }

    /// Every forgotten item; folders: the game folders Storage knows, so the holding folders of their volumes are read too.
    static func scan(gamesRoot: String?, folders: [String], buildRunning: Bool) -> [StorageItem] {
        let index = packageIndex(gamesRoot)
        var out = inDownloads(index: index)
        var roots = [heldHome]
        for p in ([gamesRoot].compactMap { $0 } + folders) {
            if let v = try? p.url.resourceValues(forKeys: [.volumeURLKey]).volume?.path, v != "/" { roots.append(v + "/.nxforge-held") }
        }
        var seen = Set<String>()
        for r in roots where seen.insert(r).inserted { out += held(in: r) }
        if !buildRunning { out += stoppedScratch() }
        return out
    }

    /// "name|bytes" of every game package under the games folder, three levels down (Switch 1/<Game>/<file>), so a copy in
    /// Downloads can be told from the only one.
    static func packageIndex(_ root: String?) -> Set<String> {
        guard let root, let e = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                               options: [.skipsPackageDescendants]) else { return [] }
        var out = Set<String>()
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true {
                if e.level >= 3 || u.lastPathComponent.hasSuffix("_build") || u.lastPathComponent == "app-backups" || u.lastPathComponent.hasPrefix(".") { e.skipDescendants() }
                continue
            }
            if packages.contains(u.pathExtension.lowercased()), let s = v?.fileSize { out.insert("\(u.lastPathComponent)|\(s)") }
        }
        return out
    }

    /// One row per entry at the top of Downloads (a folder or a file) holding game packages or unfinished downloads.
    static func inDownloads(index: Set<String>) -> [StorageItem] {
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(atPath: downloads) else { return [] }   // no Downloads access: nothing to say
        var out: [StorageItem] = []
        for name in top where name != ".DS_Store" && name != ".localized" && !name.contains(".nxforge-deleting-") {
            let path = downloads + "/" + name
            let found = bigFiles(path)
            guard !found.isEmpty else { continue }
            let unfinished = found.filter { partial.contains($0.url.pathExtension.lowercased()) }
            let copies = found.filter { index.contains("\($0.url.lastPathComponent)|\($0.bytes)") }
            let only = found.filter { f in !unfinished.contains { $0.path == f.path } && !copies.contains { $0.path == f.path } }
            let hidden = name.hasPrefix(".")
            let label = hidden ? "Hidden folder in Downloads" : "In Downloads"
            let names = found.map(\.url.lastPathComponent)
            let list = names.count == 1 ? names[0] : "\(names[0]) and \(names.count - 1) more"
            let note: String
            if only.isEmpty {
                note = unfinished.count == found.count ? "An unfinished download (\(list)). Safe to delete."
                    : copies.count == found.count ? "\(list): \(found.count == 1 ? "a copy" : "copies") of what is in your games folder. Safe to delete."
                    : "\(list): unfinished downloads and copies of what is in your games folder. Safe to delete."
            } else {
                let o = only.map(\.url.lastPathComponent)
                note = "\(o.count == 1 ? o[0] : "\(o.count) game files") \(o.count == 1 ? "is" : "are") not in your games folder\(hidden ? " (Finder hides this folder: ⇧⌘. shows it)" : ""). Move \(o.count == 1 ? "it" : "them") there, or delete in Finder."
            }
            out.append(StorageItem(kind: .forgotten, game: hidden ? name : list, path: path, bytes: Disk.size(path), label: label, detail: note, canGo: only.isEmpty))
        }
        return out
    }

    /// The game packages and unfinished downloads of minBytes or more in a file or folder, four levels down.
    static func bigFiles(_ path: String) -> [(path: String, url: URL, bytes: Int64)] {
        let u = path.url
        func take(_ f: URL) -> (String, URL, Int64)? {
            let ext = f.pathExtension.lowercased()
            guard packages.contains(ext) || partial.contains(ext) else { return nil }
            let b = Disk.size(f.path)   // a .download is a folder (Safari's bundle)
            return b >= minBytes ? (f.path, f, b) : nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue || partial.contains(u.pathExtension.lowercased()) { return take(u).map { [$0] } ?? [] }
        guard let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [(String, URL, Int64)] = []
        for case let f as URL in e {
            if partial.contains(f.pathExtension.lowercased()) { e.skipDescendants(); if let t = take(f) { out.append(t) }; continue }
            if (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { if e.level >= 4 { e.skipDescendants() }; continue }
            if let t = take(f) { out.append(t) }
        }
        return out.map { (path: $0.0, url: $0.1, bytes: $0.2) }
    }

    /// What `nxforge clean` moved into a holding folder (each with a .json note of where it came from).
    static func held(in root: String) -> [StorageItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var out: [StorageItem] = []
        for j in names where j.hasSuffix(".json") {
            let name = String(j.dropLast(5)), path = root + "/" + name
            guard fm.fileExists(atPath: path) else { continue }
            let info = (try? Data(contentsOf: (root + "/" + j).url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let from = (info["from"] as? String) ?? name
            let at = (info["at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let when = at.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "earlier"
            out.append(StorageItem(kind: .forgotten, game: from.lastComponent, path: path, bytes: Disk.size(path), label: "Held by a cleanup",
                                   detail: "Moved aside from \(from.tildePath) on \(when); deleted for good a day later. `nxforge restore \(name)` puts it back.", canGo: true))
        }
        return out
    }

    /// Temporary files a stopped build left on the Mac (a build on a drive without APFS keeps them here; a build removes its
    /// own when it ends, unless it was stopped hard).
    static func stoppedScratch() -> [StorageItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scratch)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { id in
            let path = scratch + "/" + id, b = Disk.size(path)
            return b < (64 << 20) ? nil : StorageItem(kind: .forgotten, game: id, path: path, bytes: b, label: "Left by a stopped build",
                                                      detail: "Temporary shader-compile files of a build that did not finish. Safe to delete.", canGo: true)
        }
    }

    /// What the shared-cache row should not count: the parts of ~/Library/Caches/NXForge listed as forgotten items.
    static var insideCacheDir: [String] { [heldHome, scratch] }
}
