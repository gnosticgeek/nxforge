// Genres: NXForge's own list of kinds of game, each with its sub-genres (Sports › Football, Golf; Shooter › Shoot 'em up, ...),
// and each game's genres. A game's genres come from its file in NXForge's game library (library/<title ID>/game.md, bundled in the
// app), else from Nintendo's European store page for it (Discover.swift), read into this list; a game in neither is Other.
// A sub-genre counts under its genre too, so a game listed as Golf shows under Sports and under Golf.
import Foundation

enum Genres {
    /// The genres in the order Discover lists them, each with its sub-genres in order
    static let tree: [(genre: String, subs: [String])] = [
        ("Action", []),
        ("Run and gun", []),
        ("Beat 'em up", []),
        ("Platformer", ["2D platformer", "3D platformer", "Metroidvania"]),
        ("Adventure", []),
        ("RPG", ["Action RPG", "Turn-based RPG"]),
        ("Shooter", ["Shoot 'em up", "First-person shooter"]),
        ("Fighting", ["Platform fighter"]),
        ("Racing", ["Kart racing", "Arcade racing"]),
        ("Sports", ["Football", "Golf", "Baseball", "Tennis", "Basketball", "Multi-sport"]),
        ("Puzzle", []),
        ("Strategy", []),
        ("Party", []),
        ("Music", ["Rhythm"]),
        ("Arcade", ["Retro collection"]),
        ("Simulation", []),
        ("Board game", []),
        ("Lifestyle", []),
    ]
    static let top = tree.map(\.genre)
    /// sub-genre → its genre
    static let parent: [String: String] = Dictionary(uniqueKeysWithValues: tree.flatMap { t in t.subs.map { ($0, t.genre) } })
    static func subs(of g: String) -> [String] { tree.first { $0.genre == g }?.subs ?? [] }
    static func isSub(_ g: String) -> Bool { parent[g] != nil }

    /// The store's names that are not ours as they stand
    static let storeNames: [String: String] = [
        "First-Person Shooter": "First-person shooter", "First-person Shooter": "First-person shooter",
        "Football": "Football", "Soccer": "Football", "Golf": "Golf", "Baseball": "Baseball", "Tennis": "Tennis", "Basketball": "Basketball",
        "Role-Playing": "RPG", "Role-playing": "RPG", "Board Game": "Board game", "Fitness": "Lifestyle", "Training": "Lifestyle",
    ]

    /// Sub-genres the store has no category for, read from words in a game's store description ("a classic beat 'em up"), for a
    /// game with no file in the library
    static let hintWords: [(String, [String])] = [
        ("Beat 'em up", ["beat 'em up", "beat-'em-up", "beat em up", "beat 'em-up", "beat ’em up", "beat-’em-up"]),
        ("Run and gun", ["run and gun", "run-and-gun", "run 'n' gun", "run ’n’ gun", "run 'n gun", "run-n-gun"]),
        ("Shoot 'em up", ["shoot 'em up", "shoot-'em-up", "shoot ’em up", "shoot-’em-up", "shmup", "bullet hell"]),
        ("Metroidvania", ["metroidvania"]),
        ("Kart racing", ["kart racer", "kart racing"]),
        ("First-person shooter", ["first-person shooter", "first person shooter"]),
        ("Retro collection", ["collection of classic", "classic arcade games", "retro collection"]),
    ]

    /// The sub-genres a store description names
    static func hints(_ text: String?) -> [String] {
        guard let t = text?.lowercased(), !t.isEmpty else { return [] }
        let words = Set(t.split { !$0.isLetter }.map(String.init))
        return hintWords.filter { _, keys in
            keys.contains { k in k.contains(" ") || k.contains("-") || k.contains("'") || k.contains("’") ? t.contains(k) : words.contains(k) }
        }.map(\.0)
    }

    /// A game's genres as listed (the library's, or the store's in our names), with the genre of each sub-genre added, in the order
    /// of the tree; names outside the tree are kept after them
    static func expand(_ listed: [String]) -> [String] {
        var have = Set<String>()
        for g in listed {
            let n = storeNames[g] ?? g
            have.insert(n)
            if let p = parent[n] { have.insert(p) }
        }
        let known = tree.flatMap { [$0.genre] + $0.subs }
        return known.filter(have.contains) + have.subtracting(known).sorted()
    }

    /// "Platformer" → "Platformers" for a heading; RPG and the like stay as they are
    static func plural(_ g: String) -> String {
        switch g {
        case "Puzzle": return "Puzzles"
        case "Board game": return "Board games"
        case "Retro collection": return "Retro collections"
        case "Run and gun": return g
        default: break
        }
        if g.hasSuffix("RPG") { return g + "s" }
        if g.hasSuffix("er") || g.hasSuffix("'em up") || g == "Metroidvania" { return g + "s" }
        return g
    }

    /// The genres to show for a game: its library file's as listed, else the store's
    static func shown(titleID: String?, store: [String]) -> [String] {
        titleID.flatMap { book[$0.uppercased()] } ?? store
    }

    // MARK: the game library

    /// One game's file in the library: its title and genres
    struct Entry: Equatable {
        var titleID: String
        var title: String?
        var genres: [String]
    }

    /// A library game.md (front matter nxforge_game, title_id, title, genres)
    static func entry(_ text: String) -> Entry? {
        guard let doc = MiniYAML.frontMatter(text), doc["nxforge_game"] != nil, let t = doc["title_id"] as? String,
              t.count == 16, t.allSatisfy(\.isHexDigit) else { return nil }
        let g = (doc["genres"] as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        return Entry(titleID: t.uppercased(), title: doc["title"] as? String, genres: g)
    }

    /// title ID → genres, from every library/<title ID>/game.md in the folder
    static func read(library dir: URL) -> [String: [String]] {
        let fm = FileManager.default
        var out: [String: [String]] = [:]
        for tid in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where tid.count == 16 {
            guard let text = try? String(contentsOf: dir.appending(path: tid).appending(path: "game.md"), encoding: .utf8),
                  let e = entry(text), !e.genres.isEmpty else { continue }
            out[e.titleID] = e.genres
        }
        return out
    }

    /// The library in the app (Contents/Resources/library), else the repository's when NXForge runs from a checkout
    static var libraryDir: URL? {
        let fm = FileManager.default
        if let p = ProcessInfo.processInfo.environment["NXC_LIBRARY_DIR"] { return p.url }
        if let r = Bundle.main.resourceURL?.appending(path: "library"), fm.fileExists(atPath: r.path) { return r }
        var d = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let x = d else { break }
            let lib = x.appending(path: "library")
            if fm.fileExists(atPath: lib.appending(path: "README.md").path) { return lib }
            d = x.deletingLastPathComponent()
        }
        return nil
    }

    /// The bundled library's genres, read once
    static let book: [String: [String]] = libraryDir.map(read) ?? [:]
}
