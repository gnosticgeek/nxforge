// Settings kept between runs in ~/Library/Application Support/NXForge Converter/settings.json. Before 0.8.0 the folder was
// "NxNative Converter"; the first start after the update moves it and leaves a link at the old name (Settings.supportDir).
// Paths only: the keys file's location is remembered, never its content.
import Foundation

enum Appearance: String, Codable, CaseIterable { case system = "System", light = "Light", dark = "Dark" }
enum LogDetail: String, Codable, CaseIterable { case standard = "Standard", detailed = "Detailed" }
/// The Library as rows or as a grid of covers
enum LibraryLayout: String, Codable, CaseIterable { case list, grid }
/// The Library's order
enum LibrarySort: String, Codable, CaseIterable { case name = "Name", recent = "Recently played", size = "Size" }
/// --cleanup: what the script deletes from <id>_build after a successful build
enum Cleanup: String, Codable, CaseIterable {
    case off, unused, all
    var label: String { switch self { case .off: "Keep everything"; case .unused: "Remove unused files"; case .all: "Remove build cache" } }
}

struct Settings: Codable, Equatable {
    var repo: String?
    var python: String?
    var keys: String?
    var gameDir: String?
    /// codesign identity; nil = ad-hoc
    var signIdentity: String?
    /// where new apps go; nil = beside the game files
    var outDir: String?
    /// the keys file for a game folder that has no prod.keys of its own
    var defaultKeys: String?
    /// the Library page's root: every game under it is listed (a drive or a share, such as /Volumes/Gaming/roms/switch)
    var gamesRoot: String?
    var appearance: Appearance = .system
    var notify = true
    var openAfterBuild = false
    /// false deletes the stage keys in <id>_build first, so every step runs again
    var reuseCache = true
    /// a rebuild moves the old app to app-backups/; false moves it to the Trash once the new one is built
    var keepBackups = true
    /// detailed: Copy log adds the tools' own logs from <id>_build/logs
    var logDetail: LogDetail = .standard
    /// what a successful build deletes from <id>_build (--cleanup)
    var cleanup: Cleanup = .off
    /// the converter version whose What's New was last shown (nil: never; the first start of a versioned converter shows it)
    var lastSeenVersion: String?
    var libraryLayout: LibraryLayout = .list
    var librarySort: LibrarySort = .name
    /// a clone of a private Git repository: each game's save is copied there and committed when the game quits (SaveBackup)
    var saveBackupRepo: String?
    /// push the save backup commit as well
    var saveBackupPush = false
    /// each network volume's address to mount it again ("Gaming" → smb://nas/Gaming), learned while it was mounted
    var remounts: [String: String] = [:]
    /// Updates: update the engine and the converter without asking (at launch, and on an hourly check)
    var autoUpdate = false
    /// the versions the launch sheet offered when Skip This Version was pressed ("engine 0.17.1 converter 0.2.2")
    var skippedUpdate: String?

    enum CodingKeys: String, CodingKey {
        case repo, python, keys, appearance, notify
        case gameDir = "game_dir", signIdentity = "sign_identity", outDir = "out_dir", defaultKeys = "default_keys", gamesRoot = "games_root"
        case openAfterBuild = "open_after_build", reuseCache = "reuse_cache", keepBackups = "keep_backups", logDetail = "log_detail", cleanup
        case lastSeenVersion = "last_seen_version", libraryLayout = "library_layout", librarySort = "library_sort"
        case saveBackupRepo = "save_backup_repo", saveBackupPush = "save_backup_push", remounts
        case autoUpdate = "auto_update", skippedUpdate = "skipped_update"
    }

    init() {}

