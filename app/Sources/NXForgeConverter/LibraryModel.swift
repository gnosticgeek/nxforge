// The Library page's side of the model: scanning the games folder, reading the games' own names and icons, what each game's
// build state is, tidying files (a game sharing a folder, DLC in a subfolder) and building several games one after another.
import AppKit
import Foundation
import UserNotifications

/// The Library's second filter, beside the console.
enum LibraryFilter: String, CaseIterable {
    case all = "All games", notBuilt = "Not built", plays = "Plays on NXForge", profile = "Has an NXForge profile",
         outdated = "Built on an older engine", newerUpdate = "Newer update than the build", attention = "Needs attention"
}

/// What happened to one game of Build selected.
struct BatchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let ok: Bool
    let text: String
}

/// A game's build, as the Library shows it.
struct LibraryBuild {
    var app: String
    var record: BuildRecord?
    /// the newest update version the build was made from ("extract v262144" stages), nil when unknown
    var version: UInt64?
}

extension AppModel {
    var libraryScanning: Bool { libraryProgress != nil }
    var batchRunning: Bool { batchCurrent != nil }

    func chooseGamesRoot() {
        guard let d = choose(folder: true, start: settings.gamesRoot ?? "/Volumes") else { return }
        settings.gamesRoot = d
        scanLibrary()
    }

    // MARK: scanning

    /// Scans the games folder off the main thread. The kept list stays up while it runs (no flicker on a slow share); with none
    /// kept, games show as they are found. A scan that ended early keeps the games it did not reach from the last one, so a
    /// dropped share loses nothing. Names and icons already read are carried over, and the rest are read afterwards.
    func scanLibrary() {
        guard let root = settings.gamesRoot, !libraryScanning else { return }
        detailsTask?.cancel()
        libraryProgress = (0, root, 0)
        libraryMessage = nil
        let before = library?.root == root ? library : nil
        libraryTask = Task.detached(priority: .utility) {
            var lastGames = 0
            let r = GameLibrary.scan(root: root) { n, cur, games in
                let fresh = before == nil && games.count != lastGames ? games : nil
                lastGames = games.count
                Task { @MainActor in
                    guard self.libraryScanning else { return }
                    self.libraryProgress = (n, cur, games.count)
                    if let fresh { self.library = LibraryScan(root: root, scanned: Date(), games: GameLibrary.fold(fresh)) }
                }
            }
            var out = r
            if r.stopped != nil, let before {
                // keep what the last scan found in the folders this one did not get to
                let seen = Set(r.games.map(\.folder))
                out.games = GameLibrary.fold(r.games + before.games.filter { o in !seen.contains(o.folder) && !r.games.contains { $0.id == o.id } })
            }
            if let before { out.games = GameLibrary.carryDetails(from: before.games, to: out.games) }
            await MainActor.run {
                self.library = out
                self.libraryProgress = nil
                self.libraryMessage = r.stopped
                if r.stopped == nil || !r.games.isEmpty { GameLibrary.saveCache(out) }
                self.librarySelection = self.librarySelection.filter { id in out.games.contains { $0.id == id } }
                self.readLibraryDetails()
            }
        }
    }

    func stopLibraryScan() { libraryTask?.cancel(); detailsTask?.cancel() }

