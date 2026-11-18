// A built game's media and details, kept in its own folder beside the app: `media/` holds the cover (front, back, spine), the wide
// art, the icon, the store's screenshots, the trailers' pictures and a manual added in NXForge, and `media/game.md` lists everything
// known about the game: Markdown with YAML front matter (title, title ID, versions, the build, the play options, the store's details,
// links to the trailers and the files beside it). Written from the artwork NXForge keeps on this Mac (Covers.swift, StoreInfo.swift)
// whenever that changes and after each build, so the folder follows the cache and own covers; nothing extra is downloaded (trailers
// stay links). When this Mac has nothing for a game yet (a new Mac, the artwork folder emptied) the library takes the pictures and
// details back from the game's folder. A setting turns it off (Settings › Artwork).
import AppKit
import Foundation

/// The format, apart from the files (tested)
enum GameFolderMedia {
    static let folderName = "media"
    static let fileName = "game.md"

    /// Where a game's media goes: `media/` in the folder holding its app, when that folder holds no other app (the game's folder, or
    /// its NXForge Builds folder); in a shared output folder, `media/` in the game files' folder, else "<App> media" beside the app.
    static func folder(app: String, gameFolder: String?, appsBeside: Int) -> URL {
        let parent = app.url.deletingLastPathComponent()
        if appsBeside <= 1 { return parent.appending(path: folderName) }
        if let g = gameFolder, g != parent.path { return g.url.appending(path: folderName) }
        return parent.appending(path: app.url.deletingPathExtension().lastPathComponent + " " + folderName)
    }

    /// One game's details, gathered on the main thread and written off it
    struct Item {
        var key: String
        var title: String
        var titleID: String?
        var console: String
        var app: String
        var gameFolder: String?
        var version: String?
        var publisher: String?
        var gameFiles: String?
        var newestUpdate: UInt64?
        var record: BuildRecord?
        var store: StoreInfo?
        /// a manual added in NXForge (copied), or found beside the game files (linked)
        var manual: URL?
        var manualAdded = false
        var icon: String?
        var preset: String?
        var changed: [(String, String)] = []
        var played: Double = 0
        var lastPlayed: Date?
        var dest: URL
    }

    /// The pictures written beside game.md: (name in media/ without its extension, file in the artwork folder)
    static func pictures(key: String, cache: URL, store: StoreInfo?, icon: String?, fileExists: (URL) -> Bool) -> [(name: String, source: URL)] {
        var out: [(String, URL)] = []
        for side in CoverSide.allCases {
            let own = cache.appending(path: "\(key)-\(side.rawValue)-own.png"), got = cache.appending(path: "\(key)-\(side.rawValue).jpg")
            if fileExists(own) { out.append(("cover-\(side.rawValue)", own)) } else if fileExists(got) { out.append(("cover-\(side.rawValue)", got)) }
        }
        let hero = cache.appending(path: "\(key)-hero.jpg")
        if fileExists(hero) { out.append(("wide-art", hero)) }
        if let icon, fileExists(icon.url) { out.append(("icon", icon.url)) }
        let storeDir = cache.appending(path: "store")
        for i in 0..<min(store?.shots.count ?? 0, StoreInfoStore.maxShots) {
            let f = storeDir.appending(path: String(format: "%@-%02d.jpg", key, i + 1))
            if fileExists(f) { out.append((String(format: "screenshots/%02d", i + 1), f)) }
        }
        for i in 0..<(store?.trailers?.count ?? 0) {
            let f = storeDir.appending(path: String(format: "%@-t%02d.jpg", key, i + 1))
            if fileExists(f) { out.append((String(format: "trailers/%02d", i + 1), f)) }
        }
        return out
    }

