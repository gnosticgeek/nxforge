// What Theatre's Wii theme shows of a Wii or GameCube game beyond its box: GameTDB's facts (the title, publisher, year, genres,
// age rating, players, the controllers it takes, its blurb) and libretro's thumbnails (a screenshot and the game's logo).
//
// GameTDB (www.gametdb.com) keeps one database of every Wii and GameCube disc, keyed by the six-character game ID the disc header
// carries: wiitdb.zip is downloaded once a month (10 MB), read here once, and only the English facts are kept, in wiitdb.json beside the
// covers. libretro-thumbnails (github.com/libretro-thumbnails) names its pictures after the disc's No-Intro/Redump name, so its file
// list (one request to GitHub, kept a month) is matched by title, the disc's own region first. Nothing about the Mac or the game is
// sent but the request for the file. Settings › Artwork's Download store details switches GameTDB off, Download wide art the pictures.
import AppKit
import Foundation
import SwiftUI

/// One game's facts from GameTDB, in English
struct WiiTDBEntry: Codable, Hashable {
    var title: String
    var synopsis: String?
    var developer: String?
    var publisher: String?
    var year: Int?
    var genres: [String] = []
    /// "ESRB", "PEGI", "CERO", …
    var board: String?
    /// "E", "E10+", "T", "12", …
    var rating: String?
    var players: Int?
    /// GameTDB's control types: wiimote, nunchuk, classiccontroller, gamecube, motionplus, balanceboard, wheel, zapper, …
    var controls: [String] = []
    var required: [String] = []
}

extension WiiTDBEntry {
    /// "Adventure / Platformer": the first two genres, as GameTDB lists them
    var genreText: String? {
        let g = genres.prefix(2).map { $0.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
        return g.isEmpty ? nil : g.joined(separator: " / ")
    }

    /// "1 player", "1–4 players"
    var playersText: String? {
        guard let p = players, p > 0 else { return nil }
        return p == 1 ? "1 player" : "1–\(p) players"
    }

    /// The controller the game is played with, in two lines for the tray: ("Wii Remote", "+ Nunchuk"), ("Classic Controller", nil), …
    func controller(gamecube: Bool) -> (String, String?) {
        let need = Set(required), can = Set(controls)
        if gamecube || (need.contains("gamecube") && !need.contains("wiimote")) { return ("GameCube", "Controller") }
        if need.contains("classiccontroller") && !need.contains("wiimote") { return ("Classic", "Controller") }
        if need.contains("balanceboard") { return ("Wii Remote", "+ Balance Board") }
        if need.contains("nunchuk") { return ("Wii Remote", "+ Nunchuk") }
        if need.contains("motionplus") { return ("Wii Remote", "+ MotionPlus") }
        if need.contains("wheel") { return ("Wii Remote", "+ Wii Wheel") }
        if need.contains("zapper") { return ("Wii Remote", "+ Wii Zapper") }
        if can.contains("nunchuk") { return ("Wii Remote", "+ Nunchuk") }
        return ("Wii Remote", nil)
    }

    /// Whether the controller line is a Wii Remote with a Nunchuk (the tray shows the pair), else the Remote alone
    var nunchuk: Bool { required.contains("nunchuk") || (controls.contains("nunchuk") && !required.contains("classiccontroller")) }

    /// The blurb, short enough for two lines: whole sentences up to about 150 characters (the first one alone when it is longer)
    var shortSynopsis: String? {
        guard let s = synopsis?.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        var out = ""
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, stop in
            guard let sub = sub?.trimmingCharacters(in: .whitespaces), !sub.isEmpty else { return }
            if out.isEmpty { out = sub } else if out.count + sub.count + 1 <= 150 { out += " " + sub } else { stop = true }
        }
        return out.isEmpty ? s : out
    }

    /// "Everyone", "Teen", "PEGI 12"
    var ratingWords: String? {
        guard let r = rating, !r.isEmpty else { return nil }
        switch (board ?? "").uppercased() {
        case "ESRB":
            return ["EC": "Early Childhood", "E": "Everyone", "E10+": "Everyone 10+", "T": "Teen", "M": "Mature", "AO": "Adults Only"][r] ?? r
        case "": return r
        default: return "\(board!) \(r)"
        }
    }
}

/// GameTDB's facts, read once from the copy kept beside the covers (downloaded again after a month)
@MainActor @Observable
final class WiiTDB {
    static let shared = WiiTDB()
    private(set) var revision = 0
    @ObservationIgnored private var entries: [String: WiiTDBEntry]?
    @ObservationIgnored private var loading = false

    nonisolated static var file: URL { CoverStore.dir.appending(path: "wiitdb.json") }
    nonisolated static let source = URL(string: "https://www.gametdb.com/wiitdb.zip")!

    /// The game's facts, by its six-character game ID; nil until the database is read (it is then read in the background)
    func entry(_ gameID: String?, download: Bool) -> WiiTDBEntry? {
        let _ = revision
        guard let gameID else { return nil }
        if entries == nil { load(download: download) }
        return entries?[gameID.uppercased()]
    }

