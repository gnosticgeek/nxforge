// Cloud saves for every game (Converter 0.21.2): one switch on the Saves page gives the whole library one sync folder, iCloud Drive or
// any folder. It is the engine's own Cloud saves (dm/host/save_sync.c), set the way docs/frontends.md "The cloud saves folder" says a
// front end may: the folder's path in each built app's cloudSaves.folder, which the launcher passes on as DM_SAVE_SYNC at every start.
// Each game keeps its own <folder>/<title ID>/save.dmsync there, so one folder serves them all. The switch is written again into every
// built game when it changes, when the converter starts, after a build and before each Play, so a game built later joins in.
import AppKit
import Foundation

/// A game's copy in the cloud folder, read from the header of its save.dmsync (save_sync.c: the hash at 16, the save time at 48, the device at 80).
struct CloudCopy: Equatable {
    enum State: Equatable { case none, notDownloaded, present }
    var state: State
    var saved: Date?
    var device: String?
    /// the copy is the save this Mac last synced (its <save>.sync base): nothing waits to come in
    var matchesThisMac = false
}

enum CloudSaves {
    /// iCloud Drive, as the Finder shows it
    static let drive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
    /// where the switch puts saves when no folder was chosen yet
    static let defaultFolder = drive + "/NXForge Saves"
    static var iCloudDriveOn: Bool { FileManager.default.fileExists(atPath: drive) }

    /// The game's own folder setting (nil: off)
    static func folder(app: String) -> String? {
        guard let v = LaunchSettings.defaults(app: app)?.string(forKey: "cloudSaves.folder"), !v.isEmpty else { return nil }
        return v
    }

    /// Writes the folder into the game's preferences (nil turns its cloud saves off). True when it changed.
    @discardableResult
    static func set(app: String, folder: String?) -> Bool {
        guard let d = LaunchSettings.defaults(app: app), self.folder(app: app) != folder else { return false }
        if let folder { d.set(folder, forKey: "cloudSaves.folder") } else { d.removeObject(forKey: "cloudSaves.folder") }
        d.synchronize()
        return true
    }

    /// The folder the switch gives every game: the chosen one, else one a game already uses (so turning it on keeps that game's
    /// sync where it was), else iCloud Drive › NXForge Saves.
    static func suggestedFolder(chosen: String?, apps: [String]) -> String {
        if let chosen { return chosen }
        var count: [String: Int] = [:]
        for a in apps { if let f = folder(app: a) { count[f, default: 0] += 1 } }
        return count.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? defaultFolder
    }

    /// <folder>/<title ID>/save.dmsync, or <folder>/save.dmsync when the folder is the game's own (save_sync.c cloud_path)
    static func file(folder: String, titleID: String) -> String {
        var dir = folder
        while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
        if dir.url.lastPathComponent.caseInsensitiveCompare(titleID) == .orderedSame { return dir + "/save.dmsync" }
        return "\(dir)/\(titleID.uppercased())/save.dmsync"
    }

    /// What the cloud folder holds for a game, without downloading anything
    static func copy(folder: String, titleID: String, save: String) -> CloudCopy {
        let path = file(folder: folder, titleID: titleID)
        let placeholder = path.url.deletingLastPathComponent().appendingPathComponent(".save.dmsync.icloud").path
        guard let h = FileHandle(forReadingAtPath: path) else {
            return CloudCopy(state: FileManager.default.fileExists(atPath: placeholder) ? .notDownloaded : .none)
        }
        defer { try? h.close() }
        guard let hdr = try? h.read(upToCount: 144), hdr.count == 144, hdr.prefix(8) == Data("DMSYNC1\n".utf8) else {
            return CloudCopy(state: .present)
        }
        let hash = String(decoding: hdr[16..<48], as: UTF8.self)
        let secs = hdr[48..<56].withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian
        let device = String(decoding: hdr[80..<144].prefix { $0 != 0 }, as: UTF8.self)
        return CloudCopy(state: .present, saved: secs > 0 ? Date(timeIntervalSince1970: TimeInterval(secs)) : nil,
                         device: device.isEmpty ? nil : device, matchesThisMac: base(save: save) == hash)
    }

    /// <save>.sync's base line: the hash last known to be the same here and in the cloud
    static func base(save: String) -> String? {
        guard let s = try? String(contentsOfFile: save + ".sync", encoding: .utf8) else { return nil }
        for line in s.split(separator: "\n") where line.hasPrefix("base\t") { return String(line.dropFirst(5)) }
        return nil
    }