    /// game.md: YAML front matter for programs, the same in Markdown for people. `files`: the media files written, by their name
    /// without extension ("cover-front" → "cover-front.png").
    static func document(_ it: Item, files: [String: String]) -> String {
        var y: [String] = ["---", "# Written by NXForge from what it knows about this game. It is rewritten when that changes, so edits here do not last.", "nxforge_media: 1"]
        func add(_ k: String, _ v: String?, _ indent: Int = 0) {
            guard let v, !v.isEmpty else { return }
            y.append(String(repeating: " ", count: indent) + "\(k): \(MiniYAML.quote(v))")
        }
        func num(_ k: String, _ v: Int?, _ indent: Int = 0) { if let v { y.append(String(repeating: " ", count: indent) + "\(k): \(v)") } }
        func list(_ k: String, _ v: [String], _ indent: Int) {
            guard !v.isEmpty else { return }
            let pad = String(repeating: " ", count: indent)
            y.append(pad + "\(k):")
            for s in v { y.append(pad + "  - " + MiniYAML.quote(s)) }
        }
        add("title", it.title)
        add("title_id", it.titleID)
        add("console", it.console)
        add("version", it.version)
        if let u = it.newestUpdate { num("update_version", Int(clamping: u)) }
        add("publisher", it.publisher ?? it.store?.publisher)
        add("game_files", it.gameFiles ?? it.record?.gameFiles)
        add("game_folder", it.gameFolder)
        add("app", it.app)
        if let r = it.record {
            y.append("build:")
            add("built_at", r.builtAt, 2)
            add("nxforge", r.engine.short, 2)
            add("engine_commit", String(r.engine.commit.prefix(12)), 2)
            add("engine", r.engine.label, 2)
            add("shaders", r.shaders, 2)
            num("seconds", r.seconds, 2)
        }
        if it.preset != nil || !it.changed.isEmpty || it.played > 0 {
            y.append("play:")
            add("preset", it.preset, 2)
            if !it.changed.isEmpty {
                y.append("  settings:")
                for (k, v) in it.changed { y.append("    \(MiniYAML.quote(k)): \(MiniYAML.quote(v))") }
            }
            if it.played > 0 { num("played_minutes", Int((it.played / 60).rounded()), 2) }
            if let d = it.lastPlayed { add("last_played", ISO8601DateFormatter().string(from: d), 2) }
        }
        if let s = it.store {
            y.append("store:")
            add("title", s.title, 2)
            add("page", s.page, 2)
            add("publisher", s.publisher, 2)
            add("released", s.released, 2)
            list("genres", s.genres, 2)
            num("players_from", s.playersFrom, 2)
            num("players_to", s.playersTo, 2)
            add("rating", s.rating, 2)
            add("size", s.size, 2)
            add("languages", s.languages, 2)
            list("modes", s.modes, 2)
            add("excerpt", s.excerpt, 2)
            list("about", s.about, 2)
        }
        let order = ["cover-front", "cover-back", "cover-spine", "wide-art", "icon", "manual"]
        if files.keys.contains(where: order.contains) || it.manual != nil || files.keys.contains(where: { $0.hasPrefix("screenshots/") }) {
            y.append("media:")
            for k in order { add(k.replacingOccurrences(of: "-", with: "_"), files[k], 2) }
            if files["manual"] == nil, let m = it.manual { add("manual", m.path, 2) }
            let shots = (it.store?.shots ?? []).enumerated().compactMap { i, u -> (String, String)? in
                files[String(format: "screenshots/%02d", i + 1)].map { ($0, u) }
            }
            if !shots.isEmpty {
                y.append("  screenshots:")
                for (f, u) in shots { y.append("    - file: \(MiniYAML.quote(f))"); y.append("      source: \(MiniYAML.quote(u))") }
            }
        }
        let trailers = it.store?.trailers ?? []
        if !trailers.isEmpty {
            y.append("trailers:")
            for (i, t) in trailers.enumerated() {
                var first = true
                func item(_ k: String, _ v: String?) {
                    guard let v, !v.isEmpty else { return }
                    y.append((first ? "  - " : "    ") + "\(k): \(MiniYAML.quote(v))")
                    first = false
                }
                item("url", t.watchURL?.absoluteString)
                item("title", t.title)
                item("youtube", t.youtube)
                item("file", t.file)
                item("thumbnail", files[String(format: "trailers/%02d", i + 1)])
                item("thumbnail_source", t.thumb)
            }
        }
        y.append("---")

        // the same for people
        var m: [String] = ["", "# \(it.title)", ""]
        if let f = files["cover-front"] { m += ["![Front cover](\(link(f)))", ""] }
        var facts: [(String, String)] = []
        if let t = it.titleID { facts.append(("Title ID", "`\(t)`")) }
        facts.append(("Console", it.console))
        if let v = it.version { facts.append(("Version", v)) }
        if let p = it.publisher ?? it.store?.publisher { facts.append(("Publisher", p)) }
        if let s = it.store {
            if let r = s.released { facts.append(("Released", r)) }
            if !s.genres.isEmpty { facts.append(("Genres", s.genres.joined(separator: ", "))) }
            if let p = s.players { facts.append(("Players", p)) }
            if let r = s.rating { facts.append(("Age rating", r)) }
            if let z = s.size { facts.append(("Size", z)) }
            if let l = s.languages { facts.append(("Languages", l)) }
            if !s.modes.isEmpty { facts.append(("Play modes", s.modes.joined(separator: ", "))) }
        }
        if let g = it.gameFiles ?? it.record?.gameFiles { facts.append(("Game files", g)) }
        m += ["| | |", "|---|---|"] + facts.map { "| \($0.0) | \($0.1.replacingOccurrences(of: "|", with: "\\|")) |" } + [""]
        if let s = it.store, !s.about.isEmpty || s.excerpt != nil {
            m += ["## About", ""]
            // the store's "•" lines as a Markdown list
            for p in (s.about.isEmpty ? [s.excerpt ?? ""] : s.about) {
                m += [p.split(separator: "\n").map { $0.hasPrefix("• ") ? "- " + $0.dropFirst(2) : String($0) }.joined(separator: "\n"), ""]
            }
            if let p = s.page { m += ["[Store page](\(p))", ""] }
        }
        let shots = files.keys.filter { $0.hasPrefix("screenshots/") }.sorted()
        if !shots.isEmpty {
            m += ["## Screenshots", ""]
            m += shots.map { "![](\(link(files[$0]!)))" } + [""]
        }
        if let w = files["wide-art"] { m += ["## Wide art", "", "![Wide art](\(link(w)))", ""] }
        if !trailers.isEmpty {
            m += ["## Trailers", ""]
            for (i, t) in trailers.enumerated() {
                guard let u = t.watchURL else { continue }
                m.append("- [\(t.title ?? "Trailer \(i + 1)")](\(u.absoluteString))")
            }
            m.append("")
        }
        if let r = it.record {
            m += ["## Build", "", "- App: \(it.app.lastComponent)", "- Built: \(r.builtAt) with NXForge \(r.engine.short)"]
            if let s = r.shaders { m.append("- Shaders: \(s)") }
            if let s = r.seconds { m.append("- Took: \(s / 60) min \(s % 60) s") }
            m.append("")
        }
        if it.preset != nil || !it.changed.isEmpty || it.played > 0 {
            m += ["## Play", ""]
            if let p = it.preset { m.append("- Preset: \(p)") }
            for (k, v) in it.changed { m.append("- \(k): \(v)") }
            if it.played > 0 { m.append("- Played: \(Playtime.text(it.played))") }
            m.append("")
        }
        if let f = files["manual"] { m += ["[Manual](\(link(f)))", ""] }
        return (y + m).joined(separator: "\n")
    }

