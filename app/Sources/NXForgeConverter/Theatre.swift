// Theatre: the front end full screen on a TV, for the sofa and a controller. It takes Couch Mode's place (⇧⌘F, View › Theatre,
// the Theatre button in the top bar, Settings › Theatre) and NXForge offers it when a TV is plugged in while a controller is
// connected (Settings: Ask, Always or Never). The window moves to the TV and goes full screen, the pointer hides, the Mac
// stays awake, and leaving puts the window back where it was. Four themes show the same games: Carousel, a turning ring of the
// real 3D boxes (TheatreCarousel), Cinema, wide art with rows under it like a TV app, Gallery, three covers on a quiet
// ivory wall beside the game's name, and Trailer, the game's trailer over a strip of games, filling the screen when left alone. ZL and ZR switch
// them, L and R filter the games (All, Favourites, Recently played, each genre). A plays (Continue for a game played before), Y opens the
// game's page, X Play options, − favourites, Menu the Theatre menu, B offers to leave; on Trailer the right stick sets the volume and its
// press mutes. Theatre reopens on the theme, filter and game it was left on, shows a game's details once the focus rests on it, takes its
// colour from the game's art in every theme, insets the picture for a TV that crops its edges, and puts up a screensaver when left alone.
import AppKit
import GameController
import SceneKit
import SwiftUI
import WebKit

enum TheatreTheme: String, Codable, CaseIterable {
    case carousel = "Carousel", cinema = "Cinema", gallery = "Gallery", trailer = "Trailer"

    /// Shelf (0.19.0 only) became Gallery
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = TheatreTheme(rawValue: s) ?? (s == "Shelf" ? .gallery : .carousel)
    }
    var note: String {
        switch self {
        case .carousel: "A turning ring of your boxes"
        case .cinema: "Big art, rows like a TV app"
        case .gallery: "Three covers on a quiet wall"
        case .trailer: "The trailer fills the room"
        }
    }
    var symbol: String {
        switch self {
        case .carousel: "rotate.3d"
        case .cinema: "film"
        case .gallery: "photo.on.rectangle"
        case .trailer: "play.rectangle"
        }
    }
}

/// What NXForge does when a TV appears: offer Theatre, open it straight away, or leave it to you
enum TheatreOnTV: String, Codable, CaseIterable { case ask = "Ask", always = "Always", never = "Never" }

/// How far Theatre's picture is inset from the screen's edges, for a TV that crops them (overscan): the corners of the picture
/// must show on the TV, so the clock, the counter and the button hints are never cut off
enum TheatreEdges: String, Codable, CaseIterable {
    case full = "Full", small = "Small", large = "Large"
    var title: String {
        switch self {
        case .full: "Full"
        case .small: "Inset 3 %"
        case .large: "Inset 5 %"
        }
    }
    /// of the width and of the height, on each side
    var inset: CGFloat {
        switch self {
        case .full: 0
        case .small: 0.03
        case .large: 0.05
        }
    }
    func step(_ d: Int) -> TheatreEdges {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[min(max(i + d, 0), all.count - 1)]
    }
}

/// How long Theatre waits, left alone, before its screensaver
enum TheatreSaver: String, Codable, CaseIterable {
    case five = "5 min", fifteen = "15 min", never = "Never"
    var seconds: Double? {
        switch self {
        case .five: 300
        case .fifteen: 900
        case .never: nil
        }
    }
}

/// What L and R walk on Theatre: every game, the favourites, the ones played lately, or one genre
enum TheatreFilter: Hashable {
    case all, favourites, recent, genre(String)

    var key: String {
        switch self {
        case .all: "all"
        case .favourites: "favourites"
        case .recent: "recent"
        case .genre(let g): "genre:" + g
        }
    }

    init(key: String?) {
        switch key {
        case "favourites": self = .favourites
        case "recent": self = .recent
        case let k? where k.hasPrefix("genre:"): self = .genre(String(k.dropFirst(6)))
        default: self = .all
        }
    }

    var title: String {
        switch self {
        case .all: "All games"
        case .favourites: "Favourites"
        case .recent: "Recently played"
        case .genre(let g): DiscoverState.plural(g)
        }
    }

    /// Recently played: played in the last 30 days
    static let recentDays = 30.0
    static func isRecent(_ g: StageGame, now: Date = Date()) -> Bool {
        guard let l = g.last else { return false }
        return now.timeIntervalSince(l) < recentDays * 86400
    }
}

/// One timing for a change of game on every theme, so the art, the trailer, the words and the room's colour fade together
/// (StageBackdrop's own cross-fade is 0.55 s)
enum TheatreMotion {
    static let swap = 0.55
    static var swapAnimation: Animation { .easeInOut(duration: swap) }
}

/// One of a game's details on Theatre: its genre, players, size, whether it is built, when it was played
struct TheatreFact: Hashable {
    let text: String
    let symbol: String
}

/// The Theatre menu's rows (Menu, or B for Leave)
enum TheatreMenuRow: Int, CaseIterable {
    case carousel, cinema, gallery, trailer, shuffle, edges, settings, leave
    var title: String {
        switch self {
        case .shuffle: "What Should I Play?"
        case .edges: "TV Edges"
        case .settings: "Settings"
        case .leave: "Leave Theatre"
        default: theme?.rawValue ?? ""
        }
    }
    var theme: TheatreTheme? {
        switch self {
        case .carousel: .carousel
        case .cinema: .cinema
        case .gallery: .gallery
        case .trailer: .trailer
        case .shuffle, .edges, .settings, .leave: nil
        }
    }
    static func row(_ t: TheatreTheme) -> TheatreMenuRow { allCases.first { $0.theme == t } ?? .carousel }
}

/// A screen that looks like a TV
struct TVScreen: Equatable {
    let id: CGDirectDisplayID
    let name: String
}

enum TVScreens {
    /// TV makers' names as their sets report them (a monitor from the same maker usually names its model line instead)
    static let makers = ["bravia", "hisense", "panasonic", "philips", "samsung", "sharp", "sony", "tcl", "toshiba", "vizio", "roku", "lg tv"]

    /// A TV: "TV" as a word in its name, a TV maker's name, or a screen at least 40 inches across (88 cm wide)
    static func isTV(name: String, widthMM: Double) -> Bool {
        let n = name.lowercased()
        let words = n.split { !$0.isLetter && !$0.isNumber }
        if words.contains("tv") || words.contains("television") { return true }
        if makers.contains(where: { n.contains($0) }) { return true }
        return widthMM >= 880 && widthMM < 3000   // some sets report nonsense sizes: 0, or several metres
    }

    static func id(_ s: NSScreen) -> CGDirectDisplayID? {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The first screen other than the Mac's own that looks like a TV
    @MainActor static func find() -> TVScreen? {
        for s in NSScreen.screens {
            guard let id = id(s), CGDisplayIsBuiltin(id) == 0 else { continue }
            if isTV(name: s.localizedName, widthMM: Double(CGDisplayScreenSize(id).width)) { return TVScreen(id: id, name: s.localizedName) }
        }
        return nil
    }

    @MainActor static func screen(_ id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { Self.id($0) == id } }
}

/// Watches for a TV being plugged in (and a controller connecting while one is), and for Theatre's TV going away.
@MainActor
final class TheatreWatch {
    static let shared = TheatreWatch()
    private weak var model: AppModel?
    private var observer: NSObjectProtocol?
    /// the TV last offered for: it is not offered again until it has been unplugged
    private var offered: CGDirectDisplayID?

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // a moment after the window is up, so a TV already plugged in at launch is offered too; Settings › Open on › Theatre opens it
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if model.settings.startIn == .theatre, !model.theatre, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { model.enterTheatre() }
            self?.check()
        }
    }

    func check() {
        guard let m = model, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        let tv = TVScreens.find()
        if m.theatre, let id = m.theatreScreen, TVScreens.screen(id) == nil { m.leaveTheatre(tvGone: true) }
        guard let tv else { offered = nil; if m.theatreOffer != nil { m.theatreOffer = nil }; return }
        guard !m.theatre, offered != tv.id, !m.standby else { return }
        switch m.settings.theatreOnTV {
        case .never: return
        case .always: offered = tv.id; m.enterTheatre(on: tv)
        case .ask:
            // only with a controller to hand: a TV used as a big monitor at a desk is left alone
            guard !GCController.controllers().isEmpty else { return }
            offered = tv.id
            m.theatreOffer = tv
        }
    }
}

extension AppModel {
    var mainWindow: NSWindow? { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? NSApp.mainWindow ?? NSApp.keyWindow }

    func toggleTheatre() { if theatre { leaveTheatre() } else { enterTheatre() } }

    /// Theatre on the TV (the first one found, else the screen the window is on), full screen
    func enterTheatre() { enterTheatre(on: TVScreens.find()) }

    func enterTheatre(on tv: TVScreen?) {
        theatreOffer = nil
        guard !theatre else { return }
        stageSettings = false
        playOptions = nil
        gameDetail = nil
        preview = nil
        frontEnd = true
        theatreMenu = nil
        theatreTheme = settings.theatreTheme
        theatreTouched = Date()
        theatreSaver = false
        // where Theatre was left: its filter, and the game in focus (else the one played last)
        theatreFilter = TheatreFilter(key: settings.theatreFilter)
        if !theatreFilters().contains(theatreFilter) { theatreFilter = .all }
        if theatreFocus == nil {
            let games = theatreGames()
            theatreFocus = games.first { $0.id == settings.theatreLastGame }?.id ?? Self.lastPlayed(games)?.id ?? games.first?.id
        }
        theatreSpinning = false
        theatreCurtain = nil
        theatre = true
        // a new arrival's spotlight, else welcome back on the game played last (TheatreDelight.swift)
        theatreOpeningMoment()
        theatreScreen = tv?.id
        theatreActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Theatre is on screen")
        guard ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil, let w = mainWindow else { return }
        NSCursor.setHiddenUntilMouseMoves(true)
        let full = w.styleMask.contains(.fullScreen)
        let target = tv.flatMap { TVScreens.screen($0.id) }
        if let target, w.screen != target {
            // to the TV first: out of full screen on the other screen if need be, then across, then full screen there
            theatreSavedFrame = theatreSavedFrame ?? (full ? nil : w.frame)
            Task { @MainActor [weak self] in
                if full { w.toggleFullScreen(nil); try? await Task.sleep(for: .seconds(1)) }
                w.setFrame(target.visibleFrame, display: true)
                try? await Task.sleep(for: .milliseconds(150))
                if !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
                self?.theatreMadeFullScreen = true
            }
        } else if !full {
            theatreSavedFrame = nil
            theatreMadeFullScreen = true
            w.toggleFullScreen(nil)
        }
    }

