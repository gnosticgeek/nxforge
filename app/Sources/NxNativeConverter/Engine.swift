// The engine is the NXForge checkout the script runs from: its commit is the version a game app is built
// with, shown as the release it is (git describe from the vX.Y.Z tags: 0.1.0, 0.1.0+3 three commits after it, pre-0.1.0 before the first). Each successful build is recorded in builds.json (beside settings.json) with that commit, since the
// app bundle itself does not carry one; an app built before that shows as "unknown".
import Foundation

struct EngineVersion: Codable, Hashable {
    var commit: String
    var subject: String
    var date: String
    var branch: String
    /// uncommitted changes to tracked files in the checkout when it was read
    var dirty: Bool
    /// git describe from the nearest vX.Y.Z release tag (nil before tags, and in records made before them)
    var version: String? = nil

    /// The release it is, for people: "0.1.0" at a release tag, "0.1.0+3" three commits after it, "pre-0.1.0" before the first one; the commit when no release is known
    var short: String { version.map(Engine.releaseName) ?? String(commit.prefix(7)) }
    var label: String { "\(short)\(dirty ? "+changes" : "") · \(subject) · \(date)" }
}

struct BuildRecord: Codable, Hashable, Identifiable {
    var id: String { app }
    var app: String
    var gameDir: String
    var engine: EngineVersion
    var repo: String
    var builtAt: String
    /// stages completed, and the shader count the Mac shader stage reported (nil for builds recorded before)
    var steps: Int?
    var shaders: String?
    /// "Base game + update"
    var gameFiles: String?
    /// Keep this build: one that plays well, which Rebuild all and the "older" badge leave alone (an explicit rebuild still
    /// replaces it, and its new record starts unkept). nil in records made before it.
    var kept: Bool?

    enum CodingKeys: String, CodingKey {
        case app, engine, repo, steps, shaders, kept
        case gameDir = "game_dir"
        case builtAt = "built_at"
        case gameFiles = "game_files"
    }

    var date: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: builtAt)
    }
}

/// An app moved aside by a rebuild: app-backups/<name> (<engine>, <yyyy-MM-dd-HH-mm>).app
struct Backup: Hashable, Identifiable {
    var id: String { path }
    let path: String
    let engine: String
    let date: Date?
}

