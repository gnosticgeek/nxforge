// NXForge from outside the app: nxforge:// links (the Shortcuts app's Open URLs action, so a shortcut or Siri can start a
// game), and your games in Spotlight.
//   nxforge://play/<game>      play a built game: a title ID, or its name or part of it ("zelda", "mario kart")
//   nxforge://play?game=<game> the same, for a Shortcut that fills the name in
//   nxforge://game/<game>      open the game's page
//   nxforge://theatre          Theatre, on the TV when one is plugged in
//   nxforge://home, nxforge://discover, nxforge://saves
// A Spotlight result opens the game's page (Return), where Play is one more press: a search never starts a game by itself.
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

enum GameLink {
    static let scheme = "nxforge"
    static let spotlightDomain = "org.nxforge.games"

    /// What a link asks for: its action (the host) and the game named after it, percent-decoded
    static func parse(_ u: URL) -> (action: String, game: String?)? {
        guard u.scheme?.lowercased() == scheme, let action = u.host(percentEncoded: false)?.lowercased(), !action.isEmpty else { return nil }
        let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "game" || $0.name == "name" }?.value
        let path = u.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let game = (q ?? path).trimmingCharacters(in: .whitespaces)
        return (action, game.isEmpty ? nil : game)
    }

    /// Letters and digits only, lower case, accents folded: "Pokémon™ Z-A" and "pokemon za" compare equal
    static func fold(_ s: String) -> String {
        String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// The game a few typed or spoken words mean: a title ID, the whole name, the start of a name, then every word somewhere in
    /// the name. Built games win a tie, then the one played last (the order they are given in).
    static func find<G>(_ query: String, in games: [G], name: (G) -> String, titleID: (G) -> String?, built: (G) -> Bool) -> G? {
        let q = fold(query)
        guard !q.isEmpty else { return nil }
        if let g = games.first(where: { titleID($0).map { fold($0) == q } ?? false }) { return g }
        let words = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { fold(String($0)) }.filter { !$0.isEmpty }
        let names = games.map { fold(name($0)) }
        let tests: [(String) -> Bool] = [
            { $0 == q },
            { $0.hasPrefix(q) },
            { $0.contains(q) },
            { n in !words.isEmpty && words.allSatisfy { n.contains($0) } },
        ]
        for t in tests {
            let hits = games.indices.filter { t(names[$0]) }
            if let i = hits.first(where: { built(games[$0]) }) ?? hits.first { return games[i] }
        }
        return nil
    }
}

extension AppModel {
    func findGame(_ query: String) -> StageGame? {
        GameLink.find(query, in: stageGames(), name: \.name, titleID: \.titleID, built: { $0.app != nil })
    }

    /// An nxforge:// link (AppDelegate.application(_:open:)). True when it was one.
    @discardableResult
    func openLink(_ u: URL) -> Bool {
        guard let (action, name) = GameLink.parse(u) else { return false }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        switch action {
        case "theatre": enterTheatre()
        case "home": if theatre { leaveTheatre() }; showStage(.home)
        case "discover": if theatre { leaveTheatre() }; showStage(.discover)
        case "saves": if theatre { leaveTheatre() }; showConverter(); page = .saves
        case "play", "game":
            guard let name, let g = findGame(name) else {
                showBanner(name.map { "No game matches “\($0)”" } ?? "The link names no game", detail: "nxforge://play/<name or title ID>", tone: .warning, symbol: "link")
                return true
            }
            if action == "play", g.app != nil { playFromStage(g.ref) } else { showGamePage(g) }
        default: showBanner("NXForge does not know the link “\(action)”", detail: "play, game, theatre, home, discover and saves are the ones it takes", tone: .warning, symbol: "link")
        }
        return true
    }

    /// A game's page on the front end, from a link or a Spotlight result
    func showGamePage(_ g: StageGame) {
        if theatre { leaveTheatre() }
        stageSettings = false
        frontEnd = true
        libraryFocus = g.id
        caseFlipped = false
        gameDetail = g.ref
    }

    /// A Spotlight result (its identifier is the game's id)
    func openSpotlight(_ id: String) {
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        if let g = stageGames().first(where: { $0.id == id }) { showGamePage(g) }
    }

    /// Your games in Spotlight: one item a game, replaced whole each time (a game that left the library leaves Spotlight).
    /// Called a few seconds after launch and when the library or the builds change; skipped while nothing changed.
    func indexSpotlight() {
        guard Bundle.main.bundleIdentifier != nil, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil, CSSearchableIndex.isIndexingAvailable() else { return }
        let games = stageGames()
        let stamp = games.map { "\($0.id)|\($0.name)|\($0.app ?? "")" }.joined(separator: "\n")
        guard stamp != spotlightStamp else { return }
        spotlightStamp = stamp
        let items = games.map { g in
            let a = CSSearchableItemAttributeSet(contentType: .item)
            a.title = g.name
            a.displayName = g.name
            a.contentDescription = "\(g.console == .switch2 ? "Switch 2" : "Switch") game in NXForge · \(g.app != nil ? "ready to play" : "not built yet")"
            a.keywords = ["NXForge", "Switch", "game", g.name] + (g.titleID.map { [$0] } ?? [])
            let covers = ["-front-own.png", "-front.jpg"].map { CoverStore.dir.appending(path: g.coverKey + $0).path }
            if let p = covers.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? g.icon { a.thumbnailURL = URL(fileURLWithPath: p) }
            if let last = g.last { a.lastUsedDate = last }
            return CSSearchableItem(uniqueIdentifier: g.id, domainIdentifier: GameLink.spotlightDomain, attributeSet: a)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [GameLink.spotlightDomain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items) { e in
                if let e { FileHandle.standardError.write(Data("Spotlight: \(e.localizedDescription)\n".utf8)) }
            }
        }
    }
}