    /// Back to the window as it was; `tvGone`: the TV was unplugged, so macOS has already moved the window
    func leaveTheatre(tvGone: Bool = false) {
        guard theatre else { return }
        theatre = false
        theatreMenu = nil
        theatreWatch = false
        theatreSaver = false
        theatreMoment = nil
        theatreSpinning = false
        theatreCurtain = nil
        TheatreMusic.shared.play(nil, volume: 0)
        rememberTheatreFocus()
        if let a = theatreActivity { ProcessInfo.processInfo.endActivity(a); theatreActivity = nil }
        guard let w = mainWindow else { return }
        let saved = theatreSavedFrame, made = theatreMadeFullScreen
        theatreSavedFrame = nil
        theatreMadeFullScreen = false
        guard made, !tvGone else { return }
        Task { @MainActor in
            if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); try? await Task.sleep(for: .seconds(1)) }
            // back to the screen it came from, when that is still there
            if let saved, NSScreen.screens.contains(where: { $0.frame.intersects(saved) }) { w.setFrame(saved, display: true, animate: true) }
        }
    }

    /// The games on Theatre: the built ones (every game when none is built) in the filter, favourites first, then the ones played
    /// lately (newest first), then as the front end orders them
    func theatreGames() -> [StageGame] {
        let games = stageGames()
        let built = games.filter { $0.app != nil }
        return theatreOrder(theatreFiltered(built.isEmpty ? games : built))
    }

    /// Favourites first, then the games played in the last 30 days (the newest first), then the rest in the order given;
    /// Recently played is newest first throughout
    func theatreOrder(_ games: [StageGame]) -> [StageGame] {
        let now = Date()
        let byLast: (StageGame, StageGame) -> Bool = { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
        if theatreFilter == .recent { return games.sorted(by: byLast) }
        let favs = games.filter(\.favorite)
        let recent = games.filter { !$0.favorite && TheatreFilter.isRecent($0, now: now) }.sorted(by: byLast)
        let rest = games.filter { !$0.favorite && !TheatreFilter.isRecent($0, now: now) }
        return favs + recent + rest
    }

    /// The games in the filter; when it holds none of these (a favourite unbuilt, say), all of them, so Theatre is never empty
    func theatreFiltered(_ games: [StageGame]) -> [StageGame] {
        let out: [StageGame]
        switch theatreFilter {
        case .all: return games
        case .favourites: out = games.filter(\.favorite)
        case .recent: out = games.filter { TheatreFilter.isRecent($0) }
        case .genre(let g): out = games.filter { discover.genres(of: $0).contains(g) }
        }
        return out.isEmpty ? games : out
    }

    /// The stops L and R walk: All games, then Favourites and Recently played when there are any, then each genre your games are in
    func theatreFilters() -> [TheatreFilter] {
        let games = stageGames()
        var out: [TheatreFilter] = [.all]
        if games.contains(where: \.favorite) { out.append(.favourites) }
        if games.contains(where: { TheatreFilter.isRecent($0) }) { out.append(.recent) }
        out += discover.shelves(games).map { .genre($0) }
        return out
    }

    func stepTheatreFilter(_ d: Int) {
        let all = theatreFilters()
        guard all.count > 1 else { return }
        let i = all.firstIndex(of: theatreFilter) ?? 0
        theatreFilter = all[(i + d + all.count) % all.count]
        theatreRow = 0
        theatreWatch = false
        if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { settings.theatreFilter = theatreFilter.key }
        // the game in focus stays when it is in the filter, else the filter's first
        let games = theatreTheme == .trailer ? trailerGames() : theatreGames()
        if !games.contains(where: { $0.id == theatreFocus }) { theatreFocus = games.first?.id }
    }

    /// The game in focus is kept, so Theatre reopens on it (Settings › Open on › Theatre, or the next time it opens)
    func rememberTheatreFocus() {
        guard let f = theatreFocus, f != settings.theatreLastGame, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        settings.theatreLastGame = f
    }

    /// The main button's word on Theatre: Continue for a built game played before (quick resume), else Play or the step it needs
    func theatreAction(_ g: StageGame) -> String {
        let st = status(g)
        return st == .ready && g.last != nil ? "Continue" : st.action
    }

    /// What Theatre shows of a game once the focus rests on it: when it was played, its genre, players, size, and whether it is
    /// built (or what it needs). Only what is known.
    func theatreDetails(_ g: StageGame) -> [TheatreFact] {
        var out: [TheatreFact] = []
        if let l = g.last {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            out.append(TheatreFact(text: "Played " + f.localizedString(for: l, relativeTo: Date()), symbol: "clock.arrow.circlepath"))
        }
        let info = StoreInfoStore.shared.info(g.coverKey)
        if let genre = Genres.shown(titleID: g.titleID, store: info?.genres ?? []).first ?? discover.genres(of: g).first { out.append(TheatreFact(text: genre, symbol: "tag")) }
        if let p = info?.players { out.append(TheatreFact(text: p, symbol: (info?.playersTo ?? 1) > 1 ? "person.2.fill" : "person.fill")) }
        if let b = g.game?.bytes, b > 0 { out.append(TheatreFact(text: Disk.gb(b), symbol: "internaldrive")) }
        let st = status(g)
        out.append(st == .ready ? TheatreFact(text: "Built", symbol: "checkmark.seal.fill") : TheatreFact(text: st.text, symbol: st.symbol))
        return out
    }

    /// The trailer's volume, in tens; turning it up unmutes
    func stepTheatreVolume(_ d: Int) {
        if d > 0, theatreMuted { theatreMuted = false } else { settings.theatreVolume = min(max(settings.theatreVolume + d, 0), 100) }
        theatreVolumeTick += 1
    }

    /// The screensaver goes away (a button, a key or the pointer), and the TV may not sleep again while Theatre is up
    func wakeTheatre() {
        theatreSaver = false
        theatreTouched = Date()
        if theatre, theatreActivity == nil {
            theatreActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Theatre is on screen")
        }
    }

    /// Cinema's rows: Continue playing, Favourites, a row per genre, then the games not built yet; with a filter, its games
    func theatreRows() -> [TheatreRow] {
        let all = stageGames()
        // the games drive away (or nothing built yet): every game, so Theatre still has rows
        let built = all.contains { $0.app != nil } ? all.filter { $0.app != nil } : all
        if theatreFilter != .all { return [TheatreRow(title: theatreFilter.title, games: theatreOrder(theatreFiltered(built)))] }
        var rows: [TheatreRow] = []
        let recent = built.filter { $0.last != nil }.sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
        if !recent.isEmpty { rows.append(TheatreRow(title: "Continue playing", games: Array(recent.prefix(12)))) }
        let favs = built.filter(\.favorite)
        if !favs.isEmpty { rows.append(TheatreRow(title: "Favourites", games: favs)) }
        for g in discover.shelves(built) {
            let list = built.filter { discover.genres(of: $0).contains(g) }
            if !list.isEmpty { rows.append(TheatreRow(title: DiscoverState.plural(g), games: list)) }
        }
        let byName = built.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if rows.count < 3, !byName.isEmpty { rows.append(TheatreRow(title: "All games", games: byName)) }
        let unbuilt = all.filter { $0.app == nil }
        if !unbuilt.isEmpty, unbuilt.count < all.count { rows.append(TheatreRow(title: "Not built yet", games: unbuilt)) }
        return rows
    }

    /// The game in focus on Theatre: the one picked, else the one played last, else the first
    func theatreFocused(_ games: [StageGame]) -> StageGame? {
        games.first { $0.id == theatreFocus } ?? Self.lastPlayed(games) ?? games.first
    }

    /// Cinema's row the focus is in: the one chosen, when it still holds the game
    func cinemaRow(_ rows: [TheatreRow]) -> Int {
        if rows.indices.contains(theatreRow), rows[theatreRow].games.contains(where: { $0.id == theatreFocus }) { return theatreRow }
        return rows.firstIndex { $0.games.contains { $0.id == theatreFocus } } ?? 0
    }

    /// Trailer's strip: the games in the filter, built or not, favourites first, then the ones played lately, then as the front
    /// end orders them (built, recently played, by name)
    func trailerGames() -> [StageGame] { theatreOrder(theatreFiltered(stageGames())) }

    func setTheatreTheme(_ t: TheatreTheme) {
        theatreTheme = t
        theatreWatch = false
        if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { settings.theatreTheme = t }
    }

    /// A controller's button, or its key, on Theatre
    func theatrePad(_ k: PadKey) {
        theatreTouched = Date()
        NSCursor.setHiddenUntilMouseMoves(true)
        // the screensaver: any button wakes Theatre, and does nothing else
        if theatreSaver { wakeTheatre(); return }
        // the shuffle spinning: B stops it where it is, the rest wait for it to land
        if theatreSpinning { if k == .b { theatreSpinning = false }; return }
        // a moment's card goes at any button, which then does what it does (A plays the game the card is about)
        if theatreMoment != nil, k != .r3, k != .volUp, k != .volDown { theatreMoment = nil }
        let covered = stageSettings || viewerOpen || launching != nil || playOptions != nil || gameDetail != nil || caseViewer != nil
        // Theatre's sound (the trailer, the game's music, the clicks): the right stick's press mutes, up and down set the volume
        switch k {
        case .r3: if !covered { theatreMuted.toggle(); theatreVolumeTick += 1 }; return
        case .volUp, .volDown: if !covered, theatreMenu == nil { stepTheatreVolume(k == .volUp ? 10 : -10) }; return
        default: break
        }
        if let i = theatreMenu {
            let rows = TheatreMenuRow.allCases
            switch k {
            case .up: if i > 0 { theatreCue(.step) }; theatreMenu = max(i - 1, 0)
            case .down: if i < rows.count - 1 { theatreCue(.step) }; theatreMenu = min(i + 1, rows.count - 1)
            case .left, .right: if rows[i] == .edges { settings.theatreEdges = settings.theatreEdges.step(k == .left ? -1 : 1) }
            case .a: pickTheatreMenu(rows[i])
            case .b, .menu: theatreMenu = nil
            default: break
            }
            return
        }
        // Trailer's Watch: any button brings Browse back, and does nothing else
        if theatreTheme == .trailer, theatreWatch { theatreWatch = false; return }
        // the game's page, Play options, the launch screen, Settings and the viewers work as on the front end
        if covered { stagePad(k); return }
        let focus: StageGame?
        switch theatreTheme {
        case .carousel, .gallery, .trailer:
            let games = theatreTheme == .trailer ? trailerGames() : theatreGames()
            focus = theatreFocused(games)
            if k == .down, theatreTheme == .trailer { theatreWatch = true; return }
            if (k == .left || k == .right), !games.isEmpty {
                let i = games.firstIndex { $0.id == focus?.id } ?? 0
                theatreFocus = games[(i + (k == .left ? -1 : 1) + games.count) % games.count].id
                if games.count > 1 { theatreCue(theatreTheme == .carousel ? .turn : .step) }
                return
            }
        case .cinema:
            let rows = theatreRows()
            guard !rows.isEmpty else { focus = nil; break }
            let r = cinemaRow(rows)
            let list = rows[r].games
            let c = list.firstIndex { $0.id == theatreFocus } ?? 0
            switch k {
            case .left: if c > 0 { theatreCue(.step) }; theatreFocus = list[max(c - 1, 0)].id; theatreRow = r; return
            case .right: if c < list.count - 1 { theatreCue(.step) }; theatreFocus = list[min(c + 1, list.count - 1)].id; theatreRow = r; return
            case .up, .down:
                let nr = min(max(r + (k == .up ? -1 : 1), 0), rows.count - 1)
                if nr != r { theatreCue(.step) }
                theatreRow = nr
                theatreFocus = rows[nr].games[min(c, rows[nr].games.count - 1)].id
                return
            default: focus = list.indices.contains(c) ? list[c] : list.first
            }
        }
        switch k {
        case .a:
            // plays it, or does the step that stops it from playing (docs/ux.md); the place is kept for next time
            if let g = focus { theatreFocus = g.id; rememberTheatreFocus(); fix(g) }
        case .y: if let g = focus { caseFlipped = false; gameDetail = g.ref }
        case .x: if let g = focus, g.app != nil { openPlayOptions(g.ref) }
        // L and R: the filter; ZL and ZR: the theme
        case .l, .r: stepTheatreFilter(k == .l ? -1 : 1); theatreCue(.step)
        case .zl, .zr:
            let all = TheatreTheme.allCases
            let i = all.firstIndex(of: theatreTheme) ?? 0
            setTheatreTheme(all[(i + (k == .zl ? -1 : 1) + all.count) % all.count])
            theatreCue(.theme)
        case .menu: theatreMenu = TheatreMenuRow.row(theatreTheme).rawValue; theatreCue(.open)
        case .b: theatreMenu = TheatreMenuRow.leave.rawValue; theatreCue(.open)
        case .options: if let g = focus { toggleFavorite(g); theatreCue(.step) }
        // the left stick's press: what should I play?
        case .l3: shuffleTheatre()
        default: break
        }
    }

    func pickTheatreMenu(_ r: TheatreMenuRow) {
        theatreMenu = nil
        switch r {
        case .carousel, .cinema, .gallery, .trailer: if let t = r.theme { setTheatreTheme(t); theatreCue(.theme) }
        case .shuffle: shuffleTheatre()
        // A steps the edges round and keeps the menu up, so the corners stay in view
        case .edges:
            let all = TheatreEdges.allCases
            settings.theatreEdges = all[((all.firstIndex(of: settings.theatreEdges) ?? 0) + 1) % all.count]
            theatreMenu = r.rawValue
        case .settings: settingsFocus = StageSettingRow.theatreTheme.rawValue; stageSettings = true
        case .leave: leaveTheatre()
        }
    }

    /// The offer on a TV: A opens Theatre, B says not now
    func offerPad(_ k: PadKey) {
        switch k {
        case .a: enterTheatre(on: theatreOffer)
        case .b: theatreOffer = nil
        case .x: if let tv = theatreOffer { settings.theatreOnTV = .always; enterTheatre(on: tv) }
        case .y: settings.theatreOnTV = .never; theatreOffer = nil
        default: break
        }
    }
}

struct TheatreRow: Identifiable {
    var id: String { title }
    let title: String
    let games: [StageGame]
}

/// Sizes on Theatre are for a 1080-line picture, scaled to the window: a 4K TV at full resolution gets the same layout, twice the size
private struct TheatreUnit: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var tu: CGFloat {
        get { self[TheatreUnit.self] }
        set { self[TheatreUnit.self] = newValue }
    }
}

struct TheatreView: View {
    @Bindable var model: AppModel
    @FocusState private var keys: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    /// the volume card is up (a moment after each change)
    @State private var hud = false
    /// the launch screen may show under the lights going down (it waits until the box's light fills the room)
    @State private var revealed = true
    /// NXForge is the active app (the game's music stops while a game is in front)
    @State private var active = NSApp.isActive || ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil

