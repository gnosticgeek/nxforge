// Moving saves in and out (idea 13) and backing them up to a Git repository (idea 14).
//
// Export: the save (and the device save) as one zip, "<Game> save <date>.zip", with save/ and save_device/ inside.
// Import: a zip like that, a folder holding save/ (and save_device/), a snapshot (data/save), or a save folder itself. The preview
// shows both sides (files, size, newest change) and which is newer; the import becomes a checked snapshot first and is put in
// place the way a snapshot is restored, after a snapshot of the save it replaces.
// Git backup: with Settings › Save backup repository set (a clone of a private repository), a game's save is copied into
// <repo>/<game>-<title ID>/ and committed (and pushed, if chosen) when the game quits, and from the game page's Back Up Now.
import AppKit
import Foundation

struct SaveSide: Equatable {
    var files = 0
    var bytes: Int64 = 0
    var newest: Date?
    var text: String {
        files == 0 ? "No save" : "\(files) file\(files == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))" + (newest.map { " · last changed \(relativeDay($0))" } ?? "")
    }
}

struct SaveImport: Identifiable {
    let id = UUID()
    let source: String
    let parts: [(name: String, path: String)]
    let from: SaveSide
    let to: SaveSide
    let loc: SaveLocation
    /// the temporary folder a zip was opened into, removed after
    let temp: String?
}

enum SaveTransfer {
    static func side(_ parts: [(name: String, path: String)]) -> SaveSide {
        var s = SaveSide()
        let fm = FileManager.default
        for (_, root) in parts {
            guard let walk = fm.enumerator(at: root.url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) else { continue }
            for case let u as URL in walk {
                guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                s.files += 1
                s.bytes += Int64(v.fileSize ?? 0)
                if let d = v.contentModificationDate, d > (s.newest ?? .distantPast) { s.newest = d }
            }
        }
        return s
    }

    /// The save parts in what the player chose: (save, save_device) under it, under data/ (a snapshot), or the folder itself.
    static func parts(in dir: String) -> [(name: String, path: String)] {
        let fm = FileManager.default
        for base in [dir, dir + "/data"] where fm.fileExists(atPath: base + "/save") {
            return [("save", base + "/save")] + (fm.fileExists(atPath: base + "/save_device") ? [("save_device", base + "/save_device")] : [])
        }
        // a zip of one folder: look one level down
        let subs = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
        if subs.count == 1, Source.isDir("\(dir)/\(subs[0])"), fm.fileExists(atPath: "\(dir)/\(subs[0])/save") { return parts(in: "\(dir)/\(subs[0])") }
        return [("save", dir)]
    }

    static func prepare(_ source: String, loc: SaveLocation) throws -> SaveImport {
        var dir = source, temp: String?
        if source.lowercased().hasSuffix(".zip") {
            let t = FileManager.default.temporaryDirectory.appending(path: "nxc-import-\(UUID().uuidString)").path
            guard run("/usr/bin/ditto", ["-x", "-k", source, t])?.ok == true else { throw ConverterError("could not open \(source.lastComponent)") }
            dir = t; temp = t
        }
        let p = parts(in: dir)
        return SaveImport(source: source, parts: p, from: side(p), to: side(loc.parts.filter { FileManager.default.fileExists(atPath: $0.path) }), loc: loc, temp: temp)
    }

    static func apply(_ i: SaveImport) throws -> String {
        defer { if let t = i.temp { try? FileManager.default.removeItem(atPath: t) } }
        let snap = try SaveSnapshots.importSnapshot(parts: i.parts, into: i.loc)
        let safety = try SaveSnapshots.restore(snap, to: i.loc)
        return "Save imported (\(snap.files) files)" + (safety.map { "; the one it replaced is snapshot \($0.id)" } ?? "")
    }