    func load(download: Bool) {
        guard entries == nil, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            let got = await Self.read(download: download)
            await MainActor.run {
                WiiTDB.shared.loading = false
                guard let got else { return }
                WiiTDB.shared.entries = got
                WiiTDB.shared.revision += 1
            }
        }
    }

    /// The kept copy while it is under a month old (or offline, or downloads are off), else a new one from GameTDB
    nonisolated static func read(download: Bool) async -> [String: WiiTDBEntry]? {
        let fm = FileManager.default
        let kept = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: WiiTDBEntry].self, from: $0) }
        let age = ((try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if let kept, age < 30 * 86400 || !download { return kept }
        guard download, let zip = await CoverStore.get(source), let fresh = unpack(zip) else { return kept }
        try? fm.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(fresh) { try? d.write(to: file, options: .atomic) }
        return fresh
    }

    /// wiitdb.zip → wiitdb.xml (ditto, as Finder unzips) → the English facts
    nonisolated static func unpack(_ zip: Data) -> [String: WiiTDBEntry]? {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "nxforge-wiitdb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let z = tmp.appending(path: "wiitdb.zip")
        guard (try? zip.write(to: z)) != nil else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", z.path, tmp.path]
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0, let xml = try? Data(contentsOf: tmp.appending(path: "wiitdb.xml")) else { return nil }
        let out = parse(xml)
        return out.isEmpty ? nil : out
    }

    nonisolated static func parse(_ xml: Data) -> [String: WiiTDBEntry] {
        let reader = WiiTDBReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.out
    }
}

/// Reads wiitdb.xml: <game><id/><locale lang="EN"><title/><synopsis/></locale><developer/><publisher/><date year=…/><genre/>
/// <rating type=… value=…/><input players=…><control type=… required=…/></input></game>
final class WiiTDBReader: NSObject, XMLParserDelegate {
    var out: [String: WiiTDBEntry] = [:]
    private var id = "", entry = WiiTDBEntry(title: ""), text = "", inEnglish = false, inGame = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch name {
        case "game": inGame = true; id = ""; entry = WiiTDBEntry(title: "")
        case "locale": inEnglish = a["lang"] == "EN"
        case "date": entry.year = a["year"].flatMap(Int.init)
        case "rating": entry.board = a["type"]; entry.rating = a["value"]
        case "input": entry.players = a["players"].flatMap(Int.init)
        case "control":
            if let t = a["type"] {
                entry.controls.append(t)
                if a["required"] == "true" { entry.required.append(t) }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inGame else { return }
        switch name {
        case "id": id = t.uppercased()
        case "title": if inEnglish, !t.isEmpty { entry.title = t }
        case "synopsis": if inEnglish, !t.isEmpty { entry.synopsis = String(t.prefix(600)) }
        case "locale": inEnglish = false
        case "developer": if !t.isEmpty { entry.developer = t }
        case "publisher": if !t.isEmpty { entry.publisher = t }
        case "genre": entry.genres = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case "game":
            inGame = false
            if id.count == 6, !entry.title.isEmpty { out[id] = entry }
        default: break
        }
        text = ""
    }
}

/// libretro-thumbnails' screenshot and logo for a Wii or GameCube game, kept beside its covers as <key>-snap.png and <key>-logo.png
@MainActor @Observable
final class WiiArt {
    static let shared = WiiArt()
    private(set) var revision = 0
    @ObservationIgnored private var memory: [String: NSImage] = [:]
    @ObservationIgnored private var absent = Set<String>()
    @ObservationIgnored private var asked = Set<String>()
    @ObservationIgnored private var fetch: Task<Void, Never>?

    enum Kind: String { case snap, logo }

    func image(_ key: String, _ kind: Kind) -> NSImage? {
        let _ = revision
        let k = "\(key)-\(kind.rawValue)"
        if let i = memory[k] { return i }
        if absent.contains(k) { return nil }
        if let i = NSImage(contentsOf: CoverStore.dir.appending(path: k + ".png")), i.isValid, i.size.width > 0 {
            memory[k] = i
            return i
        }
        absent.insert(k)
        return nil
    }

