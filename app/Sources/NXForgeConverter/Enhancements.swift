// Enhancements: a game's own improvements, kept apart from its cheats. An enhancement is one Markdown file in the game's
// `enhancements/` folder (beside `cheats/` and `media/`), so each can be added, shared and switched on its own:
//
//   ---
//   nxforge_enhancement: 1
//   name: "Steady 60 in full screen"
//   title_id: "010019401051C000"
//   builds: "2E90F0815B1F92A1"        (optional: the build IDs it is for, separated by spaces; none means every build)
//   on: false
//   source: "NXForge"
//   ---
//   # Steady 60 in full screen
//
//   What it does, in a paragraph or two.
//
//   ```env
//   DM_FULLSCREEN_STYLE=window
//   ```
//
// Three kinds of block, any mix of them: ```env (launch settings, one KEY=VALUE a line), ```dmnt (an Atmosphère code: a
// frame-rate patch and the like) and ```mods (the names of mod folders, one a line, from the game's mods). What NXForge does
// with the ones switched on, before every launch and the moment a switch changes, whatever opens the game (the front end,
// Theatre, Finder):
//   env   → a block of `~/Library/Application Support/nxnative/<title ID>/env.txt`, which the game's launcher reads first
//           (dm/mac/launcher.c env_file). The settings window shows those settings greyed out, set by the file.
//   dmnt  → master codes `{NXForge enhancement: <name>}` in the engine's `<build>.txt` cheat file. A master always runs, so it
//           needs no switch in `<build>.enabled`; the Cheats card, the cheats Markdown and Get Cheats leave these entries out.
//   mods  → the mods are switched on (ModState, the game's "NXForge settings.txt").
// Switching an enhancement off takes back what it added (its env lines, its codes, the mods it switched on).
//
// The library: `library/<title ID>/enhancements/*.md` in NXForge's GitHub repository. Get from Library lists the files for the
// game there and copies the ones chosen into its folder; `scripts/library.py collect` brings a game folder's own files back
// into the repository, to commit and share.
import Foundation

struct Enhancement: Identifiable, Hashable {
    /// the file's name in the enhancements folder ("steady-60-full-screen.md")
    var file: String
    var name: String
    var summary: String = ""
    var builds: [String] = []
    var on = false
    var source: String?
    var env: [String] = []
    var patch: [String] = []
    var mods: [String] = []
    var id: String { file }

    /// What it changes, for its row's pills
    var kinds: [String] {
        (env.isEmpty ? [] : ["Settings"]) + (patch.isEmpty ? [] : ["Game code"]) + (mods.isEmpty ? [] : ["Mod"])
    }

    /// Whether it is for a build (nil: the app's build is not known)
    func fits(build: String?) -> Bool {
        guard !builds.isEmpty, let build else { return true }
        return builds.contains { $0.uppercased() == build.uppercased() }
    }

    /// env lines as (key, value), comments and malformed lines left out
    var settings: [(String, String)] {
        env.compactMap { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return nil }
            let k = t[..<eq].trimmingCharacters(in: .whitespaces), v = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty, k.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
            return (k, v)
        }
    }
}

enum Enhancements {
    static let folderName = "enhancements"
    static let patchPrefix = "NXForge enhancement: "
    static let envBegin = "# --- NXForge enhancements (written by NXForge; switch them in the game's Enhancements) ---"
    static let envEnd = "# --- end of NXForge enhancements ---"
    static let repo = "gnosticgeek/nxforge"

    // MARK: Format