    /// "iCloud Drive › NXForge Saves" for a path in iCloud Drive (Obsidian's and other apps' folders too); any other path with ~
    static func shown(_ path: String) -> String {
        let docs = NSHomeDirectory() + "/Library/Mobile Documents/"
        if path == drive || path.hasPrefix(drive + "/") {
            return (["iCloud Drive"] + path.dropFirst(drive.count).split(separator: "/").map(String.init)).joined(separator: " › ")
        }
        if path.hasPrefix(docs) {   // another app's iCloud folder: iCloud~md~obsidian/Documents/… → iCloud Drive › Obsidian › …
            var parts = path.dropFirst(docs.count).split(separator: "/").map(String.init)
            if let app = parts.first { parts[0] = app.split(separator: "~").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? app }
            if parts.count > 1, parts[1] == "Documents" { parts.remove(at: 1) }
            return (["iCloud Drive"] + parts).joined(separator: " › ")
        }
        return path.tildePath
    }

    static func inICloud(_ path: String) -> Bool { path.hasPrefix(NSHomeDirectory() + "/Library/Mobile Documents/") }
}

extension AppModel {
    /// The Saves page's switch: every built game syncs through the chosen folder, or none does.
    func setCloudSavesForAll(_ on: Bool) {
        let apps = Engine.builds().map(\.app)
        if on {
            let folder = CloudSaves.suggestedFolder(chosen: settings.cloudSavesFolder, apps: apps)
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            settings.cloudSavesFolder = folder
        }
        settings.cloudSavesAll = on
        let changed = syncCloudSaves(apps: apps)
        revision += 1
        if on {
            showBanner("Cloud saves on for every game", detail: "\(changed) game\(changed == 1 ? "" : "s") changed. Each sends its save to \(CloudSaves.shown(settings.cloudSavesFolder ?? "")) at its next start.", tone: .success, symbol: "icloud")
        } else {
            showBanner("Cloud saves off", detail: "Saves stay on this Mac. The copies already in the folder are left there.", tone: .info, symbol: "icloud.slash")
        }
    }

    /// Choose where every game's save goes; with the switch on, every game moves there.
    func chooseCloudSavesFolder() {
        let start = settings.cloudSavesFolder ?? (CloudSaves.iCloudDriveOn ? CloudSaves.drive : NSHomeDirectory())
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Use for Saves"
        panel.message = "Every game's save goes here, each in a folder named after its title ID. Pick a folder in iCloud Drive to sync with your other devices."
        panel.directoryURL = URL(fileURLWithPath: start)
        guard panel.runModal() == .OK, let url = panel.url, url.path != settings.cloudSavesFolder else { return }
        settings.cloudSavesFolder = url.path
        if settings.cloudSavesAll {
            let n = syncCloudSaves(apps: Engine.builds().map(\.app))
            showBanner("Saves now go to \(CloudSaves.shown(url.path))", detail: "\(n) game\(n == 1 ? "" : "s") changed. Each sends its save there at its next start; the old folder keeps its copies.", tone: .success, symbol: "folder")
        }
        revision += 1
    }

    /// Writes the switch into each built game: the folder when it is on, nothing when off. The number of games changed.
    @discardableResult
    func syncCloudSaves(apps: [String]) -> Int {
        let target = settings.cloudSavesAll ? settings.cloudSavesFolder : nil
        return apps.reduce(0) { n, app in n + (CloudSaves.set(app: app, folder: target) ? 1 : 0) }
    }

    /// At the converter's start and after a build, with the switch on: a game built or changed since gets the folder. With it off,
    /// nothing is touched, so a game's own Cloud saves folder (chosen in its settings window) stays.
    func syncCloudSavesIfOn() {
        guard settings.cloudSavesAll, settings.cloudSavesFolder != nil else { return }
        Task.detached(priority: .utility) {
            let apps = Engine.builds().map(\.app)
            await MainActor.run { if self.syncCloudSaves(apps: apps) > 0 { self.revision += 1 } }
        }
    }

    /// Before a Play: a game built since the switch went on gets the folder too.
    func applyCloudSaves(app: String) {
        guard settings.cloudSavesAll, let f = settings.cloudSavesFolder else { return }
        CloudSaves.set(app: app, folder: f)
    }
}
