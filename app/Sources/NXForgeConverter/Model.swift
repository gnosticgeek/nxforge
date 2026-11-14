// The window's state: settings, toolchain checks, the folder's validation, the engine and the build run.
// Slow work (checks, validation, git) runs off the main thread and lands back here.
import AppKit
import Observation
import UniformTypeIdentifiers
import UserNotifications

enum Page: String, CaseIterable, Identifiable {
    case convert = "Convert", library = "Library", builds = "Builds", storage = "Storage", toolchain = "Toolchain", updates = "Updates"
    var id: String { rawValue }
    /// drawn with its own banner and big heading (HeroHeader) instead of the window title
    var hasHero: Bool { true }
    var symbol: String {
        switch self {
        case .convert: "macwindow.badge.plus"
        case .library: "books.vertical"
        case .builds: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .storage: "internaldrive"
        case .toolchain: "wrench.and.screwdriver"
        case .updates: "arrow.down.circle"
        }
    }
}

enum BuildSort: String, CaseIterable { case newest = "Newest first", oldest = "Oldest first", name = "Name" }

/// Which console a build's game is for: Switch 2 title IDs start 04 (0400486024DEC000), Switch ones 01.
enum Console: String, CaseIterable {
    case switch2 = "Switch 2", switch1 = "Switch"

    static func of(_ b: BuildRecord) -> Console {
        if let t = VerifiedGames.titleID(ofApp: b.app) { return t.hasPrefix("04") ? .switch2 : .switch1 }
        return Source.isNupFile(b.gameDir) || b.gameFiles == "NUP container" ? .switch2 : .switch1
    }
}

/// The Builds page's console filter
enum ConsoleFilter: String, CaseIterable { case all = "All", switch2 = "Switch 2", switch1 = "Switch" }

