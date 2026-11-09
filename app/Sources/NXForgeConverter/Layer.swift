// The layered engine (NXForge 0.19.0 on; UPSTREAM.md, "Engine and layer"): the checkout pins an untouched nxnative commit in
// layer/ENGINE, keeps NXForge's changes to nxnative's files as layer/patches and its own engine files as layer/files, and
// scripts/layer.py assembles them into tree/ (git-ignored), where builds run. A checkout from before keeps the engine at its root:
// every function here answers for both, so the converter works on either.
import Foundation

enum Layer {
    static let engineFile = "layer/ENGINE"
    static let script = "scripts/layer.py"

    static func isLayered(_ repo: String) -> Bool {
        FileManager.default.fileExists(atPath: repo + "/" + engineFile) && FileManager.default.fileExists(atPath: repo + "/" + script)
    }

    /// Where the engine's files are: tree/ of a layered checkout, else the checkout itself.
    static func tree(_ repo: String) -> String { isLayered(repo) ? repo + "/tree" : repo }

    /// A file of the engine (a path like "dm/games/<id>/README.md"): in tree/ when assembled, else in layer/files (an NXForge
    /// file), else nxnative's file is not readable until tree/ is assembled and the tree/ path is returned anyway.
    static func file(_ repo: String, _ rel: String) -> String {
        guard isLayered(repo) else { return repo + "/" + rel }
        let fm = FileManager.default
        let t = repo + "/tree/" + rel
        if fm.fileExists(atPath: t) { return t }
        let own = repo + "/layer/files/" + rel
        return fm.fileExists(atPath: own) ? own : t
    }

    /// Assemble tree/ from the layer (a quick no-op while it matches). nil when tree/ is ready, else what went wrong.
    static func assemble(_ repo: String, python: String? = nil) -> String? {
        guard isLayered(repo) else { return nil }
        let py = python ?? (FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") ? "/usr/bin/python3" : "python3")
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        guard let r = run(py, ["-I", repo + "/" + script, "assemble"], env: ["PATH": path], cwd: repo) else { return "cannot start \(py)" }
        if r.ok { return nil }
        let last = r.out.split(separator: "\n").filter { !$0.isEmpty }.prefix(4).joined(separator: " ")
        return last.isEmpty ? "scripts/layer.py assemble failed" : last.replacingOccurrences(of: "layer.py: ", with: "")
    }

    /// The nxnative commit pinned at a ref of the checkout ("origin/main", "HEAD"); nil when the ref has no layer (from before 0.19.0).
    static func pin(repo: String, ref: String, git: (String, [String]) -> String?) -> String? {
        guard let text = git(repo, ["show", "\(ref):\(engineFile)"]) else { return nil }
        return parsePin(text)
    }

    static func parsePin(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let l = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if l.hasPrefix("commit ") {
                let c = l.dropFirst(7).trimmingCharacters(in: .whitespaces)
                return c.count == 40 && c.allSatisfy(\.isHexDigit) ? c : nil
            }
        }
        return nil
    }

    /// Changed paths of the checkout (git diff, git log) as engine paths, for Engine.affects: layer/files/<path> is <path>; a new
    /// pin or a changed patch can touch any part of the engine, so it counts as "dm/host/" (every game's build reads it). Paths
    /// outside the layer pass through (a checkout from before 0.19.0 has the engine at its root).
    static func enginePaths(_ files: [String]) -> [String] {
        var out: [String] = []
        for f in files {
            if f.hasPrefix("layer/files/") { out.append(String(f.dropFirst("layer/files/".count))) }
            else if f == engineFile || (f.hasPrefix("layer/patches/") && f.hasSuffix(".patch")) { out.append("dm/host/" + f) }
            else { out.append(f) }
        }
        return out
    }

    // MARK: Upstream on this Mac (`layer.py local`; Converter 0.5.0)

    static let localName = "nxforge-local-engine"

    /// "<commit> <pin>" from the checkout's git folder: the newer nxnative commit tree/ is assembled on, and the pin it was
    /// taken on. Only while the pin is still that one (layer.py drops it at its next run otherwise).
    static func parseLocal(_ text: String, pin: String?) -> String? {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2, parts[0].count == 40, parts[0].allSatisfy(\.isHexDigit), let pin, parts[1] == pin, parts[0] != pin else { return nil }
        return parts[0]
    }

    /// The upstream nxnative commit this Mac's engine runs on instead of the pinned one, nil when it runs on the pin.
    static func localCommit(_ repo: String, git: (String, [String]) -> String?) -> String? {
        guard isLayered(repo), let rel = git(repo, ["rev-parse", "--git-path", localName])?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let path = rel.hasPrefix("/") ? rel : repo + "/" + rel
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parseLocal(text, pin: pin(repo: repo, ref: "HEAD", git: git))
    }

    /// `layer.py local` (take upstream nxnative's newest main on this Mac, when every patch still applies) or `local --off`
    /// (back to the pinned engine). ok and the script's last line; on a failure all of its output, since run() hands back
    /// stdout (the per-patch check, "0004-gfx-metal.patch: conflicts (…)") rather than the error on stderr.
    static func local(_ repo: String, off: Bool) -> (ok: Bool, text: String) {
        let py = FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") ? "/usr/bin/python3" : "python3"
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        guard let r = run(py, ["-I", repo + "/" + script, "local"] + (off ? ["--off"] : []), env: ["PATH": path], cwd: repo) else { return (false, "cannot start \(py)") }
        let lines = r.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let last = lines.last.map { $0.replacingOccurrences(of: "layer.py: ", with: "") } ?? (r.ok ? "" : "scripts/layer.py local failed")
        return (r.ok, r.ok ? last : lines.joined(separator: "\n"))
    }

    /// The patches a failed `layer.py local` named, from its check ("0004-gfx-metal.patch: conflicts (a, b)") or its error
    /// ("0004-gfx-metal.patch clashes in a, b"), as theme names in order, each once: ["gfx-metal", "packing"].
    static func clashes(_ text: String) -> [String] {
        guard let r = try? NSRegularExpression(pattern: #"\d{4}-([a-z0-9-]+)\.patch(?: clashes|: conflicts)"#) else { return [] }
        var seen: [String] = []
        for m in r.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let g = Range(m.range(at: 1), in: text), !seen.contains(String(text[g])) { seen.append(String(text[g])) }
        }
        return seen
    }
}
