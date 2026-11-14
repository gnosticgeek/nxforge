// What NXForge knows about a game before and after a build:
//   - its profile notes (idea 8): dm/games/<title ID>/README.md in the engine checkout, cut to its opening paragraph and its open
//     issues, beside the docs/nxforge-games.tsv result (VerifiedGames), so a long build starts knowing what to expect;
//   - whether a rebuild is worth it (idea 7): the engine commits since a build that touch what its build reads (Engine.affects),
//     the game's own profile changes marked, with a suggestion and the time the last build took.
import Foundation

struct ProfileNotes: Equatable {
    var titleID: String
    var title: String
    /// the README's first paragraph: version, engine, how it plays
    var summary: String
    /// bullets still open ("**Open:**", "Not checked", "not yet")
    var open: [String]
    /// how many issues the profile records as resolved
    var resolved: Int
    var readme: String
}

struct EngineChange: Hashable, Identifiable {
    var id: String { hash }
    let hash: String
    let subject: String
    let date: String
    /// it changes this game's own profile (dm/games/<title ID>/)
    let ownProfile: Bool
}

struct RebuildAdvice {
    let changes: [EngineChange]
    /// "Worth it: this game's own profile changed" and the like
    let verdict: String
    let worth: Bool
}

/// What a rebuild on the engine in use would have to redo, told from the build folder and the files that changed, with nothing
/// run: Preview build on Convert asks the build script itself and is exact.
struct RebuildCost: Hashable {
    enum Kind { case quick, partial, shaders, full }
    let kind: Kind
    /// the steps' times the last time they did their work (<id>_build/logs/stage_times.json); nil when none is recorded
    let seconds: Double?

    /// for the badge: "quick rebuild", "shader rebuild"
    var short: String {
        switch kind {
        case .quick: "quick rebuild"
        case .partial: "partial rebuild"
        case .shaders: "shader rebuild"
        case .full: "full rebuild"
        }
    }
    var title: String {
        let t = seconds.map { ", about \(duration($0))" } ?? ""
        return short.prefix(1).uppercased() + short.dropFirst() + t
    }
    var detail: String {
        switch kind {
        case .quick: "only the player and the app are made again; the unpacked game and its shaders are reused."
        case .partial: "the build's tools or this game's profile changed, so some steps run again; shaders whose inputs are unchanged come back from the cache. Preview build lists the steps."
        case .shaders: "the engine's shader chain changed, so every shader is translated again and the pipeline archive is made again."
        case .full: "the build folder is gone, so the game is unpacked and its shaders are built again; it needs the game files."
        }
    }

    /// The chain version the engine's shader libraries are named by: the 12 hex digits in dm/gfx/nvn/dmsh_chain.h.
    static func chain(header text: String) -> String? {
        text.range(of: #""[0-9a-f]{12}""#, options: .regularExpression).map { String(text[$0].dropFirst().dropLast()) }
    }

    /// The chains a build folder's Mac shader step finished on: shader.noindex/mac-b-<chain>.key.
    static func builtChains(buildFolder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: buildFolder + "/shader.noindex")) ?? [])
            .filter { $0.hasPrefix("mac-b-") && $0.hasSuffix(".key") }.map { String($0.dropFirst(6).dropLast(4)) }
    }

    /// The kind from what is known. chain: the engine's now; built: the chains the build folder holds (nil: no build folder);
    /// changed: the engine files that differ since the build (nil: git cannot tell). A game with no chain libraries at all
    /// (a Vulkan or OpenGL game) is judged by the files alone.
    static func kind(chain: String?, built: [String]?, changed: [String]?, titleID: String?) -> Kind {
        guard let built else { return .full }
        if let chain, !built.isEmpty, !built.contains(chain) { return .shaders }
        guard let changed else { return .partial }
        // what the unpack, rewrite and shader steps read (Engine.affects has already left out other games' profiles); the rest of a
        // build's inputs (dm/host, dm/gfx's own sources, dm/mac, the libraries) only make the player and the app
        let deep = changed.contains { p in
            guard Engine.affects(p, titleID: titleID) else { return false }
            return ["dm/tools/", "dm/gfx/tools/", "dm/games/", "dm/ios/tools/"].contains { p.hasPrefix($0) } || p == "scripts/build_ipa_from_nsp.py"
        }
        return deep ? .partial : .quick
    }

    /// The steps a rebuild of each kind runs for certain, for its time from the last run of each.
    static func seconds(_ kind: Kind, times: [String: Double]) -> Double? {
        let steps: [String]
        switch kind {
        case .quick: steps = ["Mac host", "Mac app"]
        case .shaders: steps = ["Mac shaders", "Mac host", "Pipeline archive", "Pipeline prebuild", "Mac app"]
        case .full: steps = Array(times.keys)
        case .partial: return nil
        }
        let known = steps.compactMap { times[$0] }
        if known.isEmpty || (kind == .shaders && times["Mac shaders"] == nil) || (kind == .quick && times["Mac app"] == nil) { return nil }
        return known.reduce(0, +)
    }
}