@MainActor @Observable
final class AppModel {
    var page: Page = .convert { didSet { if page != oldValue { rememberWindowState() } } }
    var settings = Settings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.appearance != oldValue.appearance { applyAppearance() }
            if let g = settings.gameDir, g != oldValue.gameDir { settings.recentSources = RecentSources.adding(g, to: settings.recentSources) }
            if settings.outDir != oldValue.outDir { Disk.outDir = settings.outDir; measure() }   // the app's drive is checked for room too
        }
    }
    var checks: [Check]?
    var env: ToolEnv?
    var checking = false
    var lastChecked: Date?
    var validation: Validation?
    var validating = false
    var validatedFor: (String, String?)?
    /// the chosen game when it needs no keys (a NUP or a dump folder), as the engine read it
    var source: SourceInfo?
    /// a dump folder's sizes are being read after its quick read (Source.read quick:)
    var sizing = false
    var game: GameInfo?
    var engine: EngineVersion?
    /// docs/nxforge-games.tsv of the engine checkout, by title ID: the Builds page's "On NXForge" row
    var verified: [String: VerifiedGame] = [:]
    var engineMessage: (ok: Bool, text: String)?
    var engineBusy = false
    var identities: [String] = []
    let run = BuildRun()
    /// bumped when a build ends or files move, so lists of apps on disk are read again
    var revision = 0
    var buildSearch = ""
    var buildSort: BuildSort = .newest
    var buildConsole: ConsoleFilter = .all
    /// Library: the last scan of the games folder (kept in library.json), and the scan running now: (folders read, folder being read)
    var library: LibraryScan? = GameLibrary.loadCache()
    var libraryProgress: (folders: Int, current: String, found: Int)?
    var librarySearch = ""
    var libraryConsole: ConsoleFilter = .all
    var libraryMessage: String?
    var libraryFilter: LibraryFilter = .all
    /// reading names and icons from the games' control data: (done, of)
    var libraryDetails: (done: Int, total: Int)?
    /// games ticked for Build selected, by id
    var librarySelection: Set<String> = []
    /// Build selected: the games still to build, the one building now, what happened to each, and why it stopped, if it did
    var batchQueue: [LibraryGame] = []
    var batchCurrent: LibraryGame?
    var batchResults: [BatchResult] = []
    var batchMessage: String?
    var libraryTask: Task<Void, Never>?
    var detailsTask: Task<Void, Never>?
    var mountObserver: NSObjectProtocol?
    var selectedBuild: String? { didSet { if selectedBuild != oldValue { rememberWindowState() } } }
    /// Rebuild all: the apps still to rebuild after the one running, and why it stopped, if it did
    var rebuildQueue: [BuildRecord] = []
    /// rebuildCost's answers; emptied when a build ends (the build folder changed)
    @ObservationIgnored var costCache: [String: RebuildCost] = [:]
    var queueMessage: String?
    /// the converter's own Python being set up: (running, what it says)
    var pythonSetup: (running: Bool, text: String)?
    /// the newest release's first change, when the engine's branch has updates
    var updateNote: String?
    private var checkedForUpdates = false
    /// the optional tools this game needs (GameNeeds), by check name, with why
    var needs: [String: String] = [:]
    /// free space against what a build of the chosen folder needs (Disk.need), measured off the main thread
    var diskNeed: Disk.Need?
    /// how long each stage of this game's build should take (Estimates), for the timeline before and during a build
    var expected: [String: Double] = [:]
    /// a warning while a build runs: free space is getting low
    var diskWarning: String?
    /// a fix ran in Terminal: check the tools again when the converter is the active app again
    var fixPending = false
    /// the converter's own What's New, shown as a sheet (ConverterUpdate)
    var whatsNew: WhatsNew?
    /// a newer converter in the engine checkout or on its update branch, and the update running
    var converterUpdate: ConverterUpdateInfo?
    var converterUpdating = false
    /// Updates (Updates.swift): what the last engine check found (nil: up to date or not checked), and when it ran
    var engineUpdate: Engine.Update?
    var lastUpdateCheck: Date?
    /// upstream nxnative's commits NXForge has not merged yet
    var upstream: UpstreamStatus?
    /// Get Upstream Now / Back to the release (Updates.swift): running, and how the last one went
    var localUpstream: (running: Bool, ok: Bool, text: String)?
    /// the sidebar version in the engine checkout, and in each built app ("" before the sidebar had one), by app path
    var sidebarCurrent: String?
    var sidebarBuilds: [String: String] = [:]
    /// the sheet offering updates at launch, and one waiting for What's New to close
    var updateOffer: UpdateOffer?
    var pendingOffer: UpdateOffer?
    /// the game page open over the Library or Builds (GamePage), and the quick preview (Space)
    var gameDetail: GameRef?
    var preview: GameRef?
    /// the game the keyboard or a controller is on, in the Library (and the grid's columns, for up and down)
    var libraryFocus: String? { didSet { if libraryFocus != oldValue { rememberWindowState() } } }
    var libraryColumns = 1
    /// the couch: the Library's covers full screen, driven by a controller (ControllerNav)
    var couchMode = false
    var commandPalette = false
    /// the last Library move, to undo (files moved into a folder of their own, or beside their game)
    var lastMove: LibraryMove?
    /// play sessions running now, by process ID (PlayTracker)
    var playing: [pid_t: PlayingNow] = [:]
    /// the last save backup of each game, by title ID (SaveBackup)
    var backupStatus: [String: (ok: Bool, text: String)] = [:]
    /// Build selected waiting to start: at a time, or once the Mac is on power (and the activity keeping it awake meanwhile)
    var batchStart: BatchStart?
    var batchWait: Task<Void, Never>?
    var batchActivity: NSObjectProtocol?
    /// the summary a failed build's notification copies (Copy error summary)
    var lastErrorSummary: String?
    var playObservers: [NSObjectProtocol] = []
    /// the note at the foot of the window (UIExtras: banners), and what Storage deleted that Undo can still put back
    var banner: Banner?
    var pendingDeletes: [PendingDelete] = []
    private var diskWatch: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?
    /// the window's model, for the Dock (a folder dropped on its icon) and the menu commands
    nonisolated(unsafe) static weak var shared: AppModel?

    init() {
        AppModel.shared = self
        Disk.outDir = settings.outDir
        run.onChange = { [weak self] in
            guard let self else { return }
            DockProgress.show(self.run)
            StatusProgress.show(self)
            guard !self.run.running, let r = self.run.result else { return }
            self.refreshGame()
            self.revision += 1
            self.buildEnded(r)
        }
        applyAppearance()
        restoreWindowState()
        purgeLeftoverDeletes()
        recheck()
        watchMounts()
        trackPlay()
        restoreBatchQueue()
        if settings.gameDir != nil { validate() }
        // back from Terminal after a Fix: check again, so a fixed tool turns green without pressing Run checks
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recheckUpdatesIfStale()
                guard let self, self.fixPending, !self.checking else { return }
                self.fixPending = false
                self.recheck()
            }
        }
    }

    /// Every required check passes, and so do the optional ones this game needs.
    var allOK: Bool { checks?.allSatisfy { $0.ok || ($0.optional && needs[$0.name] == nil) } ?? false }
    /// The optional tools this game needs that are not installed.
    var missingForGame: [Check] { (checks ?? []).filter { !$0.ok && $0.optional && needs[$0.name] != nil } }
    var passed: Int { checks?.filter(\.ok).count ?? 0 }
    var valid: Bool {
        guard let v = validation, let f = validatedFor else { return false }
        return v.ok && f.0 == settings.gameDir && (!needsKeys || f.1 == settings.keys)
    }
    /// whether the chosen game is read with prod.keys: false for a NUP or a dump folder
    var needsKeys: Bool { settings.gameDir.map(Source.needsKeys) ?? true }
    /// the folder holding the chosen game's files: the game folder, or the folder of the chosen .nup
    var gameFolder: String? { settings.gameDir.map(Source.folder) }
    var ready: Bool { allOK && valid && !run.running }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func recheck() {
        checking = true
        let s = settings
        Task.detached {
            let (c, e) = Toolchain.checkAll(s)
            let ids = Toolchain.signingIdentities()
            let ver = e.repo.flatMap(Engine.current)
            let verified = VerifiedGames.load(e.repo)
            await MainActor.run {
                let repoChanged = self.env?.repo != e.repo
                self.checks = c; self.env = e; self.identities = ids; self.engine = ver; self.verified = verified; self.checking = false; self.lastChecked = Date()
                // a NUP or a dump is read by the engine's Python: check it again now that it is known (zbic may just have been installed)
                if !self.needsKeys { self.validate() }
                if repoChanged { self.measure() }   // the game's profile (GameNeeds) is in the engine checkout
                // once per launch: look for a newer engine (a fetch; quiet when offline)
                if !self.checkedForUpdates, ver != nil { self.checkedForUpdates = true; self.engineAction(update: false, reason: .launch) }
                if repoChanged { self.refreshSidebarStatus() }
                self.showWhatsNewIfNeeded()
                self.learnRemounts()
            }
        }
    }

    func validate() {
        guard let dir = settings.gameDir else { return }
        let keys = settings.keys
        if Source.needsKeys(dir) && keys == nil { validation = nil; source = nil; refreshGame(); return }
        validating = true
        validation = nil
        source = nil
        validatedFor = (dir, keys)
        refreshGame()
        let env = self.env
        sizing = false
        Task.detached {
            // a dump folder first without its sizes, which take a walk of every file (minutes on an exFAT drive before 0.22.0)
            let (v, read) = Source.validate(dir, keys: keys, env: env, quick: true)
            let info = read.map { $0.sized ? $0 : Source.cachedSizes($0) ?? $0 }
            let sized = info?.sized ?? true
            await MainActor.run {
                guard self.validatedFor?.0 == dir else { return }   // another game was chosen meanwhile
                self.validation = v; self.source = info; self.validating = false; self.sizing = !sized
                self.refreshGame()
                if info != nil { self.measure() }   // a Switch 2 game's size and needs come from what it read
            }
            guard !sized, let env, case .success(let full) = Source.read(dir, env: env) else {
                if !sized { await MainActor.run { if self.validatedFor?.0 == dir { self.sizing = false } } }
                return
            }
            Source.remember(full)
            await MainActor.run {
                guard self.validatedFor?.0 == dir, var s = self.source else { return }
                s.romfsBytes = full.romfsBytes; s.fileBytes = full.fileBytes
                self.source = s; self.sizing = false
                self.measure()
            }
        }
        measure()
    }

    func refreshGame() {
        game = settings.gameDir.map { GameInfo.read($0, source: source) }
    }

    /// Files dropped on the Convert page (DropFiles): the game folder first, since it brings the prod.keys beside it, then a dropped keys
    /// file over that. False when the drop held nothing usable, or a build is running.
    @discardableResult func drop(_ urls: [URL]) -> Bool {
        let d = DropFiles.sort(urls)
        guard d.usable, !run.running else { return false }
        if let dir = d.gameDir { setGameDir(dir) }
        if let k = d.keys { settings.keys = k; validate() }
        return true
    }

    /// What this game's build needs (tools, disk space, time), worked out off the main thread.
    func measure() {
        guard let dir = gameFolder else { needs = [:]; diskNeed = nil; expected = [:]; return }
        let repo = env?.repo, out = settings.outDir, src = source
        let app = Engine.apps(in: Disk.appHome(dir)).first?.app ?? Engine.apps(in: dir).first?.app
        let builds = Engine.builds()
        Task.detached {
            let n = GameNeeds.detect(dir: dir, repo: repo)
            let bytes = src.map { max($0.fileBytes, $0.romfsBytes, 0) } ?? Estimates.gameBytes(dir)
            let e = Estimates.expected(gameDir: dir, gameBytes: bytes, builds: builds)
            await MainActor.run { if self.gameFolder == dir { self.needs = n; self.expected = e } }
            let d = Disk.need(gameDir: dir, outDir: out, app: app, firstBuild: src.map(Source.firstBuildBytes), gameBytes: bytes)
            await MainActor.run { if self.gameFolder == dir { self.diskNeed = d } }
        }
    }

    func setGameDir(_ dir: String) {
        // prod.keys beside the game files is the usual layout; else the default keys file, else the one chosen before
        let beside = Source.folder(of: dir) + "/prod.keys"
        if FileManager.default.fileExists(atPath: beside) { settings.keys = beside }
        else if let d = settings.defaultKeys, FileManager.default.fileExists(atPath: d) { settings.keys = d }
        settings.gameDir = dir
        validate()
        if settings.keys == nil { measure() }   // validate measures only with keys chosen
    }

    /// Check for engine updates (a fetch with tags), or update the engine and check again, so the status never stays at
    /// "Updated" while something newer has landed meanwhile. Then the converter, the sidebar and upstream are looked at too.
    func engineAction(update: Bool, reason: UpdateCheckReason = .manual) {
        guard let repo = env?.repo, !engineBusy else { return }
        engineBusy = true
        engineMessage = (true, update ? "Updating…" : "Checking…")
        let branch = engine?.branch
        Task.detached {
            var msg: (Bool, String)
            var found: Engine.Update?
            do {
                if update {
                    try Engine.update(repo)
                    let now = Engine.current(repo)?.short ?? "the newest"
                    found = try? Engine.checkUpdates(repo)
                    let more = found.flatMap { $0.count > 0 ? " · \($0.release ?? "\($0.count) more") available" : nil } ?? ""
                    msg = (true, "Updated to \(now)\(more)")
                } else {
                    let u = try Engine.checkUpdates(repo)
                    found = u
                    msg = (true, AppModel.describe(u, branch: branch))
                }
            } catch { msg = (false, "\(error)") }
            let ver = Engine.current(repo)
            let available = found.flatMap { $0.count > 0 ? $0 : nil }
            let note = available.flatMap { Engine.upstreamNote(repo, target: $0.ref) }
            let target = found?.ref
            await MainActor.run {
                self.engineMessage = msg; self.engine = ver; self.engineBusy = false; self.updateNote = note
                self.engineUpdate = available
                self.lastUpdateCheck = Date()
                self.revision += 1
                self.checkConverterUpdate(target: target, reason: update ? .manual : reason)
                self.refreshSidebarStatus()
                self.checkUpstream()
            }
        }
    }

    /// "Up to date", "0.17.1 available", or "3 updates available on main" for a branch's commits.
    nonisolated static func describe(_ u: Engine.Update, branch: String?) -> String {
        if u.count == 0 { return "Up to date" }
        if let r = u.release { return "\(r) available" }
        let onto = u.target.split(separator: "/", maxSplits: 1).last.map(String.init) ?? u.target
        let other = onto != (branch ?? onto) ? " on \(onto)" : ""
        return "\(u.count) update\(u.count == 1 ? "" : "s") available\(other)"
    }

    var updatesAvailable: Bool { engineUpdate != nil }

    /// The folder new apps go to: the setting, else beside the game files.
    var outputFolder: String? { settings.outDir ?? gameFolder.map(Disk.buildHome) }

    /// Build the chosen game, or with plan only say what a build would reuse and redo (--plan).
    /// scratch: the build folder is emptied first, so every step runs again (scratchAsked asks first).
    func build(rebuild: String? = nil, plan: Bool = false, scratch: Bool = false) {
        guard let env, let dir = settings.gameDir, let folder = gameFolder else { return }
        let keys = needsKeys ? settings.keys : nil
        if needsKeys && keys == nil { return }
        if !plan, let d = diskNeed, d.short, rebuildQueue.isEmpty, batchCurrent == nil,
           !confirm("Build with too little free space?", "\(d.text). The converter stops the build if free space drops below \(Disk.gb(Disk.stopBelow)); the steps it finished are kept for the next try. Storage lists what can be deleted.", action: "Build Anyway") { return }
        let name = game?.name ?? ""
        let out = settings.outDir.flatMap { $0 == folder || name.isEmpty ? nil : "\($0)/\(name.replacingOccurrences(of: ":", with: " - ").replacingOccurrences(of: "/", with: " - ")).app" }
        let bytes = gameBytes
        let exp = settings.reuseCache && !scratch ? expected : Estimates.expected(gameDir: folder, gameBytes: bytes, builds: Engine.builds())
        run.start(Job(gameDir: dir, keys: keys, sign: settings.signIdentity, env: env, rebuild: plan ? nil : rebuild, out: plan ? (rebuild ?? out) : out,
                      keepBackup: settings.keepBackups, reuseCache: plan || settings.reuseCache, scratch: scratch && !plan, cleanup: settings.cleanup,
                      gameFiles: source?.describe, plan: plan, gameBytes: bytes), expected: exp)
        if !plan { watchDisk(Disk.watched(gameDir: folder, outDir: settings.outDir)) }
    }

    /// Rebuild the chosen game from scratch, once confirmed: its build folder is emptied, so the game is unpacked and its shaders
    /// are translated again. A normal rebuild already redoes every step whose inputs changed; this is for a build that looks wrong.
    func scratchAsked(app: String?) {
        guard !run.running, let folder = gameFolder else { return }
        let total = Estimates.plan(Estimates.expected(gameDir: folder, gameBytes: gameBytes, builds: Engine.builds())).map(\.seconds).reduce(0, +)
        let took = total > 0 ? "A full build of this game takes about \(duration(total))." : "A full build takes 20 to 60 minutes for most games, and hours for the largest."
        let text = "This empties the game's build folder (its unpacked files, translated shaders and pipeline archive) and runs every step again. \(took) It reads the game files\(needsKeys ? " and keys" : "") again and needs as much free space as a first build.\n\nKept: your saves, the build's logs, and the Metal cache all games share. A normal rebuild already redoes every step whose inputs changed, so use this when a build looks wrong and a normal rebuild did not fix it."
        guard confirm("Rebuild from scratch?", text, action: "Rebuild from Scratch") else { return }
        build(rebuild: app, scratch: true)
    }

    /// The game's size in bytes: a Switch 2 game's files as source_info.py read them, else the packages in the folder.
    var gameBytes: Int64 { source.map { max($0.fileBytes, $0.romfsBytes, 0) } ?? gameFolder.map(Estimates.gameBytes) ?? 0 }

    /// While the build runs, every 15 s: warn when a volume it writes to gets low, and stop it before one fills up (the stage in
    /// progress is lost; the finished ones are reused by the next build).
    private func watchDisk(_ paths: [String]) {
        diskWatch?.cancel()
        diskWarning = nil
        diskWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.run.running else { return }
                let low = await Task.detached { Disk.lowest(paths) }.value
                guard self.run.running else { return }
                if let low, low.free < Disk.stopBelow {
                    let name = Disk.volumeName(low.path)
                    self.diskWarning = nil
                    self.run.stop(because: "Stopped: not enough space, only \(Disk.gb(low.free)) left on \(name). Free up space (Storage lists what can go), then build again: the finished steps are reused.")
                    return
                }
                self.diskWarning = low.flatMap { $0.free < Disk.warnBelow ? "Free space is low: \(Disk.gb($0.free)) left on \(Disk.volumeName($0.path)). The build stops by itself below \(Disk.gb(Disk.stopBelow))." : nil }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Stop, after saying what is kept: the finished stages are reused when the game is built again.
    func stopBuild() {
        guard run.running else { return }
        let kept = run.done.filter { $0.ok }.count
        let now = friendly(run.stage.name)
        let text = kept > 0
            ? "The \(kept) finished step\(kept == 1 ? " is" : "s are") kept, so building again carries on from \(now.isEmpty ? "where it stopped" : "“\(now)”"), which starts over."
            : "Nothing has finished yet, so the next build starts from the beginning."
        if confirm("Stop the build?", text, action: "Stop Build") { run.cancel() }
    }

    /// Open a built app, noting that its first (slow) launch is done.
    func openApp(_ app: String) {
        NSWorkspace.shared.open(app.url)
        Engine.setLaunched(app)
        revision += 1
    }

    /// Run a fix in Terminal; the tools are checked again when the converter comes back to the front.
    func runFix(_ cmd: String) {
        fixPending = true
        Toolchain.runInTerminal(cmd)
    }

    /// The failing checks that have a fix (required ones, and optional ones this game needs).
    var fixable: [Check] { (checks ?? []).filter { !$0.ok && (!$0.optional || needs[$0.name] != nil) && ($0.fix != nil || $0.name == "Python modules" || $0.name == "nsz") } }

    /// Fix everything fixable at once: the converter's own Python in the app (it brings nsz and zbic), the rest in one
    /// Terminal window, one command after another.
    func fixAll() {
        let all = fixable
        let python = all.contains { $0.name == "Python modules" }
        if python { setUpPython() }
        let skip: Set<String> = python ? ["Python modules", "nsz", "zbic"] : []   // the converter's own Python brings those
        let cmds = all.filter { !skip.contains($0.name) }.compactMap(\.fix)
        guard !cmds.isEmpty else { return }
        runFix(cmds.map { "echo '→ \($0.replacingOccurrences(of: "'", with: ""))'; \($0)" }.joined(separator: "; ") + "; echo; echo 'Done: switch back to NXForge Converter to check again.'")
    }

    /// A Terminal line that builds this game the way the converter does: the same PATH, DOTNET_ROOT and Python.
    var environmentLine: String {
        var parts = ["export PATH=\(shq(env?.path ?? ""))"]
        if let d = env?.dotnetRoot { parts.append("export DOTNET_ROOT=\(shq(d))") }
        if let repo = env?.repo {
            if Layer.isLayered(repo) { parts.append("python3 \(shq(repo + "/" + Layer.script)) assemble") }
            parts.append("cd \(shq(Layer.tree(repo)))")
            var cmd = "\(shq(env?.python ?? "python3")) -u \(scriptPath)"
            if let dir = settings.gameDir { cmd += " \(shq(dir))" } else { cmd += " <game folder>" }
            if let k = settings.keys { cmd += " -k \(shq(k))" }
            parts.append(cmd + " --platform mac-app")
        }
        return parts.joined(separator: "\n")
    }

    /// Keep a build as it is, or stop keeping it.
    func setKept(_ b: BuildRecord, _ on: Bool) {
        Engine.setKept(b.app, on)
        revision += 1
    }

    /// Rebuild a kept app only once it is confirmed, since the new build replaces the one that plays well.
    func rebuildAsked(_ b: BuildRecord, scratch: Bool = false) {
        if b.kept == true, !confirm("Rebuild a kept build?", "\(b.app.url.deletingPathExtension().lastPathComponent) is kept because it plays well. A rebuild replaces it (the old app goes to app-backups when Keep previous app builds is on) and the new build is not kept.", action: "Rebuild") { return }
        rebuild(b, scratch: scratch)
    }

    /// Rebuild a recorded app: its own game folder becomes the chosen one first.
    func rebuild(_ b: BuildRecord, scratch: Bool = false) {
        guard offlineGuard(b.gameDir) else {
            if !rebuildQueue.isEmpty || queueMessage == "" { queueMessage = "Rebuild all stopped: \(b.app.lastComponent)'s game files are offline."; rebuildQueue = [] }
            return
        }
        if settings.gameDir != b.gameDir { setGameDir(b.gameDir) }
        page = .convert
        Task {
            while validating { try? await Task.sleep(for: .milliseconds(200)) }
            if ready { if scratch { scratchAsked(app: b.app) } else { build(rebuild: b.app) } }
            else if !rebuildQueue.isEmpty || queueMessage == "" {
                queueMessage = "Rebuild all stopped: \(b.app.lastComponent) could not be checked against its keys."
                rebuildQueue = []
            }
        }
    }

    /// Whether a recorded build is as good as one on the engine in use now: built on it, or on an older one where nothing the
    /// build reads has changed since (a release that only touched notes, the converter or another game's profile). A commit the
    /// checkout cannot compare with counts as older.
    func isCurrent(_ b: BuildRecord) -> Bool {
        guard let e = engine else { return false }
        if b.engine.local != e.local { return false }   // on upstream nxnative (Get Upstream Now) or back: the whole engine moved
        if b.engine.commit == e.commit && !e.dirty { return true }
        guard let repo = env?.repo, let files = Engine.changedFiles(since: b.engine.commit, repo: repo, head: e) else { return false }
        let title = VerifiedGames.titleID(ofApp: b.app)
        return !files.contains { Engine.affects($0, titleID: title) }
    }

    /// What rebuilding this app on the engine in use would redo (RebuildCost), for the Older engine badge; nil when the engine
    /// or the game's folder cannot be read. Kept per app, build and engine commit, since lists ask on every redraw.
    func rebuildCost(_ b: BuildRecord) -> RebuildCost? {
        guard let e = engine, let repo = env?.repo else { return nil }
        let key = "\(b.app)\n\(b.builtAt)\n\(e.commit)\(e.dirty ? "+" : "")\(e.local ?? "")"
        if !e.dirty, let c = costCache[key] { return c }
        let folder = Source.folder(of: b.gameDir), home = Disk.buildHome(folder)
        let buildFolder = ((try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []).first { $0.hasSuffix("_build") }.map { "\(home)/\($0)" }
        let chain = (try? String(contentsOfFile: Layer.file(repo, "dm/gfx/nvn/dmsh_chain.h"), encoding: .utf8)).flatMap(RebuildCost.chain(header:))
        let title = VerifiedGames.titleID(ofApp: b.app)
        let kind = RebuildCost.kind(chain: chain, built: buildFolder.map(RebuildCost.builtChains(buildFolder:)),
                                    changed: Engine.changedEngineFiles(since: b.engine.commit, repo: repo, head: e), titleID: title)
        let cost = RebuildCost(kind: kind, seconds: RebuildCost.seconds(kind, times: Estimates.ownTimes(folder)))
        if !e.dirty { costCache[key] = cost }
        return cost
    }

    /// Built on the engine in use now, commit for commit (isCurrent also takes an older engine with nothing changed for the build).
    func isSameEngine(_ b: BuildRecord) -> Bool { b.engine.commit == engine?.commit && b.engine.local == engine?.local && engine?.dirty == false }

    /// The recorded apps built on another engine than today's, except the ones kept as they are.
    var outdatedBuilds: [BuildRecord] {
        let _ = revision
        guard engine != nil else { return [] }
        return Engine.builds().filter { FileManager.default.fileExists(atPath: $0.app) && !isCurrent($0) && $0.kept != true }
    }

    /// Rebuild every app on an older engine, one after another; a failure stops the rest.
    func rebuildAll() {
        let all = outdatedBuilds
        guard let first = all.first, !run.running else { return }
        rebuildQueue = Array(all.dropFirst())
        queueMessage = ""
        rebuild(first)
    }

    /// ⌘R: the app selected on Builds, else the newest app beside the chosen game files.
    func rebuildCurrent(scratch: Bool = false) {
        guard !run.running else { return }
        let builds = Engine.builds()
        if page == .builds, let b = builds.first(where: { $0.app == selectedBuild }) ?? builds.max(by: { $0.builtAt < $1.builtAt }) { rebuildAsked(b, scratch: scratch); return }
        if let dir = gameFolder, let a = Engine.apps(in: Disk.appHome(dir)).first ?? Engine.apps(in: dir).first, ready {
            if scratch { scratchAsked(app: a.app) } else { build(rebuild: a.app) }
        }
    }

    /// A folder (or a game file in it) dropped on the window or the Dock icon becomes the game folder.
    func openDropped(_ urls: [URL]) {
        guard !run.running, let u = urls.first else { return }
        // a .nup is the game itself; another file stands for its folder
        setGameDir(Source.isDir(u.path) || Source.isNupFile(u.path) ? u.path : u.deletingLastPathComponent().path)
        page = .convert
    }

    /// The converter's own Python: a venv in Application Support with the script's modules (and nsz), so the
    /// converter depends on no other copy of Python. Needs the network once, for pip.
    func setUpPython() {
        guard pythonSetup?.running != true else { return }
        pythonSetup = (true, "Creating the converter's Python…")
        let venv = Settings.supportDir.appending(path: "venv").path
        let base = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        Task.detached {
            let result: (Bool, String)
            if let base, NXForgeConverter.run(base, ["-m", "venv", "--clear", venv]).map({ $0.ok }) == true {
                await MainActor.run { self.pythonSetup = (true, "Installing lz4, capstone, fontTools, zstd, nsz and zbic…") }
                let pip = NXForgeConverter.run(venv + "/bin/python3", ["-m", "pip", "install", "--quiet", "--disable-pip-version-check", "lz4", "capstone", "fonttools", "nsz", "zbic==1.0.1.post1", "backports.zstd; python_version < '3.14'"])
                result = pip?.ok == true ? (true, "The converter's own Python is ready.") : (false, "pip could not install the modules: \(pip?.out.split(separator: "\n").last ?? "no output")")
            } else {
                result = (false, base == nil ? "No python3 to start from: install Python 3 (brew install python)." : "Could not create \(venv).")
            }
            await MainActor.run {
                self.pythonSetup = (false, result.1)
                if result.0 { self.settings.python = nil }   // automatic: the converter's own venv comes first
                self.recheck()
            }
        }
    }

    /// Whether Python is the converter's own (in Application Support) rather than another copy.
    var ownPython: Bool { env?.python?.hasPrefix(Settings.supportDir.path) == true }

    private func buildEnded(_ r: Result<String, ConverterError>) {
        costCache = [:]
        diskWatch?.cancel(); diskWatch = nil; diskWarning = nil
        if run.planning { return }   // a preview: it stays on Convert, with its plan
        if case .failure(let e) = r { lastErrorSummary = errorSummary(e.description) }
        if run.ipa != nil { ipaEnded(r); return }
        if batchCurrent != nil { batchBuildEnded(r) }
        let name = game?.name ?? "The game"
        if settings.notify, Bundle.main.bundleIdentifier != nil {
            let c = UNMutableNotificationContent()
            let took = run.startedAt.map { " in \(duration(Date().timeIntervalSince($0)))" } ?? ""
            switch r {
            case .success(let msg):
                if run.ipa != nil { c.title = "\(name)'s IPA is ready"; c.body = msg; c.categoryIdentifier = Notify.ipa; c.userInfo = ["path": run.ipa ?? ""] }
                else { c.title = "\(name) is ready"; c.body = "Built and signed\(took). Its first launch prepares shaders, so it takes longer than later ones."; c.categoryIdentifier = Notify.built; c.userInfo = ["path": run.app ?? ""] }
            case .failure(let e):
                c.title = e.description.hasPrefix("Stopped: only") ? "Build stopped: disk almost full" : "Build failed"; c.body = e.description
                if e.description != "stopped" { c.categoryIdentifier = Notify.failed }
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if settings.openAfterBuild, batchCurrent == nil, case .success = r, let app = run.app { openApp(app) }
        if batchCurrent != nil {
            if case .success = r { finishConvert() }
            nextInBatch()
        } else if case .success = r {
            finishConvert()
            if let next = rebuildQueue.first { rebuildQueue.removeFirst(); rebuild(next) }
            else if queueMessage == "" { queueMessage = nil }
        } else if !rebuildQueue.isEmpty || queueMessage == "" {
            measure()
            queueMessage = "Rebuild all stopped at \(game?.name ?? "a game"): its build failed."
            rebuildQueue = []
        }
    }

    /// A built game leaves Convert: the folder, its keys, the check and the activity are cleared for the next game,
    /// and Builds opens on the new app. A failed build stays on Convert with its stages and log.
    func finishConvert() {
        selectedBuild = run.app
        buildSearch = ""
        settings.gameDir = nil
        settings.keys = settings.defaultKeys
        validation = nil
        validatedFor = nil
        source = nil
        game = nil
        needs = [:]; diskNeed = nil; expected = [:]
        run.reset()
        page = .builds
    }

    func requestNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// The game's build cache, <game folder>/<title ID>_build.
    var buildCache: String? {
        guard let dir = gameFolder.map(Disk.buildHome) else { return nil }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).first { $0.hasSuffix("_build") }.map { "\(dir)/\($0)" }
    }

    /// Everything the converter knows, for a bug report (no key values: the keys file is named, never read here).
    var diagnostics: String {
        var l = ["NXForge Converter \(CONVERTER_VERSION) diagnostics, \(Date().formatted())",
                 "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                 "engine: \(env?.repo ?? "none") \(engine?.label ?? "")",
                 "python: \(env?.python ?? "none")", "DOTNET_ROOT: \(env?.dotnetRoot ?? "none")", "PATH: \(env?.path ?? "")", ""]
        l += (checks ?? []).map { "\($0.ok ? "✓" : $0.optional ? "–" : "✗") \($0.name): \($0.detail)" }
        return l.joined(separator: "\n")
    }

    /// Copy log's text: the stages, the script's messages and, with detailed logs, the tools' own logs.
    var logText: String {
        var t = (run.done.map(\.line) + run.log).joined(separator: "\n")
        if settings.logDetail == .detailed, let cache = buildCache {
            let logs = cache + "/logs"
            for f in ((try? FileManager.default.contentsOfDirectory(atPath: logs)) ?? []).sorted() {
                if let s = try? String(contentsOfFile: "\(logs)/\(f)", encoding: .utf8) { t += "\n\n==== \(f) ====\n" + s }
            }
        }
        return t
    }

    func choose(folder: Bool, start: String? = nil) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = folder
        p.canChooseFiles = !folder
        p.allowsMultipleSelection = false
        if let start { p.directoryURL = start.url }
        return p.runModal() == .OK ? p.url?.path : nil
    }

    /// The game: a folder (of NSP / XCI files, or a Switch 2 dump), any game file in a folder (an .xci or .nsp: its folder), or a
    /// Switch 2 game's .nup file itself.
    func chooseGame(start: String? = nil) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.folder] + (gameExtensions.sorted() + ["nup"]).compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = false
        p.message = "Choose the game's folder or a game file (.nsp, .xci, .nsz, .xcz), or a Switch 2 game's .nup file or dump folder"
        if let start { p.directoryURL = Source.folder(of: start).url }
        guard p.runModal() == .OK, let u = p.url else { return nil }
        return Source.isDir(u.path) || Source.isNupFile(u.path) ? u.path : u.deletingLastPathComponent().path
    }

    /// Asks on a sheet over the window in front (HIG: alerts about a window's work attach to it), waiting for the answer.
    /// An action that deletes, stops or quits gets the caution icon; "OK" alone is a notice with no Cancel.
    /// Not `hasDestructiveAction`: on macOS 26 and later in dark mode that button's red label sits on a red fill
    /// (Apple FB20158292) and can vanish altogether, which left only Cancel showing on the delete questions.
    func confirm(_ title: String, _ text: String, action: String, destructive: Bool? = nil) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: action)
        let notice = action == "OK"
        if !notice { a.addButton(withTitle: "Cancel") }
        if destructive ?? Self.isDestructive(action) { a.alertStyle = .critical }
        else if notice { a.alertStyle = .warning }
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else {
            return a.runModal() == .alertFirstButtonReturn
        }
        a.beginSheetModal(for: w) { NSApp.stopModal(withCode: $0) }
        return NSApp.runModal(for: a.window) == .alertFirstButtonReturn
    }

    /// An answer that deletes, stops or quits something.
    nonisolated static func isDestructive(_ action: String) -> Bool {
        ["Trash", "Delete", "Stop", "Quit", "Clear", "Remove"].contains(where: { action.contains($0) })
    }
}
