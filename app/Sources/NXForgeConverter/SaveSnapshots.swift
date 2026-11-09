// Save snapshots: a copy of a game's save that is checked file by file (SHA-256) when it is made and again before it is put
// back, and a restore that swaps the whole save folder in one rename, so a save is never left half restored. Restoring keeps
// the save it replaces as a snapshot first; so do Restore this version on the Builds page and a rebuild.
// After LumaNX's Worker/recovery.py (MIT, github.com/Xc1Ym/LumaNX).
//
// Where the save is (dm/mac/launcher.c): <game folder>/Saves/save beside the app, or ~/Library/Application Support/nxnative/<title ID>/save
// when the game folder is no place for it (or on a drive that is not APFS, or before the launcher has copied it in); the device save is the same path with _device.
// Snapshots go beside it: <save's folder>/save-snapshots/<id>/{manifest.json, data/save, data/save_device}. (save-backups/ there is
// Cloud saves' own, dm/host/save_sync.c.)
import AppKit
import CryptoKit
import Foundation

struct SaveFile: Codable, Equatable { var size: Int64; var sha256: String }

/// Every file and folder under a save, by path relative to the snapshot's data folder ("save/…", "save_device/…").
struct SaveInventory: Codable, Equatable {
    var files: [String: SaveFile] = [:]
    var directories: [String] = []
    var bytes: Int64 { files.values.reduce(0) { $0 + $1.size } }
}

enum SnapshotReason: String, Codable, CaseIterable {
    case manual, beforeRestore, beforeRebuild, beforeAppRestore, imported
    var label: String {
        switch self {
        case .manual: "Snapshot"
        case .imported: "Imported"
        case .beforeRestore: "Before a restore"
        case .beforeRebuild: "Before a rebuild"
        case .beforeAppRestore: "Before restoring an older app"
        }
    }
}

struct SnapshotManifest: Codable {
    var schema = 1
    var id: String
    var titleID: String
    var created: Date
    var reason: SnapshotReason
    var inventory: SaveInventory
}

struct SaveSnapshot: Identifiable, Hashable {
    var id: String
    var path: String
    var created: Date
    var reason: SnapshotReason
    var files: Int
    var bytes: Int64
}

/// A game's save: the folder the launcher hands the game, and the device save beside it.
struct SaveLocation: Equatable {
    var save: String
    var titleID: String
    var device: String { save + "_device" }
    var folder: String { save.url.deletingLastPathComponent().path }
    var snapshots: String { folder + "/save-snapshots" }
    var parts: [(name: String, path: String)] { [("save", save), ("save_device", device)] }
}

enum SaveSnapshots {
    /// renamex_np's RENAME_SWAP (<stdio.h>): both paths stay, their contents trade places in one step
    static let renameSwap: UInt32 = 0x0000_0002
    /// How many automatic snapshots (before a restore or a rebuild) stay; snapshots made with the button are never removed.
    static let keepAutomatic = 10

    /// Where the app's save is, as the launcher picks it: the game folder's when it has one, else the Library's when that has one
    /// (or the game folder can't hold a save), else the game folder's, where the next start puts it.
    static func location(app: String, titleID: String, home: String = NSHomeDirectory()) -> SaveLocation {
        let library = "\(home)/Library/Application Support/nxnative/\(titleID)/save"
        let parent = app.url.deletingLastPathComponent().path
        let usable = !parent.contains("/AppTranslocation/") && parent != "/Applications" && parent != "\(home)/Applications"
            && FileManager.default.isWritableFile(atPath: parent) && canHoldSave(parent)
        let inFolder = parent + "/Saves/save"
        if usable && hasData(inFolder) { return SaveLocation(save: inFolder, titleID: titleID) }
        if hasData(library) || !usable { return SaveLocation(save: library, titleID: titleID) }
        return SaveLocation(save: inFolder, titleID: titleID)
    }

    /// Whether a save can live on dir's drive (the launcher's save_capable): the host's save transaction clones the save folder and swaps
    /// it in on commit, which only APFS does. On an exFAT, FAT or HFS+ drive the save stays in the Library. True when the drive cannot be asked.
    static func canHoldSave(_ dir: String) -> Bool {
        guard let v = try? URL(fileURLWithPath: dir).resourceValues(forKeys: [.volumeSupportsFileCloningKey, .volumeSupportsSwapRenamingKey]),
              let clone = v.volumeSupportsFileCloning, let swap = v.volumeSupportsSwapRenaming else { return true }
        return clone && swap
    }

