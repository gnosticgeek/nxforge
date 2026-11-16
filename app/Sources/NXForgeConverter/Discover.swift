// Discover: Switch and Switch 2 games from Nintendo's European store, by genre, with what is already in your games folder marked
// In library, and a Wishlist kept on this Mac. The store's own search service answers (searching.nintendo-europe.com, the one
// the store's pages use, as for the wide art in Covers.swift): only the genre, the filters and what is typed in the search go out.
// The Wishlist is ~/Library/Application Support/NXForge Converter/wishlist.json. Everything works from a controller: the arrows
// walk the grid, A opens the game, Y adds it to the Wishlist, L and R step through Browse and the genres, B goes back.
import AppKit
import ImageIO
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
    var square: String?
    var wide: String?
    var page: String?
    var publisher: String?
    /// "11/07/2019", as the store writes it
    var released: String?
    var excerpt: String?
    /// when it went on the Wishlist
    var added: Date?

    var players: String? {
        guard let to = playersTo, to > 0 else { return nil }
        let from = playersFrom ?? 1
        return from == to ? "\(to) player\(to == 1 ? "" : "s")" : "\(from)–\(to) players"
    }

    /// the line under a card: its genres (but the one on screen), else its publisher
    func subtitle(besides genre: String?) -> String {
        let g = genres.filter { $0 != genre }.prefix(2)
        if !g.isEmpty { return g.joined(separator: " · ") }
        return publisher ?? console
    }

    var year: String? { released.flatMap { $0.count >= 4 ? String($0.suffix(4)) : nil } }
}

enum DiscoverBrowse: Hashable { case all, library, wishlist, genre(String) }
enum DiscoverPlatform: String, CaseIterable { case all = "All", switch1 = "Switch", switch2 = "Switch 2" }
enum DiscoverPlayers: String, CaseIterable {
    case any = "Any", one = "1 player", two = "2+", four = "4+"
    var least: Int? { switch self { case .any, .one: nil; case .two: 2; case .four: 4 } }
}
enum DiscoverLibrary: String, CaseIterable { case all = "All", inLibrary = "In library", notInLibrary = "Not in library" }
enum DiscoverSort: String, CaseIterable { case title = "Title A–Z", newest = "Newest", popular = "Popular" }

/// The store's search, apart from the network (tested)
enum DiscoverSource {
    static let fields = "fs_id,application_id_s,title,url,publisher,pretty_date_s,dates_released_dts,pretty_game_categories_txt,players_from,players_to,"
        + "image_url_sq_s,image_url_h2x1_s,excerpt,playable_on_txt,system_names_txt"
    /// how many games a page of the grid asks for
    static let rows = 48
    /// the store's genres that are kinds of game, in the order shown (its genre field is stemmed text, so its own list of values
    /// is "platform", "adventur"…: the names are kept here, and a filter by the name still matches)
    static let genres = ["Action", "Adventure", "Platformer", "RPG", "Racing", "Puzzle", "Strategy", "Sports", "Fighting", "Shooter", "Party",
                         "Simulation", "Arcade", "Music", "Board game", "Lifestyle"]