    /// Scan again when the games folder's drive or share is mounted, and when the Library opens on a list over a day old.
    func watchMounts() {
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] n in
            let vol = (n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            MainActor.assumeIsolated {
                guard let self, let root = self.settings.gamesRoot, let vol, root == vol || root.hasPrefix(vol + "/") else { return }
                // a share answers a moment after it mounts
                Task { try? await Task.sleep(for: .seconds(3)); self.scanLibrary() }
            }
        }
    }

    func scanIfStale() {
        guard let root = settings.gamesRoot, !libraryScanning else { return }
        if library?.root != root || (library.map { Date().timeIntervalSince($0.scanned) > 24 * 3600 } ?? true) { scanLibrary() }
    }

    // MARK: names and icons

    /// The keys file for a game folder: prod.keys beside the game, else the default keys file, else the one chosen last.
    func keysFile(for folder: String) -> String? {
        let fm = FileManager.default
        return [folder + "/prod.keys", settings.defaultKeys, settings.keys].compactMap { $0 }.first { fm.fileExists(atPath: $0) }
    }

    /// Reads the control data (name, publisher, version, icon) of the games that do not have it yet, a game at a time off the
    /// main thread, showing each as it comes. A game that could not be read is not tried again until its files change.
    func readLibraryDetails() {
        guard let l = library, !libraryScanning else { return }
        let todo = l.games.filter { $0.kind == .packages && $0.detailsKey != GameLibrary.detailsKey($0) }
        guard !todo.isEmpty else { return }
        let jobs = todo.map { g in (g, keysFile(for: g.folder)) }
        libraryDetails = (0, jobs.count)
        detailsTask?.cancel()
        detailsTask = Task.detached(priority: .utility) {
            var loaded: [String: Keys] = [:]
            for (n, (g, kf)) in jobs.enumerated() {
                if Task.isCancelled { break }
                var d = g
                if let kf {
                    if loaded[kf] == nil { loaded[kf] = try? Keys(contentsOf: kf.url) }
                    if let k = loaded[kf] {
                        // a game whose share stops answering is left for next time rather than holding the rest up
                        final class Box: @unchecked Sendable { var g: LibraryGame? }
                        let box = Box(), sem = DispatchSemaphore(value: 0)
                        DispatchQueue.global(qos: .utility).async { box.g = GameLibrary.withDetails(g, keys: k); sem.signal() }
                        if sem.wait(timeout: .now() + 30) == .success, let r = box.g { d = r } else { continue }
                    }
                } else { d.detailsKey = GameLibrary.detailsKey(g) }
                let done = d
                await MainActor.run {
                    self.libraryDetails = (n + 1, jobs.count)
                    if var l = self.library, let i = l.games.firstIndex(where: { $0.id == done.id }) { l.games[i] = done; self.library = l }
                }
            }
            await MainActor.run {
                self.libraryDetails = nil
                // the games' own names change the order
                if var l = self.library {
                    l.games.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                    self.library = l
                    GameLibrary.saveCache(l)
                }
            }
        }
    }

    // MARK: build state

    /// Each title ID's newest build whose app is still there, from the build records (an app names its title ID in its bundle ID).
    func libraryBuilds() -> [String: LibraryBuild] {
        var out: [String: LibraryBuild] = [:]
        for b in Engine.builds() where FileManager.default.fileExists(atPath: b.app) {
            guard let t = VerifiedGames.titleID(ofApp: b.app) else { continue }
            if let o = out[t], let r = o.record, r.builtAt > b.builtAt { continue }
            let v = (b.stages ?? []).compactMap { s -> UInt64? in
                guard s.name.hasPrefix("extract v") else { return nil }
                return UInt64(s.name.dropFirst(9).prefix { $0.isNumber })
            }.max()
            out[t] = LibraryBuild(app: b.app, record: b, version: v)
        }
        return out
    }

    func build(of g: LibraryGame, in builds: [String: LibraryBuild]) -> LibraryBuild? {
        if let t = g.titleID, let b = builds[t] { return b }
        return g.app.map { LibraryBuild(app: $0) }
    }

    func hasProfile(_ g: LibraryGame) -> Bool {
        guard let repo = env?.repo, let t = g.titleID else { return false }
        return FileManager.default.fileExists(atPath: "\(repo)/dm/games/\(t)")
    }

    /// The folder holds a newer update than the one the build was made from.
    func newerUpdate(_ g: LibraryGame, _ b: LibraryBuild?) -> Bool {
        guard let have = g.newestUpdate, let built = b?.version else { return false }
        return have > built
    }

    func outdated(_ b: LibraryBuild?) -> Bool { b?.record.map { !isCurrent($0) && $0.kept != true } ?? false }

    func matches(_ g: LibraryGame, _ f: LibraryFilter, _ builds: [String: LibraryBuild]) -> Bool {
        let b = build(of: g, in: builds)
        switch f {
        case .all: return true
        case .notBuilt: return b == nil
        case .plays: return g.titleID.flatMap { verified[$0] }?.result == "plays"
        case .profile: return hasProfile(g)
        case .outdated: return outdated(b)
        case .newerUpdate: return newerUpdate(g, b)
        case .attention: return g.shared || !g.notes.isEmpty || g.duplicates != nil
        }
    }

    // MARK: tidying

    /// The game becomes the one to convert. A game whose files share a folder with other games moves into a folder of its own
    /// first (the script builds one game per folder), once asked.
    func convertFromLibrary(_ g: LibraryGame) {
        guard !run.running else { return }
        var path = g.path
        if g.shared {
            guard confirm("Move \(g.displayName) into its own folder?", "The build takes one game per folder, and \(g.path.lastComponent) holds other games too. Its \(g.files.count) file\(g.files.count == 1 ? "" : "s") move into a new folder, “\(g.displayName)”, inside it. Nothing is copied or deleted.", action: "Move and Convert") else { return }
            guard let p = moveToOwnFolder(g) else { return }
            path = p
        }
        setGameDir(path)
        page = .convert
    }

    /// Moves a shared game's files into a folder of its own and updates the list; the new folder, or nil (and a message) when it failed.
    @discardableResult func moveToOwnFolder(_ g: LibraryGame) -> String? {
        do {
            let p = try GameLibrary.moveToOwnFolder(g)
            updateGame(g) { $0.path = p; $0.shared = false }
            return p
        } catch {
            libraryMessage = "Could not move \(g.displayName)'s files: \(error.localizedDescription)"
            return nil
        }
    }

    /// Moves a game's update and DLC files from its subfolders beside its other files, so the build uses them.
    func moveStray(_ g: LibraryGame) {
        let n = g.stray?.count ?? 0
        guard n > 0, confirm("Move \(n) file\(n == 1 ? "" : "s") beside \(g.displayName)?", "The build reads only the game's own folder, so the update and DLC files in its subfolders are not used. They move into \(g.path.lastComponent); nothing is copied or deleted.", action: "Move") else { return }
        do {
            try GameLibrary.moveStray(g)
            updateGame(g) { x in
                x.files = (x.files + (x.stray ?? []).map(\.lastComponent)).sorted()
                x.notes = x.notes.filter { !$0.contains("not used: the build reads") }
                x.stray = nil
                x.fileCount = x.files.count
            }
        } catch {
            libraryMessage = "Could not move \(g.displayName)'s files: \(error.localizedDescription)"
        }
    }

    private func updateGame(_ g: LibraryGame, _ change: (inout LibraryGame) -> Void) {
        guard var l = library, let i = l.games.firstIndex(where: { $0.id == g.id }) else { return }
        change(&l.games[i])
        library = l
        GameLibrary.saveCache(l)
    }

    // MARK: Build selected

    /// Free space each volume needs for these builds, against what it has: a first build about twice the game plus 10 GB
    /// (as Disk.need), a rebuild about the game's size plus 4 GB.
    func batchNeed(_ games: [LibraryGame], builds: [String: LibraryBuild]) -> [(volume: String, need: Int64, free: Int64)] {
        var by: [String: (String, Int64, Int64)] = [:]
        for g in games {
            let first = build(of: g, in: builds) == nil
            let need = first ? g.bytes * 2 + (10 << 30) : g.bytes + (4 << 30)
            let id = Disk.volumeID(g.folder)
            let cur = by[id] ?? (Disk.volumeName(g.folder), 0, Disk.free(g.folder) ?? 0)
            by[id] = (cur.0, cur.1 + need, cur.2)
        }
        return by.values.map { (volume: $0.0, need: $0.1, free: $0.2) }.sorted { $0.volume < $1.volume }
    }

    /// Builds the selected games one after another. Games sharing a folder move into their own first (asked once); a game that
    /// fails or cannot be checked is noted and the next one starts; stopping a build, or running short of space, stops the rest.
    func buildSelected() {
        guard !run.running, !batchRunning, var games = library?.games.filter({ librarySelection.contains($0.id) }), !games.isEmpty else { return }
        let builds = libraryBuilds()
        let shared = games.filter(\.shared)
        if !shared.isEmpty {
            guard confirm("Move \(shared.count) game\(shared.count == 1 ? "" : "s") into folders of their own?", "The build takes one game per folder: \(shared.map(\.displayName).joined(separator: ", ")) share a folder with other games, so each one's files move into a new folder named after it first. Nothing is copied or deleted.", action: "Move and Build") else { return }
            for (i, g) in games.enumerated() where g.shared {
                guard let p = moveToOwnFolder(g) else { return }
                games[i].path = p; games[i].shared = false
            }
        }
        let short = batchNeed(games, builds: builds).filter { $0.need > $0.free }
        if !short.isEmpty, !confirm("Build with too little free space?", short.map { "\($0.volume): about \(Disk.gb($0.need)) needed, \(Disk.gb($0.free)) free." }.joined(separator: "\n") + " Each build stops by itself before a disk fills up, and the rest are then left. Storage lists what can be deleted.", action: "Build Anyway") { return }
        batchQueue = games
        batchResults = []
        batchMessage = nil
        librarySelection = []
        nextInBatch()
    }

    /// The next game of Build selected: chosen on Convert, checked, then built; one that cannot be checked is noted and skipped.
    func nextInBatch() {
        guard !batchQueue.isEmpty else {
            if batchCurrent != nil || !batchResults.isEmpty { finishBatch() }
            return
        }
        let g = batchQueue.removeFirst()
        batchCurrent = g
        run.reset()
        setGameDir(g.path)
        page = .convert
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            while validating || checking { try? await Task.sleep(for: .milliseconds(200)) }
            guard batchCurrent == g else { return }
            if ready { build(); return }
            let why = !allOK ? "the toolchain is incomplete (see Toolchain)"
                : validation?.summary.first { !$0.ok && !$0.warn }?.text ?? (needsKeys && settings.keys == nil ? "no keys file" : "its files could not be checked")
            batchResults.append(BatchResult(name: g.displayName, ok: false, text: "Not built: \(why)"))
            nextInBatch()
        }
    }

    /// A build of Build selected ended: note it; a stop (asked for, or for disk space) ends the batch.
    func batchBuildEnded(_ r: Result<String, ConverterError>) {
        guard let g = batchCurrent else { return }
        switch r {
        case .success:
            let took = run.startedAt.map { " in \(duration(Date().timeIntervalSince($0)))" } ?? ""
            batchResults.append(BatchResult(name: g.displayName, ok: true, text: "Built\(took)"))
        case .failure(let e):
            batchResults.append(BatchResult(name: g.displayName, ok: false, text: e.description))
            if e.description == "stopped" || run.stopNote != nil {
                batchMessage = "Build selected stopped at \(g.displayName)" + (batchQueue.isEmpty ? "." : ": \(batchQueue.map(\.displayName).joined(separator: ", ")) not built.")
                batchQueue = []
            }
        }
    }

    func finishBatch() {
        batchCurrent = nil
        let ok = batchResults.filter(\.ok).count
        if batchMessage == nil { batchMessage = "Build selected finished: \(ok) of \(batchResults.count) built." }
        if settings.notify, Bundle.main.bundleIdentifier != nil {
            let c = UNMutableNotificationContent()
            c.title = "Build selected finished"
            c.body = "\(ok) of \(batchResults.count) game\(batchResults.count == 1 ? "" : "s") built."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        page = .library
    }

    /// Stop Build selected: the build running now stops (its finished steps are kept) and the rest are not started.
    func stopBatch() {
        guard batchRunning else { return }
        let rest = batchQueue.count
        guard confirm("Stop Build selected?", "\(run.running ? "The build of \(batchCurrent?.displayName ?? "this game") stops; its finished steps are kept for the next try. " : "")\(rest == 0 ? "No other game was waiting." : "\(rest) game\(rest == 1 ? "" : "s") still to build \(rest == 1 ? "is" : "are") not started.")", action: "Stop") else { return }
        batchMessage = "Build selected stopped." + (rest > 0 ? " \(batchQueue.map(\.displayName).joined(separator: ", ")) not built." : "")
        batchQueue = []
        if run.running { run.cancel() } else { finishBatch() }
    }
}
