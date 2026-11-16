// Playtime (idea 6): every session of a built game, timed while the converter is open (it notices a game app start and quit,
// however it was opened: from the converter, Finder, the Dock or Spotlight). Kept in playtime.json in Application Support, by
// title ID (an app without one by its path). The Library's Continue playing row, its Recently played order and the game page's
// chart come from it. When a game quits, its save is backed up to the save backup repository, if one is set (SaveBackup).
import AppKit
import Foundation

struct PlaySession: Codable, Hashable {
    var start: Date
    var seconds: Double
    /// measured while the session ran (PlayExtras: the game's memory, sampled; its frame rate, when frame times were recorded)
    var peakMB: Double? = nil
    var avgMB: Double? = nil
    var fps: Double? = nil
    var hitches: Int? = nil
}

struct PlayRecord: Codable, Hashable {
    var name: String
    var app: String
    var sessions: [PlaySession] = []
    var total: Double { sessions.reduce(0) { $0 + $1.seconds } }
    var last: Date? { sessions.map { $0.start.addingTimeInterval($0.seconds) }.max() }
}

/// A game running now: whose it is and since when.
struct PlayingNow {
    let key: String
    let name: String
    let app: String
    let start: Date
}

enum Playtime {
    static var file: URL { Settings.supportDir.appending(path: "playtime.json") }
    /// sessions shorter than this are a crash at launch or a peek, not play
    static let minSeconds: Double = 30
    /// sessions kept per game (older ones still count in no total: the chart shows weeks, the total is the kept sessions)
    static let keep = 500

    /// playtime.json decoded, kept while the file is unchanged (DecodedFile): Home and the Library read it on every redraw
    private static let decoded = DecodedFile<[String: PlayRecord]>()

    static func load() -> [String: PlayRecord] {
        decoded.value(file) { d in
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode([String: PlayRecord].self, from: d)
        } ?? [:]
    }

    static func save(_ all: [String: PlayRecord]) {
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(all) { try? d.write(to: file, options: .atomic) }
        decoded.drop()
    }

    @discardableResult
    static func add(key: String, name: String, app: String, start: Date, end: Date, session: PlaySession? = nil) -> PlayRecord? {
        let s = end.timeIntervalSince(start)
        guard s >= minSeconds else { return nil }
        var all = load()
        var r = all[key] ?? PlayRecord(name: name, app: app)
        r.name = name; r.app = app
        r.sessions.append(session ?? PlaySession(start: start, seconds: s))
        if r.sessions.count > keep { r.sessions.removeFirst(r.sessions.count - keep) }
        all[key] = r
        save(all)
        return r
    }

    /// Minutes played in each of the last `weeks` weeks, oldest first (this week last).
    static func weekly(_ r: PlayRecord, weeks: Int = 8, now: Date = Date()) -> [(week: Date, minutes: Double)] {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return (0..<weeks).reversed().map { i in
            let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek) ?? thisWeek
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let m = r.sessions.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.seconds } / 60
            return (start, m)
        }
    }

    /// "12 h 5 min", "45 min", "under a minute"
    static func text(_ s: Double) -> String {
        if s < 60 { return "under a minute" }
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m) min" : "\(m / 60) h\(m % 60 == 0 ? "" : " \(m % 60) min")"
    }
}

extension AppModel {
    /// The key a game's playtime is kept under: its title ID, else its app's path.
    static func playKey(app: String) -> String { VerifiedGames.titleID(ofApp: app) ?? app }

    func playRecord(app: String?, titleID: String?) -> PlayRecord? {
        let _ = revision
        let all = Playtime.load()
        if let t = titleID, let r = all[t] { return r }
        if let a = app { return all[a] ?? all[Self.playKey(app: a)] }
        return nil
    }

    /// Which built game an app that started is: one of the recorded builds (or a backup copy of one, by bundle ID).
    private func builtGame(_ a: NSRunningApplication) -> (key: String, name: String, app: String)? {
        guard let path = a.bundleURL?.standardizedFileURL.path else { return nil }
        let builds = Engine.builds()
        if let b = builds.first(where: { $0.app.url.standardizedFileURL.path == path }) {
            return (Self.playKey(app: b.app), b.app.url.deletingPathExtension().lastPathComponent, b.app)
        }
        guard let id = a.bundleIdentifier else { return nil }
        for b in builds {
            if (NSDictionary(contentsOfFile: b.app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String) == id {
                return (Self.playKey(app: b.app), b.app.url.deletingPathExtension().lastPathComponent, b.app)
            }
        }
        return nil
    }

    /// Watch game apps start and quit while the converter is open; games already running count from now.
    func trackPlay() {
        let nc = NSWorkspace.shared.notificationCenter
        for a in NSWorkspace.shared.runningApplications { started(a) }
        playObservers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let a { self?.started(a) } }
        })
        playObservers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let a { self?.quit(a) } }
        })
    }

    private func started(_ a: NSRunningApplication) {
        guard playing[a.processIdentifier] == nil, let g = builtGame(a) else { return }
        playing[a.processIdentifier] = PlayingNow(key: g.key, name: g.name, app: g.app, start: a.launchDate ?? Date())
        samplePlay()
        stepAside()
    }

    private func quit(_ a: NSRunningApplication) {
        guard let p = playing.removeValue(forKey: a.processIdentifier) else { return }
        suspended.remove(p.app.url.standardizedFileURL.path)
        let end = Date()
        let session = sessionEnded(p, pid: a.processIdentifier, end: end)
        if let r = Playtime.add(key: p.key, name: p.name, app: p.app, start: p.start, end: end, session: session), let session { showRecap(p, session: session, record: r) }
        revision += 1
        snapshotSaveAfterPlay(app: p.app)
        backUpSaveAfterPlay(app: p.app, name: p.name)
        gameQuit(app: p.app)
    }

    /// Whether a running game is kept paused behind the library.
    func isSuspended(app: String) -> Bool { !app.isEmpty && suspended.contains(app.url.standardizedFileURL.path) && isPlaying(app: app) }

    private func running(app: String) -> NSRunningApplication? {
        playing.first { $0.value.app == app }.flatMap { NSRunningApplication(processIdentifier: $0.key) }
    }

    /// Bring a running game back to the front as it is (a game kept behind the library hides itself); false when it is not running
    @discardableResult func resumeGame(app: String) -> Bool {
        guard let a = running(app: app), !a.isTerminated else { return false }
        a.unhide()
        a.activate(options: [.activateAllWindows])
        return true
    }

    /// Ask a running game to quit, as its own Quit does
    func quitGame(app: String) { running(app: app)?.terminate() }

    /// Whether a game is being played now.
    func isPlaying(app: String) -> Bool { playing.values.contains { $0.app == app } }

    /// The games played most recently, newest first, with their build (for Continue playing).
    func recentlyPlayed(limit: Int = 6) -> [(record: PlayRecord, key: String)] {
        let _ = revision
        return Playtime.load().filter { FileManager.default.fileExists(atPath: $0.value.app) && $0.value.last != nil }
            .sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }
            .prefix(limit).map { ($0.value, $0.key) }
    }
}