    /// Fetch the pictures of the games that have none yet, one after another; a game libretro has nothing for is asked again after a month
    func fetchMissing(_ games: [(key: String, gameID: String, title: String, gamecube: Bool)]) {
        let todo = games.filter { !asked.contains($0.key) }
        guard !todo.isEmpty else { return }
        for g in todo { asked.insert(g.key) }
        let previous = fetch
        fetch = Task.detached(priority: .utility) {
            await previous?.value
            let fm = FileManager.default
            try? fm.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true)
            var lists: [String: [String]] = [:]
            for g in todo {
                if Task.isCancelled { return }
                let dir = CoverStore.dir, none = dir.appending(path: "\(g.key).wiiartnone")
                let snap = dir.appending(path: "\(g.key)-snap.png"), logo = dir.appending(path: "\(g.key)-logo.png")
                if fm.fileExists(atPath: snap.path) && fm.fileExists(atPath: logo.path) { continue }
                if let d = (try? fm.attributesOfItem(atPath: none.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) < 30 * 86400 { continue }
                let repo = g.gamecube ? "Nintendo_-_GameCube" : "Nintendo_-_Wii"
                if lists[repo] == nil { lists[repo] = await Self.list(repo) }
                guard let names = lists[repo], !names.isEmpty else { continue }   // offline: asked again at the next start
                var got = false
                for (folder, out) in [("Named_Snaps", snap), ("Named_Titles", snap), ("Named_Logos", logo)] where !fm.fileExists(atPath: out.path) {
                    guard let path = Self.match(g.title, gameID: g.gameID, folder: folder, in: names), let data = await Self.picture(repo, path) else { continue }
                    try? data.write(to: out)
                    got = true
                }
                if got || fm.fileExists(atPath: snap.path) || fm.fileExists(atPath: logo.path) { try? fm.removeItem(at: none) } else { try? Data().write(to: none) }
                if got {
                    let key = g.key
                    await MainActor.run { WiiArt.shared.forget(key) }
                }
            }
        }
    }

    func forget(_ key: String) {
        for k in [Kind.snap, .logo] { memory["\(key)-\(k.rawValue)"] = nil; absent.remove("\(key)-\(k.rawValue)") }
        revision += 1
    }

    /// A picture from the repository. One picture used for several discs is kept once and the others are symbolic links to it,
    /// which GitHub serves as the link's own text (the other file's name): that file is fetched instead.
    nonisolated static func picture(_ repo: String, _ path: String) async -> Data? {
        guard let url = raw(repo, path), let data = await CoverStore.get(url) else { return nil }
        if NSImage(data: data)?.isValid == true { return data }
        guard data.count < 1024, let target = linked(path, String(decoding: data, as: UTF8.self)), let u = raw(repo, target),
              let d = await CoverStore.get(u), NSImage(data: d)?.isValid == true else { return nil }
        return d
    }

    /// "Named_Logos/A (USA).png" linking to "A (Europe).png" → "Named_Logos/A (Europe).png"
    nonisolated static func linked(_ path: String, _ link: String) -> String? {
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n"), t.hasSuffix(".png") else { return nil }
        let full = URL(fileURLWithPath: "/" + path).deletingLastPathComponent().appending(path: t).standardized.path
        return String(full.dropFirst())
    }

    nonisolated static func raw(_ repo: String, _ path: String) -> URL? {
        guard let p = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(repo)/master/\(p)")
    }

    /// The repository's picture paths ("Named_Snaps/Super Mario Galaxy (USA).png"), kept a month in covers/<repo>.json
    nonisolated static func list(_ repo: String) async -> [String] {
        let file = CoverStore.dir.appending(path: "\(repo).json"), fm = FileManager.default
        let kept = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let age = ((try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if let kept, age < 30 * 86400 { return kept }
        guard let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/\(repo)/git/trees/master?recursive=1"),
              let d = await CoverStore.get(url),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let tree = json["tree"] as? [[String: Any]] else { return kept ?? [] }
        let paths = tree.compactMap { $0["path"] as? String }.filter { $0.hasSuffix(".png") }
        if let e = try? JSONEncoder().encode(paths) { try? e.write(to: file, options: .atomic) }
        return paths
    }

    /// "Sonic & SEGA All-Stars Racing" and "Sonic _ SEGA All-Stars Racing (USA)" → "sonicsegaallstarsracing"
    nonisolated static func plain(_ s: String) -> String {
        var n = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        n = n.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        if let m = n.firstMatch(of: #/^(.*?), (the|a|an)( - .*)?$/#) { n = "\(m.2) \(m.1)\(m.3 ?? "")" }
        if n.hasPrefix("the ") { n.removeFirst(4) }
        return String(n.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// The picture in the folder whose name is the game's, in the disc's own region when there is one (E America, P Europe, J Japan)
    nonisolated static func match(_ title: String, gameID: String, folder: String, in paths: [String]) -> String? {
        let want = plain(title)
        guard !want.isEmpty else { return nil }
        let prefix = folder + "/"
        let hits = paths.filter { $0.hasPrefix(prefix) && plain(String(($0.dropFirst(prefix.count) as Substring).dropLast(4))) == want }
        guard !hits.isEmpty else { return nil }
        let region = gameID.count >= 4 ? String(gameID[gameID.index(gameID.startIndex, offsetBy: 3)]) : ""
        let words = ["E": ["USA"], "N": ["USA"], "P": ["Europe", "UK", "Australia"], "D": ["Germany", "Europe"], "F": ["France", "Europe"], "J": ["Japan"], "K": ["Korea"]][region] ?? ["USA", "Europe"]
        for w in words { if let h = hits.first(where: { $0.contains("(\(w)") || $0.contains(", \(w)") }) { return h } }
        return hits.first
    }
}