    /// The save as one zip in `folder`; its path.
    static func export(_ loc: SaveLocation, name: String, to folder: String) throws -> String {
        let fm = FileManager.default
        guard SaveSnapshots.hasSave(loc) else { throw ConverterError("there is no save to export yet") }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let stem = "\(name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")) save \(f.string(from: Date()))"
        let stage = fm.temporaryDirectory.appending(path: "nxc-export-\(UUID().uuidString)/\(stem)").path
        defer { try? fm.removeItem(atPath: stage.url.deletingLastPathComponent().path) }
        try fm.createDirectory(atPath: stage, withIntermediateDirectories: true)
        for (n, p) in loc.parts where fm.fileExists(atPath: p) { try fm.copyItem(atPath: p, toPath: "\(stage)/\(n)") }
        let zip = "\(folder)/\(stem).zip"
        guard run("/usr/bin/ditto", ["-c", "-k", "--keepParent", stage, zip])?.ok == true else { throw ConverterError("could not write \(zip.lastComponent)") }
        return zip
    }

    // MARK: Git backup

    static func git(_ repo: String, _ args: [String]) -> (ok: Bool, out: String) {
        run("/usr/bin/env", ["git", "-C", repo] + args, env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) ?? (false, "git did not start")
    }

    static func isRepo(_ path: String) -> Bool { git(path, ["rev-parse", "--is-inside-work-tree"]).out == "true" }

    /// Copy the save into the repository and commit it; what happened, in a line.
    static func backUp(_ loc: SaveLocation, name: String, repo: String, push: Bool) throws -> String {
        guard isRepo(repo) else { throw ConverterError("\(repo.tildePath) is not a Git repository") }
        guard SaveSnapshots.hasSave(loc) else { return "No save yet" }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let dest = "\(repo)/\(slug.isEmpty ? "game" : slug)-\(loc.titleID)"
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        for (n, p) in loc.parts {
            if FileManager.default.fileExists(atPath: p) {
                guard run("/usr/bin/rsync", ["-a", "--delete", p + "/", "\(dest)/\(n)/"])?.ok == true else { throw ConverterError("could not copy the \(n) folder") }
            } else { try? FileManager.default.removeItem(atPath: "\(dest)/\(n)") }
        }
        let rel = dest.lastComponent
        _ = git(repo, ["add", "-A", "--", rel])
        if git(repo, ["diff", "--cached", "--quiet", "--", rel]).ok { return "Already backed up: no change since the last backup" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let c = git(repo, ["commit", "-q", "-m", "\(name): save \(f.string(from: Date()))", "--", rel])
        guard c.ok else { throw ConverterError("git commit failed: \(c.out)") }
        if push {
            let p = git(repo, ["push", "-q"])
            if !p.ok { return "Committed, but the push failed: \(p.out.split(separator: "\n").last ?? "")" }
            return "Backed up and pushed"
        }
        return "Backed up (committed)"
    }
}

extension AppModel {
    /// After a game quits: back its save up to the repository, if one is set (off the main thread).
    func backUpSaveAfterPlay(app: String, name: String) {
        guard settings.saveBackupRepo != nil else { return }
        backUpSave(app: app, name: name)
    }

    func backUpSave(app: String, name: String) {
        guard let repo = settings.saveBackupRepo, let tid = VerifiedGames.titleID(ofApp: app) else { return }
        let loc = SaveSnapshots.location(app: app, titleID: tid), push = settings.saveBackupPush
        backupStatus[tid] = (true, "Backing up…")
        Task.detached {
            let r: (Bool, String)
            do { r = (true, try SaveTransfer.backUp(loc, name: name, repo: repo, push: push)) } catch { r = (false, "\(error)") }
            await MainActor.run { self.backupStatus[tid] = (r.0, r.1 + " · \(relativeDay(Date()))") }
        }
    }

    func chooseSaveBackupRepo() {
        guard let d = choose(folder: true, start: settings.saveBackupRepo) else { return }
        if SaveTransfer.isRepo(d) { settings.saveBackupRepo = d }
        else { _ = confirm("Not a Git repository", "\(d.tildePath) is not a clone of a Git repository. Clone your private repository (for example with GitHub Desktop or git clone), then choose that folder.", action: "OK") }
    }
}
