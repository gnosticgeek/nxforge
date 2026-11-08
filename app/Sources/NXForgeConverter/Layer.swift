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
}