    /// A word-only search, so nothing typed reads as search syntax
    static func words(_ q: String) -> String {
        String(q.map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").joined(separator: " ")
    }

    /// The filters the store applies itself
    static func filters(genre: String?, platform: DiscoverPlatform, players: DiscoverPlayers) -> [String] {
        var fq = ["type:GAME"]
        if let genre { fq.append("pretty_game_categories_txt:\"\(genre.replacingOccurrences(of: "\"", with: ""))\"") }
        switch platform {
        case .all: fq.append("(playable_on_txt:HAC OR playable_on_txt:BEE)")
        case .switch1: fq.append("playable_on_txt:HAC")
        case .switch2: fq.append("playable_on_txt:BEE")
        }
        switch players {
        case .any: break
        case .one: fq.append("players_to:1")
        case .two, .four: fq.append("players_to:[\(players.least ?? 2) TO *]")
        }
        return fq
    }

    static func url(query: String, genre: String?, platform: DiscoverPlatform, players: DiscoverPlayers, sort: DiscoverSort, start: Int) -> URL? {
        let q = words(query)
        // a search is in order of how well each title matches until a sort other than A–Z is picked
        let order: String? = switch sort {
        case .title: q.isEmpty ? "sorting_title asc" : nil
        case .newest: "dates_released_dts desc"
        // a rank, 1 the most popular; a game with none is 999999, so last
        case .popular: "popularity asc"
        }
        var items = [URLQueryItem(name: "q", value: q.isEmpty ? "*" : q)]
        var fq = filters(genre: genre, platform: platform, players: players)
        // games with no date yet are listed as out on 31/12/2050
        if sort == .newest { fq.append("dates_released_dts:[* TO NOW]") }
        items += fq.map { URLQueryItem(name: "fq", value: $0) }
        items += [URLQueryItem(name: "rows", value: "\(rows)"), URLQueryItem(name: "start", value: "\(start)"), URLQueryItem(name: "fl", value: fields),
                  URLQueryItem(name: "wt", value: "json")]
        if let order { items.append(URLQueryItem(name: "sort", value: order)) }
        var c = URLComponents(string: HeroSource.search)
        c?.queryItems = items
        return c?.url
    }

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
            func https(_ k: String) -> String? { s(k).flatMap { $0.hasPrefix("https://") ? $0 : $0.hasPrefix("//") ? "https:" + $0 : nil } }
            let on = (d["playable_on_txt"] as? [String] ?? []) + (d["system_names_txt"] as? [String] ?? [])
            let id = (d["fs_id"] as? String) ?? (d["fs_id"] as? Int).map(String.init) ?? s("url") ?? t
            var item = DiscoverItem(id: id, title: t.trimmingCharacters(in: .whitespaces))
            item.titleID = s("application_id_s")?.uppercased()
            item.genres = d["pretty_game_categories_txt"] as? [String] ?? []
            item.playersFrom = d["players_from"] as? Int
            item.playersTo = d["players_to"] as? Int
            item.console = on.contains { $0 == "BEE" || $0.contains("Switch 2") } && !on.contains("HAC") ? "Switch 2" : "Switch"
            item.square = https("image_url_sq_s")
            item.wide = https("image_url_h2x1_s")
            item.page = s("url").flatMap { $0.hasPrefix("/") && !$0.hasPrefix("//") ? HeroSource.site + $0 : nil }
            item.publisher = s("publisher")
            item.released = s("pretty_date_s")
            item.excerpt = s("excerpt")
            return item
        }
        return (items, r["numFound"] as? Int ?? items.count)
    }

    /// The same picture larger (the store names a 500 px copy)
    static func larger(_ u: String) -> URL? { HeroSource.sizes(u).first }

    /// Whether a game is one in your games folder: by its title ID, else by its name
    static func owned(_ item: DiscoverItem, ids: Set<String>, names: Set<String>) -> Bool {
        if let t = item.titleID, ids.contains(t) { return true }
        return names.contains(CoverSource.normalize(CoverSource.plain(item.title)))
    }

    /// The filters applied here, to games the store was not asked for again (the Wishlist, the ones in your games folder)
    static func keep(_ i: DiscoverItem, genre: String?, platform: DiscoverPlatform, players: DiscoverPlayers, query: String) -> Bool {
        if let genre, !i.genres.contains(genre) { return false }
        if platform == .switch1 && i.console != "Switch" { return false }
        if platform == .switch2 && i.console != "Switch 2" { return false }
        if players == .one && (i.playersTo ?? 1) != 1 { return false }
        if let n = players.least, (i.playersTo ?? 1) < n { return false }
        let q = words(query)
        return q.isEmpty || TitleMatch.matches(q, [i.title, i.publisher])
    }

    static func sorted(_ items: [DiscoverItem], by sort: DiscoverSort) -> [DiscoverItem] {
        switch sort {
        case .title, .popular: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest: return items.sorted { date($0.released) > date($1.released) }
        }
    }

    /// "11/07/2019" (day first) as a date to sort by
    static func date(_ s: String?) -> Date {
        guard let s else { return .distantPast }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd/MM/yyyy"
        return f.date(from: s) ?? .distantPast
    }
}

/// The games kept to look at later, on this Mac only
@MainActor @Observable
final class Wishlist {
    static let shared = Wishlist()
    private(set) var items: [DiscoverItem] = []

    nonisolated static var file: URL { Settings.supportDir.appending(path: "wishlist.json") }

    init() {
        if let d = try? Data(contentsOf: Self.file), let list = try? JSONDecoder().decode([DiscoverItem].self, from: d) { items = list }
    }

