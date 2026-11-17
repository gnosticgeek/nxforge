// Theatre: the front end full screen on a TV, for the sofa and a controller. It takes Couch Mode's place (⇧⌘F, View › Theatre,
// the Theatre button in the top bar, Settings › Theatre) and NXForge offers it when a TV is plugged in while a controller is
// connected (Settings: Ask, Always or Never). The window moves to the TV and goes full screen, the pointer hides, the Mac
// stays awake, and leaving puts the window back where it was. Two themes show the same games: Carousel, a turning ring of the
// real 3D boxes (TheatreCarousel), and Cinema, wide art with rows under it like a TV app. L and R switch them; the theme last
// used is kept. A plays, Y opens the game's page, X Play options, − favourites, Menu the Theatre menu, B offers to leave.
import AppKit
import GameController
import SceneKit
import SwiftUI

enum TheatreTheme: String, Codable, CaseIterable {
    case carousel = "Carousel", cinema = "Cinema"
    var note: String { self == .carousel ? "A turning ring of your boxes" : "Big art, rows like a TV app" }
    var symbol: String { self == .carousel ? "rotate.3d" : "film" }
}

/// What NXForge does when a TV appears: offer Theatre, open it straight away, or leave it to you
enum TheatreOnTV: String, Codable, CaseIterable { case ask = "Ask", always = "Always", never = "Never" }

