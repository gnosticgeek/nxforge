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
/// What the window opens on: the front end's Home shelf or Library, or the converter's pages
/// "Library" is kept as the saved value of Discover (it took the Library's place in 0.45)
enum StartIn: String, Codable, CaseIterable {
    case home = "Home", library = "Library", theatre = "Theatre", converter = "Converter"
    var title: String { self == .library ? "Discover" : rawValue }
}
/// How often the games folder is looked at for new games (LibraryModel.watchGamesFolder); manual: only Refresh scans
enum FolderCheck: String, Codable, CaseIterable {
    case minute = "1 min", ten = "10 min", hour = "1 hour", manual = "Manual"
    var seconds: Double? {
        switch self {
        case .minute: 60
        case .ten: 600
        case .hour: 3600
        case .manual: nil
        }
    }
}
/// --cleanup: what the script deletes from <id>_build after a successful build
enum Cleanup: String, Codable, CaseIterable {
    case off, unused, shaders, all
    var label: String { switch self { case .off: "Keep everything"; case .unused: "Remove unused files"; case .shaders: "Keep shader work only"; case .all: "Remove build cache" } }
    /// Whether the build deletes its copies of the game files (the big part of a build folder) once the app is ready.
    var cleansUp: Bool { self == .shaders || self == .all }
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
    /// how often the games folder is looked at for new games, in front or not, and whether coming to the front looks too
    var folderCheck: FolderCheck = .ten
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
    /// where save snapshots go (another drive, a NAS, iCloud Drive): <folder>/<title ID>/; nil beside each save (SaveSnapshots)
    var saveSnapshotsFolder: String?
    /// a checked snapshot of the save each time a game quits, when it changed
    var snapshotAfterPlay = true
    /// the Saves page's switch: every built game syncs its save through cloudSavesFolder (CloudSaves)
    var cloudSavesAll = false
    /// where every game's save goes with the switch on (kept while it is off, so turning it on again goes back there)
    var cloudSavesFolder: String?
    /// each network volume's address to mount it again ("Gaming" → smb://nas/Gaming), learned while it was mounted
    var remounts: [String: String] = [:]
    /// Updates: update the engine and the converter without asking (at launch, and on an hourly check)
    var autoUpdate = false
    /// the versions the launch sheet offered when Skip This Version was pressed ("engine 0.17.1 converter 0.2.2")
    var skippedUpdate: String?
    /// the Library's covers: the smallest width of one, in points (Bigger Covers / Smaller Covers)
    var libraryCoverSize: Double = 150
    /// the Library in a Switch 2 section and a Switch one
    var libraryGroupByConsole = false
    /// the last games chosen on Convert, newest first (RecentSources)
    var recentSources: [String] = []
    /// where the window was at the last quit: the page, the build picked on Builds and the game the Library was on
    var lastPage: String?
    var lastBuild: String?
    var lastLibraryFocus: String?
    /// the front end (Stage): what the window opens on, and how Play behaves there
    var startIn: StartIn = .home
    /// Play opens the game straight in, with its saved Play options (--no-launcher); off: its own settings window as it is set
    var straightPlay = true
    /// the first Play of a game shows its Play options once
    var firstPlayOptions = true
    /// on battery, a run takes the Battery preset without saving it
    var batteryPreset = true
    /// the front end comes back to the front when a game quits
    var returnToLibrary = true
    /// a game on another drive gets its pipeline archive copied to this Mac before it starts (LocalShaders)
    var localShaders = true
    /// box art is downloaded from GameTDB for games that have none
    var downloadCovers = true
    /// wide art for the game page and Home is downloaded from Nintendo's European store for games that have none
    var downloadHeroes = true
    /// a game's description, details and official screenshots are downloaded from its Nintendo store page when its page is opened
    var downloadStoreInfo = true
    /// a built game's media (covers, wide art, screenshots, manual) and its details (media/game.md) are kept in its own folder (GameFolderMedia)
    var mediaInGameFolder = true
    /// a card with the session's time, memory and frame rate when a game quits
    var sessionRecap = true
    /// while a game runs and NXForge is behind it, the window shows a plain card and holds no artwork
    var lightWhilePlaying = true
    /// the front end's covers as the games' square shop art instead of boxes: more to a row, and the same shape as Discover's
    var squareCovers = false
    /// Theatre's theme, and what happens when a TV is plugged in (Theatre.swift)
    var theatreTheme: TheatreTheme = .showcase
    /// Showcase's layout, the carousel or the fan
    var showcaseLayout: ShowcaseLayout = .carousel
    var theatreOnTV: TheatreOnTV = .ask
    /// a controller's Home button brings NXForge to the front on Theatre while it is behind other apps (ControllerNav.home)
    var homeOpensTheatre = true
    /// Theatre's picture inset for a TV that crops its edges, how long until the screensaver, the trailer's volume (0 to 100),
    /// and where Theatre was left: the game in focus and the filter (TheatreFilter.key), so it reopens there
    var theatreEdges: TheatreEdges = .full
    var theatreSaver: TheatreSaver = .five
    var theatreVolume = 100
    var theatreLastGame: String?
    var theatreFilter: String?
    /// Theatre's sounds (clicks as the games turn, a thunk on launch), the focused game's music (a file in its media folder),
    /// its light following the time of day, and the games it has shown (nil until it first opens: none is a new arrival then)
    var theatreSounds = true
    var theatreMusic = true
    var theatreTimeOfDay = true
    /// how a game starts on Theatre: its card into the console, or the lights going down
    var theatreLaunch: TheatreLaunch = .card
    /// the controller rumbles as a case snaps open and a card clicks home
    var theatreRumble = true
    /// the case in the hand leans with the controller (CaseTilt)
    var theatreTilt = true
    /// hours stickers, wear and the COMPLETED stamp on Theatre's cases (CaseKeepsake)
    var theatreCollector = true
    /// the games stamped COMPLETED (StageGame.favoriteKey)
    var completed: [String] = []
    var theatreSeen: [String]?
    /// a folder of MP3 or Opus files Theatre plays in the background (TheatreMusic)
    var theatreMusicFolder: String?
    /// the front end's Favourites (StageGame.favoriteKey: title IDs, or app paths for apps without one), in the order they were added
    var favorites: [String] = []