    func contains(_ i: DiscoverItem) -> Bool { items.contains { $0.id == i.id } }

    func toggle(_ i: DiscoverItem) {
        if let k = items.firstIndex(where: { $0.id == i.id }) { items.remove(at: k) } else {
            var n = i
            n.added = Date()
            items.insert(n, at: 0)
        }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(items) { try? d.write(to: Self.file, options: .atomic) }
    }
}

/// What Discover shows and where it is
@MainActor @Observable
final class DiscoverState {
    var browse: DiscoverBrowse = .genre("Platformer")
    var platform: DiscoverPlatform = .all
    var players: DiscoverPlayers = .any
    var library: DiscoverLibrary = .all
    var sort: DiscoverSort = .title
    var query = ""
    var items: [DiscoverItem] = []
    var total = 0
    var loading = false
    var failed = false
    var focus: String?
    var columns = 5
    /// the game whose page is open over the grid
    var detail: DiscoverItem?
    /// the store's pages for the games in your games folder, read once
    @ObservationIgnored var owned: [DiscoverItem]?
    @ObservationIgnored private var task: Task<Void, Never>?

    var genre: String? { if case .genre(let g) = browse { return g }; return nil }

    /// the stops L and R walk: Browse, then the genres
    var stops: [DiscoverBrowse] { [.all, .library, .wishlist] + DiscoverSource.genres.map { .genre($0) } }

    var title: String {
        switch browse {
        case .all: "All games"
        case .library: "In your library"
        case .wishlist: "Wishlist"
        case .genre(let g): Self.plural(g)
        }
    }

    /// "Platformer" → "Platformers" for the heading; RPG and the like stay as they are
    static func plural(_ g: String) -> String {
        switch g {
        case "Platformer", "Shooter", "Board game": g + "s"
        case "Puzzle": "Puzzles"
        case "RPG": "RPGs"
        default: g
        }
    }

    /// what decides the grid's games: a change of any of it starts again from the top
    var key: String { "\(browse)|\(platform)|\(players)|\(library)|\(sort)|\(query)" }

    func step(_ d: Int) {
        let s = stops
        let i = s.firstIndex(of: browse) ?? 0
        browse = s[min(max(i + d, 0), s.count - 1)]
    }

    /// The grid's games from the start: the store's search, or the Wishlist and your games' store pages filtered here
    func reload(ids: Set<String>, names: Set<String>, titleIDs: [String]) {
        task?.cancel()
        items = []
        total = 0
        failed = false
        focus = nil
        let local = browse == .wishlist || browse == .library || library == .inLibrary
        if local {
            loading = true
            task = Task {
                var pool: [DiscoverItem]
                if browse == .wishlist { pool = Wishlist.shared.items } else { pool = await ownedPages(titleIDs) }
                if browse == .wishlist && library == .inLibrary { pool = pool.filter { DiscoverSource.owned($0, ids: ids, names: names) } }
                if library == .notInLibrary { pool = pool.filter { !DiscoverSource.owned($0, ids: ids, names: names) } }
                let g = genre, p = platform, pl = players, q = query
                pool = pool.filter { DiscoverSource.keep($0, genre: g, platform: p, players: pl, query: q) }
                if browse != .wishlist || sort != .title { pool = DiscoverSource.sorted(pool, by: sort) }
                if Task.isCancelled { return }
                items = pool
                total = pool.count
                loading = false
            }
        } else {
            more(ids: ids, names: names)
        }
    }

    /// The next page of the store's search
    func more(ids: Set<String>, names: Set<String>) {
        guard !loading, browse != .wishlist, browse != .library, library != .inLibrary else { return }
        guard items.isEmpty || items.count < total else { return }
        guard let u = DiscoverSource.url(query: query, genre: genre, platform: platform, players: players, sort: sort, start: items.count) else { return }
        loading = true
        let drop = library == .notInLibrary
        let k = key
        task = Task {
            let data = await CoverStore.get(u)
            guard !Task.isCancelled, k == key else { return }
            loading = false
            guard let data else { failed = items.isEmpty; return }
            let page = DiscoverSource.parse(data)
            total = page.total
            let have = Set(items.map(\.id))
            items += page.items.filter { !have.contains($0.id) && !(drop && DiscoverSource.owned($0, ids: ids, names: names)) }
            // a page wholly in your library (Not in library) asks for the next at once
            if drop && page.items.count > 0 && items.count < 12 { more(ids: ids, names: names) }
        }
    }

