// Cheats and mods from the app (0.12.0). The engine already runs both: Atmosphère cheat files matched to the game's build
// (dm/host/hle_cheats.c: <build ID>.txt and its switches in <build ID>.enabled, in ~/Library/Application Support/nxnative/<title ID>/cheats)
// and RomFS mods (front_mac_quick_settings.inc: each folder of .../<title ID>/mods, the enabled ones overlaid at launch in the saved
// order). This file is the app's side with no views: where those folders are, a build's ID, reading and merging cheat files, the public
// cheat collections a game's codes are fetched from, installing a mod from a folder or an archive, which mods are on and in what order
// (the game's own settings file and preferences, as the sidebar keeps them), and the files two mods both replace.
import CryptoKit
import Foundation

enum GameExtras {
    static func support(titleID: String, home: String = NSHomeDirectory()) -> String { "\(home)/Library/Application Support/nxnative/\(titleID)" }
    static func cheatsDir(titleID: String, home: String = NSHomeDirectory()) -> String { support(titleID: titleID, home: home) + "/cheats" }
    static func modsDir(titleID: String, home: String = NSHomeDirectory()) -> String { support(titleID: titleID, home: home) + "/mods" }

    /// A value the packer's tables of the built app carry as "# KEY<tab>value" (Contents/Resources/dm/main.*.tsv)
    static func tableValue(app: String, file: String, key: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: app + "/Contents/Resources/dm/" + file) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4096), let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("# " + key + "\t") {
            return line.dropFirst(key.count + 3).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The main module's build ID as cheat files are named: its first 16 hex digits, upper case. nil for an app with no tables.
    static func buildID(app: String) -> String? {
        for f in ["main.cuts.tsv", "main.fixups.tsv", "main.obs.tsv"] {
            if let v = tableValue(app: app, file: f, key: "BUILD_ID"), v.count >= 16, v.allSatisfy(\.isHexDigit) { return String(v.prefix(16)).uppercased() }
        }
        return nil
    }

    /// Where the main module's code ends (a cheat that writes below it changes instructions); nil when the app does not say.
    static func textEnd(app: String) -> UInt64? {
        guard let v = tableValue(app: app, file: "main.fixups.tsv", key: "TEXT_END") else { return nil }
        return UInt64(v.hasPrefix("0x") ? String(v.dropFirst(2)) : v, radix: 16)
    }
}

// MARK: - Cheat files

/// One cheat of an Atmosphère cheat file: "[Name]" (or "{Name}", a master code, always on) and its code lines.
struct CheatEntry: Hashable, Identifiable {
    var name: String
    var master = false
    var lines: [String] = []
    /// where a fetched cheat came from ("" for the file's own)
    var source = ""
    var id: String { (master ? "{" : "[") + name + "|" + code }
    /// the code with its spacing and case evened out, to tell two copies of one cheat apart from two cheats of one name
    var code: String { lines.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased() }.filter { !$0.isEmpty }.joined(separator: "\n") }
    var text: String { (master ? "{\(name)}" : "[\(name)]") + "\n" + lines.joined(separator: "\n") + "\n" }

    /// Whether a code line stores to a fixed place in the game's own module below `textEnd`: an instruction patch.
    /// (Opcode 0, "0TMR00AA AAAAAAAA value": M 0 is the main module. Other opcodes write through registers or to the heap.)
    func patchesCode(textEnd: UInt64?) -> Bool {
        for l in lines {
            let w = l.split(whereSeparator: \.isWhitespace)
            guard w.count >= 3, w[0].count == 8, w[1].count == 8, w[0].first == "0" else { continue }
            let c = Array(w[0])
            guard c[2] == "0", let hi = UInt64(String(c[6...7]), radix: 16), let lo = UInt64(w[1], radix: 16) else { continue }
            let addr = hi << 32 | lo
            if let textEnd { if addr < textEnd { return true } } else if c[1] == "4" { return true }
        }
        return false
    }
}