    var body: some View {
        GeometryReader { geo in
            // a TV that crops its edges: the whole picture inset, black round it (Settings › Theatre › TV edges)
            let e = model.settings.theatreEdges.inset
            let size = CGSize(width: geo.size.width * (1 - 2 * e), height: geo.size.height * (1 - 2 * e))
            // a 1080th of the height, or of a 16:10 width on a narrower screen, so nothing runs off the sides
            let u = max(min(size.height / 1080, size.width / 1728), 0.5)
            ZStack {
                Color.black
                ZStack {
                    if let r = model.gameDetail, model.stageGames().contains(where: { $0.isRef(r) }) {
                        // the game's page, as on the front end (B comes back here)
                        StageView(model: model).transition(.opacity)
                    } else {
                        if model.theatreSaver {
                            TheatreScreensaver(model: model).frame(width: size.width, height: size.height).clipped().transition(.opacity)
                        } else {
                            stage.frame(width: size.width, height: size.height).clipped()
                        }
                        // the room's light by the time of day (Settings › Theatre)
                        if model.settings.theatreTimeOfDay { TheatreDaylightWash().frame(width: size.width, height: size.height) }
                        if let m = model.theatreMoment, !model.theatreSaver, model.theatreMenu == nil, model.launching == nil {
                            TheatreMomentCard(model: model, moment: m, width: size.width, height: size.height).id(m.id).transition(.opacity)
                        }
                        if model.theatreConfetti > 0 {
                            let tint = model.stageGames().first { $0.id == model.theatreMoment?.game }.map { CoverArt.tint($0) } ?? Color(red: 1, green: 0.8, blue: 0.4)
                            TheatreConfetti(tint: tint, frozen: ProcessInfo.processInfo.environment["NXC_CONFETTI"].flatMap(Double.init))
                                .id(model.theatreConfetti).frame(width: size.width, height: size.height)
                        }
                        overlays.frame(width: size.width, height: size.height)
                        if let c = model.theatreCurtain { TheatreLightsDown(model: model, curtain: c).id(c.id).frame(width: size.width, height: size.height) }
                    }
                    if hud { TheatreVolumeCard(volume: model.settings.theatreVolume, muted: model.theatreMuted).frame(width: size.width, height: size.height, alignment: .topTrailing).transition(.opacity) }
                    // choosing the edges in the menu: the picture's four corners, to check they all show on the TV
                    if model.theatreMenu == TheatreMenuRow.edges.rawValue { TheatreEdgeMarks().frame(width: size.width, height: size.height).allowsHitTesting(false) }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .environment(\.tu, u)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.3), value: model.theatreTheme)
        .animation(.spring(duration: 0.3), value: model.theatreMenu)
        .animation(.easeInOut(duration: 0.25), value: model.gameDetail)
        .animation(.spring(duration: 0.35), value: model.playOptions?.id)
        .animation(.easeInOut(duration: 0.3), value: model.launching?.id)
        .animation(.easeInOut(duration: 1.2), value: model.theatreSaver)
        .animation(.easeInOut(duration: 0.3), value: hud)
        .animation(.easeInOut(duration: 0.3), value: model.settings.theatreEdges)
        .focusable()
        .focused($keys)
        .focusEffectDisabled()
        .onAppear { keys = true }
        .onChange(of: model.gameDetail) { _, d in if d == nil { keys = true } }
        .onKeyPress(.leftArrow) { model.theatrePad(.left); return .handled }
        .onKeyPress(.rightArrow) { model.theatrePad(.right); return .handled }
        .onKeyPress(.upArrow) { model.theatrePad(.up); return .handled }
        .onKeyPress(.downArrow) { model.theatrePad(.down); return .handled }
        .onKeyPress(.return) { model.theatrePad(.a); return .handled }
        .onKeyPress(.space) { model.theatrePad(.y); return .handled }
        .onKeyPress(.escape) { model.theatrePad(.b); return .handled }
        .onKeyPress(.tab) { model.theatrePad(.zr); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { _ in model.theatrePad(.x); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "mM")) { _ in model.theatrePad(.menu); return .handled }
        // [ and ] the filter (L, R), , and . the theme (ZL, ZR)
        .onKeyPress(characters: CharacterSet(charactersIn: "[")) { _ in model.theatrePad(.l); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "]")) { _ in model.theatrePad(.r); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: ",<")) { _ in model.theatrePad(.zl); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: ".>")) { _ in model.theatrePad(.zr); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in model.theatrePad(.options); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "sS")) { _ in model.theatrePad(.r3); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in model.theatrePad(.volDown); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "=+")) { _ in model.theatrePad(.volUp); return .handled }
        // ? the shuffle (L3)
        .onKeyPress(characters: CharacterSet(charactersIn: "?/")) { _ in model.theatrePad(.l3); return .handled }
        // the genres for Cinema's rows and the filters, and the art the games still lack
        .task(id: model.stageGames().compactMap(\.titleID).joined(separator: ",")) { model.discover.load(model.stageGames().compactMap(\.titleID)) }
        .task(id: "theatre-covers") { model.fetchCovers(model.stageGames()) }
        // the focus rests on a game for a moment: its details show, its store details are read, and it is kept for next time
        .task(id: model.theatreFocus) {
            let snap = ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil
            model.theatreRested = snap
            let games = model.stageGames()
            if let g = games.first(where: { $0.id == model.theatreFocus }), model.settings.downloadStoreInfo {
                StoreInfoStore.shared.load(key: g.coverKey, titleID: g.titleID, name: g.name)
            }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            model.theatreRested = true
            // kept only when you moved to it, not when the carousel turned by itself
            if Date().timeIntervalSince(model.theatreTouched) < 4 { model.rememberTheatreFocus() }
        }
        // a moment's card, for its time
        .task(id: model.theatreMoment?.id) {
            guard let m = model.theatreMoment, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
            try? await Task.sleep(for: .seconds(m.seconds))
            if !Task.isCancelled, model.theatreMoment?.id == m.id { model.theatreMoment = nil }
        }
        // confetti clears itself after its burst
        .task(id: model.theatreConfetti) {
            guard model.theatreConfetti > 0, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
            try? await Task.sleep(for: .seconds(TheatreConfetti.length + 0.2))
            if !Task.isCancelled { model.theatreConfetti = 0 }
        }
        // the lights go down as a game starts from Theatre, and the launch screen comes up under the box's light
        .onChange(of: model.launching?.id) { old, new in
            if old == nil, new != nil, let l = model.launching { model.theatreLightsDown(l) }
        }
        .task(id: model.theatreCurtain?.id) {
            guard let c = model.theatreCurtain else { revealed = true; return }
            revealed = false
            if c.frozen != nil { return }
            try? await Task.sleep(for: .seconds(TheatreCurtain.reveal))
            revealed = true
            try? await Task.sleep(for: .seconds(TheatreCurtain.length - TheatreCurtain.reveal))
            if model.theatreCurtain?.id == c.id { model.theatreCurtain = nil }
        }
        // the focused game's music, once the focus rests on it (not on Trailer, which has its own sound)
        .task(id: musicKey) {
            let volume = model.theatreMuted ? 0 : Float(model.settings.theatreVolume) / 100 * 0.3
            guard let id = musicGame, let g = model.stageGames().first(where: { $0.id == id }) else { TheatreMusic.shared.play(nil, volume: 0); return }
            let url = await TheatreMusic.find(g, model: model)
            guard !Task.isCancelled else { return }
            TheatreMusic.shared.play(url, volume: volume)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in active = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { active = false }
        }
        .onDisappear {
            TheatreMusic.shared.play(nil, volume: 0)
            TheatreSound.shared.rest()
        }
        // the volume card, for a moment after each change
        .task(id: model.theatreVolumeTick) {
            guard model.theatreVolumeTick > 0 else { return }
            hud = true
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { hud = false }
        }
        // left alone for the screensaver's time, the screensaver; an hour into it, the TV may sleep
        .task(id: "saver") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil, let wait = model.settings.theatreSaver.seconds else { continue }
                let idle = Date().timeIntervalSince(model.theatreTouched)
                if model.theatreSaver {
                    if idle > wait + 3600, let a = model.theatreActivity { ProcessInfo.processInfo.endActivity(a); model.theatreActivity = nil }
                    continue
                }
                guard idle > wait, model.theatreMenu == nil, !model.stageSettings, model.gameDetail == nil, model.launching == nil,
                      model.playOptions == nil, !model.viewerOpen, model.caseViewer == nil else { continue }
                model.theatreWatch = false
                model.theatreSaver = true
            }
        }
        // Trailer: left alone for 6 s, the words fade and the trailer takes the room
        .task(id: "watch") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard model.theatreTheme == .trailer, !model.theatreWatch, !model.theatreSaver, model.theatreMenu == nil, !model.stageSettings, model.gameDetail == nil,
                      model.launching == nil, model.playOptions == nil, !model.viewerOpen, model.caseViewer == nil, NSApp.isActive,
                      Date().timeIntervalSince(model.theatreTouched) > 6, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { continue }
                model.theatreWatch = true
            }
        }
        // left alone, the carousel turns on by itself, a game every few seconds, like a turntable in a shop window
        .task(id: "idle") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !still, model.theatreTheme == .carousel, !model.theatreSaver, model.theatreMenu == nil, !model.stageSettings, model.gameDetail == nil,
                      model.launching == nil, model.playOptions == nil, !model.viewerOpen, NSApp.isActive,
                      Date().timeIntervalSince(model.theatreTouched) > 12, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { continue }
                let games = model.theatreGames()
                guard games.count > 1, let i = games.firstIndex(where: { $0.id == model.theatreFocused(games)?.id }) else { continue }
                if Int(Date().timeIntervalSince(model.theatreTouched)) % 5 == 0 { model.theatreFocus = games[(i + 1) % games.count].id }
            }
        }
    }

    /// The game whose music plays: the one in focus once it has rested there, while Theatre is in front and quiet
    var musicGame: String? {
        guard model.settings.theatreMusic, model.theatreTheme != .trailer, model.theatreRested, active, !model.theatreSpinning, !model.theatreSaver,
              model.launching == nil, model.theatreCurtain == nil, !model.viewerOpen, model.playing.isEmpty,
              ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return nil }
        return model.theatreFocus
    }

    var musicKey: String { "\(musicGame ?? "-")|\(model.theatreMuted)|\(model.settings.theatreVolume)" }

    @ViewBuilder var stage: some View {
        switch model.theatreTheme {
        case .carousel: CarouselTheme(model: model).transition(.opacity)
        case .cinema: CinemaTheme(model: model).transition(.opacity)
        case .trailer: TrailerTheme(model: model).transition(.opacity)
        case .gallery: GalleryTheme(model: model).transition(.opacity)
        }
    }

    @ViewBuilder var overlays: some View {
        let games = model.stageGames()
        if let o = model.playOptions {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.closePlayOptions() }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PlayOptionsPanel(model: model, state: o)
            }
            .padding(24)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        if let s = model.caseViewer { CaseViewer(model: model, state: s).id(s.game.id).transition(.opacity) }
        if let g = model.gallery { GalleryViewer(model: model, state: g).id(g.id).transition(.opacity) }
        if let m = model.manual { ManualViewer(model: model, state: m).id(m.id).transition(.opacity) }
        if let l = model.launching, revealed || model.theatreCurtain == nil || l.failure != nil {
            LaunchScreen(model: model, launch: l, game: games.first { $0.isRef(l.ref) }).transition(.opacity)
        }
        if model.viewerOpen { ViewerKeys(model: model) }
        if let i = model.theatreMenu { TheatreMenu(model: model, focus: i).transition(.opacity.combined(with: .scale(scale: 0.97))) }
    }
}

/// The wordmark at the top left, the filter in the middle, the theme and the time at the top right
struct TheatreTopBar: View {
    let theme: TheatreTheme
    /// for the filter in the middle
    var model: AppModel? = nil
    /// the words' colour: white on the dark themes, a warm near-black on Gallery's ivory wall
    var ink: Color = .white
    /// the theme's name in a capsule, or as plain words (Gallery)
    var pill = true
    @Environment(\.tu) private var u

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                Text("NX").font(.system(size: 22 * u, weight: .heavy))
                Text("FORGE").font(.system(size: 22 * u, weight: .light))
            }
            .tracking(7 * u).opacity(0.9)
            Spacer()
            if pill {
                Text(theme.rawValue.uppercased()).font(.system(size: 16 * u, weight: .semibold)).tracking(2.4 * u)
                    .padding(.horizontal, 16 * u).frame(height: 38 * u)
                    .background(ink.opacity(0.10), in: .capsule).overlay(Capsule().strokeBorder(ink.opacity(0.16), lineWidth: 1))
            } else {
                Text(theme.rawValue).font(.system(size: 26 * u, weight: .medium))
            }
            TimelineView(.everyMinute) { t in
                HStack(spacing: 10 * u) {
                    // the time of day the room's light follows
                    if model?.settings.theatreTimeOfDay == true { Image(systemName: TheatreDaylight.now.symbol).font(.system(size: 20 * u, weight: .semibold)).symbolRenderingMode(.hierarchical) }
                    Text(t.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 24 * u, weight: .medium)).monospacedDigit()
                }
                .padding(.leading, 22 * u).opacity(0.88)
            }
        }
        .padding(.horizontal, 96 * u).frame(height: 120 * u)
        .overlay { if let model { TheatreFilterChip(model: model, ink: ink) } }
        .foregroundStyle(ink)
    }
}

/// The filter L and R walk, between their buttons: "L  ‹ Favourites ›  R", with how many there are
struct TheatreFilterChip: View {
    let model: AppModel
    var ink: Color = .white
    @Environment(\.tu) private var u