    static let coverSizes: ClosedRange<Double> = 110...280

    enum CodingKeys: String, CodingKey {
        case repo, python, keys, appearance, notify
        case gameDir = "game_dir", signIdentity = "sign_identity", outDir = "out_dir", defaultKeys = "default_keys", gamesRoot = "games_root", folderCheck = "folder_check"
        case openAfterBuild = "open_after_build", reuseCache = "reuse_cache", keepBackups = "keep_backups", logDetail = "log_detail", cleanup
        case lastSeenVersion = "last_seen_version", libraryLayout = "library_layout", librarySort = "library_sort"
        case saveBackupRepo = "save_backup_repo", saveBackupPush = "save_backup_push", remounts
        case saveSnapshotsFolder = "save_snapshots_folder", snapshotAfterPlay = "snapshot_after_play"
        case cloudSavesAll = "cloud_saves_all", cloudSavesFolder = "cloud_saves_folder"
        case autoUpdate = "auto_update", skippedUpdate = "skipped_update"
        case libraryCoverSize = "library_cover_size", libraryGroupByConsole = "library_group_by_console", recentSources = "recent_sources"
        case lastPage = "last_page", lastBuild = "last_build", lastLibraryFocus = "last_library_focus"
        case startIn = "start_in", straightPlay = "straight_play", firstPlayOptions = "first_play_options", batteryPreset = "battery_preset"
        case returnToLibrary = "return_to_library", downloadCovers = "download_covers", downloadHeroes = "download_heroes", downloadStoreInfo = "download_store_info", favorites
        case mediaInGameFolder = "media_in_game_folder"
        case localShaders = "local_shaders"
        case sessionRecap = "session_recap", lightWhilePlaying = "light_while_playing"
        case squareCovers = "square_covers"
        case theatreTheme = "theatre_theme", showcaseLayout = "theatre_showcase_layout", theatreOnTV = "theatre_on_tv", homeOpensTheatre = "home_opens_theatre"
        case theatreEdges = "theatre_edges", theatreSaver = "theatre_saver", theatreVolume = "theatre_volume"
        case theatreLastGame = "theatre_last_game", theatreFilter = "theatre_filter"
        case theatreSounds = "theatre_sounds", theatreMusic = "theatre_music", theatreTimeOfDay = "theatre_time_of_day", theatreSeen = "theatre_seen", theatreMusicFolder = "theatre_music_folder"
        case theatreLaunch = "theatre_launch", theatreRumble = "theatre_rumble"
        case theatreTilt = "theatre_tilt", theatreCollector = "theatre_collector", completed
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
        folderCheck = (try? c.decodeIfPresent(FolderCheck.self, forKey: .folderCheck)) ?? .ten
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
        saveSnapshotsFolder = try? c.decodeIfPresent(String.self, forKey: .saveSnapshotsFolder)
        snapshotAfterPlay = (try? c.decodeIfPresent(Bool.self, forKey: .snapshotAfterPlay)) ?? true
        cloudSavesAll = (try? c.decodeIfPresent(Bool.self, forKey: .cloudSavesAll)) ?? false
        cloudSavesFolder = try? c.decodeIfPresent(String.self, forKey: .cloudSavesFolder)
        remounts = (try? c.decodeIfPresent([String: String].self, forKey: .remounts)) ?? [:]
        autoUpdate = (try? c.decodeIfPresent(Bool.self, forKey: .autoUpdate)) ?? false
        skippedUpdate = try? c.decodeIfPresent(String.self, forKey: .skippedUpdate)
        libraryCoverSize = min(max((try? c.decodeIfPresent(Double.self, forKey: .libraryCoverSize)) ?? 150, Settings.coverSizes.lowerBound), Settings.coverSizes.upperBound)
        libraryGroupByConsole = (try? c.decodeIfPresent(Bool.self, forKey: .libraryGroupByConsole)) ?? false
        recentSources = (try? c.decodeIfPresent([String].self, forKey: .recentSources)) ?? []
        lastPage = try? c.decodeIfPresent(String.self, forKey: .lastPage)
        lastBuild = try? c.decodeIfPresent(String.self, forKey: .lastBuild)
        lastLibraryFocus = try? c.decodeIfPresent(String.self, forKey: .lastLibraryFocus)
        startIn = (try? c.decodeIfPresent(StartIn.self, forKey: .startIn)) ?? .home
        straightPlay = (try? c.decodeIfPresent(Bool.self, forKey: .straightPlay)) ?? true
        firstPlayOptions = (try? c.decodeIfPresent(Bool.self, forKey: .firstPlayOptions)) ?? true
        batteryPreset = (try? c.decodeIfPresent(Bool.self, forKey: .batteryPreset)) ?? true
        returnToLibrary = (try? c.decodeIfPresent(Bool.self, forKey: .returnToLibrary)) ?? true
        downloadCovers = (try? c.decodeIfPresent(Bool.self, forKey: .downloadCovers)) ?? true
        downloadHeroes = (try? c.decodeIfPresent(Bool.self, forKey: .downloadHeroes)) ?? true
        downloadStoreInfo = (try? c.decodeIfPresent(Bool.self, forKey: .downloadStoreInfo)) ?? true
        mediaInGameFolder = (try? c.decodeIfPresent(Bool.self, forKey: .mediaInGameFolder)) ?? true
        favorites = (try? c.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        localShaders = (try? c.decodeIfPresent(Bool.self, forKey: .localShaders)) ?? true
        sessionRecap = (try? c.decodeIfPresent(Bool.self, forKey: .sessionRecap)) ?? true
        lightWhilePlaying = (try? c.decodeIfPresent(Bool.self, forKey: .lightWhilePlaying)) ?? true
        squareCovers = (try? c.decodeIfPresent(Bool.self, forKey: .squareCovers)) ?? false
        theatreTheme = (try? c.decodeIfPresent(TheatreTheme.self, forKey: .theatreTheme)) ?? .showcase
        // a settings file from before Showcase: its Carousel or Fan theme is the layout to open on
        let savedTheme = (try? c.decodeIfPresent(String.self, forKey: .theatreTheme)).flatMap { $0 }
        showcaseLayout = (try? c.decodeIfPresent(ShowcaseLayout.self, forKey: .showcaseLayout)).flatMap { $0 }
            ?? savedTheme.flatMap { ShowcaseLayout.saved(theme: $0) } ?? .carousel
        theatreOnTV = (try? c.decodeIfPresent(TheatreOnTV.self, forKey: .theatreOnTV)) ?? .ask
        homeOpensTheatre = (try? c.decodeIfPresent(Bool.self, forKey: .homeOpensTheatre)) ?? true
        theatreEdges = (try? c.decodeIfPresent(TheatreEdges.self, forKey: .theatreEdges)) ?? .full
        theatreSaver = (try? c.decodeIfPresent(TheatreSaver.self, forKey: .theatreSaver)) ?? .five
        theatreVolume = min(max((try? c.decodeIfPresent(Int.self, forKey: .theatreVolume)) ?? 100, 0), 100)
        theatreLastGame = try? c.decodeIfPresent(String.self, forKey: .theatreLastGame)
        theatreFilter = try? c.decodeIfPresent(String.self, forKey: .theatreFilter)
        theatreSounds = (try? c.decodeIfPresent(Bool.self, forKey: .theatreSounds)) ?? true
        theatreMusic = (try? c.decodeIfPresent(Bool.self, forKey: .theatreMusic)) ?? true
        theatreTimeOfDay = (try? c.decodeIfPresent(Bool.self, forKey: .theatreTimeOfDay)) ?? true
        theatreLaunch = (try? c.decodeIfPresent(TheatreLaunch.self, forKey: .theatreLaunch)) ?? .card
        theatreRumble = (try? c.decodeIfPresent(Bool.self, forKey: .theatreRumble)) ?? true
        theatreTilt = (try? c.decodeIfPresent(Bool.self, forKey: .theatreTilt)) ?? true
        theatreCollector = (try? c.decodeIfPresent(Bool.self, forKey: .theatreCollector)) ?? true
        completed = (try? c.decodeIfPresent([String].self, forKey: .completed)) ?? []
        theatreSeen = try? c.decodeIfPresent([String].self, forKey: .theatreSeen)
        theatreMusicFolder = try? c.decodeIfPresent(String.self, forKey: .theatreMusicFolder)
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
        // a snapshot that picks a game for Convert (NXC_CONVERT) leaves the real settings as they were
        let env = ProcessInfo.processInfo.environment
        if env["NXC_CONVERT"] != nil { return }
        // and one that sets Theatre's edges or volume
        if env["NXC_SNAPSHOT"] != nil, env["NXC_EDGES"] != nil || env["NXC_VOLUME"] != nil { return }
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