enum CheatFile {
    /// Read a cheat file's text. Lines before the first heading are kept as a nameless master (Atmosphère runs them always).
    static func parse(_ text: String, source: String = "") -> [CheatEntry] {
        var out: [CheatEntry] = []
        var cur: CheatEntry?
        func close() { if let c = cur, !(c.name.isEmpty && c.code.isEmpty) { out.append(c) }; cur = nil }
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("["), let e = l.lastIndex(of: "]"), e > l.startIndex {
                close(); cur = CheatEntry(name: String(l[l.index(after: l.startIndex)..<e]).trimmingCharacters(in: .whitespaces), source: source)
            } else if l.hasPrefix("{"), let e = l.lastIndex(of: "}"), e > l.startIndex {
                close(); cur = CheatEntry(name: String(l[l.index(after: l.startIndex)..<e]).trimmingCharacters(in: .whitespaces), master: true, source: source)
            } else if !l.isEmpty {
                if cur == nil { cur = CheatEntry(name: "", master: true, source: source) }
                cur?.lines.append(l)
            }
        }
        close()
        return out
    }

    static func text(_ entries: [CheatEntry]) -> String {
        entries.map { $0.name.isEmpty ? $0.lines.joined(separator: "\n") + "\n" : $0.text }.joined(separator: "\n")
    }

    /// The cheats of `new` the file does not hold yet (by code, so a cheat under another name is not added twice), named so that
    /// none shares a name with a different cheat already there ("Name (2)").
    static func additions(to old: [CheatEntry], from new: [CheatEntry]) -> [CheatEntry] {
        var codes = Set(old.map(\.code)), names = Set(old.map { $0.name.lowercased() })
        var add: [CheatEntry] = []
        for var e in new where !e.code.isEmpty && !codes.contains(e.code) {
            if e.name.isEmpty { continue }   // a collection's loose lines are not ours to run always
            var n = e.name, i = 2
            while names.contains(n.lowercased()) { n = "\(e.name) (\(i))"; i += 1 }
            e.name = n
            codes.insert(e.code); names.insert(n.lowercased()); add.append(e)
        }
        return add
    }

    /// The key the engine keeps a cheat's switch under: its name, "Name #2" for the second entry of that name (hle_cheats.c cheat_key).
    static func keys(_ entries: [CheatEntry]) -> [String] {
        var seen: [String: Int] = [:]
        return entries.map { e in
            let n = seen[e.name, default: 0]; seen[e.name] = n + 1
            return n == 0 ? e.name : "\(e.name) #\(n + 1)"
        }
    }

    static func path(dir: String, build: String) -> String { "\(dir)/\(build).txt" }
    static func enabledPath(dir: String, build: String) -> String { "\(dir)/\(build).enabled" }

    static func load(dir: String, build: String) -> [CheatEntry] {
        (try? String(contentsOfFile: path(dir: dir, build: build), encoding: .utf8)).map { parse($0) } ?? []
    }

    static func enabled(dir: String, build: String) -> Set<String> {
        let t = (try? String(contentsOfFile: enabledPath(dir: dir, build: build), encoding: .utf8)) ?? ""
        return Set(t.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }

    static func setEnabled(_ keys: Set<String>, order: [String], dir: String, build: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = order.filter(keys.contains).map { $0 + "\n" }.joined()
        try text.write(toFile: enabledPath(dir: dir, build: build), atomically: true, encoding: .utf8)
    }

    /// Add cheats to the build's file (made if it is not there); the file as it was is kept beside it once ("<build>.txt.before-download").
    @discardableResult
    static func add(_ new: [CheatEntry], dir: String, build: String) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = path(dir: dir, build: build)
        let old = load(dir: dir, build: build)
        let add = additions(to: old, from: new)
        guard !add.isEmpty else { return 0 }
        if fm.fileExists(atPath: p), !fm.fileExists(atPath: p + ".before-download") { try? fm.copyItem(atPath: p, toPath: p + ".before-download") }
        let existing = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        let sep = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"
        try (existing + sep + text(add)).write(toFile: p, atomically: true, encoding: .utf8)
        return add.count
    }
}

/// The public collections a game's cheats are fetched from, by title ID and build ID. Nothing of them ships with NXForge: a file is
/// downloaded when the player asks, and the codes they pick are written into their own cheats folder.
enum CheatSources {
    struct Source { let name, page: String }
    static let general = Source(name: "switch-cheats-db", page: "https://github.com/HamletDuFromage/switch-cheats-db")
    static let graphics = Source(name: "NX-60FPS-RES-GFX-Cheats", page: "https://github.com/ChanseyIsTheBest/NX-60FPS-RES-GFX-Cheats")

