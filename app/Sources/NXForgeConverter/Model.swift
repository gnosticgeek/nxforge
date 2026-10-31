// The window's state: settings, toolchain checks, the folder's validation, the engine and the build run.
// Slow work (checks, validation, git) runs off the main thread and lands back here.
import AppKit
import Observation
import UniformTypeIdentifiers
import UserNotifications

enum Page: String, CaseIterable, Identifiable {
    case convert = "Convert", builds = "Builds", toolchain = "Toolchain", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .convert: "macwindow.badge.plus"
        case .builds: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .toolchain: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }
}

enum BuildSort: String, CaseIterable { case newest = "Newest first", oldest = "Oldest first", name = "Name" }

@MainActor @Observable
final class AppModel {
    var page: Page = .convert
    var settings = Settings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.appearance != oldValue.appearance { applyAppearance() }
        }
    }
    var checks: [Check]?
    var env: ToolEnv?
    var checking = false
    var lastChecked: Date?
    var validation: Validation?
    var validating = false
    var validatedFor: (String, String)?
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
    var selectedBuild: String?
    /// Rebuild all: the apps still to rebuild after the one running, and why it stopped, if it did
    var rebuildQueue: [BuildRecord] = []
    var queueMessage: String?
    /// the converter's own Python being set up: (running, what it says)
    var pythonSetup: (running: Bool, text: String)?
    /// the newest release's first change, when the engine's branch has updates
    var updateNote: String?
    private var checkedForUpdates = false
    /// the window's model, for the Dock (a folder dropped on its icon) and the menu commands
    nonisolated(unsafe) static weak var shared: AppModel?

    init() {
        AppModel.shared = self
        run.onChange = { [weak self] in
            guard let self else { return }
            DockProgress.show(self.run)
            guard !self.run.running, let r = self.run.result else { return }
            self.refreshGame()
            self.revision += 1
            self.buildEnded(r)
        }
        applyAppearance()
        recheck()
        if settings.gameDir != nil && settings.keys != nil { validate() }
    }

    var allOK: Bool { checks?.allSatisfy { $0.ok || $0.optional } ?? false }
    var passed: Int { checks?.filter(\.ok).count ?? 0 }
    var valid: Bool {
        guard let v = validation, let f = validatedFor else { return false }
        return v.ok && f.0 == settings.gameDir && f.1 == settings.keys
    }
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
                self.checks = c; self.env = e; self.identities = ids; self.engine = ver; self.verified = verified; self.checking = false; self.lastChecked = Date()
                // once per launch: look for a newer engine (a fetch; quiet when offline)
                if !self.checkedForUpdates, ver != nil { self.checkedForUpdates = true; self.engineAction(update: false) }
            }
        }
    }

    func validate() {
        guard let dir = settings.gameDir, let keys = settings.keys else { return }
        validating = true
        validation = nil
        validatedFor = (dir, keys)
        refreshGame()
        Task.detached {
            let v = GameFiles.validate(dir: dir.url, keysURL: keys.url)
            await MainActor.run { self.validation = v; self.validating = false }
        }
    }

    func refreshGame() {
        game = settings.gameDir.map(GameInfo.read)
    }

    func setGameDir(_ dir: String) {
        // prod.keys beside the game files is the usual layout; else the default keys file, else the one chosen before
        let beside = dir + "/prod.keys"
        if FileManager.default.fileExists(atPath: beside) { settings.keys = beside }
        else if let d = settings.defaultKeys, FileManager.default.fileExists(atPath: d) { settings.keys = d }
        settings.gameDir = dir
        validate()
    }

    func engineAction(update: Bool) {
        guard let repo = env?.repo else { return }
        engineBusy = true
        engineMessage = (true, update ? "Updating…" : "Checking…")
        Task.detached {
            let msg: (Bool, String)
            var target: String?
            do {
                if update { try Engine.update(repo); msg = (true, "Updated") }
                else {
                    let (n, up) = try Engine.checkUpdates(repo)
                    target = up
                    // a merged release branch updates from main: say so, since Update engine switches to it
                    let onto = up.split(separator: "/", maxSplits: 1).last.map(String.init) ?? up
                    let other = onto != (Engine.current(repo)?.branch ?? onto) ? " on \(onto)" : ""
                    msg = (true, n == 0 ? "Up to date" : "\(n) update\(n == 1 ? "" : "s") available\(other)")
                }
            } catch { msg = (false, "\(error)") }
            let ver = Engine.current(repo)
            let note = msg.1.contains("available") ? target.flatMap { Engine.upstreamNote(repo, target: $0) } : nil
            await MainActor.run { self.engineMessage = msg; self.engine = ver; self.engineBusy = false; self.updateNote = note }
        }
    }

    var updatesAvailable: Bool { engineMessage.map { $0.ok && $0.text.contains("available") } ?? false }

    /// The folder new apps go to: the setting, else beside the game files.
    var outputFolder: String? { settings.outDir ?? settings.gameDir }

    func build(rebuild: String? = nil) {
        guard let env, let dir = settings.gameDir, let keys = settings.keys else { return }
        let name = game?.name ?? ""
        let out = settings.outDir.flatMap { $0 == dir || name.isEmpty ? nil : "\($0)/\(name.replacingOccurrences(of: ":", with: " - ").replacingOccurrences(of: "/", with: " - ")).app" }
        run.start(Job(gameDir: dir, keys: keys, sign: settings.signIdentity, env: env, rebuild: rebuild, out: out,
                      keepBackup: settings.keepBackups, reuseCache: settings.reuseCache, cleanup: settings.cleanup))
    }

    /// Keep a build as it is, or stop keeping it.
    func setKept(_ b: BuildRecord, _ on: Bool) {
        Engine.setKept(b.app, on)
        revision += 1
    }

    /// Rebuild a kept app only once it is confirmed, since the new build replaces the one that plays well.
    func rebuildAsked(_ b: BuildRecord) {
        if b.kept == true, !confirm("Rebuild a kept build?", "\(b.app.url.deletingPathExtension().lastPathComponent) is kept because it plays well. A rebuild replaces it (the old app goes to app-backups when Keep previous app builds is on) and the new build is not kept.", action: "Rebuild") { return }
        rebuild(b)
    }

    /// Rebuild a recorded app: its own game folder becomes the chosen one first.
    func rebuild(_ b: BuildRecord) {
        if settings.gameDir != b.gameDir { setGameDir(b.gameDir) }
        page = .convert
        Task {
            while validating { try? await Task.sleep(for: .milliseconds(200)) }
            if ready { build(rebuild: b.app) }
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
        if b.engine.commit == e.commit && !e.dirty { return true }
        guard let repo = env?.repo, let files = Engine.changedFiles(since: b.engine.commit, repo: repo, head: e) else { return false }
        let title = VerifiedGames.titleID(ofApp: b.app)
        return !files.contains { Engine.affects($0, titleID: title) }
    }

    /// Built on the engine in use now, commit for commit (isCurrent also takes an older engine with nothing changed for the build).
    func isSameEngine(_ b: BuildRecord) -> Bool { b.engine.commit == engine?.commit && engine?.dirty == false }

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
    func rebuildCurrent() {
        guard !run.running else { return }
        let builds = Engine.builds()
        if page == .builds, let b = builds.first(where: { $0.app == selectedBuild }) ?? builds.max(by: { $0.builtAt < $1.builtAt }) { rebuildAsked(b); return }
        if let dir = settings.gameDir, let a = Engine.apps(in: settings.outDir ?? dir).first ?? Engine.apps(in: dir).first, ready { build(rebuild: a.app) }
    }

    /// A folder (or a game file in it) dropped on the window or the Dock icon becomes the game folder.
    func openDropped(_ urls: [URL]) {
        guard !run.running, let u = urls.first else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
        setGameDir(isDir.boolValue ? u.path : u.deletingLastPathComponent().path)
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
                await MainActor.run { self.pythonSetup = (true, "Installing lz4, capstone, fontTools, zstd and nsz…") }
                let pip = NXForgeConverter.run(venv + "/bin/python3", ["-m", "pip", "install", "--quiet", "--disable-pip-version-check", "lz4", "capstone", "fonttools", "nsz", "backports.zstd; python_version < '3.14'"])
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
        let name = game?.name ?? "The game"
        if settings.notify, Bundle.main.bundleIdentifier != nil {
            let c = UNMutableNotificationContent()
            switch r {
            case .success: c.title = "\(name) is ready"; c.body = "The Mac app was built and signed."
            case .failure(let e): c.title = "Build failed"; c.body = e.description
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if settings.openAfterBuild, case .success = r, let app = run.app { NSWorkspace.shared.open(app.url) }
        if case .success = r {
            finishConvert()
            if let next = rebuildQueue.first { rebuildQueue.removeFirst(); rebuild(next) }
            else if queueMessage == "" { queueMessage = nil }
        } else if !rebuildQueue.isEmpty || queueMessage == "" {
            queueMessage = "Rebuild all stopped at \(game?.name ?? "a game"): its build failed."
            rebuildQueue = []
        }
    }

    /// A built game leaves Convert: the folder, its keys, the check and the activity are cleared for the next game,
    /// and Builds opens on the new app. A failed build stays on Convert with its stages and log.
    private func finishConvert() {
        selectedBuild = run.app
        buildSearch = ""
        settings.gameDir = nil
        settings.keys = settings.defaultKeys
        validation = nil
        validatedFor = nil
        game = nil
        run.reset()
        page = .builds
    }

    func requestNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// The game's build cache, <game folder>/<title ID>_build.
    var buildCache: String? {
        guard let dir = settings.gameDir else { return nil }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).first { $0.hasSuffix("_build") }.map { "\(dir)/\($0)" }
    }

    /// Everything the converter knows, for a bug report (no key values: the keys file is named, never read here).
    var diagnostics: String {
        var l = ["NXForge Converter diagnostics, \(Date().formatted())",
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

    /// The game folder, picked as the folder itself or as any game file in it (an .xci or .nsp).
    func chooseGame(start: String? = nil) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.folder] + gameExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = false
        p.message = "Choose the game's folder, or a game file (.nsp, .xci, .nsz, .xcz) in it"
        if let start { p.directoryURL = start.url }
        guard p.runModal() == .OK, let u = p.url else { return nil }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
        return isDir.boolValue ? u.path : u.deletingLastPathComponent().path
    }

    func confirm(_ title: String, _ text: String, action: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: action)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}