    /// A relative link that survives spaces
    static func link(_ f: String) -> String { f.contains(" ") ? "<\(f)>" : f }

    /// The details game.md holds, read back as the store's details (for a Mac that has not looked the game up)
    static func storeInfo(_ doc: [String: Any]) -> StoreInfo? {
        guard let s = doc["store"] as? [String: Any], let title = s["title"] as? String else { return nil }
        var i = StoreInfo(title: title)
        func str(_ k: String) -> String? { s[k] as? String }
        func strs(_ k: String) -> [String] { (s[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
        i.page = str("page"); i.publisher = str("publisher"); i.released = str("released"); i.genres = strs("genres")
        i.playersFrom = s["players_from"] as? Int; i.playersTo = s["players_to"] as? Int
        i.rating = str("rating"); i.size = str("size"); i.languages = str("languages"); i.modes = strs("modes")
        i.excerpt = str("excerpt"); i.about = strs("about")
        i.shots = ((doc["media"] as? [String: Any])?["screenshots"] as? [Any])?.compactMap { ($0 as? [String: Any])?["source"] as? String } ?? []
        i.trailers = ((doc["trailers"] as? [Any]) ?? []).compactMap { x -> StoreVideo? in
            guard let t = x as? [String: Any] else { return nil }
            let v = StoreVideo(youtube: t["youtube"] as? String, file: t["file"] as? String, thumb: t["thumbnail_source"] as? String, title: t["title"] as? String)
            return v.youtube == nil && v.file == nil ? nil : v
        }
        return i
    }

    // MARK: files

    /// Copy what changed into media/, drop the pictures that went (a cover back to the downloaded one, a screenshot fewer), and
    /// rewrite game.md when it reads differently. Returns false when the folder could not be written (a read-only drive).
    @discardableResult
    static func write(_ it: Item) -> Bool {
        let fm = FileManager.default
        let dest = it.dest
        let pics = pictures(key: it.key, cache: CoverStore.dir, store: it.store, icon: it.icon) { fm.fileExists(atPath: $0.path) }
        guard !pics.isEmpty || it.store != nil || it.record != nil else { return true }
        do { try fm.createDirectory(at: dest, withIntermediateDirectories: true) } catch { return false }
        var files: [String: String] = [:], keep = Set<String>()
        var all = pics.map { ($0.name, $0.source) }
        if it.manualAdded, let m = it.manual { all.append(("manual", m)) }
        for (name, src) in all {
            let ext = src.pathExtension.lowercased().isEmpty ? "jpg" : src.pathExtension.lowercased()
            let rel = name + "." + ext
            let out = dest.appending(path: rel)
            if needsCopy(src, out) {
                try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                let tmp = out.deletingLastPathComponent().appending(path: ".\(out.lastPathComponent).part")
                try? fm.removeItem(at: tmp)
                guard (try? fm.copyItem(at: src, to: tmp)) != nil else { continue }
                if fm.fileExists(atPath: out.path) { _ = try? fm.replaceItemAt(out, withItemAt: tmp) } else { try? fm.moveItem(at: tmp, to: out) }
            }
            files[name] = rel
            keep.insert(rel)
        }
        // the pictures NXForge wrote before that have no source now; anything else in the folder is left alone
        for sub in ["", "screenshots/", "trailers/"] {
            let dir = dest.appending(path: sub)
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where ours(sub + f) && !keep.contains(sub + f) {
                try? fm.removeItem(at: dir.appending(path: f))
            }
        }
        for sub in ["screenshots", "trailers"] {
            let dir = dest.appending(path: sub)
            if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? fm.removeItem(at: dir) }
        }
        let text = document(it, files: files)
        let doc = dest.appending(path: fileName)
        if (try? String(contentsOf: doc, encoding: .utf8)) != text {
            do { try Data(text.utf8).write(to: doc, options: .atomic) } catch { return false }
        }
        return true
    }

    /// A file NXForge writes in media/ (by its name), so one gone from the artwork folder is removed here too
    static func ours(_ rel: String) -> Bool {
        let base = (rel as NSString).deletingPathExtension, ext = (rel as NSString).pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "pdf", "heic", "tif", "tiff", "gif", "webp"].contains(ext) else { return false }
        if ["cover-front", "cover-back", "cover-spine", "wide-art", "icon", "manual"].contains(base) { return true }
        return base.range(of: #"^(screenshots|trailers)/\d\d$"#, options: .regularExpression) != nil
    }

    static func needsCopy(_ src: URL, _ out: URL) -> Bool {
        let fm = FileManager.default
        guard let a = try? fm.attributesOfItem(atPath: src.path) else { return false }
        guard let b = try? fm.attributesOfItem(atPath: out.path) else { return true }
        if (a[.size] as? Int64) != (b[.size] as? Int64) { return true }
        let ma = a[.modificationDate] as? Date ?? .distantPast, mb = b[.modificationDate] as? Date ?? .distantPast
        return ma > mb
    }

    /// When this Mac has no artwork and no store details for a game but its folder does: take them back (covers, wide art, store
    /// details, screenshots, trailer pictures, an added manual). Returns whether anything came back.
    static func restore(key: String, from dest: URL) -> Bool {
        let fm = FileManager.default
        let cache = CoverStore.dir, store = StoreInfoStore.dir
        let had = ((try? fm.contentsOfDirectory(atPath: cache.path)) ?? []).contains { $0.hasPrefix(key + "-") }
            || fm.fileExists(atPath: StoreInfoStore.file(key).path)
        guard !had, let text = try? String(contentsOf: dest.appending(path: fileName), encoding: .utf8), let doc = MiniYAML.frontMatter(text) else { return false }
        try? fm.createDirectory(at: store, withIntermediateDirectories: true)
        var any = false
        func take(_ rel: String?, _ to: URL) {
            guard let rel, !rel.hasPrefix("/"), !rel.contains(".."), !fm.fileExists(atPath: to.path) else { return }
            let src = dest.appending(path: rel)
            guard fm.fileExists(atPath: src.path) else { return }
            if (try? fm.copyItem(at: src, to: to)) != nil { any = true }
        }
        let media = doc["media"] as? [String: Any] ?? [:]
        for side in CoverSide.allCases {
            guard let rel = media["cover_" + side.rawValue] as? String else { continue }
            // an own cover is kept as PNG, a downloaded one as JPEG
            take(rel, cache.appending(path: rel.lowercased().hasSuffix(".png") ? "\(key)-\(side.rawValue)-own.png" : "\(key)-\(side.rawValue).jpg"))
        }
        if let rel = media["wide_art"] as? String, rel.lowercased().hasSuffix(".jpg") { take(rel, cache.appending(path: "\(key)-hero.jpg")) }
        if let rel = media["manual"] as? String { try? fm.createDirectory(at: GameManual.dir, withIntermediateDirectories: true); take(rel, GameManual.added(key)) }
        if let info = storeInfo(doc), let d = try? JSONEncoder().encode(info) {
            if (try? d.write(to: StoreInfoStore.file(key))) != nil { any = true }
            let shots = (media["screenshots"] as? [Any])?.compactMap { ($0 as? [String: Any])?["file"] as? String } ?? []
            for (i, f) in shots.enumerated() { take(f, StoreInfoStore.shot(key, i)) }
            for (i, t) in ((doc["trailers"] as? [Any]) ?? []).enumerated() { take((t as? [String: Any])?["thumbnail"] as? String, StoreInfoStore.videoThumb(key, i)) }
        }
        return any
    }
}

/// The YAML game.md is written in, and enough of a reader for it: block maps and lists, strings in double quotes (JSON escapes,
/// which YAML reads the same), whole numbers and true/false.
enum MiniYAML {
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if u.value < 0x20 || u.value == 0x7F || u.value == 0x2028 || u.value == 0x2029 || u.value == 0xFEFF { out += String(format: "\\u%04X", u.value) }
                else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    static func scalar(_ raw: String) -> Any {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") {
            if let d = t.data(using: .utf8), let s = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String { return s }
            return String(t.dropFirst().dropLast())
        }
        if t == "true" { return true }
        if t == "false" { return false }
        if let i = Int(t) { return i }
        return t
    }

    /// The front matter of a Markdown file, between its first two "---" lines
    static func frontMatter(_ text: String) -> [String: Any]? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
        return parse(Array(lines[1..<end]))
    }

