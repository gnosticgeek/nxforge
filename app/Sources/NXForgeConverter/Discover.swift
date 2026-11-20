// Discover: your games, all of them or by genre. Only the games in your games folder (and apps built from files outside it) are
// here: a game's genres are its file's in NXForge's game library (library/<title ID>/game.md, Genres.swift), else its page's on
// Nintendo's European store, looked up by title ID through the store's own search service (searching.nintendo-europe.com, as for
// the wide art in Covers.swift); only the title IDs go out. A game in neither goes under Other. Genres with sub-genres (Sports ›
// Football, Golf) open under the genre when it is chosen. Owned or Built, the console filters and Favourites work as they do everywhere on the stage.
// Everything works from a controller: the arrows walk the grid, A plays, Y opens the game's page, L and R step through All games
// and the genres, B goes back Home.
import AppKit
import SwiftUI

/// A game as the store lists it
struct DiscoverItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var titleID: String?
    var genres: [String] = []
    var playersFrom: Int?
    var playersTo: Int?
    var console: String = "Switch"

    var players: String? {
        guard let to = playersTo, to > 0 else { return nil }
        let from = playersFrom ?? 1
        return from == to ? "\(to) player\(to == 1 ? "" : "s")" : "\(from)–\(to) players"
    }
}

enum DiscoverBrowse: Hashable { case all, genre(String) }

/// The store's search, apart from the network (tested)
enum DiscoverSource {
    static let fields = "fs_id,application_id_s,title,url,pretty_game_categories_txt,players_from,players_to,playable_on_txt,system_names_txt"
    /// the genres, in the order shown (Genres.tree); any other genre one of your games has comes after them
    static let genres = Genres.top
    /// where a game the store does not list (or lists with no genre) goes
    static let other = "Other"

    /// The games with these title IDs (a page of the store for the ones in your games folder)
    static func byIDs(_ ids: [String]) -> URL? {
        let q = ids.map { $0.lowercased() }.filter { $0.count == 16 && $0.allSatisfy(\.isHexDigit) }
        guard !q.isEmpty else { return nil }
        return HeroSource.url(["q": "*", "fq": "type:GAME AND application_id_s:(\(q.joined(separator: " OR ")))", "rows": "\(q.count * 3)"], fields: fields)
    }