    static func parse(_ text: String, file: String) -> Enhancement? {
        let fm = MiniYAML.frontMatter(text) ?? [:]
        guard fm["nxforge_enhancement"] != nil || fm["name"] != nil else { return nil }
        var e = Enhancement(file: file, name: (fm["name"] as? String) ?? (file as NSString).deletingPathExtension)
        e.on = (fm["on"] as? Bool) ?? false
        e.source = fm["source"] as? String
        if let b = fm["builds"] as? String { e.builds = b.split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0).uppercased() }.filter { $0.count == 16 } }
        else if let b = fm["builds"] as? [Any] { e.builds = b.compactMap { ($0 as? String)?.uppercased() }.filter { $0.count == 16 } }
        var lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines = Array(lines[(end + 1)...])
        }
        var fence: String?, para: [String] = [], summaryDone = false
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("```") {
                if fence != nil { fence = nil }
                else { fence = s.dropFirst(3).split(separator: " ").first.map { $0.lowercased() } ?? ""; if !para.isEmpty { summaryDone = true } }
                continue
            }
            if let f = fence {
                guard !s.isEmpty else { continue }
                switch f {
                case "env": e.env.append(s)
                case "dmnt": e.patch.append(s)
                case "mods", "mod": e.mods.append(s)
                default: break
                }
                continue
            }
            // the summary: the first paragraph of text, headings left out
            if s.isEmpty || s.hasPrefix("#") { if !para.isEmpty { summaryDone = true }; continue }
            if !summaryDone { para.append(s) }
        }
        e.summary = para.joined(separator: " ")
        return e
    }

    /// The file's text with its `on:` line set (added to the front matter when it has none)
    static func setOn(_ text: String, _ on: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return "---\nnxforge_enhancement: 1\non: \(on)\n---\n" + text
        }
        if let i = lines[1..<end].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on:") }) { lines[i] = "on: \(on)" }
        else { lines.insert("on: \(on)", at: end) }
        return lines.joined(separator: "\n")
    }

    /// A safe file name for a new enhancement
    static func fileName(_ name: String) -> String {
        let s = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(s).split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "enhancement" : String(slug.prefix(60))) + ".md"
    }

    // MARK: Folder

    /// The enhancements folder beside the cheats folder: "cheats" → "enhancements", "<App> cheats" → "<App> enhancements"
    static func folder(cheats: URL) -> URL {
        let n = cheats.lastPathComponent
        let base = n.hasSuffix(" " + GameFolderCheats.folderName) ? String(n.dropLast(GameFolderCheats.folderName.count)) + folderName : folderName
        return cheats.deletingLastPathComponent().appending(path: base)
    }

    /// Where a game's enhancements live when NXForge does not keep files in the game's folder
    static func supportFolder(titleID: String, home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: GameExtras.support(titleID: titleID, home: home)).appending(path: folderName)
    }

    /// A built game's enhancements folder: beside the app's cheats or media folder (a folder shared by several apps: "<App>
    /// enhancements"), else the engine's folder for the game when the app's folder holds neither
    static func folder(app: String, titleID: String) -> URL {
        let fm = FileManager.default, parent = app.url.deletingLastPathComponent(), own = app.url.deletingPathExtension().lastPathComponent
        let shared = parent.appending(path: "\(own) \(folderName)"), plain = parent.appending(path: folderName)
        for (probe, result) in [("\(own) \(folderName)", shared), ("\(own) \(GameFolderCheats.folderName)", shared), ("\(own) \(GameFolderMedia.folderName)", shared),
                                (folderName, plain), (GameFolderCheats.folderName, plain), (GameFolderMedia.folderName, plain)]
        where fm.fileExists(atPath: parent.appending(path: probe).path) { return result }
        return supportFolder(titleID: titleID)
    }

    static func load(folder: URL) -> [Enhancement] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted()
        return names.compactMap { n in (try? String(contentsOf: folder.appending(path: n), encoding: .utf8)).flatMap { parse($0, file: n) } }
    }

    static func setOn(_ e: Enhancement, _ on: Bool, folder: URL) throws {
        let u = folder.appending(path: e.file)
        let t = try String(contentsOf: u, encoding: .utf8)
        try Data(setOn(t, on).utf8).write(to: u, options: .atomic)
    }

    // MARK: Applying

    /// env.txt's text with NXForge's block replaced by `lines` (taken out when empty); the player's own lines are kept
    static func envText(_ old: String, lines: [String]) -> String {
        var keep: [String] = [], inside = false
        for l in old.components(separatedBy: "\n") {
            if l == envBegin { inside = true; continue }
            if inside { if l == envEnd { inside = false }; continue }
            keep.append(l)
        }
        while keep.last?.isEmpty == true { keep.removeLast() }
        var out = keep
        if !lines.isEmpty {
            // the launcher keeps the first value it reads for a variable: NXForge's block goes first, so a switched-on
            // enhancement wins over an older line of the player's further down
            out = [envBegin] + lines + [envEnd] + (keep.isEmpty ? [] : [""] + keep)
        }
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    /// The cheat entries with the enhancements' codes taken out
    static func strip(_ entries: [CheatEntry]) -> [CheatEntry] { entries.filter { !($0.master && $0.name.hasPrefix(patchPrefix)) } }

    /// The engine's cheat entries for a build: the player's cheats as they are, then one master per switched-on enhancement code
    static func withPatches(_ entries: [CheatEntry], _ list: [Enhancement]) -> [CheatEntry] {
        strip(entries) + list.filter { $0.on && !$0.patch.isEmpty }.map { CheatEntry(name: patchPrefix + $0.name, master: true, lines: $0.patch) }
    }

    /// What the switched-on enhancements need, written where the game reads it. `app` is the built game (its build ID and its
    /// mods file); `previous` is what was on before a change, so mods an enhancement switched on go off with it.
    /// Load a built game's enhancements and write what the switched-on ones need (before a launch, after a file changed by hand)
    @discardableResult
    static func apply(app: String) -> String? {
        guard let tid = VerifiedGames.titleID(ofApp: app) else { return nil }
        return apply(load(folder: folder(app: app, titleID: tid)), titleID: tid, app: app)
    }

    @discardableResult
    static func apply(_ list: [Enhancement], titleID: String, app: String?, previous: [Enhancement] = [], home: String = NSHomeDirectory()) -> String? {
        let fm = FileManager.default
        let build = app.flatMap { GameExtras.buildID(app: $0) }
        let active = list.filter { $0.on && $0.fits(build: build) }
        var problem: String?
        // env.txt
        let sup = GameExtras.support(titleID: titleID, home: home), envPath = sup + "/env.txt"
        let old = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        var seen = Set<String>(), lines: [String] = []
        for e in active { for (k, v) in e.settings where seen.insert(k).inserted { lines.append("\(k)=\(v)") } }
        let new = envText(old, lines: lines)
        if new != old {
            do {
                try fm.createDirectory(atPath: sup, withIntermediateDirectories: true)
                if new.isEmpty { try? fm.removeItem(atPath: envPath) } else { try new.write(toFile: envPath, atomically: true, encoding: .utf8) }
            } catch { problem = "Could not write the game's env.txt: \(error.localizedDescription)" }
        }
        // the codes, in the build's cheat file
        if let build {
            let dir = GameExtras.cheatsDir(titleID: titleID, home: home), p = CheatFile.path(dir: dir, build: build)
            let had = CheatFile.load(dir: dir, build: build)
            let want = withPatches(had, active)
            if want != had && !(had.isEmpty && want.isEmpty) {
                do {
                    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    if want.isEmpty { try? fm.removeItem(atPath: p) } else { try CheatFile.text(want).write(toFile: p, atomically: true, encoding: .utf8) }
                } catch { problem = "Could not write the game's codes: \(error.localizedDescription)" }
            }
        }
        // mods
        if let app {
            let wantMods = Set(active.flatMap(\.mods)), hadMods = Set(previous.filter { $0.on }.flatMap(\.mods)).subtracting(wantMods)
            if !wantMods.isEmpty || !hadMods.isEmpty {
                var s = ModState.load(app: app)
                let before = s.on
                s.on = s.on.filter { !hadMods.contains($0) }
                for m in wantMods.sorted() where !s.on.contains(m) {
                    if fm.fileExists(atPath: GameExtras.modsDir(titleID: titleID, home: home) + "/" + m) { s.on.append(m) }
                    else { problem = "The mod \"\(m)\" is not in the game's mods: add it in Mods first." }
                }
                if s.on != before { s.save(app: app) }
            }
        }
        return problem
    }

    // MARK: Library (GitHub)

    struct LibraryItem: Identifiable, Hashable { let file: String; let download: URL; var id: String { file } }

    static func libraryURL(titleID: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/contents/library/\(titleID.uppercased())/\(folderName)")!
    }

    static func parseListing(_ data: Data) -> [LibraryItem] {
        guard let a = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return a.compactMap { o in
            guard (o["type"] as? String) == "file", let n = o["name"] as? String, n.hasSuffix(".md"), !n.hasPrefix("."),
                  let d = o["download_url"] as? String, let u = URL(string: d) else { return nil }
            return LibraryItem(file: n, download: u)
        }
    }

    /// The library's enhancements for a game: nil when GitHub could not be reached, [] when it has none
    static func library(titleID: String) async -> [(LibraryItem, Enhancement)]? {
        var req = URLRequest(url: libraryURL(titleID: titleID), timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse else { return nil }
        if h.statusCode == 404 { return [] }
        guard h.statusCode == 200 else { return nil }
        var out: [(LibraryItem, Enhancement)] = []
        for item in parseListing(data) {
            guard let (d, r) = try? await URLSession.shared.data(from: item.download), (r as? HTTPURLResponse)?.statusCode == 200,
                  let t = String(data: d, encoding: .utf8), let e = parse(t, file: item.file) else { continue }
            out.append((item, e))
        }
        return out
    }

    /// Copy a library file into the game's folder, switched off (a file of that name already there is kept)
    static func install(_ item: LibraryItem, folder: URL) async throws {
        let (d, r) = try await URLSession.shared.data(from: item.download)
        guard (r as? HTTPURLResponse)?.statusCode == 200, let t = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appending(path: item.file)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try Data(setOn(t, false).utf8).write(to: dest, options: .atomic)
    }
}