    /// A folder with anything in it besides Finder's .DS_Store (the launcher's has_data).
    static func hasData(_ dir: String) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).contains { $0 != ".DS_Store" }
    }

    static func hasSave(_ loc: SaveLocation) -> Bool { hasData(loc.save) || hasData(loc.device) }

    /// Whether this game is running: its app, or any copy of it (backups share the bundle ID).
    @MainActor static func isRunning(app: String) -> Bool {
        let id = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String
        let path = app.url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains { r in
            (id != nil && r.bundleIdentifier == id) || r.bundleURL?.standardizedFileURL.path == path
        }
    }

    // MARK: checking

    static func sha256(_ path: String) throws -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { throw ConverterError("cannot read \(path)") }
        defer { try? h.close() }
        var hash = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The files and folders under each part (a missing part is no entries). Links and special files stop it: a save holds neither.
    static func inventory(_ parts: [(name: String, path: String)]) throws -> SaveInventory {
        let fm = FileManager.default
        var inv = SaveInventory()
        for (name, root) in parts {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
            let a = try fm.attributesOfItem(atPath: root)
            guard a[.type] as? FileAttributeType == .typeDirectory, isDir.boolValue else { throw ConverterError("\(root) is not a folder") }
            inv.directories.append(name)
            guard let walk = fm.enumerator(atPath: root) else { continue }
            for case let rel as String in walk {
                let p = "\(root)/\(rel)", key = "\(name)/\(rel)"
                let attrs = try fm.attributesOfItem(atPath: p)
                switch attrs[.type] as? FileAttributeType {
                case .typeDirectory?: inv.directories.append(key)
                case .typeRegular?: inv.files[key] = SaveFile(size: (attrs[.size] as? NSNumber)?.int64Value ?? 0, sha256: try sha256(p))
                default: throw ConverterError("the save holds a link or a special file, so it is left as it is: \(p)")
                }
            }
        }
        inv.directories.sort()
        return inv
    }

    /// Copy what the inventory names from parts into dest/<part>/…, then check the copy against it.
    private static func copyChecked(_ inv: SaveInventory, from parts: [(name: String, path: String)], to dest: String) throws {
        let fm = FileManager.default
        let roots = Dictionary(uniqueKeysWithValues: parts.map { ($0.name, $0.path) })
        func source(_ key: String) -> String {
            let name = String(key.split(separator: "/", maxSplits: 1)[0]), rest = key.dropFirst(name.count)
            return (roots[name] ?? "") + rest
        }
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        for d in inv.directories { try fm.createDirectory(atPath: "\(dest)/\(d)", withIntermediateDirectories: true) }
        for k in inv.files.keys.sorted() {
            try fm.copyItem(atPath: source(k), toPath: "\(dest)/\(k)")   // a clone on APFS
            let fd = open("\(dest)/\(k)", O_RDONLY); if fd >= 0 { fsync(fd); close(fd) }
        }
        let copied = try inventory(inv.directories.filter { !$0.contains("/") }.map { ($0, "\(dest)/\($0)") })
        guard copied == inv else { throw ConverterError("the copy of the save does not match it file for file; nothing was changed") }
    }

    private static func enoughSpace(_ dir: String, for inv: SaveInventory) throws {
        let free = Disk.free(dir) ?? .max
        guard free >= inv.bytes + (64 << 20) else { throw ConverterError("not enough free space for a copy of the save (\(inv.bytes >> 20) MB); nothing was changed") }
    }

    // MARK: snapshots

    /// A checked copy of the save; nil when there is no save yet.
    @discardableResult
    static func snapshot(_ loc: SaveLocation, reason: SnapshotReason) throws -> SaveSnapshot? {
        guard hasSave(loc) else { return nil }
        let fm = FileManager.default
        let inv = try inventory(loc.parts)
        try fm.createDirectory(atPath: loc.snapshots, withIntermediateDirectories: true)
        try enoughSpace(loc.snapshots, for: inv)
        let id = snapshotID()
        let stage = "\(loc.snapshots)/.making-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: stage) }
        try copyChecked(inv, from: loc.parts, to: stage + "/data")
        // a save the game changed while it was being copied is no snapshot
        guard try inventory(loc.parts) == inv else { throw ConverterError("the save changed while it was being copied: quit the game and try again") }
        let m = SnapshotManifest(id: id, titleID: loc.titleID, created: Date(), reason: reason, inventory: inv)
        try encoder.encode(m).write(to: URL(fileURLWithPath: stage + "/manifest.json"), options: .atomic)
        try fm.moveItem(atPath: stage, toPath: "\(loc.snapshots)/\(id)")
        if reason != .manual { prune(loc) }
        return SaveSnapshot(id: id, path: "\(loc.snapshots)/\(id)", created: m.created, reason: reason, files: inv.files.count, bytes: inv.bytes)
    }

    /// "2026-11-05 21.44.42 3f9a": the time it was made and four random characters, so two in one second differ.
    private static func snapshotID() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date()) + " " + String(UUID().uuidString.prefix(4)).lowercased()
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    /// A snapshot's manifest, refused when it is damaged or names paths outside the snapshot.
    static func manifest(_ path: String, titleID: String) throws -> SnapshotManifest {
        guard let d = FileManager.default.contents(atPath: path + "/manifest.json"),
              let m = try? decoder.decode(SnapshotManifest.self, from: d), m.schema == 1, m.titleID == titleID,
              m.id == path.url.lastPathComponent else { throw ConverterError("this snapshot's record is damaged; nothing was changed") }
        for k in Array(m.inventory.files.keys) + m.inventory.directories {
            let parts = k.split(separator: "/", omittingEmptySubsequences: false)
            guard let top = parts.first, top == "save" || top == "save_device", !parts.contains(".."), !parts.contains(""), !k.hasPrefix("/") else {
                throw ConverterError("this snapshot's record names a path outside the save; nothing was changed")
            }
        }
        return m
    }

    /// The game's snapshots, newest first.
    static func list(_ loc: SaveLocation) -> [SaveSnapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: loc.snapshots)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { n in
            let p = "\(loc.snapshots)/\(n)"
            guard let m = try? manifest(p, titleID: loc.titleID) else { return nil }
            return SaveSnapshot(id: n, path: p, created: m.created, reason: m.reason, files: m.inventory.files.count, bytes: m.inventory.bytes)
        }.sorted { $0.created > $1.created }
    }

    /// Automatic snapshots beyond keepAutomatic go to the Trash, oldest first.
    static func prune(_ loc: SaveLocation) {
        for s in list(loc).filter({ $0.reason != .manual }).dropFirst(keepAutomatic) {
            try? FileManager.default.trashItem(at: s.path.url, resultingItemURL: nil)
        }
    }

    /// Put a snapshot back: checked again, copied beside the save and checked, the current save kept as a snapshot,
    /// then each folder swapped in with one rename. Returns the snapshot of the save it replaced (nil when there was none).
    @discardableResult
    static func restore(_ s: SaveSnapshot, to loc: SaveLocation) throws -> SaveSnapshot? {
        let fm = FileManager.default
        let m = try manifest(s.path, titleID: loc.titleID)
        let data = s.path + "/data"
        let parts = m.inventory.directories.filter { !$0.contains("/") }
        guard try inventory(parts.map { ($0, "\(data)/\($0)") }) == m.inventory else {
            throw ConverterError("this snapshot no longer matches what was saved in it (a file changed or is missing); nothing was changed")
        }
        try fm.createDirectory(atPath: loc.folder, withIntermediateDirectories: true)
        try enoughSpace(loc.folder, for: m.inventory)
        let stage = "\(loc.folder)/.restoring-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: stage) }
        try copyChecked(m.inventory, from: parts.map { ($0, "\(data)/\($0)") }, to: stage)
        let safety = try snapshot(loc, reason: .beforeRestore)
        for (name, target) in loc.parts {
            let staged = "\(stage)/\(name)"
            let exists = fm.fileExists(atPath: target)
            if !fm.fileExists(atPath: staged) {
                // the snapshot had no such folder (no device save then): the current one is in the safety snapshot, so it goes
                if exists { try fm.moveItem(atPath: target, toPath: "\(stage)/old-\(name)") }
                continue
            }
            if exists {
                guard renamex_np(staged, target, renameSwap) == 0 else {
                    throw ConverterError("could not swap \(name) in (\(String(cString: strerror(errno)))); it is as it was, and the save before the restore is in snapshot \(safety?.id ?? "none")")
                }
            } else {
                try fm.moveItem(atPath: staged, toPath: target)
            }
        }
        return safety
    }

    /// A save from elsewhere (an exported zip, another Mac's save folder, a snapshot) made into a checked snapshot of this game,
    /// which restore() then puts in place: so an import is checked like any restore, and the imported save stays as a snapshot.
    @discardableResult
    static func importSnapshot(parts: [(name: String, path: String)], into loc: SaveLocation) throws -> SaveSnapshot {
        let fm = FileManager.default
        let inv = try inventory(parts)
        guard !inv.files.isEmpty else { throw ConverterError("there is no save in it: no files") }
        try fm.createDirectory(atPath: loc.snapshots, withIntermediateDirectories: true)
        try enoughSpace(loc.snapshots, for: inv)
        let id = snapshotID()
        let stage = "\(loc.snapshots)/.making-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: stage) }
        try copyChecked(inv, from: parts, to: stage + "/data")
        let m = SnapshotManifest(id: id, titleID: loc.titleID, created: Date(), reason: .imported, inventory: inv)
        try encoder.encode(m).write(to: URL(fileURLWithPath: stage + "/manifest.json"), options: .atomic)
        try fm.moveItem(atPath: stage, toPath: "\(loc.snapshots)/\(id)")
        return SaveSnapshot(id: id, path: "\(loc.snapshots)/\(id)", created: m.created, reason: .imported, files: inv.files.count, bytes: inv.bytes)
    }

    static func trash(_ s: SaveSnapshot) throws { try FileManager.default.trashItem(at: s.path.url, resultingItemURL: nil) }
}