    var body: some View {
        let all = model.theatreFilters()
        if all.count > 1 {
            let i = all.firstIndex(of: model.theatreFilter) ?? 0
            HStack(spacing: 14 * u) {
                TheatreHints(model: model, light: ink != .white).glyph("L")
                VStack(spacing: 2 * u) {
                    Text(model.theatreFilter.title).font(.system(size: 20 * u, weight: .semibold)).lineLimit(1)
                    // a dot a filter while there are few; with many genres a row of dots is only noise, so "3 of 17"
                    if all.count <= 8 {
                        HStack(spacing: 5 * u) {
                            ForEach(all.indices, id: \.self) { k in
                                Circle().fill(ink.opacity(k == i ? 0.95 : 0.3)).frame(width: 5 * u, height: 5 * u)
                            }
                        }
                    } else {
                        Text("\(i + 1) of \(all.count)").font(.system(size: 13 * u, weight: .medium)).monospacedDigit().opacity(0.55)
                    }
                }
                .frame(minWidth: 180 * u)
                TheatreHints(model: model, light: ink != .white).glyph("R")
            }
            .padding(.horizontal, 16 * u).padding(.vertical, 8 * u)
            .background(ink.opacity(0.08), in: .capsule)
            .animation(.easeInOut(duration: 0.25), value: model.theatreFilter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Filter: \(model.theatreFilter.title), L and R change it")
        }
    }
}

/// The buttons along the foot: the controller's own symbols when one is connected (PadGlyph)
struct TheatreHints: View {
    let model: AppModel
    var focus: StageGame?
    /// on a light wall: dark words, and the button symbols turned dark (PadGlyph draws them light)
    var light = false
    /// ZL and ZR for the theme (Gallery leaves theme switching to the menu)
    var themes = true
    /// L and R for the filter
    var filters = true
    /// L3 for the shuffle (off on the themes' feet, which are full: it is in the Theatre menu and on the shuffle's card)
    var shuffle = false
    var back = "Leave"
    var size: CGFloat = 20
    @Environment(\.tu) private var u

    var body: some View {
        // every action on Theatre has a button, so it is all drivable from the sofa without a keyboard
        HStack(spacing: 30 * u) {
            if let g = focus {
                // the same word as the main button: Continue, Play, or the step that stops it playing (docs/ux.md, Status words)
                hint("A", model.theatreAction(g), filled: true)
                hint("Y", "Details")
                if g.app != nil { hint("X", "Options") }
            }
            if filters, model.theatreFilters().count > 1 { hint("L", "R", "Filter") }
            if shuffle { hint("L3", "Shuffle") }
            if themes { hint("ZL", "ZR", "Theme") }
            hint("+", "Menu")
            hint("B", back)
        }
        .font(.system(size: size * u, weight: .medium))
        .foregroundStyle(light ? GalleryTheme.ink : .white.opacity(0.82))
    }

    /// a button's symbol, half as big again as on the front end (it is drawn at a fixed size, so scaled into its own frame)
    func glyph(_ k: String, filled: Bool = false) -> some View {
        PadGlyph(text: k, filled: filled, dark: light).fixedSize().scaleEffect(u * 1.4).frame(width: (k.count > 1 ? 38 : 30) * u * 1.4, height: 24 * u * 1.4)
    }

    func hint(_ k: String, _ text: String, filled: Bool = false) -> some View {
        HStack(spacing: 8 * u) { glyph(k, filled: filled); Text(text) }
    }

    func hint(_ k1: String, _ k2: String, _ text: String) -> some View {
        HStack(spacing: 8 * u) { glyph(k1); glyph(k2); Text(text) }
    }
}

struct TheatreMenu: View {
    let model: AppModel
    let focus: Int
    @Environment(\.tu) private var u

    var body: some View {
        let games = model.theatreTheme == .trailer ? model.trailerGames() : model.theatreGames()
        let tint = model.theatreFocused(games).map { CoverArt.tint($0) } ?? .clear
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { model.theatreMenu = nil }
            VStack(alignment: .leading, spacing: 8 * u) {
                Text("Theatre").font(.system(size: 40 * u, weight: .bold)).padding(.bottom, 14 * u)
                ForEach(TheatreMenuRow.allCases, id: \.self) { r in
                    let on = r.rawValue == focus
                    let current = r.theme == model.theatreTheme
                    Button { model.pickTheatreMenu(r) } label: {
                        HStack(spacing: 18 * u) {
                            Image(systemName: icon(r)).font(.system(size: 24 * u, weight: .semibold)).frame(width: 34 * u)
                            VStack(alignment: .leading, spacing: 3 * u) {
                                Text(r.title).font(.system(size: 26 * u, weight: .semibold))
                                if let n = note(r) { Text(n).font(.system(size: 17 * u)).foregroundStyle(on ? Color.black.opacity(0.6) : StageLook.faint) }
                            }
                            Spacer()
                            if current { Image(systemName: "checkmark").font(.system(size: 22 * u, weight: .bold)) }
                            if r == .edges {
                                HStack(spacing: 10 * u) {
                                    Image(systemName: "chevron.left").opacity(on ? 1 : 0)
                                    Text(model.settings.theatreEdges.title).font(.system(size: 20 * u, weight: .semibold)).monospacedDigit()
                                    Image(systemName: "chevron.right").opacity(on ? 1 : 0)
                                }
                            }
                        }
                        .padding(.horizontal, 24 * u).padding(.vertical, 16 * u)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background(on ? Color.white : Color.white.opacity(0.06), in: .rect(cornerRadius: 18 * u))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if r == .trailer || r == .edges { Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 8 * u) }
                }
            }
            .padding(40 * u)
            .frame(width: 620 * u)
            .background(StageLook.panel.opacity(0.85), in: .rect(cornerRadius: 34 * u))
            // the room's colour, from the game in focus
            .background(LinearGradient(colors: [tint.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 34 * u))
            .glassEffect(.regular, in: .rect(cornerRadius: 34 * u))
            .shadow(color: .black.opacity(0.6), radius: 60 * u, y: 30 * u)
        }
    }

    func icon(_ r: TheatreMenuRow) -> String {
        switch r {
        case .carousel, .cinema, .gallery, .trailer: r.theme?.symbol ?? ""
        case .shuffle: "dice"
        case .edges: "rectangle.dashed"
        case .settings: "gearshape"
        case .leave: "rectangle.portrait.and.arrow.right"
        }
    }

    func note(_ r: TheatreMenuRow) -> String? {
        switch r {
        case .carousel, .cinema, .gallery, .trailer: r.theme?.note
        case .shuffle: "Spin the shelf and land on a game (L3)"
        case .edges: "Can you see all four corners? ← → to inset the picture"
        case .settings: nil
        case .leave: "Back to the window on your Mac"
        }
    }
}

/// The card NXForge shows when a TV is plugged in while a controller is connected
struct TheatreOffer: View {
    @Bindable var model: AppModel
    let tv: TVScreen

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "tv").font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                Text("Open Theatre on \(tv.name)?").font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
                Text("Your games full screen on the TV, for the sofa and a controller. Leave it any time with B.")
                    .font(.system(size: 15)).foregroundStyle(StageLook.soft).multilineTextAlignment(.center).frame(maxWidth: 400)
                HStack(spacing: 12) {
                    Button { model.theatreOffer = nil } label: { HStack(spacing: 8) { PadGlyph(text: "B"); Text("Not Now") } }
                        .buttonStyle(StageButton())
                    Button { model.enterTheatre(on: tv) } label: { HStack(spacing: 8) { PadGlyph(text: "A", filled: true); Text("Open Theatre") } }
                        .buttonStyle(StageButton(primary: true))
                }
                .padding(.top, 6)
                HStack(spacing: 18) {
                    Button { model.settings.theatreOnTV = .always; model.enterTheatre(on: tv) } label: { HStack(spacing: 6) { PadGlyph(text: "X"); Text("Always open it on a TV") } }
                    Button { model.settings.theatreOnTV = .never; model.theatreOffer = nil } label: { HStack(spacing: 6) { PadGlyph(text: "Y"); Text("Never ask") } }
                }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.faint)
            }
            .padding(36)
            .frame(width: 520)
            .background(StageLook.panel.opacity(0.85), in: .rect(cornerRadius: 28))
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Carousel

/// A ring of the games' real boxes, seen from a little above so the far side shows behind; the one in front steps out onto a
/// floor that reflects it, and the room takes its colour from the game's art. Left and right turn it, the right stick spins the
/// box in front, and left alone it turns on by itself.
struct CarouselTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u

    var body: some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        ZStack {
            StageBackdrop(tint: focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75), art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "")
            // a soft light from above, on the box in front
            RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.92).opacity(0.14), .clear], center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: 560 * u)
                .ignoresSafeArea().allowsHitTesting(false)
            // the room darkens smoothly down to the floor, which is all but clear, so there is no line where the floor ends
            LinearGradient(stops: [.init(color: .clear, location: 0.04), .init(color: .black.opacity(0.42), location: 0.24), .init(color: .black.opacity(0.62), location: 0.6)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            // a pool of light on the floor where the box in front stands, warmed by the game's colour
            GeometryReader { geo in
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.16), (focus.map { CoverArt.tint($0) } ?? .white).opacity(0.10), .clear],
                                         center: .center, startRadius: 0, endRadius: 420 * u))
                    .frame(width: 840 * u, height: 190 * u)
                    .blur(radius: 18 * u)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.655)
            }
            .ignoresSafeArea().allowsHitTesting(false)
            TheatreCarousel(games: games, focus: index, revision: CoverStore.shared.revision)
                .ignoresSafeArea()
            // the room's sides fall into shadow, so the eye goes to the middle
            RadialGradient(colors: [.clear, .black.opacity(0.5)], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 520 * u, endRadius: 1250 * u)
                .ignoresSafeArea().allowsHitTesting(false)
            // the foot of the room darkens under the caption
            LinearGradient(stops: [.init(color: .clear, location: 0.66), .init(color: .black.opacity(0.85), location: 0.9), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                TheatreTopBar(theme: .carousel, model: model)
                Spacer()
                if let g = focus {
                    VStack(spacing: 14 * u) {
                        Text(g.name).font(.system(size: 64 * u, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.6), radius: 18 * u, y: 4 * u)
                        Text(Self.facts(g)).font(.system(size: 22 * u, weight: .regular)).tracking(1.2 * u).foregroundStyle(StageLook.soft)
                        TheatreDetails(model: model, game: g, showSize: false).padding(.top, 2 * u)
                    }
                    .id(g.id).transition(.opacity)
                    .padding(.horizontal, 120 * u)
                }
                HStack(alignment: .bottom) {
                    if !games.isEmpty {
                        (Text(String(format: "%02d", index + 1)).foregroundStyle(.white).fontWeight(.semibold) + Text("  /  " + String(format: "%02d", games.count) + "   GAMES").foregroundStyle(StageLook.faint))
                            .font(.system(size: 19 * u)).tracking(3 * u).monospacedDigit()
                    }
                    Spacer()
                    TheatreHints(model: model, focus: focus)
                }
                .padding(.horizontal, 96 * u).padding(.top, 36 * u).padding(.bottom, 42 * u)
            }
            .animation(TheatreMotion.swapAnimation, value: focus?.id)
        }
    }

    static func facts(_ g: StageGame) -> String {
        var out: [String] = []
        if let p = g.game?.publisher, !p.isEmpty { out.append(p) }
        out.append(g.console.rawValue)
        if let b = g.game?.bytes, b > 0 { out.append(Disk.gb(b)) }
        out.append(g.total > 60 ? "\(Playtime.text(g.total)) played" : g.app == nil ? "Not built yet" : "Not played yet")
        return out.joined(separator: "   ·   ")
    }
}

/// Which game each of the ring's places shows: the ring has `slots` places and turns one place a step, so the places out of
/// sight behind take the next games along as it turns, and any number of games goes round a ring of 12 to 16. Five games or
/// more always make a full ring of at least 12, so two boxes show either side of the one in front (a ring of 8 showed one
/// either side, turned almost edge on); fewer than five make a ring that small, so no game shows twice.
enum CarouselRing {
    static func slots(for count: Int) -> Int { count < 5 ? max(count, 1) : min(max(count, 12), 16) }

    /// the game in place `slot` with the ring at step `position` (the place in front is position mod slots): the game that many
    /// places along from the one in front, either way round, wrapping at the ends of the list
    static func game(slot: Int, position: Int, slots: Int, count: Int) -> Int {
        guard slots > 0, count > 0 else { return 0 }
        let front = ((position % slots) + slots) % slots
        var d = ((slot - front) % slots + slots) % slots
        if d >= (slots + 1) / 2 { d -= slots }
        return (((position + d) % count) + count) % count
    }
}