    private func ownedPages(_ titleIDs: [String]) async -> [DiscoverItem] {
        if let owned { return owned }
        var out: [DiscoverItem] = [], seen = Set<String>()
        for start in stride(from: 0, to: titleIDs.count, by: HeroSource.batch) {
            let part = Array(titleIDs[start..<min(start + HeroSource.batch, titleIDs.count)])
            guard let u = DiscoverSource.byIDs(part), let d = await CoverStore.get(u) else { continue }
            // one entry for each game: its shortest title (a Switch 2 Edition shares the ID)
            for i in DiscoverSource.parse(d).items.sorted(by: { $0.title.count < $1.title.count }) {
                guard let t = i.titleID, !seen.contains(t) else { continue }
                seen.insert(t)
                out.append(i)
            }
        }
        owned = out
        return out
    }

    func moveFocus(dx: Int = 0, dy: Int = 0) {
        guard !items.isEmpty else { return }
        guard let f = focus, let i = items.firstIndex(where: { $0.id == f }) else { focus = items.first?.id; return }
        focus = items[min(max(i + dx + dy * max(columns, 1), 0), items.count - 1)].id
    }

    var focused: DiscoverItem? { items.first { $0.id == focus } ?? items.first }
}

extension AppModel {
    /// The title IDs and names in your games folder, to mark the store's games In library
    func discoverOwned() -> (ids: Set<String>, names: Set<String>, list: [String]) {
        let games = stageGames()
        let list = games.compactMap { $0.titleID?.uppercased() }
        return (Set(list), Set(games.map { CoverSource.normalize(CoverSource.plain($0.name)) }), list)
    }

    func discoverReload() {
        let o = discoverOwned()
        discover.reload(ids: o.ids, names: o.names, titleIDs: o.list)
    }

    func discoverMore() {
        let o = discoverOwned()
        discover.more(ids: o.ids, names: o.names)
    }

    /// The game in your library a store game is, if it is one
    func discoverGame(_ i: DiscoverItem) -> StageGame? {
        let games = stageGames()
        if let t = i.titleID, let g = games.first(where: { $0.titleID?.uppercased() == t }) { return g }
        let n = CoverSource.normalize(CoverSource.plain(i.title))
        return games.first { CoverSource.normalize(CoverSource.plain($0.name)) == n }
    }

    /// View game: its page in the Library when you have it, else its store page here
    func discoverOpen(_ i: DiscoverItem) {
        discover.focus = i.id
        if let g = discoverGame(i) { libraryFocus = g.id; caseFlipped = false; gameDetail = g.ref } else { discover.detail = i }
    }

    func discoverPad(_ k: PadKey) {
        let d = discover
        if let open = d.detail {
            switch k {
            case .b, .menu: d.detail = nil
            case .y: Wishlist.shared.toggle(open)
            case .a, .x: if let p = open.page.flatMap(URL.init(string:)) { NSWorkspace.shared.open(p) }
            default: break
            }
            return
        }
        switch k {
        case .left: d.moveFocus(dx: -1)
        case .right: d.moveFocus(dx: 1)
        case .up: d.moveFocus(dy: -1)
        case .down: d.moveFocus(dy: 1)
        case .a: if let i = d.focused { discoverOpen(i) }
        case .y, .options: if let i = d.focused { Wishlist.shared.toggle(i); if d.browse == .wishlist { discoverReload() } }
        case .x: if let p = d.focused?.page.flatMap(URL.init(string:)) { NSWorkspace.shared.open(p) }
        case .l: d.step(-1)
        case .r: d.step(1)
        case .b: stageTab = .home
        case .menu: settingsFocus = 0; stageSettings = true
        }
    }
}

/// A picture from the store, read once and kept small (the URL cache keeps the file between starts)
struct RemoteArt: View {
    let url: URL?
    var side = 600
    @State private var image: NSImage?