    static func generalURL(titleID: String) -> URL { URL(string: "https://raw.githubusercontent.com/HamletDuFromage/switch-cheats-db/master/cheats/\(titleID.uppercased()).json")! }
    static func graphicsURL(titleID: String, build: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/ChanseyIsTheBest/NX-60FPS-RES-GFX-Cheats/main/titles/\(titleID.uppercased())/cheats/\(build.uppercased()).txt")!
    }

    /// switch-cheats-db's file for a title: {"<build ID>": {"[Name]": "[Name]\ncode\n", …}, …, "attribution": {…}}
    static func parseGeneral(_ data: Data, build: String) -> (cheats: [CheatEntry], otherBuilds: [String]) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        var cheats: [CheatEntry] = []
        var others: [String] = []
        for (k, v) in o where k.count == 16 && k.allSatisfy(\.isHexDigit) {
            guard k.uppercased() == build.uppercased() else { others.append(k.uppercased()); continue }
            guard let d = v as? [String: Any] else { continue }
            for name in d.keys.sorted() { if let t = d[name] as? String { cheats += CheatFile.parse(t, source: general.name) } }
        }
        return (cheats, others.sorted())
    }

    struct Found {
        var cheats: [CheatEntry] = []
        /// builds of this game the general collection has codes for, when it has none for this one
        var otherBuilds: [String] = []
        var failed: [String] = []
    }

    static func get(_ url: URL) async -> (data: Data?, status: Int) {
        var req = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        req.setValue("NXForge", forHTTPHeaderField: "User-Agent")
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return (nil, 0) }
        let s = (r as? HTTPURLResponse)?.statusCode ?? 0
        return (s == 200 ? d : nil, s)
    }

    static func fetch(titleID: String, build: String) async -> Found {
        async let a = get(generalURL(titleID: titleID))
        async let b = get(graphicsURL(titleID: titleID, build: build))
        let (ga, gb) = await (a, b)
        var f = Found()
        if let d = ga.data { let p = parseGeneral(d, build: build); f.cheats += p.cheats; if p.cheats.isEmpty { f.otherBuilds = p.otherBuilds } }
        else if ga.status != 404 { f.failed.append(general.name) }
        if let d = gb.data, let t = String(data: d, encoding: .utf8) { f.cheats += CheatFile.parse(t, source: graphics.name) }
        else if gb.status != 404 { f.failed.append(graphics.name) }
        // one cheat offered by both collections is listed once
        var seen = Set<String>()
        f.cheats = f.cheats.filter { !$0.name.isEmpty && !$0.code.isEmpty && seen.insert($0.code).inserted }
        return f
    }
}

// MARK: - Mods

struct ModInfo: Identifiable, Hashable {
    var name: String
    /// the game files it replaces, as paths inside the game's RomFS
    var files: [String] = []
    var bytes: Int64 = 0
    /// it carries code patches (an exefs folder), which the engine does not load
    var hasCode = false
    var id: String { name }
}

enum ModError: LocalizedError {
    case otherGame(String), empty, unpack(String), exists(String)
    var errorDescription: String? {
        switch self {
        case .otherGame(let t): "This mod is for another game (title ID \(t))."
        case .empty: "No game files were found in it."
        case .unpack(let m): "The archive could not be opened. \(m)"
        case .exists(let n): "A mod named “\(n)” is already installed."
        }
    }
}