struct TheatreCarousel: NSViewRepresentable {
    let games: [StageGame]
    /// the game in front, in `games`
    let focus: Int
    /// CoverStore's: new art reaches the boxes
    let revision: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let v = CaseSCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.scene = context.coordinator.scene
        v.delegate = context.coordinator
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        context.coordinator.update(games: games, focus: focus)
        v.pointOfView = context.coordinator.camera
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        context.coordinator.update(games: games, focus: focus)
        if v.pointOfView !== context.coordinator.camera { v.pointOfView = context.coordinator.camera }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let scene = SCNScene()
        private let ring = SCNNode()
        private(set) var camera: SCNNode?
        private var boxes: [TheatreBox] = []
        private var slots = 0
        /// the ring's step: grows or shrinks by one a step, either way round, never jumping back across the ends of the list
        private var position = 0
        private var lastFocus: Int?
        private var lastCount = 0
        // read by the render loop: plain numbers
        private var angle = 0.0
        private var target = 0.0
        private var front = 0
        private var spin = 0.0
        private var last = 0.0
        var still = false
        static let spacing = 1.7
        /// how far the boxes beside the front one turn back towards you (0 none, 1 all the way)
        static let toward = 0.45

        var radius: Double { max(Double(slots) * Self.spacing / (2 * .pi), 1.6) }

        static let floorAlpha: CGFloat = 0   // the reflections still show on a clear floor

        override init() {
            super.init()
            scene.rootNode.addChildNode(ring)
            // a dark floor that reflects the boxes, fading out with distance
            let floor = SCNFloor()
            floor.reflectivity = 0.18
            floor.reflectionFalloffStart = 0
            // the reflection fades out a third of the way down the box, before the caption
            floor.reflectionFalloffEnd = 0.6
            floor.reflectionResolutionScaleFactor = 0.6
            let m = SCNMaterial()
            m.diffuse.contents = NSColor(white: 0.02, alpha: 1)
            m.lightingModel = .constant
            // all but clear, so the floor has no far edge to draw a line across the room: the room darkens behind it instead
            m.transparency = Self.floorAlpha
            m.writesToDepthBuffer = true
            floor.materials = [m]
            let f = SCNNode(geometry: floor)
            f.position = SCNVector3(x: 0, y: -0.86, z: 0)
            scene.rootNode.addChildNode(f)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 520
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 620
            key.eulerAngles = SCNVector3(x: -0.5, y: 0.35, z: 0)
            scene.rootNode.addChildNode(key)
            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .directional
            rim.light?.intensity = 360
            rim.eulerAngles = SCNVector3(x: -0.25, y: -2.4, z: 0)
            scene.rootNode.addChildNode(rim)
        }

        private func layout(_ n: Int) {
            guard n != slots else { return }
            for b in boxes { b.node.removeFromParentNode() }
            slots = n
            boxes = (0..<n).map { _ in TheatreBox() }
            let r = radius
            for (s, b) in boxes.enumerated() {
                let a = Double(s) * 2 * .pi / Double(n)
                b.place = a
                b.node.position = SCNVector3(x: CGFloat(r * sin(a)), y: 0, z: CGFloat(r * cos(a)))
                b.node.eulerAngles = SCNVector3(x: 0, y: CGFloat(a), z: 0)
                ring.addChildNode(b.node)
            }
            // the camera a little above the ring and in front of it: the box in front fills about half the height
            camera?.removeFromParentNode()
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 30
            cam.camera?.zNear = 0.1
            cam.camera?.zFar = 100
            cam.position = SCNVector3(x: 0, y: 1.35, z: CGFloat(r + 8.4))
            // looking a little lower than the boxes' middle lifts the ring up the screen, so the floor and the reflection sit
            // above the caption rather than under its words
            cam.look(at: SCNVector3(x: 0, y: -0.74, z: CGFloat(r - 1.0)))
            scene.rootNode.addChildNode(cam)
            camera = cam
        }

        @MainActor func update(games: [StageGame], focus: Int) {
            let count = games.count
            layout(CarouselRing.slots(for: count))
            guard count > 0 else { return }
            // the shorter way round to the new game, so the ring turns the way the stick was pushed
            if let lf = lastFocus, lastCount == count, lf != focus {
                var d = ((focus - lf) % count + count) % count
                if d > count / 2 { d -= count }
                position += d
            } else if lastFocus == nil || lastCount != count {
                position = focus
            }
            lastFocus = focus
            lastCount = count
            front = ((position % slots) + slots) % slots
            target = -Double(position) * 2 * .pi / Double(slots)
            for (s, b) in boxes.enumerated() {
                let g = games[CarouselRing.game(slot: s, position: position, slots: slots, count: count)]
                b.show(g)
                b.lit = s == front ? 1 : 0
            }
        }

        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = last == 0 ? 0 : min(time - last, 0.1)
            last = time
            let k = still ? 1 : min(1, 5.5 * dt)
            angle += (target - angle) * k
            ring.eulerAngles = SCNVector3(x: 0, y: CGFloat(angle), z: 0)
            // the right stick turns the box in front; let go, it comes back with a slow sway
            let stick = CaseStick.x
            if abs(stick) > 0.15 { spin += stick * 3.2 * dt } else {
                let turn = 2 * Double.pi
                let rest = turn * (spin / turn).rounded() + (still ? 0 : 0.05 * sin(time * 0.7))
                spin += (rest - spin) * min(1, 2.6 * dt)
            }
            let r = radius
            for (s, b) in boxes.enumerated() {
                b.glow += (b.lit - b.glow) * (still ? 1 : min(1, 6 * dt))
                let out = r + 0.75 * b.glow
                b.node.position = SCNVector3(x: CGFloat(out * sin(b.place)), y: CGFloat(0.06 * b.glow), z: CGFloat(out * cos(b.place)))
                // where the box is round the ring as you see it (0 in front), so the ones beside it turn part of the way back
                // towards you and their covers read, rather than facing straight out from the ring
                let rel = atan2(sin(b.place + angle), cos(b.place + angle))
                b.node.eulerAngles = SCNVector3(x: 0, y: CGFloat(b.place - Self.toward * rel + (s == front ? spin : 0) * b.glow), z: 0)
                // lit by how near the front it is: the ones beside it clearly, the next ones less, the box in front fully
                let facing = cos(rel)
                b.dim(0.22 + 0.36 * max(facing, 0) + 0.42 * b.glow)
                // the boxes round the back fade away, so the far side of the ring is not a row of dark slabs
                b.node.opacity = CGFloat(min(max((facing - 0.05) / 0.4, 0), 1))
            }
        }
    }
}

/// One box on the ring: the case as the game's page draws it (CaseModelView), the insert's sides from CoverArt
final class TheatreBox: @unchecked Sendable {
    let node = SCNNode()
    private let materials: [SCNMaterial]
    private let shellFaces = SCNMaterial()
    private let shellEdges = SCNMaterial()
    private var shown: String?
    private var shade = -1.0
    /// the place round the ring, in radians, and how far it is lit (1 in front)
    var place = 0.0
    var lit = 0.0
    var glow = 0.0

    init() {
        let insert = SCNBox(width: CaseSize.insertWidth, height: CaseSize.insertHeight, length: CaseSize.insertDepth, chamferRadius: 0.002)
        materials = (0..<6).map { _ in
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = NSColor(white: 0.12, alpha: 1)
            m.specular.contents = NSColor(white: 0.18, alpha: 1)
            m.shininess = 0.25
            return m
        }
        insert.materials = materials   // front, right, back, left (the spine), top, bottom
        let paper = SCNNode(geometry: insert)
        paper.position = SCNVector3(x: CGFloat(CaseSize.insertShift), y: 0, z: 0)
        node.addChildNode(paper)
        let outline = NSBezierPath(roundedRect: NSRect(x: -CaseSize.width / 2, y: -CaseSize.height / 2, width: CaseSize.width, height: CaseSize.height),
                                   xRadius: CaseSize.corner, yRadius: CaseSize.corner)
        outline.flatness = 0.004
        let shell = SCNShape(path: outline, extrusionDepth: CaseSize.depth)
        shell.chamferRadius = 0.004
        for m in [shellFaces, shellEdges] {
            m.lightingModel = .blinn
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            m.shininess = 0.9
        }
        shellFaces.specular.contents = NSColor(white: 0.85, alpha: 1)
        shellEdges.specular.contents = NSColor(white: 0.6, alpha: 1)
        shell.materials = [shellFaces, shellFaces, shellEdges, shellEdges, shellEdges]
        let plastic = SCNNode(geometry: shell)
        plastic.renderingOrder = 10
        plastic.castsShadow = false
        node.addChildNode(plastic)
    }

    @MainActor func show(_ g: StageGame) {
        let key = g.id + "|\(CoverStore.shared.revision)"
        guard key != shown else { return }
        shown = key
        let store = CoverStore.shared
        let edge = NSColor(white: 0.12, alpha: 1)
        materials[0].diffuse.contents = CoverArt.front(g) ?? edge
        materials[2].diffuse.contents = store.image(g.coverKey, .back) ?? NSColor(white: 0.08, alpha: 1)
        materials[3].diffuse.contents = CoverArt.spine(g) ?? edge
        let red = g.console == .switch2
        materials[1].diffuse.contents = CaseEdgeArt.image(red: red, across: true)
        for i in [4, 5] { materials[i].diffuse.contents = CaseEdgeArt.image(red: red, across: false) }
        for i in [1, 4, 5] {
            let m = materials[i]
            m.specular.contents = NSColor(white: 0.05, alpha: 1)
            m.blendMode = .alpha
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = false
        }
        shellFaces.diffuse.contents = red ? NSColor(red: 0.85, green: 0.10, blue: 0.12, alpha: 0.10) : NSColor(white: 1, alpha: 0.05)
        shellEdges.diffuse.contents = red ? NSColor(red: 0.80, green: 0.06, blue: 0.10, alpha: 0.42) : NSColor(white: 0.95, alpha: 0.16)
    }

    /// How lit the box is: the ones away from the front fall into shadow
    func dim(_ v: Double) {
        guard abs(v - shade) > 0.004 else { return }
        shade = v
        let c = NSColor(white: CGFloat(v), alpha: 1)
        for m in materials { m.multiply.contents = c }
    }
}

// MARK: Cinema