    @MainActor static let cache = NSCache<NSURL, NSImage>()
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 400 << 20, directory: Settings.supportDir.appending(path: "discover-cache"))
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        return URLSession(configuration: c)
    }()

    var body: some View {
        ZStack {
            Color(white: 0.14)
            if let image { Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: url) {
            guard let url else { image = nil; return }
            if let i = Self.cache.object(forKey: url as NSURL) { image = i; return }
            image = nil
            let max = side
            guard let (d, r) = try? await Self.session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                guard let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
                let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: max]
                return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
            }.value
            guard let cg, !Task.isCancelled else { return }
            let i = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            Self.cache.setObject(i, forKey: url as NSURL)
            image = i
        }
    }
}

struct DiscoverView: View {
    @Bindable var model: AppModel
    @Bindable var state: DiscoverState
    @Namespace private var marks
    static let side: CGFloat = 40, cell: CGFloat = 170, gap: CGFloat = 26

    var body: some View {
        let owned = model.discoverOwned()
        let wish = Wishlist.shared
        HStack(spacing: 0) {
            sidebar(count: wish.items.count).frame(width: 214)
            Rectangle().fill(.white.opacity(0.10)).frame(width: 1).padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 14) {
                heading
                filterRow
                grid(owned: owned)
                if let i = state.focused { DiscoverBar(model: model, item: i, owned: DiscoverSource.owned(i, ids: owned.ids, names: owned.names), genre: state.genre) }
            }
            .padding(.leading, 30).padding(.trailing, Self.side).padding(.bottom, 12)
        }
        .overlay {
            if let d = state.detail {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { state.detail = nil }
                    DiscoverDetail(model: model, item: d).padding(16)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3), value: state.detail?.id)
        .task(id: state.key + "|\(model.library?.games.count ?? 0)") {
            // a search waits for a pause in the typing
            if !state.query.isEmpty { try? await Task.sleep(for: .milliseconds(300)); if Task.isCancelled { return } }
            model.discoverReload()
        }
    }

    func sidebar(count: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse").font(.system(size: 24, weight: .heavy)).tracking(-0.4).padding(.leading, 14).padding(.bottom, 8)
                item("All games", .all, symbol: "square.grid.2x2")
                item("In your library", .library, symbol: "books.vertical")
                item("Wishlist", .wishlist, symbol: "heart", count: count)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 14).padding(.horizontal, 8)
                Text("GENRES").font(.system(size: 11, weight: .bold)).fontWidth(.expanded).kerning(1.6).foregroundStyle(StageLook.faint)
                    .padding(.leading, 14).padding(.bottom, 6)
                ForEach(DiscoverSource.genres, id: \.self) { g in item(DiscoverState.plural(g), .genre(g)) }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 20)
        }
        .scrollIndicators(.never)
    }

    func item(_ title: String, _ b: DiscoverBrowse, symbol: String? = nil, count: Int? = nil) -> some View {
        let on = state.browse == b
        return Button { state.browse = b } label: {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: on && symbol == "heart" ? "heart.fill" : symbol).font(.system(size: 13, weight: .semibold)).frame(width: 18) }
                Text(title).font(.system(size: 15, weight: on ? .bold : .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if let count, count > 0 { Text("\(count)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.8) : StageLook.faint) }
            }
            .padding(.horizontal, 14).frame(height: 38)
            .foregroundStyle(on ? Color.white : Color(white: 0.88))
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

    var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.genre != nil ? "Discover / Genres" : "Discover").font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.faint)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(state.title).font(.system(size: 32, weight: .heavy)).tracking(-0.6)
                    if state.total > 0 { Text("\(state.total.formatted()) game\(state.total == 1 ? "" : "s")").foregroundStyle(StageLook.soft).monospacedDigit() }
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(StageLook.faint)
                TextField("Search games", text: $state.query).textFieldStyle(.plain)
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                        .buttonStyle(.plain).accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 14).frame(minWidth: 180, maxWidth: 360).frame(height: 34)
            .background(.white.opacity(0.06), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
        }
        .padding(.top, 6)
    }

    var filterRow: some View {
        HStack(spacing: 10) {
            menu("Platform", state.platform.rawValue, DiscoverPlatform.allCases.map(\.rawValue)) { v in state.platform = DiscoverPlatform(rawValue: v) ?? .all }
            menu("Players", state.players.rawValue, DiscoverPlayers.allCases.map(\.rawValue)) { v in state.players = DiscoverPlayers(rawValue: v) ?? .any }
            if state.browse != .library {
                menu("Library", state.library.rawValue, DiscoverLibrary.allCases.map(\.rawValue)) { v in state.library = DiscoverLibrary(rawValue: v) ?? .all }
            }
            Spacer(minLength: 8)
            menu("Sort", state.sort.rawValue, DiscoverSort.allCases.map(\.rawValue)) { v in state.sort = DiscoverSort(rawValue: v) ?? .title }
        }
    }

    /// A boxed "Platform: All" menu, as on Builds (BoxMenu)
    func menu(_ label: String, _ value: String, _ options: [String], _ pick: @escaping (String) -> Void) -> some View {
        BoxMenu {
            ForEach(options, id: \.self) { o in
                Button { pick(o) } label: { if o == value { Label(o, systemImage: "checkmark") } else { Text(o) } }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label + ":").foregroundStyle(StageLook.soft)
                Text(value).fontWeight(.semibold).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(StageLook.soft).padding(.leading, 12)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14).frame(height: 34)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16)))
        }
        .fixedSize()
        .accessibilityLabel("\(label): \(value)")
    }

    @ViewBuilder func grid(owned: (ids: Set<String>, names: Set<String>, list: [String])) -> some View {
        if state.items.isEmpty {
            VStack(spacing: 12) {
                if state.loading { ProgressView().controlSize(.large) }
                else {
                    Image(systemName: state.failed ? "wifi.slash" : state.browse == .wishlist ? "heart" : "magnifyingglass").font(.system(size: 38)).foregroundStyle(StageLook.soft)
                    Text(emptyText).font(.system(size: 15, weight: .medium)).foregroundStyle(StageLook.soft).multilineTextAlignment(.center).frame(maxWidth: 420)
                    if state.failed { Button("Try Again") { model.discoverReload() }.buttonStyle(StageButton(height: 36)) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell + 60), spacing: Self.gap, alignment: .top)], alignment: .leading, spacing: 22) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { n, i in
                            DiscoverCard(item: i, focused: state.focused?.id == i.id, owned: DiscoverSource.owned(i, ids: owned.ids, names: owned.names),
                                         wished: Wishlist.shared.contains(i), subtitle: i.subtitle(besides: state.genre))
                                .id(i.id)
                                .onTapGesture(count: 2) { model.discoverOpen(i) }
                                .simultaneousGesture(TapGesture().onEnded { state.focus = i.id })
                                .contextMenu {
                                    Button("View Game") { model.discoverOpen(i) }
                                    Button(Wishlist.shared.contains(i) ? "Remove from Wishlist" : "Add to Wishlist") { Wishlist.shared.toggle(i) }
                                    if let p = i.page.flatMap(URL.init(string:)) { Button("Open in Nintendo eShop") { NSWorkspace.shared.open(p) } }
                                }
                                .onAppear { if n >= state.items.count - 10 { model.discoverMore() } }
                        }
                    }
                    .padding(.top, 14).padding(.bottom, 20).padding(.horizontal, 6)
                    if state.loading { ProgressView().frame(maxWidth: .infinity).padding(.bottom, 16) }
                }
                .scrollIndicators(.automatic)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03), .init(color: .black, location: 0.97),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onChange(of: state.focus) { _, f in if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } } }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                state.columns = max(Int((w - 12 + Self.gap) / (Self.cell + Self.gap)), 1)
            }
        }
    }

    var emptyText: String {
        if state.failed { return "Nintendo's store did not answer. Check the connection and try again." }
        if !DiscoverSource.words(state.query).isEmpty { return "Nothing matches “\(state.query)”." }
        if state.browse == .wishlist { return "Your Wishlist is empty. Press Y or the heart on a game to keep it here." }
        if state.browse == .library { return "None of your games was found in Nintendo's store with these filters." }
        return "No games here with these filters."
    }
}