    static func parse(_ raw: [String]) -> [String: Any]? {
        var lines: [(indent: Int, text: String)] = raw.compactMap { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            return (l.prefix { $0 == " " }.count, t)
        }
        var i = 0
        return block(&lines, &i, lines.first?.indent ?? 0) as? [String: Any]
    }

    /// "key: value" or "\"a key\": value" → (key, value text, possibly empty); nil for a line that is not a key
    static func keyValue(_ t: String) -> (String, String)? {
        if t.hasPrefix("\"") {
            var esc = false, end: String.Index?
            var i = t.index(after: t.startIndex)
            while i < t.endIndex {
                let c = t[i]
                if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { end = i; break }
                i = t.index(after: i)
            }
            guard let end else { return nil }
            let after = t[t.index(after: end)...]
            guard after.hasPrefix(":"), after.count == 1 || after.dropFirst().hasPrefix(" ") else { return nil }
            return ((scalar(String(t[...end])) as? String) ?? "", String(after.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        guard let c = t.range(of: ":"), t[..<c.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
              !t[..<c.lowerBound].isEmpty, c.upperBound == t.endIndex || t[c.upperBound] == " " else { return nil }
        return (String(t[..<c.lowerBound]), String(t[c.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private static func block(_ lines: inout [(indent: Int, text: String)], _ i: inout Int, _ indent: Int) -> Any {
        if i < lines.count, lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
            var out: [Any] = []
            while i < lines.count, lines[i].indent == indent, lines[i].text.hasPrefix("- ") {
                let rest = String(lines[i].text.dropFirst(2))
                if keyValue(rest) != nil {
                    // a map in a list: its first line stands where the dash was
                    lines[i] = (indent + 2, rest)
                    out.append(block(&lines, &i, indent + 2))
                } else {
                    out.append(scalar(rest))
                    i += 1
                }
            }
            return out
        }
        var out: [String: Any] = [:]
        while i < lines.count, lines[i].indent >= indent {
            // a line deeper than its map (not written by NXForge) is passed over
            if lines[i].indent > indent { i += 1; continue }
            if lines[i].text.hasPrefix("- ") { break }
            guard let kv = keyValue(lines[i].text) else { i += 1; continue }
            let (k, v) = kv
            i += 1
            if v.isEmpty {
                if i < lines.count, lines[i].indent > indent || (lines[i].indent == indent && lines[i].text.hasPrefix("- ")) {
                    out[k] = block(&lines, &i, lines[i].indent)
                }
            } else {
                out[k] = scalar(v)
            }
        }
        return out
    }
}

/// Keeps every built game's media folder in step, a moment after the artwork, the store details or the builds change
@MainActor
final class GameFolderMediaSync {
    static let shared = GameFolderMediaSync()
    private var pending: Task<Void, Never>?
    private var restoredAsked = Set<String>()
    /// folders that could not be written (a read-only drive), not tried again until NXForge starts again
    private var failed = Set<String>()

    func schedule(_ model: AppModel, delay: Double = 2) {
        guard model.settings.mediaInGameFolder else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.run(model)
        }
    }

    private func run(_ model: AppModel) {
        let all = model.stageGames()
        // every game's cheats, built or not, into its folder (and back from it), apart from a game that is running
        let cheats = all.compactMap { g in cheatsTarget(g, model: model, games: all) }.filter { !failed.contains($0.folder.path) }
        if !cheats.isEmpty {
            Task.detached(priority: .utility) {
                let bad = cheats.filter { !GameFolderCheats.sync($0.info, folder: $0.folder, engineDir: $0.engineDir) }.map(\.folder.path)
                await MainActor.run { GameFolderMediaSync.shared.failed.formUnion(bad) }
            }
        }
        let games = all.filter { $0.app != nil }
        guard !games.isEmpty else { return }
        let builds = Engine.builds()
        let appParents = games.compactMap { $0.app.map { $0.url.deletingLastPathComponent().path } }
        let store = StoreInfoStore.shared
        var items: [GameFolderMedia.Item] = []
        for g in games {
            guard let app = g.app, FileManager.default.fileExists(atPath: app) else { continue }
            let parent = app.url.deletingLastPathComponent().path
            let dest = GameFolderMedia.folder(app: app, gameFolder: g.game?.folder, appsBeside: appParents.filter { $0 == parent }.count)
            guard !failed.contains(dest.path) else { continue }
            let manual = GameManual.find(g)
            let record = builds.filter { $0.app == app }.max { $0.builtAt < $1.builtAt }
            items.append(GameFolderMedia.Item(key: g.coverKey, title: g.name, titleID: g.titleID, console: g.console.rawValue, app: app,
                                              gameFolder: g.game?.folder, version: g.version, publisher: g.game?.publisher,
                                              gameFiles: g.game?.contents, newestUpdate: g.game?.newestUpdate, record: record,
                                              store: store.info(g.coverKey), manual: manual,
                                              manualAdded: manual == GameManual.added(g.coverKey), icon: g.icon,
                                              played: g.total, lastPlayed: g.last, dest: dest))
        }
        let asked = restoredAsked
        for it in items { restoredAsked.insert(it.key) }
        Task.detached(priority: .utility) {
            var restored: [String] = [], bad: [String] = []
            for var it in items {
                // the folder's media first, for a Mac that has none of this game's yet
                if !asked.contains(it.key), GameFolderMedia.restore(key: it.key, from: it.dest) { restored.append(it.key) }
                let settings = LaunchSettings.load(app: it.app)
                if !settings.isEmpty {
                    let values = Dictionary(settings.map { ($0.env, LaunchSettings.value($0, app: it.app)) }, uniquingKeysWith: { a, _ in a })
                    it.preset = PlayOptions.current(settings: settings, values: values).rawValue
                    it.changed = settings.filter { !$0.isDefault(values[$0.env] ?? $0.def) }.map { ($0.label, PlayOptions.valueText($0, values[$0.env] ?? $0.def)) }
                }
                if restored.contains(it.key) { continue }   // written next time, with the details it brought back
                if !GameFolderMedia.write(it) { bad.append(it.dest.path) }
            }
            let back = restored, failed = bad
            await MainActor.run {
                GameFolderMediaSync.shared.failed.formUnion(failed)
                for k in back { CoverStore.shared.forget(k); GameManual.found[k] = nil }
                if !back.isEmpty { StoreInfoStore.shared.reread(back) }
            }
        }
    }

    struct CheatsTarget: Sendable { var info: GameFolderCheats.Info; var folder: URL; var engineDir: String }

    /// Where a game's cheats go: beside its media folder; for a game not built yet, `cheats/` in its own folder (not one shared
    /// with other games). nil without a title ID, while the game runs, or with the setting off.
    func cheatsTarget(_ g: StageGame, model: AppModel, games: [StageGame]? = nil) -> CheatsTarget? {
        guard model.settings.mediaInGameFolder, let tid = g.titleID else { return nil }
        let folder: URL
        if let app = g.app {
            guard FileManager.default.fileExists(atPath: app), !model.isPlaying(app: app) else { return nil }
            let parent = app.url.deletingLastPathComponent().path
            let n = (games ?? model.stageGames()).filter { $0.app?.url.deletingLastPathComponent().path == parent }.count
            folder = GameFolderCheats.folder(media: GameFolderMedia.folder(app: app, gameFolder: g.game?.folder, appsBeside: n))
        } else if let lg = g.game, !lg.shared, FileManager.default.fileExists(atPath: lg.folder) {
            folder = lg.folder.url.appending(path: GameFolderCheats.folderName)
        } else { return nil }
        return CheatsTarget(info: .init(title: g.name, titleID: tid, version: g.version), folder: folder, engineDir: GameExtras.cheatsDir(titleID: tid))
    }

    /// The game's cheats folder, for Show Folder; nil when they are not kept in the game's folder
    func cheatsFolder(titleID: String, model: AppModel) -> URL? {
        guard let g = model.stageGames().first(where: { $0.titleID?.uppercased() == titleID.uppercased() }) else { return nil }
        return cheatsTarget(g, model: model).map(\.folder)
    }

    /// A Cheats card changed or is about to read a game's cheats: bring that game's into step now
    func syncCheats(titleID: String, model: AppModel) async {
        let targets = model.stageGames().filter { $0.titleID?.uppercased() == titleID.uppercased() }.compactMap { cheatsTarget($0, model: model) }
        guard !targets.isEmpty else { return }
        let bad = await Task.detached(priority: .userInitiated) {
            targets.filter { !GameFolderCheats.sync($0.info, folder: $0.folder, engineDir: $0.engineDir) }.map(\.folder.path)
        }.value
        failed.formUnion(bad)
    }

    /// A built game's media folder
    func folder(_ g: StageGame, model: AppModel) -> URL? {
        guard let app = g.app else { return nil }
        let parent = app.url.deletingLastPathComponent().path
        let n = model.stageGames().filter { $0.app?.url.deletingLastPathComponent().path == parent }.count
        return GameFolderMedia.folder(app: app, gameFolder: g.game?.folder, appsBeside: n)
    }

    /// Game menu › Show Media Folder: written now if it is not there yet
    func show(_ g: StageGame, model: AppModel) {
        guard let dest = folder(g, model: model) else { return }
        if FileManager.default.fileExists(atPath: dest.appending(path: GameFolderMedia.fileName).path) {
            NSWorkspace.shared.activateFileViewerSelecting([dest.appending(path: GameFolderMedia.fileName)])
            return
        }
        schedule(model, delay: 0)
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(250))
                if FileManager.default.fileExists(atPath: dest.appending(path: GameFolderMedia.fileName).path) { break }
            }
            NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: dest.path) ? dest.appending(path: GameFolderMedia.fileName) : g.app!.url])
        }
    }

    /// The player went back to the downloaded covers: their own pictures leave the game's folder too
    func ownCoversRemoved(_ g: StageGame, model: AppModel) {
        guard let dest = folder(g, model: model) else { return }
        for side in CoverSide.allCases { try? FileManager.default.removeItem(at: dest.appending(path: "cover-\(side.rawValue).png")) }
        schedule(model, delay: 0.5)
    }
}