/// The game's wide art across the whole screen, drifting slowly, with its name, what you have played and Resume or Play; under
/// it rows of games like a TV app: Continue playing, Favourites, each genre you have, and the games not built yet.
struct CinemaTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in content(width: geo.size.width) }
    }

    @ViewBuilder func content(width: CGFloat) -> some View {
        let rows = model.theatreRows()
        let r = model.cinemaRow(rows)
        let list = rows.indices.contains(r) ? rows[r].games : []
        let col = list.firstIndex { $0.id == model.theatreFocus } ?? 0
        let focus = list.indices.contains(col) ? list[col] : nil
        ZStack(alignment: .topLeading) {
            StageLook.background.ignoresSafeArea()
            if let g = focus {
                CinemaArt(game: g)
                    .scaleEffect(drift ? 1.10 : 1.03, anchor: UnitPoint(x: 0.7, y: 0.35))
                    .animation(.easeInOut(duration: 28).repeatForever(autoreverses: true), value: drift)
                    .id(g.id).transition(.opacity)
                    .ignoresSafeArea()
            }
            // the art falls away to the left, under the words, and to the foot, under the rows
            LinearGradient(stops: [.init(color: StageLook.background.opacity(0.94), location: 0), .init(color: StageLook.background.opacity(0.72), location: 0.32),
                                   .init(color: StageLook.background.opacity(0.08), location: 0.64), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
            LinearGradient(stops: [.init(color: .clear, location: 0.38), .init(color: StageLook.background.opacity(0.86), location: 0.68), .init(color: StageLook.background, location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            // the room's colour, from the game's art, glowing up from the foot under the words and the rows
            if let g = focus {
                RadialGradient(colors: [CoverArt.tint(g).opacity(0.34), CoverArt.tint(g).opacity(0.08), .clear], center: UnitPoint(x: 0.12, y: 1.05),
                               startRadius: 0, endRadius: 1100 * u)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 0) {
                TheatreTopBar(theme: .cinema, model: model).frame(width: width)
                Spacer(minLength: 0)
                if let g = focus { info(g, row: rows.indices.contains(r) ? rows[r].title : "").id(g.id).transition(.opacity) }
                rowsView(rows, current: r, col: col)
                    .frame(width: width, height: 322 * u, alignment: .topLeading).clipped()
                HStack { Spacer(); TheatreHints(model: model, focus: focus) }
                    .padding(.horizontal, 96 * u).padding(.bottom, 40 * u).frame(width: width)
            }
            .frame(width: width)
        }
        .animation(TheatreMotion.swapAnimation, value: focus?.id)
        .onAppear { if !still { drift = true } }
    }

    func info(_ g: StageGame, row: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.uppercased()).font(.system(size: 18 * u, weight: .semibold)).tracking(6 * u).foregroundStyle(Color(red: 1, green: 0.81, blue: 0.43))
            Text(g.name).font(.system(size: 84 * u, weight: .heavy)).tracking(-2.6 * u).lineLimit(2).minimumScaleFactor(0.6)
                .padding(.top, 18 * u).frame(maxWidth: 1000 * u, alignment: .leading)
            HStack(spacing: 16 * u) {
                Text(CarouselTheme.facts(g))
                if g.console == .switch2 {
                    Text("SWITCH 2").font(.system(size: 15 * u, weight: .bold)).tracking(1.5 * u)
                        .padding(.horizontal, 10 * u).padding(.vertical, 3 * u).overlay(RoundedRectangle(cornerRadius: 6 * u).strokeBorder(.white.opacity(0.4)))
                }
            }
            .font(.system(size: 23 * u)).foregroundStyle(StageLook.soft).padding(.top, 22 * u)
            TheatreDetails(model: model, game: g, showSize: false).padding(.top, 16 * u)
            HStack(spacing: 18 * u) {
                Button { model.theatrePad(.a) } label: {
                    Label(model.theatreAction(g), systemImage: model.status(g).actionSymbol)
                        .font(.system(size: 24 * u, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 34 * u).frame(height: 64 * u).background(.white, in: .rect(cornerRadius: 14 * u))
                }
                .buttonStyle(.plain)
                Button { model.theatrePad(.y) } label: { ghost("Details") }.buttonStyle(.plain)
                if g.app != nil { Button { model.theatrePad(.x) } label: { ghost("Play options") }.buttonStyle(.plain) }
            }
            .padding(.top, 28 * u)
        }
        .padding(.horizontal, 96 * u).padding(.bottom, 34 * u)
    }

    func ghost(_ t: String) -> some View {
        Text(t).font(.system(size: 24 * u, weight: .semibold))
            .padding(.horizontal, 30 * u).frame(height: 64 * u)
            .background(.white.opacity(0.14), in: .rect(cornerRadius: 14 * u))
            .overlay(RoundedRectangle(cornerRadius: 14 * u).strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    /// The row in focus, with the next one peeking under it; earlier rows have scrolled away above
    func rowsView(_ rows: [TheatreRow], current r: Int, col: Int) -> some View {
        let cardW = 400 * u, gap = 26 * u
        return VStack(alignment: .leading, spacing: 30 * u) {
            ForEach(Array(rows.enumerated()).filter { $0.offset >= r && $0.offset <= r + 1 }, id: \.element.id) { i, row in
                VStack(alignment: .leading, spacing: 16 * u) {
                    Text(row.title).font(.system(size: 24 * u, weight: .semibold)).padding(.leading, 96 * u)
                    HStack(spacing: gap) {
                        ForEach(Array(row.games.enumerated()), id: \.element.id) { k, g in
                            // only the cards near the focus draw their art
                            let near = abs(k - (i == r ? col : 0)) < 7
                            CinemaCard(game: g, focused: i == r && k == col, near: near)
                                .frame(width: cardW, height: cardW * 9 / 16)
                                .help(TheatreDetails.line(model, g))
                                .onTapGesture { model.theatreRow = i; model.theatreFocus = g.id; model.theatreTouched = Date() }
                        }
                    }
                    .padding(.leading, 96 * u)
                    .offset(x: i == r ? -CGFloat(max(col - 2, 0)) * (cardW + gap) : 0)
                    .animation(.spring(duration: 0.45), value: col)
                }
                .opacity(i == r ? 1 : 0.5)
            }
        }
        .animation(.spring(duration: 0.45), value: r)
    }
}

// MARK: Trailer

struct TrailerClock: Equatable {
    var at: Double
    var length: Double
    static func text(_ t: Double) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }
}

/// Trailer: two states of one screen. Browse: the game in focus's trailer plays across the top, and a dark panel under it holds
/// the game's name, facts and buttons on the left and a strip of every game on the right, so the words never sit on the video.
/// Watch (after 6 s left alone, or ↓): the panel and the bar fade away and the trailer takes the room, with only the game's
/// name and ↑ Browse at the foot; any button, or moving the pointer, brings Browse back. The sound is low while browsing and
/// full while watching; S, or the speaker at the top, mutes it. A game with no trailer YouTube will play here shows its wide
/// art drifting, and its store screenshots in turn while watching.
struct TrailerTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @State private var clock: TrailerClock?
    @State private var pointer: CGPoint?

    static let cream = Color(red: 0.98, green: 0.93, blue: 0.84)
    static let panelColor = Color(red: 0.055, green: 0.05, blue: 0.047)

    var body: some View {
        GeometryReader { geo in content(geo.size) }
    }

    @ViewBuilder func content(_ size: CGSize) -> some View {
        let games = model.trailerGames()
        let focus = model.theatreFocused(games)
        let watch = model.theatreWatch
        let panel = 330 * u
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let g = focus {
                // the full picture, raised by half the panel while browsing so its middle shows above it
                TrailerScreen(model: model, game: g, watch: watch, muted: model.theatreMuted, volume: model.settings.theatreVolume, clock: $clock)
                    .id(g.id)
                    .frame(width: size.width, height: size.height)
                    .offset(y: watch ? 0 : -panel / 2)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: size.width, height: 220 * u).allowsHitTesting(false).opacity(watch ? 0 : 1)
            topBar(focus).frame(width: size.width).opacity(watch ? 0 : 1).allowsHitTesting(!watch)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panelView(games, focus).frame(width: size.width, height: panel)
            }
            .offset(y: watch ? 60 * u : 0).opacity(watch ? 0 : 1).allowsHitTesting(!watch)
            if let g = focus {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 30 * u) {
                        Text(g.name.uppercased()).font(.system(size: 17 * u, weight: .semibold)).tracking(5 * u).lineLimit(1)
                        Spacer()
                        HStack(spacing: 8 * u) { TheatreHints(model: model).glyph("R3"); Text(model.theatreMuted ? "Sound on" : "Mute") }
                        HStack(spacing: 8 * u) { TheatreHints(model: model).glyph("RS"); Text("Volume") }
                        HStack(spacing: 10 * u) { Image(systemName: "arrow.up"); Text("Any button: Browse") }
                    }
                    .font(.system(size: 18 * u, weight: .medium))
                    .shadow(color: .black.opacity(0.7), radius: 8 * u)
                    .padding(.horizontal, 64 * u).padding(.bottom, 44 * u)
                }
                .frame(width: size.width, height: size.height)
                .opacity(watch ? 1 : 0).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: watch)
        .animation(TheatreMotion.swapAnimation, value: focus?.id)
        // the pointer moving brings Browse back (a still pointer, or a twitch, does not)
        .onContinuousHover { p in
            guard case .active(let at) = p else { return }
            if let o = pointer, hypot(at.x - o.x, at.y - o.y) > 12 {
                model.theatreTouched = Date()
                if model.theatreWatch { model.theatreWatch = false }
                pointer = at
            } else if pointer == nil { pointer = at }
        }
    }

    func topBar(_ g: StageGame?) -> some View {
        HStack(spacing: 22 * u) {
            HStack(spacing: 0) {
                Text("NX").font(.system(size: 22 * u, weight: .heavy))
                Text("FORGE").font(.system(size: 22 * u, weight: .light))
            }
            .tracking(7 * u).opacity(0.92)
            Spacer()
            Group {
                if let c = clock {
                    Text("TRAILER  •  \(TrailerClock.text(c.at)) / \(TrailerClock.text(c.length))")
                } else {
                    Text("TRAILER")
                }
            }
            .font(.system(size: 16 * u, weight: .semibold)).tracking(2.4 * u).monospacedDigit()
            Button { model.theatreMuted.toggle(); model.theatreVolumeTick += 1 } label: {
                Image(systemName: model.theatreMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18 * u, weight: .semibold)).frame(width: 40 * u, height: 40 * u).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(model.theatreMuted ? "Sound on (S, or press the right stick)" : "Mute (S, or press the right stick)")
        }
        .padding(.horizontal, 64 * u).frame(height: 110 * u)
        .overlay { TheatreFilterChip(model: model) }
        .shadow(color: .black.opacity(0.5), radius: 6 * u)
    }

    func panelView(_ games: [StageGame], _ focus: StageGame?) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                info(focus).frame(width: 600 * u, alignment: .leading)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 150 * u).padding(.top, 8 * u)
                // the strip is far wider than the screen: it hangs off a box the width that is left, and is cut to it
                Color.clear.frame(maxWidth: .infinity, maxHeight: 200 * u)
                    .overlay(alignment: .topLeading) { strip(games, focus).fixedSize() }
                    .clipped()
            }
            .padding(.top, 34 * u)
            Spacer(minLength: 0)
            HStack(spacing: 28 * u) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                HStack(spacing: 8 * u) { Image(systemName: "arrow.down"); Text("Watch") }
                HStack(spacing: 6 * u) { Image(systemName: "arrow.left"); Image(systemName: "arrow.right"); Text("Browse") }
                let hints = TheatreHints(model: model)
                if model.theatreFilters().count > 1 { HStack(spacing: 6 * u) { hints.glyph("L"); hints.glyph("R"); Text("Filter") } }
                HStack(spacing: 6 * u) { hints.glyph("ZL"); hints.glyph("ZR"); Text("Theme") }
                HStack(spacing: 6 * u) { hints.glyph("R3"); Text(model.theatreMuted ? "Sound on" : "Mute") }
                HStack(spacing: 6 * u) { hints.glyph("RS"); Text("Volume") }
                HStack(spacing: 6 * u) { hints.glyph("+"); Text("Menu") }
                HStack(spacing: 6 * u) { hints.glyph("B"); Text("Leave") }
            }
            .font(.system(size: 17 * u, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            .padding(.horizontal, 64 * u).padding(.bottom, 26 * u)
        }
        .background {
            // the room's colour, from the game's art, washed over the dark panel
            ZStack {
                Self.panelColor
                if let g = focus { LinearGradient(colors: [CoverArt.tint(g).opacity(0.22), CoverArt.tint(g).opacity(0.05)], startPoint: .top, endPoint: .bottom) }
            }
        }
    }

    @ViewBuilder func info(_ g: StageGame?) -> some View {
        if let g {
            let st = model.status(g)
            VStack(alignment: .leading, spacing: 0) {
                Text(g.name.uppercased()).font(.system(size: 40 * u, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.55)
                HStack(spacing: 10 * u) {
                    Text([g.game?.publisher, g.console.rawValue].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "  ·  "))
                    if st != .ready {
                        Image(systemName: "diamond").font(.system(size: 13 * u, weight: .semibold)).padding(.leading, 8 * u)
                        Text(st.text)
                    } else if g.total > 60 {
                        Text("·  \(Playtime.text(g.total)) played")
                    }
                }
                .font(.system(size: 19 * u)).foregroundStyle(.white.opacity(0.72)).padding(.top, 12 * u).lineLimit(1)
                TheatreDetails(model: model, game: g, size: 15, status: false).padding(.top, 10 * u)
                HStack(spacing: 18 * u) {
                    Button { model.theatrePad(.a) } label: {
                        HStack(spacing: 10 * u) { TheatreHints(model: model).glyph("A", filled: true).colorInvert(); Text(model.theatreAction(g)) }
                            .font(.system(size: 21 * u, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 22 * u).frame(height: 54 * u)
                            .background(Self.cream, in: .rect(cornerRadius: 12 * u))
                    }
                    .buttonStyle(.plain)
                    Button { model.theatrePad(.y) } label: {
                        HStack(spacing: 10 * u) { TheatreHints(model: model).glyph("Y"); Text("Details") }
                            .font(.system(size: 21 * u, weight: .semibold))
                            .padding(.horizontal, 22 * u).frame(height: 54 * u)
                            .overlay(RoundedRectangle(cornerRadius: 12 * u).strokeBorder(.white.opacity(0.4), lineWidth: 1.5 * u))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 18 * u)
            }
            .padding(.leading, 64 * u).padding(.trailing, 36 * u)
            .id(g.id).transition(.opacity)
        }
    }

    func strip(_ games: [StageGame], _ focus: StageGame?) -> some View {
        let cardW = 250 * u, gap = 22 * u
        let col = games.firstIndex { $0.id == focus?.id } ?? 0
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(games.enumerated()), id: \.element.id) { k, g in
                // only the cards near the focus draw their art
                TrailerCard(game: g, focused: k == col, near: abs(k - col) < 8, width: cardW)
                    .onTapGesture { model.theatreFocus = g.id; model.theatreTouched = Date() }
                    .help(TheatreDetails.line(model, g))
            }
        }
        .padding(.leading, 34 * u)
        .offset(x: -CGFloat(max(col - 2, 0)) * (cardW + gap))
        .animation(.spring(duration: 0.4), value: col)
    }
}

struct TrailerCard: View {
    let game: StageGame
    let focused: Bool
    let near: Bool
    let width: CGFloat
    @Environment(\.tu) private var u

    var body: some View {
        let _ = CoverStore.shared.revision
        VStack(spacing: 12 * u) {
            ZStack {
                CoverArt.tint(game).opacity(0.5)
                if near, let art = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) ?? GalleryCover.square(game.coverKey) {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: 10 * u))
            .overlay(RoundedRectangle(cornerRadius: 10 * u).strokeBorder(TrailerTheme.cream, lineWidth: focused ? 3 * u : 0))
            .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 16 * u, y: 8 * u)
            Text(game.name.uppercased()).font(.system(size: 13 * u, weight: .semibold)).tracking(1.6 * u)
                .multilineTextAlignment(.center).lineLimit(2).frame(width: width)
                .foregroundStyle(.white.opacity(focused ? 1 : 0.68))
        }
        .contentShape(.rect)
        .animation(.easeInOut(duration: 0.25), value: focused)
    }
}

