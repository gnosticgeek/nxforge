// Runs scripts/build_ipa_from_nsp.py --platform mac-app --progress json and follows its events
// (stage, step, progress, stage_end, say: docs/development.md), then checks the app's signature.
import Foundation
import Observation
import Darwin

struct Job {
    /// the game as chosen: a folder, or a .nup file (Source)
    var gameDir: String
    /// nil for a game that needs no keys (a NUP or a dump folder)
    var keys: String?
    var sign: String?
    var env: ToolEnv
    /// Rebuild this app in place: it is moved to app-backups/ first and put back if the build fails.
    var rebuild: String?
    /// where the app goes (-o); nil = <game name>.app in the game folder
    var out: String?
    /// false: the replaced app goes to the Trash once the new one is built, not to app-backups/
    var keepBackup = true
    /// false: delete the stage keys in <id>_build first, so every step runs again
    var reuseCache = true
    /// Rebuild from scratch: empty <id>_build first (all but its logs, profile and run folders), so the game is unpacked and its
    /// shaders are translated again. The Metal cache every game shares is left alone.
    var scratch = false
    /// what a successful build deletes from <id>_build (--cleanup)
    var cleanup: Cleanup = .off
    /// "Base game + update" for the build record; nil = read from the folder's file names
    var gameFiles: String?
    /// --plan: say what a build would reuse and redo, and build nothing
    var plan = false
    /// "ios": an unsigned IPA for iPhone and iPad (--platform ios), beside the game files; nothing is recorded or replaced
    var ios = false

    /// the folder holding the game's files, where <id>_build, the lock and the app go
    var folder: String { Source.folder(of: gameDir) }
    /// a Game Boy Advance cartridge file (GBA.swift): scripts/gba_build.py converts it
    var gba: Bool { GBA.isGame(gameDir) }
    /// the game files' size, recorded so other games' first builds can be estimated from this one
    var gameBytes: Int64 = 0
}

struct Stage: Hashable {
    var k = 0, n = 0
    var name = "", step = ""
    var fraction: Double?
    var detail = ""
    /// the script's seconds left for this stage (the rate of its last minute); nil while unknown
    var eta: Double?
}

struct StageDone: Hashable, Identifiable {
    var id: Int { k }
    let k: Int, n: Int
    let name: String
    let ok: Bool
    let seconds: Int
    let summary: String

    /// the stage reused its last output ("reused", "…, reused (inputs unchanged)"), not one that reused part of its work
    /// ("Metal libraries: 9,807 reused, 3,412 compiled" after a 50-minute shader stage)
    var reused: Bool { stageReused(summary) }
    /// a --plan run's stage that a build would do again
    var redo: Bool { summary.contains("would be redone") }
    var line: String {
        "[\(k)/\(n)] \(name) (\(seconds / 60):\(String(format: "%02d", seconds % 60)))" + (summary.isEmpty ? "" : ": \(summary)")
    }
}

/// One step of a Preview build (the script's "plan" event): reused, done again, or after the step the check stopped at.
struct PlanRow: Hashable, Identifiable {
    enum State: String { case reused, redo, follows }
    var id: String { stage }
    let stage: String
    let state: State
    let why: String
    /// how long the step took the last time it did its work; nil when no build recorded it
    let seconds: Double?

    /// The rows of a "plan" event; a row with a state this converter does not know is left out.
    static func rows(_ event: [String: Any]) -> [PlanRow] {
        (event["rows"] as? [[String: Any]] ?? []).compactMap { r in
            guard let stage = r["stage"] as? String, let state = (r["state"] as? String).flatMap(State.init(rawValue:)) else { return nil }
            return PlanRow(stage: stage, state: state, why: r["why"] as? String ?? "", seconds: (r["secs"] as? NSNumber)?.doubleValue)
        }
    }