/// The Theatre menu's rows (Menu, or B for Leave)
enum TheatreMenuRow: Int, CaseIterable {
    case carousel, cinema, settings, leave
    var title: String {
        switch self {
        case .carousel: "Carousel"
        case .cinema: "Cinema"
        case .settings: "Settings"
        case .leave: "Leave Theatre"
        }
    }
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
        // a moment after the window is up, so a TV already plugged in at launch is offered too
        Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(2)); self?.check() }
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
    func enterTheatre(on tv: TVScreen? = TVScreens.find()) {
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
        if theatreFocus == nil { theatreFocus = Self.lastPlayed(theatreGames())?.id ?? theatreGames().first?.id }
        theatre = true
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

    /// The games on Theatre: the built ones (every game when none is built), favourites first, then as the front end orders them
    func theatreGames() -> [StageGame] {
        let games = stageGames()
        let built = games.filter { $0.app != nil }
        let shelf = built.isEmpty ? games : built
        return shelf.filter(\.favorite) + shelf.filter { !$0.favorite }
    }

    /// Cinema's rows: Continue playing, Favourites, a row per genre, then the games not built yet
    func theatreRows() -> [TheatreRow] {
        let all = stageGames()
        let built = all.filter { $0.app != nil }
        var rows: [TheatreRow] = []
        let recent = all.filter { $0.last != nil && $0.app != nil }.sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
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
        if !unbuilt.isEmpty { rows.append(TheatreRow(title: "Not built yet", games: unbuilt)) }
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

    func setTheatreTheme(_ t: TheatreTheme) {
        theatreTheme = t
        if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { settings.theatreTheme = t }
    }

    /// A controller's button, or its key, on Theatre
    func theatrePad(_ k: PadKey) {
        theatreTouched = Date()
        NSCursor.setHiddenUntilMouseMoves(true)
        if let i = theatreMenu {
            let rows = TheatreMenuRow.allCases
            switch k {
            case .up: theatreMenu = max(i - 1, 0)
            case .down: theatreMenu = min(i + 1, rows.count - 1)
            case .a: pickTheatreMenu(rows[i])
            case .b, .menu: theatreMenu = nil
            default: break
            }
            return
        }
        // the game's page, Play options, the launch screen, Settings and the viewers work as on the front end
        if stageSettings || viewerOpen || launching != nil || playOptions != nil || gameDetail != nil { stagePad(k); return }
        let focus: StageGame?
        switch theatreTheme {
        case .carousel:
            let games = theatreGames()
            focus = theatreFocused(games)
            if (k == .left || k == .right), !games.isEmpty {
                let i = games.firstIndex { $0.id == focus?.id } ?? 0
                theatreFocus = games[(i + (k == .left ? -1 : 1) + games.count) % games.count].id
                return
            }
        case .cinema:
            let rows = theatreRows()
            guard !rows.isEmpty else { focus = nil; break }
            let r = cinemaRow(rows)
            let list = rows[r].games
            let c = list.firstIndex { $0.id == theatreFocus } ?? 0
            switch k {
            case .left: theatreFocus = list[max(c - 1, 0)].id; theatreRow = r; return
            case .right: theatreFocus = list[min(c + 1, list.count - 1)].id; theatreRow = r; return
            case .up, .down:
                let nr = min(max(r + (k == .up ? -1 : 1), 0), rows.count - 1)
                theatreRow = nr
                theatreFocus = rows[nr].games[min(c, rows[nr].games.count - 1)].id
                return
            default: focus = list.indices.contains(c) ? list[c] : list.first
            }
        }
        switch k {
        case .a:
            guard let g = focus else { return }
            // a game not built yet opens its page, which says what it needs
            if g.app != nil { playFromStage(g.ref) } else { caseFlipped = false; gameDetail = g.ref }
        case .y: if let g = focus { caseFlipped = false; gameDetail = g.ref }
        case .x: if let g = focus, g.app != nil { openPlayOptions(g.ref) }
        case .l, .r:
            let all = TheatreTheme.allCases
            let i = all.firstIndex(of: theatreTheme) ?? 0
            setTheatreTheme(all[(i + (k == .l ? -1 : 1) + all.count) % all.count])
        case .menu: theatreMenu = TheatreMenuRow(rawValue: theatreTheme == .carousel ? 0 : 1)?.rawValue
        case .b: theatreMenu = TheatreMenuRow.leave.rawValue
        case .options: if let g = focus { toggleFavorite(g) }
        default: break
        }
    }

    func pickTheatreMenu(_ r: TheatreMenuRow) {
        theatreMenu = nil
        switch r {
        case .carousel: setTheatreTheme(.carousel)
        case .cinema: setTheatreTheme(.cinema)
        case .settings: settingsFocus = StageSettingRow.theatreTheme.rawValue; stageSettings = true
        case .leave: leaveTheatre()
        }
    }

    /// The offer on a TV: A opens Theatre, B says not now
    func offerPad(_ k: PadKey) {
        switch k {
        case .a: enterTheatre(on: theatreOffer)
        case .b: theatreOffer = nil
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

    var body: some View {
        GeometryReader { geo in
            let u = max(geo.size.height / 1080, 0.5)
            ZStack {
                if let r = model.gameDetail, model.stageGames().contains(where: { $0.isRef(r) }) {
                    // the game's page, as on the front end (B comes back here)
                    StageView(model: model).transition(.opacity)
                } else {
                    stage
                    overlays
                }
            }
            .environment(\.tu, u)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.3), value: model.theatreTheme)
        .animation(.spring(duration: 0.3), value: model.theatreMenu)
        .animation(.easeInOut(duration: 0.25), value: model.gameDetail)
        .animation(.spring(duration: 0.35), value: model.playOptions?.id)
        .animation(.easeInOut(duration: 0.3), value: model.launching?.id)
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
        .onKeyPress(.tab) { model.theatrePad(.r); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { _ in model.theatrePad(.x); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "mM")) { _ in model.theatrePad(.menu); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "[")) { _ in model.theatrePad(.l); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "]")) { _ in model.theatrePad(.r); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in model.theatrePad(.options); return .handled }
        // the genres for Cinema's rows, and the art the games still lack
        .task(id: model.stageGames().compactMap(\.titleID).joined(separator: ",")) { model.discover.load(model.stageGames().compactMap(\.titleID)) }
        .task(id: "theatre-covers") { model.fetchCovers(model.stageGames()) }
        // left alone, the carousel turns on by itself, a game every few seconds, like a turntable in a shop window
        .task(id: "idle") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !still, model.theatreTheme == .carousel, model.theatreMenu == nil, !model.stageSettings, model.gameDetail == nil,
                      model.launching == nil, model.playOptions == nil, !model.viewerOpen, NSApp.isActive,
                      Date().timeIntervalSince(model.theatreTouched) > 12, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { continue }
                let games = model.theatreGames()
                guard games.count > 1, let i = games.firstIndex(where: { $0.id == model.theatreFocused(games)?.id }) else { continue }
                if Int(Date().timeIntervalSince(model.theatreTouched)) % 5 == 0 { model.theatreFocus = games[(i + 1) % games.count].id }
            }
        }
    }

    @ViewBuilder var stage: some View {
        switch model.theatreTheme {
        case .carousel: CarouselTheme(model: model).transition(.opacity)
        case .cinema: CinemaTheme(model: model).transition(.opacity)
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
        if let l = model.launching { LaunchScreen(model: model, launch: l, game: games.first { $0.isRef(l.ref) }).transition(.opacity) }
        if model.viewerOpen { ViewerKeys(model: model) }
        if let i = model.theatreMenu { TheatreMenu(model: model, focus: i).transition(.opacity.combined(with: .scale(scale: 0.97))) }
    }
}