    // every field optional on disk: older settings files (and the Rust app's) lack the newer ones
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        python = try c.decodeIfPresent(String.self, forKey: .python)
        keys = try c.decodeIfPresent(String.self, forKey: .keys)
        gameDir = try c.decodeIfPresent(String.self, forKey: .gameDir)
        signIdentity = try c.decodeIfPresent(String.self, forKey: .signIdentity)
        outDir = try c.decodeIfPresent(String.self, forKey: .outDir)
        defaultKeys = try c.decodeIfPresent(String.self, forKey: .defaultKeys)
        gamesRoot = try c.decodeIfPresent(String.self, forKey: .gamesRoot)
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .system
        notify = (try? c.decodeIfPresent(Bool.self, forKey: .notify)) ?? true
        openAfterBuild = (try? c.decodeIfPresent(Bool.self, forKey: .openAfterBuild)) ?? false
        reuseCache = (try? c.decodeIfPresent(Bool.self, forKey: .reuseCache)) ?? true
        keepBackups = (try? c.decodeIfPresent(Bool.self, forKey: .keepBackups)) ?? true
        logDetail = (try? c.decodeIfPresent(LogDetail.self, forKey: .logDetail)) ?? .standard
        cleanup = (try? c.decodeIfPresent(Cleanup.self, forKey: .cleanup)) ?? .off
        lastSeenVersion = try? c.decodeIfPresent(String.self, forKey: .lastSeenVersion)
        libraryLayout = (try? c.decodeIfPresent(LibraryLayout.self, forKey: .libraryLayout)) ?? .list
        librarySort = (try? c.decodeIfPresent(LibrarySort.self, forKey: .librarySort)) ?? .name
        saveBackupRepo = try? c.decodeIfPresent(String.self, forKey: .saveBackupRepo)
        saveBackupPush = (try? c.decodeIfPresent(Bool.self, forKey: .saveBackupPush)) ?? false
        remounts = (try? c.decodeIfPresent([String: String].self, forKey: .remounts)) ?? [:]
        autoUpdate = (try? c.decodeIfPresent(Bool.self, forKey: .autoUpdate)) ?? false
        skippedUpdate = try? c.decodeIfPresent(String.self, forKey: .skippedUpdate)
    }

    /// NXC_SUPPORT_DIR points the settings and build records elsewhere (for testing beside a running copy)
    static let supportDir: URL = {
        if let d = ProcessInfo.processInfo.environment["NXC_SUPPORT_DIR"] { return URL(fileURLWithPath: d) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "NXForge Converter")
        migrateSupportDir(from: base.appending(path: "NxNative Converter"), to: dir)
        return dir
    }()

    /// Moves the pre-0.8.0 folder (settings, build records, the converter's Python and any engine clone in it) to the new
    /// name once, and leaves a symbolic link at the old name, so paths saved inside it (a venv, `repo`) still resolve.
    /// Nothing happens when the new folder exists or the old one is missing or already a link.
    static func migrateSupportDir(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.path),
              let attrs = try? fm.attributesOfItem(atPath: old.path), attrs[.type] as? FileAttributeType == .typeDirectory else { return }
        do {
            try fm.moveItem(at: old, to: new)
            try? fm.createSymbolicLink(at: old, withDestinationURL: new)
        } catch {
            FileHandle.standardError.write(Data("could not move \(old.path) to \(new.path): \(error.localizedDescription)\n".utf8))
        }
    }

    static func load() -> Settings {
        guard let d = try? Data(contentsOf: supportDir.appending(path: "settings.json")), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(self) { try? d.write(to: Settings.supportDir.appending(path: "settings.json")) }
    }

    /// The preferences Restore defaults resets; the chosen folders and files stay.
    mutating func restoreDefaults() {
        let d = Settings()
        signIdentity = d.signIdentity; outDir = d.outDir; defaultKeys = d.defaultKeys; appearance = d.appearance; notify = d.notify
        openAfterBuild = d.openAfterBuild; reuseCache = d.reuseCache; keepBackups = d.keepBackups; logDetail = d.logDetail; cleanup = d.cleanup; python = nil
    }
}

extension String {
    /// "/Users/tom/Documents/x" → "~/Documents/x"
    var tildePath: String { (self as NSString).abbreviatingWithTildeInPath }
    var url: URL { URL(fileURLWithPath: self) }
    var lastComponent: String { (self as NSString).lastPathComponent }
}

/// "Today at 20:04", "Yesterday at 18:32", "Mar 10, 2025 at 14:17".
func relativeDay(_ d: Date) -> String {
    let cal = Calendar.current
    let time = d.formatted(date: .omitted, time: .shortened)
    if cal.isDateInToday(d) { return "Today at \(time)" }
    if cal.isDateInYesterday(d) { return "Yesterday at \(time)" }
    return "\(d.formatted(.dateTime.month(.abbreviated).day().year())) at \(time)"
}

/// Run a program and wait: (exit status 0, stdout or else stderr, trimmed). nil when it cannot start.
@discardableResult
func run(_ exe: String, _ args: [String], env: [String: String]? = nil, cwd: String? = nil) -> (ok: Bool, out: String)? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, n in n } }
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: o.isEmpty ? e : o, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return (p.terminationStatus == 0, text)
}

/// Single-quote a path for a shell command.
func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