enum Mods {
    /// The folder of a mod that holds its RomFS files, as the engine looks for it (front_mac_quick_settings.inc mod_root)
    static func root(_ mod: String, titleID: String) -> String {
        for sub in ["romfs", "atmosphere/contents/\(titleID)/romfs", "contents/\(titleID)/romfs", "\(titleID)/romfs"] {
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: mod + "/" + sub, isDirectory: &dir), dir.boolValue { return mod + "/" + sub }
        }
        return mod
    }

    static func names(dir: String) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { n in
            var d: ObjCBool = false
            return !n.hasPrefix(".") && fm.fileExists(atPath: dir + "/" + n, isDirectory: &d) && d.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The mods in load order: the saved order first, then the rest by name (the engine's mods_list)
    static func ordered(_ found: [String], saved: [String]) -> [String] {
        var o: [String] = []
        for n in saved where found.contains(n) && !o.contains(n) { o.append(n) }
        return o + found.filter { !o.contains($0) }
    }

    static func info(dir: String, name: String, titleID: String) -> ModInfo {
        let mod = dir + "/" + name, r = root(mod, titleID: titleID), fm = FileManager.default
        var m = ModInfo(name: name)
        let rurl = URL(fileURLWithPath: r).standardizedFileURL
        if let e = fm.enumerator(at: rurl, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in e {
                guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
                let rel = String(u.standardizedFileURL.path.dropFirst(rurl.path.count + 1))
                if r == mod, rel.hasPrefix("exefs/") || rel == "NXForge mod.txt" { continue }
                m.files.append(rel); m.bytes += Int64(v.fileSize ?? 0)
            }
        }
        m.files.sort()
        for sub in ["exefs", "atmosphere/contents/\(titleID)/exefs", "contents/\(titleID)/exefs", "\(titleID)/exefs", "atmosphere/exefs_patches", "exefs_patches"] where fm.fileExists(atPath: mod + "/" + sub) { m.hasCode = true }
        return m
    }

    /// Files more than one of `mods` (in load order) replace: the first mod holding a file wins, as the engine overlays them.
    static func clashes(_ mods: [ModInfo]) -> [(file: String, winner: String, losers: [String])] {
        var owner: [String: [String]] = [:]
        for m in mods { for f in m.files { owner[f.lowercased(), default: []].append(m.name) } }
        return owner.filter { $0.value.count > 1 }.map { ($0.key, $0.value[0], Array($0.value.dropFirst())) }.sorted { $0.0 < $1.0 }
    }

    /// A name a mod folder can have: no path or list separators (the overlay list splits on ':', the settings file on '|')
    static func safeName(_ s: String) -> String {
        var n = s.map { "/:|\\\n\r\t".contains($0) ? "-" : $0 }.reduce(into: "") { $0.append($1) }.trimmingCharacters(in: .whitespaces)
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "Mod" : String(n.prefix(80))
    }

    static let archiveTypes: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz", "xz", "bz2"]

    /// Where the game files of an unpacked download are. `top` is a folder holding what was unpacked or dropped. A mod comes as
    /// romfs/…, atmosphere/contents/<title ID>/romfs/…, <title ID>/romfs/…, any of them inside more folders, or as bare game files
    /// (then `top` is the mod, or the one folder in it when that folder is named as the download, `wrapper`). Returns the folder
    /// to install as the mod (one the engine's mod_root reads).
    static func locate(in top: String, titleID: String, wrapper: String? = nil) throws -> String {
        let fm = FileManager.default
        func entries(_ p: String) -> (dirs: [String], files: [String]) {
            var d: [String] = [], f: [String] = []
            for n in ((try? fm.contentsOfDirectory(atPath: p)) ?? []).sorted() where !n.hasPrefix(".") && n != "__MACOSX" {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: p + "/" + n, isDirectory: &isDir), isDir.boolValue { d.append(n) } else { f.append(n) }
            }
            return (d, f)
        }
        func isTitle(_ n: String) -> Bool { n.count == 16 && n.allSatisfy(\.isHexDigit) }
        // a folder named romfs, or a title ID's folder, up to four folders down says where the game files are
        var level = [top]
        for _ in 0..<5 {
            var next: [String] = []
            for here in level {
                let d = entries(here).dirs
                if d.contains(where: { $0.lowercased() == "romfs" }) { return here }
                for c in ["atmosphere/contents", "contents", "atmosphere/titles", "titles", "."] {
                    let base = c == "." ? here : here + "/" + c
                    let ids = entries(base).dirs.filter(isTitle)
                    if ids.isEmpty { continue }
                    if let mine = ids.first(where: { $0.uppercased() == titleID.uppercased() }) {
                        if fm.fileExists(atPath: base + "/" + mine + "/romfs") { return base + "/" + mine }
                        throw ModError.empty   // only code patches for this game
                    }
                    throw ModError.otherGame(ids[0].uppercased())
                }
                next += d.map { here + "/" + $0 }
            }
            level = Array(next.prefix(400))
            if level.isEmpty { break }
        }
        // bare game files
        let e = entries(top)
        if e.dirs.isEmpty && e.files.isEmpty { throw ModError.empty }
        let notes = e.files.allSatisfy { ["txt", "md", "png", "jpg", "jpeg", "url", "html", "pdf"].contains(($0 as NSString).pathExtension.lowercased()) }
        if e.dirs.count == 1, notes, let wrapper, e.dirs[0].lowercased() == wrapper.lowercased() { return top + "/" + e.dirs[0] }
        return top
    }

    /// Unpack an archive into a new folder (bsdtar reads zip, 7z, rar and tar).
    static func unpack(_ archive: String, to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        p.arguments = ["-x", "-f", archive, "-C", dir]
        let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { throw ModError.unpack(error.localizedDescription) }
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw ModError.unpack(String(data: e, encoding: .utf8)?.split(separator: "\n").last.map(String.init) ?? "") }
    }

    /// Install a mod from a folder or an archive into the game's mods folder; returns the mod's name. `note` is kept in the mod
    /// ("NXForge mod.txt": where it came from).
    @discardableResult
    static func install(from src: String, titleID: String, name: String? = nil, note: String? = nil, modsDir: String? = nil) throws -> String {
        let fm = FileManager.default
        let dir = modsDir ?? GameExtras.modsDir(titleID: titleID)
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src, isDirectory: &isDir) else { throw ModError.empty }
        let base = safeName(name ?? ((src as NSString).lastPathComponent as NSString).deletingPathExtension)
        let temp = dir + "/.installing-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: temp) }
        let from: String
        if isDir.boolValue { from = try locate(in: src, titleID: titleID) }
        else {
            guard archiveTypes.contains((src as NSString).pathExtension.lowercased()) else { throw ModError.unpack("Not a folder or a zip, 7z or rar archive.") }
            try unpack(src, to: temp)
            from = try locate(in: temp, titleID: titleID, wrapper: ((src as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        var n = base, i = 2
        while fm.fileExists(atPath: dir + "/" + n) { n = "\(base) \(i)"; i += 1 }
        let dest = dir + "/" + n
        if from.hasPrefix(temp + "/") || from == temp { try fm.moveItem(atPath: from, toPath: dest) } else { try fm.copyItem(atPath: from, toPath: dest) }
        if info(dir: dir, name: n, titleID: titleID).files.isEmpty { try? fm.removeItem(atPath: dest); throw ModError.empty }
        if let note { try? note.write(toFile: dest + "/NXForge mod.txt", atomically: true, encoding: .utf8) }
        return n
    }

    static func note(dir: String, name: String) -> String? {
        (try? String(contentsOfFile: "\(dir)/\(name)/NXForge mod.txt", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Which mods are on and their order, where the game reads them: its settings file beside the app ("NXForge settings.txt": the lines
/// mods_on and mod_order, which win at launch) and its preferences (DMQuickSettings.mods.<game> and .modOrder.<game> in the app's own
/// domain), kept in step.
struct ModState {
    var on: [String] = []
    var order: [String] = []

    static func settingsFile(app: String) -> String { ((app as NSString).deletingLastPathComponent as NSString).appendingPathComponent("NXForge settings.txt") }

    static func list(_ s: String) -> [String] { s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    /// A setting's value in a settings file's text; nil when the line is missing or a comment
    static func fileValue(_ text: String, _ key: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "="), l[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key else { continue }
            return l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The file's text with a setting's line replaced (its comment form too), or added at the end
    static func fileSetting(_ text: String, _ key: String, _ value: [String]) -> String {
        let line = value.isEmpty ? "# \(key) =    (folder names, separated by |)" : "\(key) = \(value.joined(separator: " | "))"
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var done = false
        for i in lines.indices {
            var l = lines[i].trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("#") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard let eq = l.firstIndex(of: "="), l[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key else { continue }
            if done { lines[i] = "" } else { lines[i] = line; done = true }
        }
        if !done { if lines.last == "" { lines.removeLast() }; lines.append(line); lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// The name the game's preferences are keyed by: the settings file's first line names it, else a saved key does
    static func gameName(app: String) -> String? {
        if let t = try? String(contentsOfFile: settingsFile(app: app), encoding: .utf8), let first = t.split(whereSeparator: \.isNewline).first,
           first.hasPrefix("# NXForge Sidebar settings for "), let p = first.range(of: " (", options: .backwards) {
            return String(first[first.index(first.startIndex, offsetBy: 31)..<p.lowerBound])
        }
        guard let id = LaunchSettings.bundleID(app: app), let d = UserDefaults.standard.persistentDomain(forName: id) else { return nil }
        for k in d.keys.sorted() where k.hasPrefix("DMQuickSettings.") {
            let rest = k.dropFirst(16)
            if let dot = rest.firstIndex(of: ".") { return String(rest[rest.index(after: dot)...]) }
        }
        return nil
    }

    static func load(app: String) -> ModState {
        if let t = try? String(contentsOfFile: settingsFile(app: app), encoding: .utf8) {
            return ModState(on: fileValue(t, "mods_on").map(list) ?? [], order: fileValue(t, "mod_order").map(list) ?? [])
        }
        guard let name = gameName(app: app), let d = LaunchSettings.defaults(app: app) else { return ModState() }
        return ModState(on: d.stringArray(forKey: "DMQuickSettings.mods.\(name)") ?? [], order: d.stringArray(forKey: "DMQuickSettings.modOrder.\(name)") ?? [])
    }

    func save(app: String) {
        let f = Self.settingsFile(app: app), fm = FileManager.default
        let name = Self.gameName(app: app)
        if let t = try? String(contentsOfFile: f, encoding: .utf8) {
            let n = Self.fileSetting(Self.fileSetting(t, "mods_on", on), "mod_order", order)
            if n != t { try? n.write(toFile: f, atomically: true, encoding: .utf8) }
        } else if name == nil, fm.isWritableFile(atPath: (f as NSString).deletingLastPathComponent) {
            // a game that has not run yet has neither a file nor a name to key its preferences by: a file with these two lines
            // (and my sidebar defaults, which such a game would have started from) is what it reads at its first launch
            let mine = (try? String(contentsOfFile: NSHomeDirectory() + "/Library/Application Support/NXForge/Sidebar defaults.txt", encoding: .utf8)) ?? ""
            let carried = mine.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
            let t = Self.fileSetting(Self.fileSetting(carried.isEmpty ? "" : carried + "\n", "mods_on", on), "mod_order", order)
            try? t.write(toFile: f, atomically: true, encoding: .utf8)
        }
        if let name, let d = LaunchSettings.defaults(app: app) {
            d.set(on, forKey: "DMQuickSettings.mods.\(name)")
            d.set(order, forKey: "DMQuickSettings.modOrder.\(name)")
            d.synchronize()
        }
    }
}

// MARK: - GameBanana

/// GameBanana's public API (apiv11), read when the player opens the mod browser: the game by name, its mods a page at a time, and a
/// mod's files. A download is checked against the MD5 GameBanana lists for it.
enum GameBanana {
    struct Game: Hashable, Identifiable { let id: Int; let name: String }
    struct Mod: Hashable, Identifiable {
        let id: Int
        let name, author, category, version, page: String
        let thumb: URL?
        let updated: Date
        let likes, views: Int
        let obsolete: Bool
    }
    struct File: Hashable, Identifiable {
        let id: Int
        let name: String
        let bytes: Int64
        let url: URL
        let md5: String
        let clean: Bool
    }
    struct Page { var mods: [Mod]; var total: Int; var perPage: Int }

    static let base = "https://gamebanana.com/apiv11"

    static func json(_ url: URL) async -> Any? {
        guard let d = await CheatSources.get(url).data else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    /// A store or cart name as GameBanana would list it: no trademark signs, no edition in brackets
    static func searchName(_ name: String) -> String {
        var n = name.replacingOccurrences(of: "™", with: "").replacingOccurrences(of: "®", with: "")
        while let a = n.firstIndex(of: "["), let b = n[a...].firstIndex(of: "]") { n.removeSubrange(a...b) }
        return n.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func parseGames(_ o: Any?) -> [Game] {
        ((o as? [String: Any])?["_aRecords"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["_idRow"] as? Int, let n = r["_sName"] as? String else { return nil }
            return Game(id: id, name: n)
        }
    }

    static func games(named name: String) async -> [Game] {
        var c = URLComponents(string: base + "/Util/Game/NameMatch")!
        c.queryItems = [URLQueryItem(name: "_sName", value: searchName(name))]
        guard let u = c.url else { return [] }
        return parseGames(await json(u))
    }

    /// The best match of a game's name among GameBanana's: the same name without case and punctuation, else the first
    static func best(_ games: [Game], for name: String) -> Game? {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let k = key(searchName(name))
        return games.first { key($0.name) == k } ?? games.first
    }

    static func parseMods(_ o: Any?) -> Page {
        let d = o as? [String: Any] ?? [:], meta = d["_aMetadata"] as? [String: Any] ?? [:]
        let mods: [Mod] = (d["_aRecords"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["_idRow"] as? Int, let n = r["_sName"] as? String, (r["_sModelName"] as? String ?? "Mod") == "Mod" else { return nil }
            var thumb: URL?
            if let img = ((r["_aPreviewMedia"] as? [String: Any])?["_aImages"] as? [[String: Any]])?.first, let b = img["_sBaseUrl"] as? String,
               let f = (img["_sFile530"] ?? img["_sFile220"] ?? img["_sFile"]) as? String { thumb = URL(string: b + "/" + f) }
            return Mod(id: id, name: n, author: (r["_aSubmitter"] as? [String: Any])?["_sName"] as? String ?? "",
                       category: (r["_aRootCategory"] as? [String: Any])?["_sName"] as? String ?? "", version: r["_sVersion"] as? String ?? "",
                       page: r["_sProfileUrl"] as? String ?? "https://gamebanana.com/mods/\(id)", thumb: thumb,
                       updated: Date(timeIntervalSince1970: TimeInterval(r["_tsDateModified"] as? Int ?? r["_tsDateAdded"] as? Int ?? 0)),
                       likes: r["_nLikeCount"] as? Int ?? 0, views: r["_nViewCount"] as? Int ?? 0, obsolete: r["_bIsObsolete"] as? Bool ?? false)
        }
        return Page(mods: mods, total: meta["_nRecordCount"] as? Int ?? mods.count, perPage: meta["_nPerpage"] as? Int ?? 15)
    }

    static func mods(game: Int, page: Int, search: String = "") async -> Page? {
        var c = URLComponents(string: base + "/Game/\(game)/Subfeed")!
        c.queryItems = [URLQueryItem(name: "_nPage", value: String(page)), URLQueryItem(name: "_sSort", value: "default"), URLQueryItem(name: "_csvModelInclusions", value: "Mod")]
        if search.count >= 3 { c.queryItems?.append(URLQueryItem(name: "_sName", value: search)) }
        guard let u = c.url, let o = await json(u) else { return nil }
        return parseMods(o)
    }

    static func parseFiles(_ o: Any?) -> [File] {
        ((o as? [String: Any])?["_aFiles"] as? [[String: Any]] ?? []).compactMap { f in
            guard let id = f["_idRow"] as? Int, let n = f["_sFile"] as? String, let s = f["_sDownloadUrl"] as? String, let u = URL(string: s), u.scheme == "https" else { return nil }
            let av = f["_sAvResult"] as? String ?? "", an = f["_sAnalysisResult"] as? String ?? ""
            return File(id: id, name: n, bytes: Int64(f["_nFilesize"] as? Int ?? 0), url: u, md5: (f["_sMd5Checksum"] as? String ?? "").lowercased(),
                        clean: (av.isEmpty || av == "clean") && (an.isEmpty || an == "ok"))
        }
    }

    static func files(mod: Int) async -> [File] {
        guard let u = URL(string: base + "/Mod/\(mod)/DownloadPage") else { return [] }
        return parseFiles(await json(u))
    }

    static func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Download a mod's file to a temporary folder under its own name; throws when it does not match GameBanana's checksum
    static func download(_ f: File) async throws -> String {
        var req = URLRequest(url: f.url, timeoutInterval: 120)
        req.setValue("NXForge", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ModError.unpack("GameBanana did not send the file.") }
        if !f.md5.isEmpty, md5(data) != f.md5 { throw ModError.unpack("The download does not match GameBanana's checksum.") }
        let dir = NSTemporaryDirectory() + "nxforge-mod-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = dir + "/" + Mods.safeName(f.name)
        try data.write(to: URL(fileURLWithPath: p))
        return p
    }
}