/// The wordmark at the top left, the theme and the time at the top right
struct TheatreTopBar: View {
    let theme: TheatreTheme
    @Environment(\.tu) private var u

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                Text("NX").font(.system(size: 22 * u, weight: .heavy))
                Text("FORGE").font(.system(size: 22 * u, weight: .light))
            }
            .tracking(7 * u).opacity(0.9)
            Spacer()
            Text(theme.rawValue.uppercased()).font(.system(size: 16 * u, weight: .semibold)).tracking(2.4 * u)
                .padding(.horizontal, 16 * u).frame(height: 38 * u)
                .background(.white.opacity(0.10), in: .capsule).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            TimelineView(.everyMinute) { t in
                Text(t.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 24 * u, weight: .medium)).monospacedDigit()
                    .padding(.leading, 22 * u).opacity(0.88)
            }
        }
        .padding(.horizontal, 96 * u).frame(height: 120 * u)
    }
}

/// The buttons along the foot: the controller's own symbols when one is connected (PadGlyph)
struct TheatreHints: View {
    let model: AppModel
    var focus: StageGame?
    @Environment(\.tu) private var u

    var body: some View {
        HStack(spacing: 34 * u) {
            if let g = focus {
                hint("A", g.app != nil ? "Play" : "View", filled: true)
                hint("Y", "Details")
                if g.app != nil { hint("X", "Options") }
            }
            hint("L", "R", "Theme")
            hint("+", "Menu")
            hint("B", "Leave")
        }
        .font(.system(size: 20 * u, weight: .medium))
        .foregroundStyle(.white.opacity(0.82))
    }