    /// One page of the search: its games and how many there are in all
    static func parse(_ data: Data) -> (items: [DiscoverItem], total: Int) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = o["response"] as? [String: Any],
              let docs = r["docs"] as? [[String: Any]] else { return ([], 0) }
        let items: [DiscoverItem] = docs.compactMap { d in
            guard let t = d["title"] as? String else { return nil }
            func s(_ k: String) -> String? { (d[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            let on = (d["playable_on_txt"] as? [String] ?? []) + (d["system_names_txt"] as? [String] ?? [])
            let id = (d["fs_id"] as? String) ?? (d["fs_id"] as? Int).map(String.init) ?? s("url") ?? t
            var item = DiscoverItem(id: id, title: t.trimmingCharacters(in: .whitespaces))
            item.titleID = s("application_id_s")?.uppercased()
            item.genres = d["pretty_game_categories_txt"] as? [String] ?? []
            item.playersFrom = d["players_from"] as? Int
            item.playersTo = d["players_to"] as? Int
            item.console = on.contains { $0 == "BEE" || $0.contains("Switch 2") } && !on.contains("HAC") ? "Switch 2" : "Switch"
            return item
        }
        return (items, r["numFound"] as? Int ?? items.count)
    }

    /// Each title ID's genres, from the store's pages for your games: one entry for each game, its shortest title's (a Switch 2
    /// Edition shares the ID)
    static func genreMap(_ pages: [DiscoverItem]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for i in pages.sorted(by: { $0.title.count < $1.title.count }) {
            guard let t = i.titleID, out[t] == nil else { continue }
            out[t] = i.genres
        }
        return out
    }

    /// A game's genres with their sub-genres: the library's for its title ID, else the store's, else Other
    static func genres(of titleID: String?, in map: [String: [String]], book: [String: [String]] = Genres.book) -> [String] {
        let id = titleID?.uppercased()
        let listed = id.flatMap { book[$0] } ?? id.flatMap { map[$0] } ?? []
        let g = Genres.expand(listed)
        return g.isEmpty ? [other] : g
    }

    /// The genres to list (not the sub-genres), in order: the usual ones first, then any others, Other last; only ones that have a game
    static func order(_ found: Set<String>) -> [String] {
        let top = found.filter { !Genres.isSub($0) }
        return genres.filter(top.contains) + top.subtracting(genres + [other]).sorted() + (top.contains(other) ? [other] : [])
    }

    /// A genre's sub-genres that have a game, in order
    static func subs(of g: String, _ found: Set<String>) -> [String] { Genres.subs(of: g).filter(found.contains) }
}

/// Where Discover is, and the genres of your games
@MainActor @Observable
final class DiscoverState {
    var browse: DiscoverBrowse = .all
    /// title ID → its genres on the store, for the games in your games folder
    var genreMap: [String: [String]] = [:]
    var loading = false
    /// the title IDs the map was read for: a new game in the folder reads it again
    @ObservationIgnored private var readFor: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    var genre: String? { if case .genre(let g) = browse { return g }; return nil }

    var title: String {
        switch browse {
        case .all: "All games"
        case .genre(let g): Self.plural(g)
        }
    }

    /// "Platformer" → "Platformers" for the heading; RPG and the like stay as they are
    nonisolated static func plural(_ g: String) -> String { Genres.plural(g) }

    /// the genre on screen's genre: itself, or the one a sub-genre is under
    var openGenre: String? { genre.map { Genres.parent[$0] ?? $0 } }

    func genres(of g: StageGame) -> [String] { DiscoverSource.genres(of: g.titleID, in: genreMap) }

    /// the genres your games are in, in the order listed (not the sub-genres)
    func shelves(_ games: [StageGame]) -> [String] { DiscoverSource.order(Set(games.flatMap { genres(of: $0) })) }

    /// a genre's sub-genres that your games are in
    func subs(of g: String, _ games: [StageGame]) -> [String] { DiscoverSource.subs(of: g, Set(games.flatMap { genres(of: $0) })) }

    /// the stops L and R walk: All games, then the genres, with the open genre's sub-genres after it
    func stops(_ games: [StageGame]) -> [DiscoverBrowse] {
        [.all] + shelves(games).flatMap { g in [DiscoverBrowse.genre(g)] + (g == openGenre ? subs(of: g, games).map { .genre($0) } : []) }
    }

    /// The games under the genre on screen
    func inBrowse(_ games: [StageGame]) -> [StageGame] {
        guard let g = genre else { return games }
        return games.filter { genres(of: $0).contains(g) }
    }

    /// Reads the store's pages for the games once, and again when the games change
    func load(_ titleIDs: [String]) {
        let ids = Array(Set(titleIDs.map { $0.uppercased() })).sorted()
        guard ids != readFor, !ids.isEmpty else { return }
        readFor = ids
        task?.cancel()
        loading = true
        task = Task {
            var pages: [DiscoverItem] = []
            for start in stride(from: 0, to: ids.count, by: HeroSource.batch) {
                let part = Array(ids[start..<min(start + HeroSource.batch, ids.count)])
                guard let u = DiscoverSource.byIDs(part), let d = await CoverStore.get(u) else { continue }
                pages += DiscoverSource.parse(d).items
            }
            if Task.isCancelled { return }
            if pages.isEmpty { readFor = [] }   // the store did not answer: try again next time
            else { genreMap = DiscoverSource.genreMap(pages) }
            loading = false
        }
    }
}

extension AppModel {
    /// L and R on Discover: the next genre, or Home from All games
    func discoverStep(_ d: Int) {
        let stops = discover.stops(stageGames())
        let i = stops.firstIndex(of: discover.browse) ?? 0
        if i + d < 0 { stageTab = .home; return }
        discover.browse = stops[min(i + d, stops.count - 1)]
        libraryFocus = nil
    }
}

struct DiscoverView: View {
    @Bindable var model: AppModel
    @Bindable var state: DiscoverState
    /// every game, and the ones on screen
    let games: [StageGame]
    let shown: [StageGame]
    let focus: StageGame?
    @Namespace private var marks

    var body: some View {
        let pool = model.stageScope == .built ? games.filter { $0.app != nil } : games
        HStack(spacing: 0) {
            sidebar(pool).frame(width: 214)
            Rectangle().fill(.white.opacity(0.10)).frame(width: 1).padding(.vertical, 8)
            StageLibrary(model: model, all: state.inBrowse(games), games: shown, focus: focus, title: state.title,
                         eyebrow: eyebrow, side: 30)
        }
        .task(id: games.compactMap(\.titleID).joined(separator: ",")) { state.load(games.compactMap(\.titleID)) }
    }

    func sidebar(_ pool: [StageGame]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse").font(.system(size: 24, weight: .heavy)).tracking(-0.4).padding(.leading, 14).padding(.bottom, 8)
                item("All games", .all, symbol: "square.grid.2x2", count: pool.count)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 14).padding(.horizontal, 8)
                HStack(spacing: 8) {
                    Text("GENRES").font(.system(size: 11, weight: .bold)).fontWidth(.expanded).kerning(1.6).foregroundStyle(StageLook.faint)
                    if state.loading { ProgressView().controlSize(.mini) }
                }
                .padding(.leading, 14).padding(.bottom, 6)
                ForEach(state.shelves(games), id: \.self) { g in
                    let subs = state.subs(of: g, games)
                    item(DiscoverState.plural(g), .genre(g), count: pool.filter { state.genres(of: $0).contains(g) }.count, more: subs.isEmpty ? nil : g == state.openGenre)
                    if g == state.openGenre {
                        ForEach(subs, id: \.self) { s in
                            item(DiscoverState.plural(s), .genre(s), count: pool.filter { state.genres(of: $0).contains(s) }.count, sub: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 20)
        }
        .scrollIndicators(.never)
    }

    /// "Discover / Genres", or "Discover / Sports" over a sub-genre
    var eyebrow: String {
        guard let g = state.genre else { return "Discover" }
        return "Discover / " + (Genres.parent[g].map(DiscoverState.plural) ?? "Genres")
    }

    /// A row of the sidebar. `more`: the genre has sub-genres (true while they show under it); `sub`: a sub-genre, set in under its genre
    func item(_ title: String, _ b: DiscoverBrowse, symbol: String? = nil, count: Int, more: Bool? = nil, sub: Bool = false) -> some View {
        let on = state.browse == b
        return Button { withAnimation(.spring(duration: 0.28)) { state.browse = b }; model.libraryFocus = nil } label: {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 18) }
                Text(title).font(.system(size: sub ? 14 : 15, weight: on ? .bold : .medium)).lineLimit(1)
                if let more {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(more ? 90 : 0))
                        .foregroundStyle(StageLook.faint)
                }
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.8) : StageLook.faint)
            }
            .padding(.leading, sub ? 30 : 14).padding(.trailing, 14).frame(height: sub ? 34 : 38)
            .foregroundStyle(on ? Color.white : count == 0 ? StageLook.faint : Color(white: 0.88))
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 10).fill(convertAccent.opacity(0.42))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .matchedGeometryEffect(id: "browse", in: marks)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.28), value: state.browse)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
