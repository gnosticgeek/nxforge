// The keys file (prod.keys) chosen once in Settings: every build, rebuild, Build Selected and the command line use it, and
// NXForge asks only when it is missing or does not read. Only its path is kept (settings "default_keys"); the file is read to
// check it (how many keys, whether header_key is there) and its values are never shown, copied, logged or put in a report.
import Foundation

/// What Settings says about the saved keys file.
enum KeysStatus: Equatable {
    case notSet, missing, unreadable, incomplete, ok(Int)

    var ok: Bool { if case .ok = self { true } else { false } }
    var text: String {
        switch self {
        case .notSet: "Not set: NXForge asks for it at the first build"
        case .missing: "Missing: the file is not there (a drive not connected?)"
        case .unreadable: "Unreadable: not a keys file NXForge can read"
        case .incomplete: "Incomplete: no header_key, so no game can be read"
        case .ok(let n): "Found · \(n) keys"
        }
    }
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .notSet: "key"
        default: "exclamationmark.triangle.fill"
        }
    }
}

enum KeysFile {
    /// Reads the file only to judge it; nothing of its content leaves this function.
    static func status(_ path: String?) -> KeysStatus {
        guard let p = path, !p.isEmpty else { return .notSet }
        guard FileManager.default.fileExists(atPath: p) else { return .missing }
        guard let k = try? Keys(contentsOf: p.url) else { return .unreadable }
        return k.key("header_key", size: 32) == nil ? .incomplete : .ok(k.count)
    }

    /// Where a prod.keys usually is: the games folder (and the folder above it), the switch tools' ~/.switch, the emulators'
    /// keys folders, Documents and Downloads.
    static func candidates(gamesRoot: String?) -> [String] {
        let home = NSHomeDirectory()
        var dirs: [String] = []
        if let r = gamesRoot { dirs += [r, (r as NSString).deletingLastPathComponent] }
        dirs += ["\(home)/.switch"]
        dirs += ["Ryujinx/system", "yuzu/keys", "suyu/keys", "citron/keys", "eden/keys", "sudachi/keys"].map { "\(home)/Library/Application Support/\($0)" }
        dirs += ["\(home)/Documents", "\(home)/Downloads", "\(home)/Desktop"]
        var seen = Set<String>()
        return dirs.map { $0 + "/prod.keys" }.filter { seen.insert($0).inserted }
    }

    /// The first of the usual places holding a keys file that reads, for Settings to offer.
    static func suggestion(gamesRoot: String?) -> String? {
        candidates(gamesRoot: gamesRoot).first { status($0).ok }
    }

    /// The keys a game folder builds with: the saved keys file, else a prod.keys beside the game's files.
    static func resolve(saved: String?, gameFolder: String?) -> String? {
        let fm = FileManager.default
        if let s = saved, fm.fileExists(atPath: s) { return s }
        if let g = gameFolder, fm.fileExists(atPath: g + "/prod.keys") { return g + "/prod.keys" }
        return nil
    }
}