/// A game in the grid: its square art, In library or a heart in the corner, its name and genres
struct DiscoverCard: View {
    let item: DiscoverItem
    let focused: Bool
    let owned: Bool
    let wished: Bool
    let subtitle: String
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        VStack(alignment: .leading, spacing: 8) {
            RemoteArt(url: item.square.flatMap(URL.init(string:)))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if wished { badge(nil, symbol: "heart.fill", color: Color(red: 1, green: 0.42, blue: 0.55)) }
                        if owned { badge("In library", symbol: "bookmark.fill", color: convertAccent) }
                    }
                    .padding(8)
                }
                .overlay {
                    shape.strokeBorder(convertAccent, lineWidth: 3).padding(-5)
                        .shadow(color: convertAccent.opacity(0.8), radius: 10)
                        .opacity(focused ? 1 : 0)
                }
                .shadow(color: .black.opacity(0.45), radius: focused ? 18 : 8, y: 6)
                .scaleEffect(focused ? 1.035 : hover ? 1.02 : 1)
                .animation(.spring(duration: 0.22), value: focused)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14.5, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + (owned ? ", in your library" : "") + (wished ? ", on your Wishlist" : ""))
        .accessibilityAddTraits(.isButton)
    }

    func badge(_ text: String?, symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            if let text { Text(text).font(.system(size: 11.5, weight: .semibold)) }
        }
        .padding(.horizontal, text == nil ? 7 : 9).frame(height: 24)
        .background(.black.opacity(0.62), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}