    /// a button's symbol, half as big again as on the front end (it is drawn at a fixed size, so scaled into its own frame)
    func glyph(_ k: String, filled: Bool = false) -> some View {
        PadGlyph(text: k, filled: filled).scaleEffect(u * 1.4).frame(width: 30 * u * 1.4, height: 24 * u * 1.4)
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
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { model.theatreMenu = nil }
            VStack(alignment: .leading, spacing: 8 * u) {
                Text("Theatre").font(.system(size: 40 * u, weight: .bold)).padding(.bottom, 14 * u)
                ForEach(TheatreMenuRow.allCases, id: \.self) { r in
                    let on = r.rawValue == focus
                    let current = (r == .carousel && model.theatreTheme == .carousel) || (r == .cinema && model.theatreTheme == .cinema)
                    Button { model.pickTheatreMenu(r) } label: {
                        HStack(spacing: 18 * u) {
                            Image(systemName: icon(r)).font(.system(size: 24 * u, weight: .semibold)).frame(width: 34 * u)
                            VStack(alignment: .leading, spacing: 3 * u) {
                                Text(r.title).font(.system(size: 26 * u, weight: .semibold))
                                if let n = note(r) { Text(n).font(.system(size: 17 * u)).foregroundStyle(on ? Color.black.opacity(0.6) : StageLook.faint) }
                            }
                            Spacer()
                            if current { Image(systemName: "checkmark").font(.system(size: 22 * u, weight: .bold)) }
                        }
                        .padding(.horizontal, 24 * u).padding(.vertical, 16 * u)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background(on ? Color.white : Color.white.opacity(0.06), in: .rect(cornerRadius: 18 * u))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if r == .cinema { Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 8 * u) }
                }
            }
            .padding(40 * u)
            .frame(width: 620 * u)
            .background(StageLook.panel.opacity(0.85), in: .rect(cornerRadius: 34 * u))
            .glassEffect(.regular, in: .rect(cornerRadius: 34 * u))
            .shadow(color: .black.opacity(0.6), radius: 60 * u, y: 30 * u)
        }
    }

    func icon(_ r: TheatreMenuRow) -> String {
        switch r {
        case .carousel: TheatreTheme.carousel.symbol
        case .cinema: TheatreTheme.cinema.symbol
        case .settings: "gearshape"
        case .leave: "rectangle.portrait.and.arrow.right"
        }
    }

    func note(_ r: TheatreMenuRow) -> String? {
        switch r {
        case .carousel: TheatreTheme.carousel.note
        case .cinema: TheatreTheme.cinema.note
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
                    Button("Always open it on a TV") { model.settings.theatreOnTV = .always; model.enterTheatre(on: tv) }
                    Button("Never ask") { model.settings.theatreOnTV = .never; model.theatreOffer = nil }
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
            TheatreCarousel(games: games, focus: index, revision: CoverStore.shared.revision)
                .ignoresSafeArea()
            // the foot of the room darkens under the caption
            LinearGradient(stops: [.init(color: .clear, location: 0.62), .init(color: .black.opacity(0.85), location: 0.9), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                TheatreTopBar(theme: .carousel)
                Spacer()
                if let g = focus {
                    VStack(spacing: 16 * u) {
                        Text(g.name).font(.system(size: 66 * u, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.5)
                        Text(Self.facts(g)).font(.system(size: 22 * u, weight: .regular)).tracking(1.2 * u).foregroundStyle(StageLook.soft)
                    }
                    .id(g.id).transition(.opacity)
                    .padding(.horizontal, 120 * u)
                }
                HStack(alignment: .bottom) {
                    if !games.isEmpty {
                        (Text(String(format: "%02d", index + 1)).foregroundStyle(.white).fontWeight(.semibold) + Text("  /  \(games.count)   GAMES").foregroundStyle(StageLook.faint))
                            .font(.system(size: 19 * u)).tracking(3 * u).monospacedDigit()
                    }
                    Spacer()
                    TheatreHints(model: model, focus: focus)
                }
                .padding(.horizontal, 96 * u).padding(.top, 44 * u).padding(.bottom, 42 * u)
            }
            .animation(.easeInOut(duration: 0.35), value: focus?.id)
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
/// sight behind take the next games along as it turns, and any number of games goes round a ring of 16.
enum CarouselRing {
    static func slots(for count: Int) -> Int { min(max(count, 1), 16) }

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
        static let spacing = 1.55

        var radius: Double { max(Double(slots) * Self.spacing / (2 * .pi), 1.6) }

        override init() {
            super.init()
            scene.rootNode.addChildNode(ring)
            // a dark floor that reflects the boxes, fading out with distance
            let floor = SCNFloor()
            floor.reflectivity = 0.22
            floor.reflectionFalloffStart = 0
            floor.reflectionFalloffEnd = 1.6
            floor.reflectionResolutionScaleFactor = 0.6
            let m = SCNMaterial()
            m.diffuse.contents = NSColor(white: 0.02, alpha: 1)
            m.lightingModel = .constant
            m.transparency = 0.55
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
            cam.position = SCNVector3(x: 0, y: 1.25, z: CGFloat(r + 6.6))
            cam.look(at: SCNVector3(x: 0, y: 0.32, z: CGFloat(r - 1.2)))
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
                b.node.eulerAngles = SCNVector3(x: 0, y: CGFloat(b.place + (s == front ? spin : 0) * b.glow), z: 0)
                b.dim(0.38 + 0.62 * b.glow)
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
                    .id(g.id).transition(.opacity)
                    .ignoresSafeArea()
            }
            // the art falls away to the left, under the words, and to the foot, under the rows
            LinearGradient(stops: [.init(color: StageLook.background.opacity(0.94), location: 0), .init(color: StageLook.background.opacity(0.72), location: 0.32),
                                   .init(color: StageLook.background.opacity(0.08), location: 0.64), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
            LinearGradient(stops: [.init(color: .clear, location: 0.38), .init(color: StageLook.background.opacity(0.86), location: 0.68), .init(color: StageLook.background, location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                TheatreTopBar(theme: .cinema)
                Spacer(minLength: 0)
                if let g = focus { info(g, row: rows.indices.contains(r) ? rows[r].title : "").id(g.id).transition(.opacity) }
                rowsView(rows, current: r, col: col)
                    .frame(height: 360 * u, alignment: .top).clipped()
                HStack { Spacer(); TheatreHints(model: model, focus: focus) }
                    .padding(.horizontal, 96 * u).padding(.bottom, 40 * u)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: focus?.id)
        .animation(.easeInOut(duration: 28).repeatForever(autoreverses: true), value: drift)
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
            HStack(spacing: 18 * u) {
                Button { model.theatrePad(.a) } label: {
                    Label(g.app == nil ? "View" : g.last != nil ? "Resume" : "Play", systemImage: g.app == nil ? "info.circle" : "play.fill")
                        .font(.system(size: 24 * u, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 34 * u).frame(height: 64 * u).background(.white, in: .rect(cornerRadius: 14 * u))
                }
                .buttonStyle(.plain)
                Button { model.theatrePad(.y) } label: { ghost("Details") }.buttonStyle(.plain)
                if g.app != nil { Button { model.theatrePad(.x) } label: { ghost("Play Options") }.buttonStyle(.plain) }
            }
            .padding(.top, 34 * u)
        }
        .padding(.horizontal, 96 * u).padding(.bottom, 40 * u)
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
            CoverArt.tint(game).opacity(0.5)
            if near, let art = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            }
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
        .clipShape(.rect(cornerRadius: 16 * u))
        .overlay(RoundedRectangle(cornerRadius: 16 * u).strokeBorder(.white, lineWidth: focused ? 4 * u : 0))
        .shadow(color: .black.opacity(focused ? 0.7 : 0.5), radius: (focused ? 34 : 18) * u, y: (focused ? 26 : 14) * u)
        .scaleEffect(focused ? 1.09 : 1)
        .zIndex(focused ? 1 : 0)
        .animation(.spring(duration: 0.3), value: focused)
    }
}