/// What plays behind Trailer: the game's wide art drifting slowly, then its first YouTube trailer that YouTube will play here
/// (from 5 s in, past the logos most trailers open with, looping back to 5 s), faded in once the picture moves. It loads once
/// the focus has rested on the game for a moment, and stops while a game starts or runs, a viewer is open or NXForge is in
/// the background. With no trailer, Watch shows the store's screenshots in turn.
struct TrailerScreen: View {
    let model: AppModel
    let game: StageGame
    let watch: Bool
    let muted: Bool
    /// Settings' trailer volume, 0 to 100: all of it while watching, a quarter while browsing
    var volume = 100
    @Binding var clock: TrailerClock?
    @State private var rested = false
    @State private var playing = false
    @State private var skip = 0
    @State private var shot = 0
    @State private var drift = false
    @State private var active = NSApp.isActive || ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = StoreInfoStore.shared.revision
        // the trailers in the page's order; one whose owner allows it only on YouTube is skipped
        let ids = (StoreInfoStore.shared.info(game.coverKey)?.trailers ?? []).compactMap(\.youtube)
        let id = ids.indices.contains(skip) ? ids[skip] : nil
        let shots = id == nil && watch ? StoreInfoStore.shared.shots(game.coverKey) : []
        let on = rested && active && model.launching == nil && !model.viewerOpen && model.caseViewer == nil && !model.theatreSaver
        GeometryReader { geo in
            ZStack {
                CinemaArt(game: game)
                    .scaleEffect(drift ? 1.10 : 1.02, anchor: UnitPoint(x: 0.6, y: 0.4))
                    .animation(.easeInOut(duration: 28).repeatForever(autoreverses: true), value: drift)
                if !shots.isEmpty, let img = NSImage(contentsOf: shots[shot % shots.count]) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .id(shot % shots.count).transition(.opacity)
                }
                if let id, on {
                    TrailerBackdropPlayer(id: id, start: 5, volume: muted ? 0 : watch ? volume : (volume + 3) / 4,
                                          // a second's wait: YouTube flashes its pause sign as it starts
                                          playing: { Task { try? await Task.sleep(for: .seconds(1)); playing = true } },
                                          failed: { playing = false; clock = nil; skip += 1 },
                                          time: { at, length in if playing { clock = TrailerClock(at: at, length: length) } })
                        .id(id)
                        .opacity(playing ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height).clipped()
        }
        .animation(.easeInOut(duration: 0.8), value: playing)
        .animation(.easeInOut(duration: 1.2), value: shot)
        .onChange(of: on) { _, v in if !v { playing = false; clock = nil } }
        .onAppear { if !still { drift = true } }
        .onDisappear { clock = nil }
        .task {
            if model.settings.downloadStoreInfo { StoreInfoStore.shared.load(key: game.coverKey, titleID: game.titleID, name: game.name) }
            try? await Task.sleep(for: .seconds(1.2))
            rested = true
        }
        // no trailer: a screenshot every 6 s while watching
        .task(id: watch) {
            while watch, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                if watch { shot += 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in active = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { active = false }
        }
    }
}

/// YouTube's player through its IFrame API, sized to cover the view (cropped like art, a touch larger so YouTube's title bar and
/// logo fall off the edges), no controls, ads blocked as in YouTubePlayer. `playing` is called when the picture is moving.
struct TrailerBackdropPlayer: NSViewRepresentable {
    let id: String
    let start: Int
    /// 0 to 100 (0 mutes); changed while it plays
    let volume: Int
    let playing: () -> Void
    /// YouTube won't play it here (its owner allows it only on YouTube: error 101/150, or it is gone)
    let failed: () -> Void
    /// where it is and how long it is, in seconds, once a second while it plays
    let time: (Double, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var playing: () -> Void = {}
        var failed: () -> Void = {}
        var time: (Double, Double) -> Void = { _, _ in }
        var volume = -1
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let b = m.body as? String else { return }
            if b == "playing" { MainActor.assumeIsolated { playing() }; return }
            if b.hasPrefix("t ") {
                let p = b.split(separator: " ").compactMap { Double($0) }
                if p.count == 2 { MainActor.assumeIsolated { time(p[0], p[1]) } }
                return
            }
            print("Theatre trailer: YouTube \(b)")
            MainActor.assumeIsolated { failed() }
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.playing = playing
        context.coordinator.failed = failed
        context.coordinator.time = time
        context.coordinator.volume = volume
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(context.coordinator, name: "nxf")
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}
        #p{position:absolute;left:50%;top:50%;width:max(100vw,177.78vh);height:max(56.25vw,100vh);transform:translate(-50%,-50%) scale(1.12);pointer-events:none}
        </style></head><body><div id="p"></div><script>
        var s = document.createElement('script'); s.src = 'https://www.youtube.com/iframe_api'; document.head.appendChild(s);
        var told = false, player = null, want = \(volume), cur = 0, fading = null;
        function nocc() { try { player.unloadModule('captions'); player.unloadModule('cc'); player.setOption('captions', 'track', {}); } catch (x) {} }
        function put(n) { cur = n; if (!player || !player.setVolume) return; if (n <= 0) { player.mute(); } else { player.unMute(); player.setVolume(n); } }
        // the sound glides to n over ms, never jumps: in as the picture fades in, out as the game changes, and between Browse and Watch
        function fade(n, ms) {
          if (!player || !player.setVolume) { want = n; return; }
          clearInterval(fading); var from = cur, steps = Math.max(1, Math.round(ms / 40)), i = 0;
          fading = setInterval(function () { i++; put(Math.round(from + (n - from) * i / steps)); if (i >= steps) clearInterval(fading); }, 40);
        }
        function vol(n) { want = n; if (told) fade(n, 450); }
        setInterval(function () {
          try { if (told && player && player.getCurrentTime) { window.webkit.messageHandlers.nxf.postMessage('t ' + player.getCurrentTime() + ' ' + player.getDuration()); } } catch (x) {}
        }, 1000);
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', { host: 'https://www.youtube-nocookie.com', videoId: '\(id)',
            playerVars: { autoplay: 1, start: \(start), controls: 0, disablekb: 1, rel: 0, modestbranding: 1, iv_load_policy: 3,
                          playsinline: 1, fs: 0, cc_load_policy: 0 },
            events: {
              onReady: function (e) { nocc(); put(0); e.target.playVideo(); },
              onError: function (e) { window.webkit.messageHandlers.nxf.postMessage('error ' + e.data); },
              onStateChange: function (e) {
                if (e.data === YT.PlayerState.PLAYING) { nocc(); }
                if (e.data === YT.PlayerState.PLAYING && !told) { told = true; fade(want, 1400); window.webkit.messageHandlers.nxf.postMessage('playing'); }
                if (e.data === YT.PlayerState.ENDED) { e.target.seekTo(\(start)); e.target.playVideo(); }
              }
            } });
        }
        </script></body></html>
        """
        VideoAds.rules { list in
            if let list { v.configuration.userContentController.add(list) }
            v.loadHTMLString(html, baseURL: URL(string: "https://github.com/gnosticgeek/nxforge"))
        }
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        context.coordinator.playing = playing
        context.coordinator.failed = failed
        context.coordinator.time = time
        if context.coordinator.volume != volume {
            context.coordinator.volume = volume
            v.evaluateJavaScript("vol(\(volume))")
        }
    }

    /// The sound fades out with the picture rather than stopping dead, then the page is emptied
    static func dismantleNSView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "nxf")
        v.evaluateJavaScript("fade(0, \(Int(TheatreMotion.swap * 1000)))")
        DispatchQueue.main.asyncAfter(deadline: .now() + TheatreMotion.swap + 0.1) {
            v.stopLoading()
            v.loadHTMLString("", baseURL: nil)
        }
    }
}

/// A game's wide art: its hero, else a screenshot or its cover blurred big (GameKeyArt's order)
struct CinemaArt: View {
    let game: StageGame

    var body: some View {
        let _ = CoverStore.shared.revision
        GeometryReader { geo in
            if let art = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                StageBackdrop(tint: CoverArt.tint(game), art: CoverArt.ambient(game), artKey: game.id)
            }
        }
    }
}

struct CinemaCard: View {
    let game: StageGame
    let focused: Bool
    var near = true
    @Environment(\.tu) private var u

    var body: some View {
        let _ = CoverStore.shared.revision
        ZStack(alignment: .bottomLeading) {
            // the art fills the card's own size and no more: as a plain layer of the ZStack it made the card as big as the
            // art, so the cards ran into each other with no gap and lost their round corners
            CoverArt.tint(game).opacity(0.5)
                .overlay {
                    if near, let art = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) {
                        Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8 * u) {
                Text(game.name).font(.system(size: 19 * u, weight: .semibold)).lineLimit(1)
                if game.total > 60 {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4 * u)
                        .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(.white).frame(width: g.size.width * min(0.92, 0.12 + game.total / 36000)) } }
                }
            }
            .padding(.horizontal, 18 * u).padding(.bottom, 14 * u)
        }
        .opacity(game.app == nil ? 0.55 : 1)
        // the cards beside the focus a shade darker, so the one in focus stands out without a heavier outline
        .brightness(focused ? 0 : -0.07)
        .clipShape(.rect(cornerRadius: 16 * u))
        .overlay(RoundedRectangle(cornerRadius: 16 * u).strokeBorder(.white, lineWidth: focused ? 4 * u : 0))
        .shadow(color: .black.opacity(focused ? 0.7 : 0.5), radius: (focused ? 34 : 18) * u, y: (focused ? 26 : 14) * u)
        .scaleEffect(focused ? 1.09 : 1)
        .zIndex(focused ? 1 : 0)
        .animation(.spring(duration: 0.3), value: focused)
    }
}

extension View {
    /// colorInvert() when `on`
    @ViewBuilder func colorInvert(_ on: Bool) -> some View {
        if on { colorInvert() } else { self }
    }
}

// MARK: Gallery

/// Three covers on a quiet ivory wall: the game in focus in the middle with a fine bronze outline and a marker under it, one
/// neighbour either side, and its name, platform and time played on the left with the main button. Nothing moves on its own;
/// a step slides the covers in about 0.2 s (a fade with Reduce Motion). A game with no cover shows its icon on a plain card
/// with its name, never a made-up box. Laid out on a 1920 x 1080 canvas (u is a 1080th of the height), so a TV of another
/// shape keeps the proportions: a narrow screen drops the neighbours before any text shrinks.
struct GalleryTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    static let ivory = Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE5 / 255)
    static let ink = Color(red: 0x29 / 255, green: 0x25 / 255, blue: 0x1F / 255)
    static let soft = Color(red: 0x65 / 255, green: 0x5C / 255, blue: 0x51 / 255)
    static let bronze = Color(red: 0x93 / 255, green: 0x61 / 255, blue: 0x3F / 255)

    // the covers, in 1080ths: width and centre height of the one in focus and of its neighbours, and the clear gap between
    static let focusW: CGFloat = 312, focusMidY: CGFloat = 462
    static let sideW: CGFloat = 245, sideMidY: CGFloat = 483
    static let gap: CGFloat = 44

    var body: some View {
        GeometryReader { geo in content(width: geo.size.width, height: geo.size.height) }
    }

    @ViewBuilder func content(width: CGFloat, height: CGFloat) -> some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        // the covers' own region, right of the words: x 740 to the right safe edge
        let left = 740 * u, right = width - 96 * u
        let roomForSides = right - left >= (Self.focusW + 2 * (Self.sideW + Self.gap)) * u
        ZStack(alignment: .topLeading) {
            Self.ivory.ignoresSafeArea()
            // the game's colour, the faintest wash on the wall behind the covers
            if let g = focus {
                RadialGradient(colors: [CoverArt.tint(g).opacity(0.13), .clear], center: UnitPoint(x: 0.68, y: 0.44), startRadius: 0, endRadius: 760 * u)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            covers(games, index: index, sides: roomForSides).frame(width: right - left, height: 640 * u).clipped()
                .offset(x: left, y: 170 * u)
            if let g = focus {
                info(g).frame(width: 554 * u, alignment: .leading).offset(x: 96 * u, y: 250 * u)
                    .id(g.id).transition(.opacity)
            }
            VStack(spacing: 0) {
                TheatreTopBar(theme: .gallery, model: model, ink: Self.ink, pill: false).padding(.top, 20 * u).frame(width: width)
                Spacer(minLength: 0)
                foot(games, index: index, focus: focus).frame(width: width)
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .animation(still ? nil : .easeOut(duration: 0.22), value: focus?.id)
        .animation(TheatreMotion.swapAnimation, value: focus.map { CoverArt.tint($0) })
    }

    /// The name, then one short fact a line (only what is known), the status when it cannot play, and the main button
    func info(_ g: StageGame) -> some View {
        let st = model.status(g)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Self.bronze).frame(width: 52 * u, height: 4 * u)
            Text(g.name).font(.system(size: 78 * u, weight: .medium, design: .serif)).tracking(-1 * u)
                .lineLimit(3).minimumScaleFactor(0.72).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Self.ink).padding(.top, 26 * u)
            VStack(alignment: .leading, spacing: 12 * u) {
                Text(g.console.rawValue)
                if g.total > 0 { Text("\(Playtime.text(g.total)) played") }
                if st != .ready { Label(st.text, systemImage: st.symbol).foregroundStyle(Self.bronze) }
            }
            .font(.system(size: 27 * u)).foregroundStyle(Self.soft).padding(.top, 22 * u)
            TheatreDetails(model: model, game: g, ink: Self.soft, size: 19, status: false).padding(.top, 18 * u)
            Button { model.theatrePad(.a) } label: {
                HStack(spacing: 16 * u) {
                    PadGlyph(text: "A", filled: true).scaleEffect(u * 1.5).frame(width: 34 * u, height: 34 * u)
                    Text(model.theatreAction(g)).font(.system(size: 30 * u, weight: .semibold))
                }
                .foregroundStyle(Self.ivory)
                .padding(.horizontal, 30 * u).frame(minWidth: 200 * u, minHeight: 64 * u, alignment: .leading)
                .background(Self.ink, in: .rect(cornerRadius: 12 * u))
            }
            .buttonStyle(.plain).padding(.top, 34 * u)
        }
    }

    /// The cover in focus in the middle of the region and one either side; one more either side waits just out of sight so
    /// a step slides it in. A short library shows only the covers it has, with no empty places.
    func covers(_ games: [StageGame], index: Int, sides: Bool) -> some View {
        let n = games.count
        var places: [Int] = []
        if n > 0 {
            places = [0]
            if sides && n > 1 { places.append(1) }
            if sides && n > 2 { places.insert(-1, at: 0) }
            if sides && n > 3 { places.append(2) }
            if sides && n > 4 { places.insert(-2, at: 0) }
        }
        return GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                ForEach(places, id: \.self) { d in
                    let g = games[((index + d) % n + n) % n]
                    let w = (d == 0 ? Self.focusW : Self.sideW) * u
                    let step = (Self.focusW / 2 + Self.gap + Self.sideW / 2) * u
                    let x = d == 0 ? mid : mid + CGFloat(d.signum()) * (step + CGFloat(abs(d) - 1) * (Self.sideW + Self.gap) * u)
                    let y = ((d == 0 ? Self.focusMidY : Self.sideMidY) - 170) * u
                    GalleryCover(game: g, focused: d == 0, width: w)
                        .position(x: x, y: y)
                        .opacity(abs(d) > 1 ? 0 : 1)
                        .onTapGesture { model.theatreFocus = g.id; model.theatreTouched = Date() }
                        .help(TheatreDetails.line(model, g))
                        .id(g.id)
                }
            }
        }
    }

    func foot(_ games: [StageGame], index: Int, focus: StageGame?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Rectangle().fill(Self.bronze).frame(width: 4 * u, height: 34 * u)
                Text("Your collection").font(.system(size: 32 * u, weight: .medium)).padding(.leading, 18 * u)
                Spacer()
                if !games.isEmpty {
                    (Text(String(format: "%02d", index + 1)).foregroundStyle(Self.bronze) + Text(" / " + String(format: "%02d", games.count)))
                        .font(.system(size: 36 * u, design: .serif)).monospacedDigit()
                }
            }
            .frame(height: 50 * u)
            Rectangle().fill(Self.ink.opacity(0.18)).frame(height: 1).padding(.top, 20 * u)
            HStack { Spacer(); TheatreHints(model: model, focus: focus, light: true, themes: false, back: "Back", size: 24) }
                .frame(height: 50 * u).padding(.top, 15 * u)
        }
        .foregroundStyle(Self.ink)
        // the collection line about y 900, the buttons about y 975
        .padding(.horizontal, 96 * u).padding(.bottom, 80 * u)
    }
}

/// One cover in the Gallery: the real front at its own proportions, or the icon on a plain card with the name. The one in
/// focus lifts a little and has a fine bronze outline with a gap of the wall's colour, and a marker and "Selected" under it.
struct GalleryCover: View {
    /// the square art read once a game (only the few covers on screen ask)
    @MainActor static var squares: [String: NSImage?] = [:]
    @MainActor static func square(_ key: String) -> NSImage? {
        if let s = squares[key] { return s }
        let img = CoverStore.file(key + "-square").flatMap { NSImage(contentsOf: $0) }
        squares[key] = .some(img)
        return img
    }

    let game: StageGame
    let focused: Bool
    let width: CGFloat
    @Environment(\.tu) private var u

    var body: some View {
        let _ = CoverStore.shared.revision
        let art = CoverStore.shared.image(game.coverKey, .front)
        let ratio = art.map { $0.size.width > 0 && $0.size.height > 0 ? $0.size.width / $0.size.height : CoverSource.aspect } ?? CoverSource.aspect
        let h = width / ratio
        let corner = 6 * u
        VStack(spacing: 0) {
            ZStack {
                if let art {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    fallback(h: h)
                }
            }
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: GalleryTheme.ink.opacity(focused ? 0.16 : 0.10), radius: (focused ? 16 : 10) * u, y: (focused ? 12 : 7) * u)
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: corner + 8 * u).strokeBorder(GalleryTheme.bronze, lineWidth: 2.5 * u).padding(-8.5 * u)
                }
            }
            .offset(y: focused ? -6 * u : 0)
        }
        .frame(width: width, height: h)
        .overlay(alignment: .bottom) {
            if focused {
                VStack(spacing: 10 * u) {
                    Rectangle().fill(GalleryTheme.bronze).frame(width: 40 * u, height: 3 * u)
                    Text("Selected").font(.system(size: 24 * u, design: .serif)).foregroundStyle(GalleryTheme.ink)
                }
                .fixedSize().offset(y: 64 * u)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name + (focused ? ", selected" : ""))
    }

    /// No cover: the store's square art for the game, else its icon, sharp and no bigger than it has pixels for (a Retina point
    /// is two pixels), on a matte card with the game's name. Never a made-up box.
    func fallback(h: CGFloat) -> some View {
        let art = Self.square(game.coverKey) ?? CoverArt.icon(game)
        let px = art.map { img in img.representations.map { CGFloat($0.pixelsWide) }.max() ?? img.size.width } ?? 0
        let side = min(width * 0.8, max(px / 2, 1))
        return ZStack {
            Color(red: 0.91, green: 0.88, blue: 0.83)
            VStack(spacing: 18 * u) {
                if let art {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: side * 0.08))
                }
                Text(game.name).font(.system(size: width * 0.075, weight: .medium, design: .serif)).multilineTextAlignment(.center)
                    .foregroundStyle(GalleryTheme.ink).lineLimit(3).padding(.horizontal, width * 0.1)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6 * u).strokeBorder(GalleryTheme.ink.opacity(0.10), lineWidth: 1))
    }
}

// MARK: Details, screensaver, volume, edges

/// A game's details once the focus has rested on it for a moment (AppModel.theatreDetails): when it was played, its genre,
/// players, size and whether it is built, as quiet capsules that fade in, so moving quickly along the games stays calm
struct TheatreDetails: View {
    let model: AppModel
    let game: StageGame
    var ink: Color = .white
    var size: CGFloat = 18
    /// the built / needs-a-build capsule (left out where the theme already says it)
    var status = true
    /// the size capsule (left out where the facts line already has it)
    var showSize = true
    @Environment(\.tu) private var u

    var body: some View {
        let _ = StoreInfoStore.shared.revision
        let facts = model.theatreDetails(game)
            .filter { status || ($0.symbol != "checkmark.seal.fill" && $0.text != model.status(game).text) }
            .filter { showSize || $0.symbol != "internaldrive" }
        HStack(spacing: 10 * u) {
            ForEach(facts, id: \.self) { f in
                HStack(spacing: 7 * u) {
                    Image(systemName: f.symbol).font(.system(size: size * 0.8 * u, weight: .semibold))
                    Text(f.text).lineLimit(1)
                }
                .font(.system(size: size * u, weight: .medium))
                .padding(.horizontal, 12 * u).frame(height: size * 1.8 * u)
                .background(ink.opacity(0.10), in: .capsule)
                .overlay(Capsule().strokeBorder(ink.opacity(0.14), lineWidth: 1))
            }
        }
        .foregroundStyle(ink.opacity(0.9))
        .fixedSize()
        .opacity(model.theatreRested ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: model.theatreRested)
        .accessibilityElement(children: .combine)
    }

    /// the same, as one line for a pointer's tooltip
    @MainActor static func line(_ model: AppModel, _ g: StageGame) -> String {
        ([g.name] + model.theatreDetails(g).map(\.text)).joined(separator: " · ")
    }
}

/// Theatre left alone (Settings › Theatre › Screensaver): the games' wide art in turn, a slow drift on each, dimmed, with a
/// quiet clock and the game's name that move corner to corner so nothing stays in one place on the TV. Any button, a key or
/// the pointer wakes it. No trailers play here: it is meant to be quiet, and an hour in the TV is let sleep.
struct TheatreScreensaver: View {
    let model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var step = 0
    @State private var drift = false
    @State private var pointer: CGPoint?

    var body: some View {
        let _ = CoverStore.shared.revision
        let games = model.theatreGames().filter { CoverStore.shared.hero($0.coverKey) != nil || CoverArt.wide($0) != nil }
        let list = games.isEmpty ? model.theatreGames() : games
        let g = list.isEmpty ? nil : list[step % list.count]
        // the words' corner: bottom left, bottom right, top right, top left in turn
        let corner: Alignment = [.bottomLeading, .bottomTrailing, .topTrailing, .topLeading][step % 4]
        let lead = corner == .bottomLeading || corner == .topLeading
        GeometryReader { geo in
            ZStack {
                Color.black
                if let g, let art = CoverStore.shared.hero(g.coverKey) ?? CoverArt.wide(g) {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .scaleEffect(drift ? 1.12 : 1.02, anchor: lead ? .topTrailing : .topLeading)
                        .animation(still ? nil : .linear(duration: 14), value: drift)
                        .id(g.id).transition(.opacity)
                }
                Color.black.opacity(0.42)
                VStack(alignment: lead ? .leading : .trailing, spacing: 6 * u) {
                    TimelineView(.everyMinute) { t in
                        Text(t.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 96 * u, weight: .thin)).monospacedDigit()
                    }
                    if let g { Text(g.name).font(.system(size: 24 * u, weight: .medium)).opacity(0.75).id(g.id).transition(.opacity) }
                }
                .opacity(0.62)
                .padding(.horizontal, 110 * u).padding(.vertical, 90 * u)
                .frame(width: geo.size.width, height: geo.size.height, alignment: corner)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 2), value: step)
        .contentShape(.rect)
        .onTapGesture { model.wakeTheatre() }
        .onContinuousHover { p in
            guard case .active(let at) = p, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
            if let o = pointer, hypot(at.x - o.x, at.y - o.y) > 12 { model.wakeTheatre() } else if pointer == nil { pointer = at }
        }
        .task {
            // a new picture every 12 s, the drift starting again on each
            while !Task.isCancelled {
                drift = false
                try? await Task.sleep(for: .milliseconds(60))
                drift = true
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                step += 1
            }
        }
    }
}

/// The trailer's volume for a moment after it changes: a speaker and ten steps, at the top right
struct TheatreVolumeCard: View {
    let volume: Int
    let muted: Bool
    @Environment(\.tu) private var u

    var body: some View {
        HStack(spacing: 14 * u) {
            Image(systemName: muted || volume == 0 ? "speaker.slash.fill" : volume < 40 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                .font(.system(size: 22 * u, weight: .semibold)).frame(width: 34 * u)
            HStack(spacing: 4 * u) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2 * u).fill(.white.opacity(!muted && i < volume / 10 ? 0.95 : 0.22)).frame(width: 12 * u, height: 22 * u)
                }
            }
            Text(muted ? "Muted" : "\(volume) %").font(.system(size: 18 * u, weight: .semibold)).monospacedDigit().frame(width: 76 * u, alignment: .trailing)
        }
        .padding(.horizontal, 20 * u).frame(height: 62 * u)
        .background(StageLook.panel.opacity(0.8), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 120 * u).padding(.trailing, 64 * u)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muted ? "Muted" : "Volume \(volume) percent")
    }
}

/// The picture's corners while TV Edges is chosen in the menu: if one is cut off on the TV, inset the picture
struct TheatreEdgeMarks: View {
    @Environment(\.tu) private var u

    var body: some View {
        let arm = 70 * u, w = 6 * u
        let corners: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let a = corners[i]
                ZStack(alignment: a) {
                    Rectangle().fill(Color(red: 1, green: 0.81, blue: 0.43)).frame(width: arm, height: w)
                    Rectangle().fill(Color(red: 1, green: 0.81, blue: 0.43)).frame(width: w, height: arm)
                }
                .frame(width: arm, height: arm, alignment: a)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: a)
            }
        }
    }
}
