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

enum GameInsights {
    static func notes(repo: String, titleID: String) -> ProfileNotes? {
        let path = "\(repo)/dm/games/\(titleID.uppercased())/README.md"
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
            let files = lines.dropFirst().filter { !$0.isEmpty }
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