    /// "About 18 min", "About 18 min, up to 44 min if every later step is redone", "Nothing to redo: the app is up to date"
    static func total(_ rows: [PlanRow]) -> String {
        let redo = rows.filter { $0.state == .redo }, later = rows.filter { $0.state == .follows }
        if redo.isEmpty { return later.isEmpty ? "Nothing to redo: the app is up to date" : "Nothing is redone for certain" }
        let est = redo.compactMap(\.seconds).reduce(0, +), worst = est + later.compactMap(\.seconds).reduce(0, +)
        let n = "\(redo.count) step\(redo.count == 1 ? "" : "s") redone"
        if est == 0 { return "\(n); no earlier build timed \(redo.count == 1 ? "it" : "them")" }
        return "\(n), about \(duration(est))" + (worst > est ? ", up to \(duration(worst)) if every later step is redone too" : "")
    }
}

@MainActor @Observable
final class BuildRun {
    var running = false
    var stage = Stage()
    var done: [StageDone] = []
    var log: [String] = []
    var app: String?
    /// the IPA an iPhone and iPad build made (Job.ios)
    var ipa: String?
    var backup: String?
    var result: Result<String, ConverterError>?
    /// the run is a --plan (Preview build): its result is the plan, and nothing was built
    var planning = false
    /// a Preview build's steps, from the script's "plan" event (empty on an engine from before it: the plan is then only text)
    var plan: [PlanRow] = []
    /// when the build and the running stage started, and when the script last said anything (a stage that has been quiet
    /// for minutes is still working: the window says so instead of looking frozen)
    var startedAt: Date?
    var stageStartedAt: Date?
    var lastActivity: Date?
    /// seconds each stage should take (Estimates.expected), for the time left
    var expected: [String: Double] = [:]
    /// why the converter stopped the build itself, shown instead of "stopped"
    var stopNote: String?
    /// paused by the converter while a disk it writes to is nearly full: the script and everything it started are stopped where
    /// they stand (SIGSTOP), and carry on (SIGCONT) once there is room (Model.watchDisk)
    var paused = false
    var pausedAt: Date?
    /// paused by the person (Pause on the Convert page or the build strip): only they let it carry on
    var held = false
    /// the converter's own log of the build in <id>_build/logs, once it ends
    var logFile: String?
    private var process: Process?
    /// keeps the Mac from idle sleep (and the app from App Nap) while a build runs
    private var activity: NSObjectProtocol?
    /// called on the main thread after each change (the command line prints from it)
    var onChange: (() -> Void)?
    /// the script's plain output lines not yet in `log`: they join it about ten times a second, not one main-thread hop (and one
    /// redraw of the log) per line, which made a long shader build's log slower the longer it got
    nonisolated private let pending = PendingLines()