enum Engine {
    private static func git(_ repo: String, _ args: [String]) -> String? {
        guard let r = run("/usr/bin/env", ["git", "-C", repo] + args, env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]), r.ok else { return nil }
        return r.out
    }

    static func current(_ repo: String) -> EngineVersion? {
        guard let log = git(repo, ["log", "-1", "--format=%H%x1f%s%x1f%cs"]) else { return nil }
        let p = log.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3 else { return nil }
        let branch = git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]) ?? ""
        let dirty = !(git(repo, ["status", "--porcelain", "--untracked-files=no"]) ?? "").isEmpty
        return EngineVersion(commit: p[0], subject: p[1], date: p[2], branch: branch, dirty: dirty, version: versionOf(p[0], repo: repo))
    }

    /// After a fetch: how many commits the upstream branch has that HEAD lacks.
    static func checkUpdates(_ repo: String) throws -> Int {
        guard git(repo, ["fetch", "--quiet", "origin"]) != nil else { throw ConverterError("git fetch failed") }
        guard let up = git(repo, ["rev-parse", "--abbrev-ref", "@{upstream}"]) else { throw ConverterError("this branch has no upstream branch to update from") }
        return Int(git(repo, ["rev-list", "--count", "HEAD..\(up)"]) ?? "0") ?? 0
    }

    /// Fast-forward to the upstream branch; refuses when that would need a merge.
    static func update(_ repo: String) throws {
        guard git(repo, ["pull", "--ff-only", "--quiet"]) != nil else { throw ConverterError("the engine cannot fast-forward (local changes or diverged branch)") }
    }

    private static var buildsFile: URL { Settings.supportDir.appending(path: "builds.json") }

    static func builds() -> [BuildRecord] {
        guard let d = try? Data(contentsOf: buildsFile) else { return [] }
        let all = (try? JSONDecoder().decode([BuildRecord].self, from: d)) ?? []
        // records made before releases were tagged: their release looked up in the engine's history, in the checkout
        // they were built from, else in today's engine (the checkout may have moved since: nxnative-src → NXForge)
        lazy var engine = Toolchain.findRepo(Settings.load())
        return all.map { b in
            var b = b
            if b.engine.version == nil {
                let repo = Toolchain.isRepo(b.repo) ? b.repo : engine
                b.engine.version = repo.flatMap { versionOf(b.engine.commit, repo: $0) }
            }
            return b
        }
    }

    /// "v0.1.0" → "0.1.0", "v0.1.0-3-gabc1234" (git describe) → "0.1.0+3", "pre-v0.1.0" → "pre-0.1.0"
    static func releaseName(_ describe: String) -> String {
        var s = describe; let pre = s.hasPrefix("pre-"); if pre { s.removeFirst(4) }
        if s.hasPrefix("v") { s.removeFirst() }
        let p = s.split(separator: "-")
        if p.count >= 3, p.last?.hasPrefix("g") == true, let n = Int(p[p.count - 2]) { s = p.dropLast(2).joined(separator: "-") + "+\(n)" }
        return pre ? "pre-" + s : s
    }

    private static var versionCache: [String: String] = [:]   // commit → describe, or "" when it has no release
    /// A commit's release (git describe from the nearest vX.Y.Z tag), or "pre-<first release after it>" for one from before the first tag; nil when the engine's history does not have it
    static func versionOf(_ commit: String, repo: String) -> String? {
        if let v = versionCache[commit] { return v.isEmpty ? nil : v }
        var v = git(repo, ["describe", "--tags", "--match", "v[0-9]*", commit])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if v.isEmpty, let after = git(repo, ["tag", "--contains", commit, "--list", "v[0-9]*", "--sort=v:refname"])?.split(separator: "\n").first { v = "pre-" + after }
        versionCache[commit] = v
        return v.isEmpty ? nil : v
    }

    /// The newest release's first change from the upstream branch's CHANGELOG.md, after a fetch: "0.1.1 · Quick settings sidebar …"
    static func upstreamNote(_ repo: String) -> String? {
        guard let up = git(repo, ["rev-parse", "--abbrev-ref", "@{upstream}"]), let log = git(repo, ["show", "\(up):CHANGELOG.md"]) else { return nil }
        let lines = log.split(separator: "\n").map { String($0) }
        guard let h = lines.firstIndex(where: { $0.hasPrefix("## ") }) else { return nil }
        let title = lines[h].dropFirst(3).split(separator: " (").first.map(String.init) ?? ""
        let first = lines[(h + 1)...].first { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)).replacingOccurrences(of: "**", with: "") } ?? ""
        let note = first.count > 110 ? String(first.prefix(110)) + "…" : first
        return note.isEmpty ? title : "\(title) · \(note)"
    }

    /// Drop an app from the build records (the app itself is left where it is).
    static func forget(_ app: String) {
        let all = builds().filter { $0.app != app }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(all) { try? d.write(to: buildsFile) }
    }

    /// Keep a build (or stop keeping it): Rebuild all then passes it by.
    static func setKept(_ app: String, _ on: Bool) {
        guard var b = builds().first(where: { $0.app == app }) else { return }
        b.kept = on ? true : nil
        record(b)
    }

    static func record(_ b: BuildRecord) {
        var all = builds().filter { $0.app != b.app }
        all.append(b)
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(all) { try? d.write(to: buildsFile) }
    }

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    /// The game apps in a folder (top level), each with the build recorded for it.
    static func apps(in dir: String) -> [(app: String, build: BuildRecord?)] {
        let known = builds()
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items.filter { $0.hasSuffix(".app") && FileManager.default.fileExists(atPath: "\(dir)/\($0)/Contents/MacOS/dmhost") }
            .sorted()
            .map { name in let p = "\(dir)/\(name)"; return (p, known.first { $0.app == p }) }
    }

    /// The copies a rebuild kept of this app, newest first.
    static func backups(of app: String) -> [Backup] {
        let u = app.url
        let dir = u.deletingLastPathComponent().appending(path: "app-backups").path
        let stem = u.deletingPathExtension().lastPathComponent + " ("
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH-mm"
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix(stem) && $0.hasSuffix(").app") }.map { name in
            let inner = name.dropFirst(stem.count).dropLast(5).split(separator: ", ")
            return Backup(path: "\(dir)/\(name)", engine: String(inner.first ?? "?"), date: inner.count > 1 ? f.date(from: String(inner[1])) : nil)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// "Base game + update", "Base game + 2 DLC" from the folder's file names.
    static func describeFiles(_ dir: String) -> String {
        let names = GameFiles.list(in: dir.url).map(\.lastPathComponent)
        let tails = names.compactMap { n -> String? in
            guard let r = n.range(of: #"\[[0-9A-Fa-f]{16}\]"#, options: .regularExpression) else { return nil }
            return String(n[r].dropFirst(14).prefix(3))
        }
        // an update is tagged …800, though some dumps tag it with the base game's ID and only a version above v0 (Cyber Shadow)
        let versioned = names.filter { $0.range(of: #"\[v[1-9][0-9]*\]"#, options: .regularExpression) != nil }.count
        let upd = max(tails.filter { $0 == "800" }.count, versioned)
        let dlc = tails.filter { $0 != "800" && $0 != "000" }.count
        var parts = ["Base game"]
        if upd > 0 { parts.append("update") }
        if dlc > 0 { parts.append("\(dlc) DLC") }
        return parts.joined(separator: " + ")
    }

    /// Move an app aside before rebuilding it: <folder>/app-backups/<name> (<engine or "old engine">, <time>).app.
    /// A rename on the same volume, so it is instant and takes no space.
    static func backUp(_ app: String, engine: EngineVersion?) throws -> String {
        let u = URL(fileURLWithPath: app)
        let dir = u.deletingLastPathComponent().appending(path: "app-backups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = now().replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "-")
        let dst = dir.appending(path: "\(u.deletingPathExtension().lastPathComponent) (\(engine?.short ?? "old engine"), \(stamp)).app")
        do { try FileManager.default.moveItem(at: u, to: dst) } catch { throw ConverterError("cannot move \(app) aside: \(error.localizedDescription)") }
        return dst.path
    }
}