/// Along the foot of the grid: the game in focus, Wishlist and View game
struct DiscoverBar: View {
    let model: AppModel
    let item: DiscoverItem
    let owned: Bool
    let genre: String?

    var body: some View {
        let wished = Wishlist.shared.contains(item)
        HStack(spacing: 14) {
            RemoteArt(url: item.square.flatMap(URL.init(string:)), side: 160).frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(([item.subtitle(besides: nil)] + [item.players, item.console].compactMap { $0 }).joined(separator: "  ·  "))
                    .font(.system(size: 13)).foregroundStyle(StageLook.soft).lineLimit(1)
            }
            Spacer(minLength: 8)
            if owned {
                Label("In your library", systemImage: "bookmark.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(convertAccent)
            }
            Button { Wishlist.shared.toggle(item); if model.discover.browse == .wishlist { model.discoverReload() } } label: {
                Label("Wishlist", systemImage: wished ? "heart.fill" : "heart")
            }
            .buttonStyle(StageButton(height: 40)).help(wished ? "Remove from your Wishlist (Y)" : "Add to your Wishlist (Y)")
            Button { model.discoverOpen(item) } label: { Text("View game") }
                .buttonStyle(StageButton(primary: true, height: 40)).help(owned ? "Its page in your Library (A)" : "What the store says about it (A)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(StageLook.panel.opacity(0.88), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StageLook.edge, lineWidth: 1))
    }
}

/// A store game's page over the grid: its wide art, what it is, the store's pitch, Wishlist and the store page
struct DiscoverDetail: View {
    let model: AppModel
    let item: DiscoverItem

    var body: some View {
        let wished = Wishlist.shared.contains(item)
        VStack(alignment: .leading, spacing: 0) {
            RemoteArt(url: (item.wide ?? item.square).flatMap(DiscoverSource.larger), side: 1200)
                .frame(height: 230).frame(maxWidth: .infinity).clipped()
                .overlay(alignment: .topTrailing) {
                    Button { model.discover.detail = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32).glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain).padding(12).accessibilityLabel("Close")
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.title).font(.system(size: 28, weight: .heavy)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                    Text(facts.joined(separator: "  ·  ")).font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.soft)
                    if !item.genres.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(item.genres.prefix(4), id: \.self) { g in
                                Text(g).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 24)
                                    .background(.white.opacity(0.10), in: .capsule)
                            }
                        }
                    }
                    if let e = item.excerpt {
                        Text(StoreSource.plainText(e)).font(.system(size: 14.5)).foregroundStyle(Color(white: 0.88)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
            }
            HStack(spacing: 10) {
                Button { Wishlist.shared.toggle(item) } label: { Label(wished ? "On your Wishlist" : "Add to Wishlist", systemImage: wished ? "heart.fill" : "heart") }
                    .buttonStyle(StageButton(height: 42))
                Spacer()
                if let p = item.page.flatMap(URL.init(string:)) {
                    Button { NSWorkspace.shared.open(p) } label: { Label("Nintendo eShop", systemImage: "arrow.up.right") }
                        .buttonStyle(StageButton(primary: true, height: 42)).help("Opens the game's page on Nintendo's store in your browser (A)")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
        .frame(width: 520)
        .frame(maxHeight: .infinity)
        .background(StageLook.panel, in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(StageLook.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30)
    }

    var facts: [String] {
        [item.console, item.players, item.publisher, item.year].compactMap { $0 }
    }
}
