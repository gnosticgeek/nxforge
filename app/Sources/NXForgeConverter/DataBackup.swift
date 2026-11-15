// A checked copy, once a day, of what NXForge alone knows (Converter 0.14.0, from RetroReplay's daily verified backup): the time
// played (playtime.json), the settings with the favourites and the keys file's place (settings.json), the build records
// (builds.json), the last library scan (library.json) and the covers you chose yourself (covers/*-own.*). A rebuild can make
// every app again; it cannot make these again. Each copy is read back and compared (SHA-256) before it counts, the last 7 days
// are kept, and Restore puts one back after first copying what is there now.
import AppKit
import CryptoKit
import Foundation

struct DataBackupFile: Codable, Hashable {
    var path: String
    var bytes: Int64
    var sha256: String
}

struct DataBackupManifest: Codable, Hashable {
    var made: Date
    var files: [DataBackupFile]
    var verified: Bool
}

/// One kept copy: its folder and what its manifest says
struct DataBackupEntry: Identifiable, Hashable {
    var id: String { folder.path }
    let folder: URL
    let manifest: DataBackupManifest
    var name: String { folder.lastPathComponent }
}

enum DataBackup {
    static var dir: URL { Settings.supportDir.appending(path: "backups") }
    static let keep = 7
    /// the files at the top of the support folder that a backup copies
    static let topFiles = ["settings.json", "playtime.json", "builds.json", "library.json"]

    /// What a backup copies now: paths relative to the support folder.
    static func sources(root: URL = Settings.supportDir, fm: FileManager = .default) -> [String] {
        var out = topFiles.filter { fm.fileExists(atPath: root.appending(path: $0).path) }
        let covers = root.appending(path: "covers")
        for f in ((try? fm.contentsOfDirectory(atPath: covers.path)) ?? []).sorted() where f.contains("-own.") {
            out.append("covers/\(f)")
        }
        return out
    }

    static func sha256(_ u: URL) -> String? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// The kept copies, newest first
    static func list(fm: FileManager = .default) -> [DataBackupEntry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { n -> DataBackupEntry? in
            let f = dir.appending(path: n)
            guard let d = try? Data(contentsOf: f.appending(path: "manifest.json")), let m = try? dec.decode(DataBackupManifest.self, from: d) else { return nil }
            return DataBackupEntry(folder: f, manifest: m)
        }
        .sorted { $0.manifest.made > $1.manifest.made }
    }

    /// The newest copy that was checked
    static func latest() -> DataBackupEntry? { list().first { $0.manifest.verified } }

    /// Copies the files into backups/<name>, reads each copy back against its source, and writes the manifest. Returns the
    /// manifest (verified false when a copy did not match), or nil when nothing could be written.
    @discardableResult
    static func make(name: String? = nil, now: Date = Date(), root: URL = Settings.supportDir, fm: FileManager = .default) -> DataBackupManifest? {
        let dest = root.appending(path: "backups").appending(path: name ?? stamp(now))
        let tmp = root.appending(path: "backups").appending(path: ".partial-\(UUID().uuidString)")
        do { try fm.createDirectory(at: tmp, withIntermediateDirectories: true) } catch { return nil }
        var files: [DataBackupFile] = [], ok = true
        for rel in sources(root: root, fm: fm) {
            let src = root.appending(path: rel), to = tmp.appending(path: rel)
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let want = sha256(src), (try? fm.copyItem(at: src, to: to)) != nil else { ok = false; continue }
            let got = sha256(to)
            if got != want { ok = false }
            let bytes = ((try? fm.attributesOfItem(atPath: to.path))?[.size] as? NSNumber)?.int64Value ?? 0
            files.append(DataBackupFile(path: rel, bytes: bytes, sha256: want))
        }
        let m = DataBackupManifest(made: now, files: files, verified: ok && !files.isEmpty)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(m), (try? d.write(to: tmp.appending(path: "manifest.json"))) != nil else { try? fm.removeItem(at: tmp); return nil }
        // the day's copy is replaced only by one that is complete
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        guard (try? fm.moveItem(at: tmp, to: dest)) != nil else { try? fm.removeItem(at: tmp); return nil }
        prune(root: root, fm: fm)
        return m
    }