    /// A plain output line, from the build's threads.
    nonisolated func queue(_ line: String) {
        guard pending.add(line) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { self.flushLog() } }
    }

    /// The waiting lines into `log`. Everything on the main thread that reads the log or adds to it after the script said something
    /// calls this first, so lines stay in the order the script printed them.
    func flushLog() {
        let lines = pending.take()
        guard !lines.isEmpty else { return }
        log += lines
        lastActivity = Date()
        onChange?()
    }

    func start(_ job: Job, expected: [String: Double] = [:]) {
        _ = pending.take()
        running = true; stage = Stage(); done = []; log = []; app = nil; ipa = nil; backup = nil; result = nil; planning = job.plan; plan = []; stopNote = nil; logFile = nil
        startedAt = Date(); stageStartedAt = nil; lastActivity = Date(); self.expected = job.plan ? [:] : expected
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building a Mac app")
        Thread.detachNewThread { [weak self] in
            let r = Self.perform(job, run: self)
            DispatchQueue.main.async {
                guard let self else { return }
                self.flushLog()
                if let a = self.activity { ProcessInfo.processInfo.endActivity(a); self.activity = nil }
                self.running = false
                self.process = nil
                self.paused = false; self.pausedAt = nil; self.held = false
                if case .failure(let e) = r, e.description == "stopped", let note = self.stopNote { self.result = .failure(ConverterError(note)) } else { self.result = r }
                self.onChange?()
            }
        }
    }

    /// Back to the state before any build (after a successful one has been handed to Builds).
    func reset() {
        guard !running else { return }
        stage = Stage(); done = []; log = []; app = nil; ipa = nil; backup = nil; result = nil; planning = false; plan = []; stopNote = nil; logFile = nil; startedAt = nil; stageStartedAt = nil
    }

    /// Ask the script to stop as Ctrl-C would (it ends the stage and exits with 130); a paused build is let go first, so it can.
    func cancel() {
        if paused { resume() }
        process?.interrupt()
    }

    /// Stop the build where it stands, every process of it, until resume(). False when there is nothing to pause.
    @discardableResult
    func pause() -> Bool {
        guard running, !paused, let p = process, p.isRunning else { return false }
        Self.signalTree(p.processIdentifier, SIGSTOP)
        paused = true; pausedAt = Date()
        onChange?()
        return true
    }

    /// Let a paused build carry on; the time it waited is left out of its stage's elapsed time and time left.
    func resume() {
        guard paused else { return }
        if let p = process { Self.signalTree(p.processIdentifier, SIGCONT) }
        if let t = pausedAt {
            let waited = Date().timeIntervalSince(t)
            stageStartedAt = stageStartedAt?.addingTimeInterval(waited); startedAt = startedAt?.addingTimeInterval(waited)
        }
        paused = false; pausedAt = nil; held = false; lastActivity = Date()
        onChange?()
    }

    /// A process and every process under it (children of children too), the process first.
    nonisolated static func tree(_ root: pid_t) -> [pid_t] {
        var out = [root], i = 0
        while i < out.count {
            var buf = [pid_t](repeating: 0, count: 1024)
            let n = Int(proc_listchildpids(out[i], &buf, Int32(buf.count * MemoryLayout<pid_t>.size)))
            for c in buf.prefix(max(0, min(n, buf.count))) where c > 0 && !out.contains(c) { out.append(c) }
            i += 1
        }
        return out
    }

    /// SIGSTOP from the top down (the script first, so it starts nothing new; a second pass takes what it started meanwhile);
    /// SIGCONT from the bottom up.
    nonisolated static func signalTree(_ root: pid_t, _ sig: Int32) {
        if sig == SIGSTOP {
            var done = Set<pid_t>()
            for _ in 0..<2 { for p in tree(root) where done.insert(p).inserted { kill(p, SIGSTOP) } }
        } else {
            for p in tree(root).reversed() { kill(p, sig) }
        }
    }

    /// Stop the build for a reason of the converter's own (low disk space): the failure then says why.
    func stop(because note: String) {
        guard running, stopNote == nil else { return }
        stopNote = note
        cancel()
    }

    private func main(_ f: @escaping @MainActor (BuildRun) -> Void) {
        DispatchQueue.main.async { f(self); self.onChange?() }
    }

    nonisolated private static func perform(_ job: Job, run r: BuildRun?) -> Result<String, ConverterError> {
        guard let r else { return .failure(ConverterError("cancelled")) }
        // NXForge: while a build runs, macOS must not nap the app or let the Mac idle-sleep, and the build keeps user-initiated priority
        // (performance cores) when the window is in the background; without this a hidden converter's build can drift onto the efficiency cores
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building a game app")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let say: (String) -> Void = { m in DispatchQueue.main.async { r.flushLog(); r.log.append(m); r.onChange?() } }
        do {
            if job.gba { try? FileManager.default.createDirectory(atPath: job.folder, withIntermediateDirectories: true) }
            let lock = try FolderLock(job.folder)
            defer { lock.release() }
            guard let repo = job.env.repo else { throw ConverterError("no NXForge engine checkout") }
            guard let engine = Engine.current(repo) else { throw ConverterError("cannot read the engine's git commit") }
            if let e = Layer.assemble(repo, python: job.env.python) { throw ConverterError("the engine tree is not assembled: \(e)") }   // the checkout may have moved since the checks
            let tree = Layer.tree(repo)
            if job.plan {   // nothing is moved, built or recorded
                guard let src = try? String(contentsOfFile: tree + "/" + scriptPath, encoding: .utf8), src.contains("'--plan'") else {
                    throw ConverterError("this engine has no --plan: update the engine to preview a build")
                }
                return .success(try build(job, repo: repo, run: r))
            }
            if job.ios {   // an IPA beside the game files: no app is replaced or recorded
                let ipa = try build(job, repo: repo, run: r)
                let log = writeLog(job.folder, run: r)
                if job.cleanup == .all { let left = removeBuildFolders(job.folder, app: nil, log: log); DispatchQueue.main.async { r.logFile = left.log } }
                DispatchQueue.main.async { r.ipa = ipa }
                let gb = ((try? FileManager.default.attributesOfItem(atPath: ipa)[.size] as? NSNumber)?.doubleValue ?? 0) / 1_073_741_824
                return .success(String(format: "%@ (%.1f GB): install it with AltStore, Sideloadly or Xcode", ipa.lastComponent, gb))
            }
            var backup: String?
            if let app = job.rebuild {
                // a new engine may change how the game reads its save: keep a checked copy first (best effort; the build goes on without one)
                if let id = VerifiedGames.titleID(ofApp: app) {
                    do { if let s = try SaveSnapshots.snapshot(SaveSnapshots.location(app: app, titleID: id), reason: .beforeRebuild) { say("save snapshot \(s.id) made before the rebuild") } }
                    catch { say("warning: no save snapshot before the rebuild: \(error)") }
                }
                let old = Engine.builds().first { $0.app == app }?.engine
                let b = try Engine.backUp(app, engine: old)
                backup = b
                say("old app moved to \(b)")
                DispatchQueue.main.async { r.backup = b }
            }
            if job.scratch {
                let n = emptyBuildFolder(job.folder)
                say(n > 0 ? "from scratch: the build folder is emptied (logs, profile and run kept), so every step runs again" : "from scratch: there was no build folder to empty")
            } else if !job.reuseCache { forgetStageKeys(job.folder); say("cached build steps cleared: every step runs again") }
            do {
                let app = try build(job, repo: repo, run: r)
                let (steps, shaders, stages, seconds) = DispatchQueue.main.sync {
                    r.flushLog()
                    return (r.done.filter(\.ok).count, r.done.first { $0.name.hasPrefix("Mac shaders") }.flatMap(shaderCount),
                     r.done.map { StageRecord(name: $0.name, seconds: $0.seconds, reused: $0.reused, ok: $0.ok) },
                     r.startedAt.map { Int(Date().timeIntervalSince($0)) })
                }
                var logFile = writeLog(job.folder, run: r)
                if job.cleanup == .all {   // "Remove build cache": nothing of the build is left beside the game, its logs go to ~/Library/Logs/NXForge
                    let left = removeBuildFolders(job.folder, app: app, log: logFile)
                    logFile = left.log
                    if !left.removed.isEmpty { say("build folders removed: \(left.removed.joined(separator: ", ")); the logs are in \(left.logDir ?? "~/Library/Logs/NXForge")") }
                    DispatchQueue.main.async { r.logFile = left.log }
                }
                Engine.record(BuildRecord(app: app, gameDir: job.gameDir, engine: engine, repo: repo, builtAt: Engine.now(), steps: steps, shaders: shaders,
                                          gameFiles: job.gameFiles ?? Engine.describeFiles(job.gameDir), stages: stages, seconds: seconds, log: logFile,
                                          gameBytes: job.gameBytes > 0 ? job.gameBytes : nil))
                let msg = try verify(app)
                if let b = backup, !job.keepBackup, (try? FileManager.default.trashItem(at: b.url, resultingItemURL: nil)) != nil {
                    say("old app moved to the Trash")
                    DispatchQueue.main.async { r.backup = nil }
                }
                return .success(msg)
            } catch {
                _ = writeLog(job.folder, run: r)
                // keep a working game: put the old app back unless the failed build left something in its place
                if let b = backup, let app = job.rebuild, !FileManager.default.fileExists(atPath: app), (try? FileManager.default.moveItem(atPath: b, toPath: app)) != nil {
                    say("build failed: the old app is back at \(app)")
                    DispatchQueue.main.async { r.backup = nil }
                }
                throw error
            }
        } catch let e as ConverterError {
            return .failure(e)
        } catch {
            return .failure(ConverterError("\(error)"))
        }
    }

    /// The build's stages and messages to <id>_build/logs/converter-<time>.log (beside the tools' own logs), for the Builds page
    /// and for a failed build's report; nil when there is no build folder to put it in.
    nonisolated private static func writeLog(_ gameDir: String, run r: BuildRun) -> String? {
        let fm = FileManager.default, dir = Disk.buildHome(gameDir)
        guard let b = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).first(where: { $0.hasSuffix("_build") }) else { return nil }
        let logs = "\(dir)/\(b)/logs"
        try? fm.createDirectory(atPath: logs, withIntermediateDirectories: true)
        let stamp = Engine.now().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "-")
        let path = "\(logs)/converter-\(stamp).log"
        let text = DispatchQueue.main.sync { r.flushLog(); return (r.done.map(\.line) + [""] + r.log).joined(separator: "\n") + "\n" }
        guard (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return nil }
        DispatchQueue.main.async { r.logFile = path }
        return path
    }

    /// Where a game's build logs go once "Remove build cache" took its build folder: ~/Library/Logs/NXForge/<title ID>.
    nonisolated static func archivedLogs(_ titleID: String, home: String = NSHomeDirectory()) -> String { "\(home)/Library/Logs/NXForge/\(titleID)" }

    /// A game's archived build logs folder (archivedLogs), when it has one.
    nonisolated static func archivedLogs(of gameFolder: String) -> String? {
        guard let id = GameNeeds.titleID(gameFolder) else { return nil }
        let d = archivedLogs(id)
        return FileManager.default.fileExists(atPath: d) ? d : nil
    }

    /// After a successful build with "Remove build cache" (--cleanup all): the script's cleanup keeps <id>_build/logs and profile/
    /// (and run/), a provisional profile's <id>_survey, and the app's pack key (<name>.app.key) beside the app, which left the
    /// game folder looking as if nothing had been cleaned. The built app needs none of them, and the next build starts over anyway:
    /// the logs move to ~/Library/Logs/NXForge/<title ID> (the Builds page, Copy log and the time estimates read them there),
    /// then every <16 hex digits>_build and _survey folder in the game folder and in its build home (NXForge Builds on the output
    /// drive) goes, with the app's .key and an emptied NXForge Builds/<game> folder. Never the game files, the keys or the app.
    /// Returns the converter log's new path, the archive folder and what went.
    nonisolated static func removeBuildFolders(_ gameFolder: String, app: String?, log: String?, home: String = NSHomeDirectory()) -> (log: String?, logDir: String?, removed: [String]) {
        let fm = FileManager.default, buildHome = Disk.buildHome(gameFolder)
        func isWork(_ n: String) -> Bool { n.range(of: #"^[0-9A-Fa-f]{16}_(build|survey)$"#, options: .regularExpression) != nil }
        var newLog = log, logDir: String?, removed: [String] = []
        for dir in Set([gameFolder, buildHome]).sorted() {
            for n in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where isWork(n) {
                let p = "\(dir)/\(n)"
                if n.hasSuffix("_build"), let files = try? fm.contentsOfDirectory(atPath: p + "/logs"), !files.isEmpty {
                    let dest = archivedLogs(String(n.prefix(16)).uppercased(), home: home)
                    try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                    var moved = true
                    for f in files where !f.hasPrefix("._") {
                        try? fm.removeItem(atPath: "\(dest)/\(f)")
                        if (try? fm.moveItem(atPath: "\(p)/logs/\(f)", toPath: "\(dest)/\(f)")) == nil,
                           (try? fm.copyItem(atPath: "\(p)/logs/\(f)", toPath: "\(dest)/\(f)")) == nil { moved = false }
                        if log == "\(p)/logs/\(f)" { newLog = "\(dest)/\(f)" }
                    }
                    logDir = dest
                    if !moved { continue }   // a log that could not be kept: leave the build folder rather than lose it
                }
                if (try? fm.removeItem(atPath: p)) != nil { removed.append(n) }
            }
        }
        if let app {
            let key = app + ".key"
            if fm.fileExists(atPath: key), (try? fm.removeItem(atPath: key)) != nil { removed.append(key.lastComponent) }
        }
        if buildHome != gameFolder, let left = try? fm.contentsOfDirectory(atPath: buildHome), left.allSatisfy({ $0 == ".DS_Store" || $0.hasPrefix("._") }) {
            try? fm.removeItem(atPath: buildHome)
        }
        return (newLog, logDir, removed)
    }

    /// The stage keys (sha256 of each stage's inputs, <id>_build/**/*.key) that let the script reuse a stage.
    nonisolated private static func forgetStageKeys(_ gameDir: String) {
        let fm = FileManager.default, dir = Disk.buildHome(gameDir)
        for b in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter({ $0.hasSuffix("_build") }) {
            let root = "\(dir)/\(b)"
            for case let rel as String in fm.enumerator(atPath: root) ?? NSEnumerator() where rel.hasSuffix(".key") && !rel.hasPrefix("extract/") {
                try? fm.removeItem(atPath: "\(root)/\(rel)")
            }
        }
    }

    /// What a from-scratch rebuild keeps of <id>_build: the logs (with the stage times the estimates read), a provisional
    /// profile and the run folder, as the script's own --cleanup all does.
    nonisolated static let scratchKeeps: Set<String> = ["logs", "profile", "run"]

    /// Empty the game's build folder for a rebuild from scratch; returns how many entries went.
    @discardableResult
    nonisolated static func emptyBuildFolder(_ gameDir: String) -> Int {
        let fm = FileManager.default, dir = Disk.buildHome(gameDir)
        var n = 0
        for b in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter({ $0.hasSuffix("_build") }) {
            let root = "\(dir)/\(b)"
            for e in ((try? fm.contentsOfDirectory(atPath: root)) ?? []) where !scratchKeeps.contains(e) {
                if (try? fm.removeItem(atPath: "\(root)/\(e)")) != nil { n += 1 }
            }
        }
        return n
    }

    /// "12,691 of 12,691 shaders ready, reused" → "12,691"
    nonisolated static func shaderCount(_ s: StageDone) -> String? {
        guard let r = s.summary.range(of: " shaders ready") else { return nil }
        return s.summary[..<r.lowerBound].components(separatedBy: " of ").last
    }

    /// The app's path, or with job.plan the script's plan.
    nonisolated private static func build(_ job: Job, repo: String, run r: BuildRun) throws -> String {
        guard let py = job.env.python else { throw ConverterError("no Python with the script's modules") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        let tree = Layer.tree(repo)
        var args = ["-u", tree + "/" + scriptPath, job.gameDir, "--platform", job.ios ? "ios" : "mac-app", "--progress", "json"]
        if job.gba {
            // a Game Boy Advance cartridge: its own script (in the checkout, not the engine tree), its app and build folder in the game's own folder (GBA.home)
            try? FileManager.default.createDirectory(atPath: job.folder, withIntermediateDirectories: true)
            args = ["-u", repo + "/" + GBA.helper, job.gameDir, "--progress", "json", "--home", job.folder, "--name", GBA.cleanName(job.gameDir)]
            if let o = job.rebuild { args += ["-o", o] }   // else in the game's own folder, with its build folder and media
            if job.scratch || !job.reuseCache { args.append("--fresh") }
            if job.cleanup == .all { args.append("--cleanup") }   // the C and object files are what makes Convert again quick: only "all" removes them
        } else {
        if let k = job.keys { args += ["-k", k] }
        if job.plan { args.append("--plan") }
        if !job.ios, let id = job.sign { args += ["--mac-sign", id] }
        if !job.ios, let o = job.rebuild ?? job.out { args += ["-o", o] }
        if job.cleanup != .off { args += ["--cleanup", job.cleanup.rawValue] }
        if let w = Disk.workDir(job.folder) {   // a game on a network share: build on a local drive (Disk.isNetwork)
            try? FileManager.default.createDirectory(atPath: (w as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            args += ["--work-dir", w]
        }
        }
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: job.gba ? repo : tree)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = job.env.path
        env["PYTHONUNBUFFERED"] = "1"
        if env["DOTNET_ROOT"] == nil, let d = job.env.dotnetRoot { env["DOTNET_ROOT"] = d }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.qualityOfService = .userInitiated   // inherited by the script's compilers (metal, metal-tt, the translator): the scheduler keeps them on the performance cores first
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { throw ConverterError("cannot start \(py): \(error.localizedDescription)") }
        DispatchQueue.main.async { r.process = p }

        let errDone = DispatchSemaphore(value: 0)
        var errLines: [String] = []
        Thread.detachNewThread {
            for l in Lines(err.fileHandleForReading) { errLines.append(l); r.queue(l) }
            errDone.signal()
        }
        var appPath: String?, plan: String?
        for line in Lines(out.fileHandleForReading) {
            if let a = event(line, run: r, ext: job.ios ? ".ipa" : ".app") { appPath = a }
            if job.plan, let m = planMessage(line) { plan = m }
        }
        p.waitUntilExit()
        errDone.wait()
        switch p.terminationStatus {
        case 0: break
        case 130: throw ConverterError("stopped")
        default:
            // the script's own last red line, which names the failed step and its log
            let red = DispatchQueue.main.sync { r.flushLog(); return r.log.last { $0.contains("[RED]") } } ?? errLines.last
            throw ConverterError(red ?? "the script exited with \(p.terminationStatus)")
        }
        if job.plan { return plan ?? "the script printed no plan" }
        guard let appPath else { throw ConverterError("the script finished but named no \(job.ios ? "IPA" : "app")") }
        if !job.ios { DispatchQueue.main.async { r.app = appPath } }
        return appPath
    }

    /// The --plan summary ("plan (--plan: nothing was built or changed):" and its lines) from a say event.
    nonisolated static func planMessage(_ line: String) -> String? {
        guard let v = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], v["ev"] as? String == "say",
              let msg = v["msg"] as? String, msg.hasPrefix("plan (") else { return nil }
        return msg
    }

    /// One stdout line of the script; returns the app's path from its "done: <path>.app (…)" message.
    nonisolated private static func event(_ line: String, run r: BuildRun, ext: String = ".app") -> String? {
        guard let v = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let ev = v["ev"] as? String else {
            r.queue(line)
            return nil
        }
        let str = { (k: String) in v[k] as? String ?? "" }
        let num = { (k: String) in (v[k] as? NSNumber)?.doubleValue }
        var app: String?
        if ev == "say", let msg = v["msg"] as? String, let i = msg.range(of: "done: "), let j = msg[i.upperBound...].range(of: ext) {
            app = String(msg[i.upperBound..<j.upperBound])
        }
        DispatchQueue.main.async {
            r.flushLog()
            r.lastActivity = Date()
            switch ev {
            case "stage":
                r.stage = Stage(k: Int(num("k") ?? 0), n: Int(num("n") ?? 0), name: str("name"), step: str("step"))
                r.stageStartedAt = Date()
            case "step":
                r.stage.step = str("step")
                r.stage.eta = nil
            case "progress":
                r.stage.step = str("step")
                r.stage.fraction = num("frac")
                var d = ""
                if let done = num("done"), let total = num("total") {
                    let est = (v["est"] as? Bool) == true ? "~" : ""
                    d = str("unit") == "B" ? String(format: "%.1f/%@%.1f GB", done / 1e9, est, total / 1e9) : "\(Int(done))/\(est)\(Int(total)) \(str("unit"))"
                }
                r.stage.eta = num("eta")
                r.stage.detail = d
            case "stage_end":
                r.done.append(StageDone(k: r.stage.k, n: r.stage.n, name: r.stage.name, ok: (v["ok"] as? Bool) ?? true, seconds: Int(num("elapsed") ?? 0), summary: str("summary")))
                r.stage.fraction = 1
                r.stage.eta = nil
            case "plan":
                r.plan = PlanRow.rows(v)
            case "say":
                r.log += str("msg").split(separator: "\n").map(String.init)
            default:
                r.log.append(line)
            }
            r.onChange?()
        }
        return app
    }

    /// The app must be a bundle with an executable launcher and a valid signature.
    nonisolated static func verify(_ app: String) throws -> String {
        let exe = app + "/Contents/MacOS/nxnative"   // the game app's executable keeps the engine's upstream name (dm/mac/pack_app.py)
        guard FileManager.default.isExecutableFile(atPath: exe) else { throw ConverterError("\(app) has no executable launcher") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", "--deep", "--strict", app]
        let e = Pipe()
        p.standardError = e
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw ConverterError("signature check failed: " + String(decoding: e.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // codesign -dv writes to stderr
        let d = Process()
        d.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        d.arguments = ["-dv", app]
        let de = Pipe()
        d.standardError = de
        d.standardOutput = Pipe()
        try d.run()
        let info = String(decoding: de.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        d.waitUntilExit()
        let signer = info.split(separator: "\n").first { $0.hasPrefix("Authority=") }.map { String($0.dropFirst(10)) } ?? (info.contains("Signature=adhoc") ? "ad-hoc" : "unknown")
        return "\(app) is signed (\(signer)) and the signature verifies"
    }
}

/// One build per game folder at a time, across this app's windows and command-line runs: two builds of the
/// same folder share <id>_build/ and the output app, and clobber each other.
struct FolderLock {
    let path: String

    init(_ dir: String) throws {
        path = dir + "/.nxforge-converter.lock"
        if let pid = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), let n = Int32(pid), kill(n, 0) == 0 {
            throw ConverterError("another build of this folder is running (process \(n)); wait for it to finish")
        }
        do { try String(getpid()).write(toFile: path, atomically: true, encoding: .utf8) } catch { throw ConverterError("cannot write \(path): \(error.localizedDescription)") }
    }

    func release() { try? FileManager.default.removeItem(atPath: path) }
}

/// The lines of a pipe as they arrive.
struct Lines: Sequence, IteratorProtocol {
    let handle: FileHandle
    var buffer = Data()
    var eof = false

    init(_ h: FileHandle) { handle = h }

    mutating func next() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return String(decoding: line, as: UTF8.self)
            }
            if eof {
                guard !buffer.isEmpty else { return nil }
                defer { buffer.removeAll() }
                return String(decoding: buffer, as: UTF8.self)
            }
            let chunk = handle.availableData
            if chunk.isEmpty { eof = true } else { buffer.append(chunk) }
        }
    }
}

/// Lines handed from the build's threads to the main thread in batches (BuildRun.queue).
final class PendingLines: @unchecked Sendable {   // @unchecked: every access to `lines` holds `lock`
    private var lines: [String] = []
    private let lock = NSLock()

    /// Adds a line; true when it is the first one waiting (the caller then schedules the flush).
    func add(_ line: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        return lines.count == 1
    }

    func take() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let all = lines
        lines = []
        return all
    }
}