enum GameInsights {
    static func notes(repo: String, titleID: String) -> ProfileNotes? {
        let path = Layer.file(repo, "dm/games/\(titleID.uppercased())/README.md")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(text, titleID: titleID, readme: path)
    }

    static func parse(_ text: String, titleID: String, readme: String) -> ProfileNotes {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var title = titleID
        if let h = lines.first(where: { $0.hasPrefix("# ") }) {
            title = String(h.dropFirst(2)).replacingOccurrences(of: #"\s*\(`?[0-9A-Fa-f]{16}`?\)"#, with: "", options: .regularExpression)
        }
        // the first paragraph after the heading
        var summary: [String] = []
        var started = false
        for l in lines.drop(while: { !$0.hasPrefix("# ") }).dropFirst() {
            if l.trimmingCharacters(in: .whitespaces).isEmpty { if started { break } else { continue } }
            if l.hasPrefix("#") || l.hasPrefix("|") || l.hasPrefix("- ") { if started { break } else { continue } }
            started = true
            summary.append(l)
        }
        let bullets = lines.filter { $0.hasPrefix("- ") }
        let open = bullets.filter { b in b.contains("**Open") || b.contains("Open:**") || b.hasPrefix("- **Not ") || b.contains("**Unresolved") || b.contains("**Known issue") }
            .map(clean)
        let resolved = bullets.filter { $0.hasPrefix("- **Resolved") }.count
        return ProfileNotes(titleID: titleID, title: title, summary: clean(summary.joined(separator: " ")), open: open, resolved: resolved, readme: readme)
    }

    /// Markdown cut down for a label: no links' targets, code ticks or bold marks, at most 400 characters.
    static func clean(_ s: String) -> String {
        var t = s.hasPrefix("- ") ? String(s.dropFirst(2)) : s
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return t.count > 400 ? String(t.prefix(400)) + "…" : t
    }

    private static func git(_ repo: String, _ args: [String]) -> String? {
        guard let r = run("/usr/bin/env", ["git", "-C", repo] + args, env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]), r.ok else { return nil }
        return r.out
    }

    /// The commits since `commit` that change something this game's build reads, newest first; nil when git cannot tell.
    static func changes(since commit: String, repo: String, titleID: String?) -> [EngineChange]? {
        guard let out = git(repo, ["log", "--no-merges", "--format=\u{1e}%h\u{1f}%s\u{1f}%cs", "--name-only", "\(commit)..HEAD"]) else { return nil }
        var result: [EngineChange] = []
        for block in out.split(separator: "\u{1e}") {
            let lines = block.split(separator: "\n").map(String.init)
            guard let head = lines.first else { continue }
            let p = head.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3 else { continue }
            let files = Layer.enginePaths(lines.dropFirst().filter { !$0.isEmpty })
            guard files.contains(where: { Engine.affects($0, titleID: titleID) }) else { continue }
            let own = titleID.map { t in files.contains { $0.uppercased().hasPrefix("DM/GAMES/\(t.uppercased())/") } } ?? false
            result.append(EngineChange(hash: p[0], subject: p[1], date: p[2], ownProfile: own))
        }
        return result
    }

    static func advice(_ changes: [EngineChange], lastSeconds: Int?) -> RebuildAdvice {
        let took = lastSeconds.map { " The last build took \(duration(Double($0)))." } ?? ""
        if changes.isEmpty {
            return RebuildAdvice(changes: [], verdict: "Nothing this game's build reads has changed: a rebuild would make the same app.", worth: false)
        }
        let own = changes.filter(\.ownProfile).count
        if own > 0 {
            return RebuildAdvice(changes: changes, verdict: "Worth it: \(own) change\(own == 1 ? "" : "s") to this game's own profile, and \(changes.count - own) general one\(changes.count - own == 1 ? "" : "s").\(took)", worth: true)
        }
        let n = changes.count
        return RebuildAdvice(changes: changes, verdict: "\(n) general change\(n == 1 ? "" : "s") to the engine (host, graphics or the build) since this build. Rebuild if something looked wrong, or to stay current.\(took)", worth: n >= 5)
    }
}