    /// Keeps the newest `keep` daily copies (and every copy taken before a restore from the last 30 days)
    static func prune(root: URL = Settings.supportDir, fm: FileManager = .default) {
        let base = root.appending(path: "backups")
        let names = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).filter { !$0.hasPrefix(".") }
        let daily = names.filter { !$0.contains("before-restore") }.sorted(by: >)
        for n in daily.dropFirst(keep) { try? fm.removeItem(at: base.appending(path: n)) }
        let cutoff = stamp(Date().addingTimeInterval(-30 * 86400))
        for n in names where n.contains("before-restore") && n < cutoff { try? fm.removeItem(at: base.appending(path: n)) }
        // a copy that never finished
        for n in ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []) where n.hasPrefix(".partial-") { try? fm.removeItem(at: base.appending(path: n)) }
    }

    /// Whether today's checked copy is there already
    static func doneToday(now: Date = Date()) -> Bool {
        list().contains { $0.name == stamp(now) && $0.manifest.verified }
    }

    /// Puts a copy back: what is there now is copied first (backups/<date>-before-restore), then each file of the copy that
    /// still matches its manifest replaces the current one. Returns the files put back, or nil when the safety copy failed.
    static func restore(_ e: DataBackupEntry, root: URL = Settings.supportDir, fm: FileManager = .default) -> Int? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd-HHmmss"
        guard make(name: f.string(from: Date()) + "-before-restore", root: root, fm: fm) != nil else { return nil }
        var n = 0
        for file in e.manifest.files {
            let src = e.folder.appending(path: file.path), to = root.appending(path: file.path)
            guard sha256(src) == file.sha256 else { continue }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = to.deletingLastPathComponent().appending(path: ".restore-\(UUID().uuidString)")
            guard (try? fm.copyItem(at: src, to: tmp)) != nil else { continue }
            if fm.fileExists(atPath: to.path) {
                if (try? fm.replaceItemAt(to, withItemAt: tmp)) != nil { n += 1 } else { try? fm.removeItem(at: tmp) }
            } else if (try? fm.moveItem(at: tmp, to: to)) != nil { n += 1 }
        }
        return n
    }
}

extension AppModel {
    /// Once a day (at start, and when NXForge comes to the front a day later), off the main thread.
    func backUpDataIfDue() {
        guard !backupRunning else { return }
        if let last = lastDataBackup, Calendar.current.isDateInToday(last) { return }
        backUpData(force: false)
    }

    func backUpData(force: Bool) {
        guard !backupRunning else { return }
        backupRunning = true
        Task { @MainActor [weak self] in
            let m = await Task.detached(priority: .utility) { () -> DataBackupManifest? in
                if !force && DataBackup.doneToday() { return DataBackup.latest()?.manifest }
                return DataBackup.make()
            }.value
            guard let self else { return }
            self.backupRunning = false
            if let m, m.verified { self.lastDataBackup = m.made; self.dataBackupFailed = false }
            else { self.dataBackupFailed = true }
            if force {
                if let m, m.verified { self.showBanner("NXForge's data is backed up", detail: "\(m.files.count) files copied and checked.", tone: .success) }
                else { self.showBanner("The backup did not complete", detail: "A copy did not match its file, or the support folder could not be written.", tone: .warning) }
            }
        }
    }

    /// Restore from a kept copy, after asking; reloads what was put back.
    func restoreData(_ e: DataBackupEntry) {
        let when = e.manifest.made.formatted(date: .abbreviated, time: .shortened)
        guard confirm("Restore NXForge's data from \(when)?", "Your time played, settings, favourites, build records, library list and your own covers go back to how they were then. What is there now is copied first, so this can be undone by restoring that copy.", action: "Restore") else { return }
        let n = DataBackup.restore(e)
        guard let n else { showBanner("Nothing was restored", detail: "The copy of what is there now could not be made first.", tone: .warning); return }
        settings = Settings.load()
        library = GameLibrary.loadCache()
        revision += 1
        showBanner("Restored \(n) file\(n == 1 ? "" : "s") from \(when)", tone: .success)
    }
}
