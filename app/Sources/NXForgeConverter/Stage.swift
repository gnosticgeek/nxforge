// The front end: the games as covers on a dark stage lit by the focused game's colours, shown instead of the converter's
// pages (the Converter tab goes back to them). Home is a shelf under the game last played, Library every game in the games
// folder (the ones not built yet dimmed), a game's page has its box in 3D, and Play goes straight into the game
// (PlayOptions.swift). Everything works from a controller (ControllerNav → stagePad), the keyboard and the pointer.
import AppKit
import GameController
import SwiftUI

enum StageTab: String, CaseIterable { case home = "Home", discover = "Discover", library = "Library" }
/// The Library's two collections: every game in the games folder, or only the ones built and playable on this Mac
enum StageScope: String, CaseIterable { case owned = "Owned", built = "Built" }
enum StageFilter: String, CaseIterable {
    case all = "All", favorites = "Favourites", switch2 = "Switch 2", switch1 = "Switch", notBuilt = "Not built yet"
    /// the filters that mean something in a collection: Built has no unbuilt games
    static func shown(_ scope: StageScope) -> [StageFilter] { scope == .built ? allCases.filter { $0 != .notBuilt } : allCases }
}

/// A game as the front end shows it: a Library game with its build, or an app built from files outside the games folder.
struct StageGame: Identifiable, Hashable {
    var id: String
    var ref: GameRef
    var name: String
    var console: Console
    var titleID: String?
    var icon: String?
    var app: String?
    var version: String?
    var last: Date?
    var total: Double = 0
    var outdated = false
    var game: LibraryGame?
    var favorite = false

    var coverKey: String { CoverStore.key(titleID: titleID, name: name) }
    /// what Settings.favorites keeps for it: the title ID, else the app
    var favoriteKey: String { titleID ?? app ?? id }
    func isRef(_ r: GameRef) -> Bool { (ref.libraryID != nil && ref.libraryID == r.libraryID) || (app != nil && app == r.app) }
}

enum StageLook {
    static let background = Color(red: 0.031, green: 0.035, blue: 0.047)
    static let soft = Color(white: 0.80)
    static let faint = Color(white: 0.66)
    static let panel = Color(red: 0.11, green: 0.118, blue: 0.15)

    /// the light along a card's or a button's top edge
    static let edge = LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)
    /// a card's fill: a little lighter at the top
    static let card = LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)

    /// Fine grey noise, tiled over the stage: it breaks up the banding of the big soft gradients
    @MainActor static let grain: NSImage = {
        let n = 192
        var px = [UInt8](repeating: 255, count: n * n * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 40)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return NSImage(cgImage: cg, size: NSSize(width: n / 2, height: n / 2))
    }()

    static func played(_ d: Date?) -> String {
        guard let d else { return "Not played yet" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Played today" }
        if cal.isDateInYesterday(d) { return "Played yesterday" }
        return "Played \(d.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// The front end's Settings rows a controller steps through, in their order on screen
enum StageSettingRow: Int, CaseIterable { case straightPlay, firstPlayOptions, batteryPreset, returnToLibrary, localShaders, sessionRecap, lightWhilePlaying, squareCovers, downloadCovers, downloadHeroes, downloadStoreInfo, mediaInGameFolder, startIn }

enum PadKey { case left, right, up, down, a, b, x, y, l, r, menu, options }

extension AppModel {
    /// Every game the front end knows, built ones first, then the most recently played, then by name.
    func stageGames() -> [StageGame] {
        let _ = revision
        let builds = libraryBuilds(), plays = Playtime.load()
        var out: [StageGame] = [], apps = Set<String>(), titles = Set<String>()
        for g in library?.games ?? [] {
            if let t = g.titleID {   // the same game in two folders is one cover
                if titles.contains(t) { continue }
                titles.insert(t)
            }
            let b = build(of: g, in: builds)
            if let a = b?.app { apps.insert(a) }
            let rec = g.titleID.flatMap { plays[$0] } ?? b.flatMap { plays[$0.app] }
            out.append(StageGame(id: g.id, ref: GameRef(libraryID: g.id, app: b?.app), name: g.displayName, console: g.console, titleID: g.titleID,
                                 icon: g.icon, app: b?.app, version: g.version, last: rec?.last, total: rec?.total ?? 0, outdated: outdated(b), game: g))
        }
        for (t, b) in builds where !apps.contains(b.app) && !titles.contains(t) {
            let rec = plays[t] ?? plays[b.app]
            out.append(StageGame(id: b.app, ref: GameRef(libraryID: nil, app: b.app), name: b.app.url.deletingPathExtension().lastPathComponent,
                                 console: b.record.map { Console.of($0) } ?? (t.hasPrefix("04") ? .switch2 : .switch1), titleID: t, icon: nil, app: b.app,
                                 version: nil, last: rec?.last, total: rec?.total ?? 0, outdated: outdated(b), game: nil))
        }
        // two copies of one game under different title IDs (a second dump, another region) are one cover: the built one, else the first
        var seen: [String: Int] = [:], one: [StageGame] = []
        for g in out {
            let k = "\(g.console)|\(CoverSource.normalize(g.name))"
            if let i = seen[k] {
                if one[i].app == nil && g.app != nil { one[i] = g }
            } else { seen[k] = one.count; one.append(g) }
        }
        let favs = Set(settings.favorites)
        for i in one.indices { one[i].favorite = favs.contains(one[i].favoriteKey) }
        return one.sorted { a, b in
            if (a.app != nil) != (b.app != nil) { return a.app != nil }
            if a.last != b.last { return (a.last ?? .distantPast) > (b.last ?? .distantPast) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The games on screen: Home's shelf has the built ones (every game when none is built), favourites first, Library the filter's.
    func stageShown(_ games: [StageGame]) -> [StageGame] {
        if stageTab == .home {
            let built = games.filter { $0.app != nil }
            let shelf = built.isEmpty ? games : built
            return shelf.filter(\.favorite) + shelf.filter { !$0.favorite }
        }
        if stageTab == .discover { return [] }
        var out = stageScope == .built ? games.filter { $0.app != nil } : games
        switch stageFilter {
        case .all: break
        case .favorites: out = out.filter(\.favorite)
        case .switch2: out = out.filter { $0.console == .switch2 }
        case .switch1: out = out.filter { $0.console == .switch1 }
        case .notBuilt: out = out.filter { $0.app == nil }
        }
        let q = stageSearch.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { out = TitleMatch.sorted(out.filter { TitleMatch.matches(q, [$0.name, $0.titleID]) }, query: q, title: \.name, last: \.last) }
        return out
    }

    /// Where L and R go in the Library, in order
    static let libraryStops: [(StageScope, StageFilter)] = StageScope.allCases.flatMap { sc in StageFilter.shown(sc).map { (sc, $0) } }

    /// The game in focus: the one picked, else on Home the one played last (Continue playing), else the first
    func stageFocus(_ shown: [StageGame]) -> StageGame? {
        shown.first { $0.id == libraryFocus } ?? (stageTab == .home ? Self.lastPlayed(shown) : nil) ?? shown.first
    }

    static func lastPlayed(_ games: [StageGame]) -> StageGame? {
        games.filter { $0.last != nil }.max { ($0.last ?? .distantPast) < ($1.last ?? .distantPast) }
    }

    /// Adds the game to Favourites (Home's shelf starts with them, and the Library has a filter), or takes it off
    func toggleFavorite(_ g: StageGame) {
        if let i = settings.favorites.firstIndex(of: g.favoriteKey) { settings.favorites.remove(at: i) } else { settings.favorites.append(g.favoriteKey) }
        revision += 1
    }

    func moveStageFocus(dx: Int = 0, dy: Int = 0) {
        let shown = stageShown(stageGames())
        guard !shown.isEmpty else { return }
        // from the game on screen (Home's is the one played last until one is picked)
        guard let cur = stageFocus(shown), let i = shown.firstIndex(where: { $0.id == cur.id }) else { libraryFocus = shown.first?.id; return }
        let step = stageTab == .home ? dx : dx + dy * max(stageColumns, 1)
        libraryFocus = shown[min(max(i + step, 0), shown.count - 1)].id
    }

    func showStage(_ tab: StageTab) {
        frontEnd = true
        gameDetail = nil
        stageTab = tab
    }

    func showConverter() {
        playOptions = nil
        stageSettings = false
        gameDetail = nil
        frontEnd = false
    }

    func toggleFullScreen() {
        (NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    /// A controller's button, or its key on the keyboard, on the front end.
    func stagePad(_ k: PadKey) {
        if viewerOpen { viewerPad(k); return }
        if let l = launching {
            if let f = l.failure {
                switch k {
                case .a: retryLaunch()
                case .x: if f.fix != nil && f.fix != .showLog { launchFix(f) } else if let p = f.log { reveal(p) }
                case .y: if let p = f.log { reveal(p) }
                case .b: launching = nil
                default: break
                }
            } else if k == .b { launching = nil }
            return
        }
        if stageSettings {
            switch k {
            case .b, .menu: stageSettings = false
            case .up: settingsFocus = max(settingsFocus - 1, 0)
            case .down: settingsFocus = min(settingsFocus + 1, StageSettingRow.allCases.count - 1)
            case .a: stepSetting(StageSettingRow.allCases[settingsFocus], by: 1, toggle: true)
            case .left: stepSetting(StageSettingRow.allCases[settingsFocus], by: -1)
            case .right: stepSetting(StageSettingRow.allCases[settingsFocus], by: 1)
            default: break
            }
            return
        }
        if let o = playOptions {
            let rows = o.rows
            switch k {
            case .up: o.focus = max(o.focus - 1, 0)
            case .down: o.focus = min(o.focus + 1, max(rows.count - 1, 0))
            case .left: if rows.indices.contains(o.focus) { o.step(rows[o.focus], by: -1) }
            case .right: if rows.indices.contains(o.focus) { o.step(rows[o.focus], by: 1) }
            case .l: o.moveTab(-1)
            case .r: o.moveTab(1)
            case .y: o.nextPreset()
            case .a: playWithOptions(save: true)
            case .x: playWithOptions(save: false)
            case .b, .menu: closePlayOptions()
            case .options: break
            }
            return
        }
        if let r = gameDetail {
            switch k {
            case .a: playFromStage(r)
            case .x: openPlayOptions(r)
            case .b: gameDetail = nil
            case .y, .r: if let g = stageGames().first(where: { $0.isRef(r) }) { openCaseViewer(g) }
            case .menu: settingsFocus = 0; stageSettings = true
            case .options: if let g = stageGames().first(where: { $0.isRef(r) }) { toggleFavorite(g) }
            default: break
            }
            return
        }
        if stageTab == .discover { discoverPad(k); return }
        let focus = stageFocus(stageShown(stageGames()))
        switch k {
        case .left: moveStageFocus(dx: -1)
        case .right: moveStageFocus(dx: 1)
        case .up: moveStageFocus(dy: -1)
        case .down: moveStageFocus(dy: 1)
        case .a: if let g = focus { libraryFocus = g.id; playFromStage(g.ref) }
        case .x: if let g = focus { libraryFocus = g.id; openPlayOptions(g.ref) }
        case .y: if let g = focus { libraryFocus = g.id; caseFlipped = false; gameDetail = g.ref }
        case .b: if stageTab == .library { stageTab = .home }
        // L and R walk Home, then the Library's collections and their filters: Owned's, then Built's
        case .l:
            let steps = Self.libraryStops
            if stageTab == .library, let i = steps.firstIndex(where: { $0 == (stageScope, stageFilter) }), i > 0 { (stageScope, stageFilter) = steps[i - 1] } else { stageTab = .home }
        case .r:
            let steps = Self.libraryStops
            if stageTab == .home { stageTab = .library }
            else if let i = steps.firstIndex(where: { $0 == (stageScope, stageFilter) }), i + 1 < steps.count { (stageScope, stageFilter) = steps[i + 1] }
        case .menu: settingsFocus = 0; stageSettings = true
        case .options: if let g = focus { libraryFocus = g.id; toggleFavorite(g) }
        }
    }

    /// A Settings row from a controller: left and right change it, A flips a switch
    func stepSetting(_ row: StageSettingRow, by d: Int, toggle: Bool = false) {
        func flip(_ v: inout Bool) { v = toggle ? !v : d > 0 }
        switch row {
        case .straightPlay: flip(&settings.straightPlay)
        case .firstPlayOptions: flip(&settings.firstPlayOptions)
        case .batteryPreset: flip(&settings.batteryPreset)
        case .returnToLibrary: flip(&settings.returnToLibrary)
        case .localShaders: flip(&settings.localShaders)
        case .sessionRecap: flip(&settings.sessionRecap)
        case .lightWhilePlaying: flip(&settings.lightWhilePlaying)
        case .squareCovers: flip(&settings.squareCovers)
        case .downloadCovers: flip(&settings.downloadCovers)
        case .downloadHeroes: flip(&settings.downloadHeroes)
        case .downloadStoreInfo: flip(&settings.downloadStoreInfo)
        case .mediaInGameFolder: flip(&settings.mediaInGameFolder)
        case .startIn:
            let all = StartIn.allCases
            if let i = all.firstIndex(of: settings.startIn) { settings.startIn = all[(i + d + all.count) % all.count] }
        }
    }

    /// Play from the options panel: with the choices kept for the game, or for this run only.
    func playWithOptions(save: Bool) {
        guard let o = playOptions else { return }
        let once = save ? [:] : o.changed
        if save { o.save() }
        let saved = save ? o.values : o.saved
        playOptions = nil
        launch(o.ref, app: o.app, name: o.name, settings: o.settings, saved: saved, once: once, note: once.isEmpty ? nil : "These options are for this run only")
    }

    /// The pictures the games still lack are fetched (a setting).
    func fetchCovers(_ games: [StageGame]) {
        CoverStore.shared.showHeroes = settings.downloadHeroes
        CoverStore.shared.fetchNintendoLife(games.map { ($0.coverKey, $0.titleID, $0.name, $0.console.rawValue) },
                                            heroes: settings.downloadHeroes, boxes: settings.downloadCovers)
        if settings.downloadHeroes { CoverStore.shared.fetchHeroes(games.map { ($0.coverKey, $0.titleID, $0.name) }) }
        if settings.downloadCovers || settings.squareCovers { CoverStore.shared.fetchSquares(games.map { ($0.coverKey, $0.titleID, $0.name) }) }
        guard settings.downloadCovers else { return }
        CoverStore.shared.fetchMissing(games.map { ($0.coverKey, $0.name) })
    }

    func chooseCover(_ g: StageGame, _ side: CoverSide) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose the \(side.rawValue) cover for \(g.name)"
        p.prompt = "Use as Cover"
        guard p.runModal() == .OK, let u = p.url else { return }
        if !CoverStore.shared.setOwn(g.coverKey, side, from: u) { showBanner("That picture could not be read", tone: .warning) }
    }

    /// A cover from a picture's address on the web (a link copied from a shop or a fan site, already filled in when one is on
    /// the clipboard). Only what the player gives is downloaded, once, and kept on this Mac like a chosen file.
    func coverFromLink(_ g: StageGame, _ side: CoverSide) {
        let a = NSAlert()
        a.messageText = "\(side == .front ? "Front" : "Back") Cover from a Link"
        a.informativeText = "Paste the address of a picture of \(g.name)'s \(side.rawValue) cover. A shop's picture of the whole case is cut down to the printed cover."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://…"
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), clip.hasPrefix("http") { field.stringValue = clip }
        a.accessoryView = field
        a.addButton(withTitle: "Use as Cover")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            showBanner("That is not a web address", detail: "A link to a picture starts with https://", tone: .warning)
            return
        }
        let key = g.coverKey, name = g.name
        showBanner("Downloading the cover for \(name)…", symbol: "arrow.down.circle")
        Task {
            let data = await CoverStore.get(url, browser: true)
            if let data, CoverStore.shared.setOwn(key, side, data: data) {
                self.showBanner("New \(side.rawValue) cover for \(name)", tone: .success)
            } else {
                self.showBanner(data == nil ? "That link could not be downloaded" : "That link is not a picture", detail: text, tone: .warning)
            }
        }
    }
}

struct StageButton: ButtonStyle {
    var primary = false
    var height: CGFloat = 46
    /// the main action's glow, in the game's colour
    var glow: Color? = nil
    /// real glass, for the few large buttons over the stage itself
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: primary ? 17 : 15, weight: primary ? .bold : .semibold))
            .padding(.horizontal, primary ? 26 : 20).frame(height: height)
            .foregroundStyle(primary ? Color.black : Color.white)
        Group {
            if primary {
                label.background(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom), in: .capsule)
                    .shadow(color: (glow ?? .white).opacity(glow == nil ? 0.18 : 0.60), radius: height * 0.42, y: height * 0.12)
            } else if glass {
                label.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                label.background(StageLook.card, in: .capsule).overlay(Capsule().strokeBorder(StageLook.edge, lineWidth: 1))
            }
        }
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .animation(.spring(duration: 0.2), value: configuration.isPressed)
        .contentShape(.capsule)
    }
}

/// A controller button in the hint bar
/// The symbol on each of the connected controller's buttons, as the system names it (a.circle, xmark.circle, l1.rectangle.roundedbottom…):
/// the hints show the button that does the thing on this pad, so Confirm is ✕ on a PlayStation pad and never assumed to be "A"
/// (from RetroReplay's ControllerPrompts). Empty without a controller: the hints keep their letters.
@MainActor @Observable
final class PadLabels {
    static let shared = PadLabels()
    private(set) var symbols: [PadKey: String] = [:]

    func refresh() {
        guard let p = GCController.controllers().lazy.compactMap(\.extendedGamepad).first else { symbols = [:]; return }
        var s: [PadKey: String] = [:]
        func put(_ k: PadKey, _ b: GCControllerButtonInput?) { if let n = b?.sfSymbolsName, NSImage(systemSymbolName: n, accessibilityDescription: nil) != nil { s[k] = n } }
        put(.a, p.buttonA); put(.b, p.buttonB); put(.x, p.buttonX); put(.y, p.buttonY)
        put(.l, p.leftShoulder); put(.r, p.rightShoulder); put(.menu, p.buttonMenu); put(.options, p.buttonOptions)
        if s != symbols { symbols = s }
    }

    static func key(_ text: String) -> PadKey? {
        switch text {
        case "A": .a
        case "B": .b
        case "X": .x
        case "Y": .y
        case "L": .l
        case "R": .r
        case "+": .menu
        case "−": .options
        default: nil
        }
    }

    /// The symbol to draw for a hint's letter, filled for the main action when the symbol has a filled form
    func symbol(_ text: String, filled: Bool) -> String? {
        guard let k = Self.key(text), let n = symbols[k] else { return nil }
        if filled, NSImage(systemSymbolName: n + ".fill", accessibilityDescription: nil) != nil { return n + ".fill" }
        return n
    }
}

struct PadGlyph: View {
    let text: String
    var filled = false

    var body: some View {
        if let sym = PadLabels.shared.symbol(text, filled: filled) {
            Image(systemName: sym).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(filled ? Color.white : StageLook.soft)
                .frame(minWidth: 22, minHeight: 22)
                .accessibilityLabel(text)
        } else {
            letter
        }
    }

    var letter: some View {
        Text(text).font(.system(size: 11, weight: .heavy))
            .padding(.horizontal, text.count > 1 ? 7 : 0).frame(minWidth: 22, minHeight: 22)
            .foregroundStyle(filled ? Color.black : StageLook.soft)
            .background(filled ? Color.white : Color.clear, in: .capsule)
            .overlay(Capsule().strokeBorder(filled ? Color.clear : StageLook.soft, lineWidth: 1.5))
    }
}

/// The stage's light: the focused game's own art, far out of focus, fills the room; its colour is brightest top left with
/// a cooler turn of it top right, the corners fall away, and it all fades to black below, under a fine grain.
struct StageBackdrop: View {
    let tint: Color
    /// the game's art, small (CoverArt.ambient), and what names it, so one game's fades into the next's
    var art: NSImage? = nil
    var artKey = ""
    /// how bright the light is: full on the front end, lower behind the converter's pages of text
    var strength: Double = 1
    /// the two lights drift slowly, so the room is never quite still
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                StageLook.background
                // the art comes blurred already (CoverArt.soften): a live 60-point blur of the whole window was a full-screen pass a
                // frame on a 4K display. Reduce Transparency: no art through the room, only its colour.
                if let art, !solid {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h).scaleEffect(1.3).saturation(1.5)
                        .opacity(0.42 * strength)
                        .id(artKey).transition(.opacity)
                }
                Circle().fill(RadialGradient(colors: [tint.opacity(0.42 * strength), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.48))
                    .frame(width: w * 0.96, height: w * 0.96).position(x: w * 0.22, y: h * 0.12)
                    .offset(x: drift ? w * 0.05 : -w * 0.03, y: drift ? h * 0.04 : -h * 0.02)
                Circle().fill(RadialGradient(colors: [tint.opacity(0.24 * strength), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.40))
                    .frame(width: w * 0.8, height: w * 0.8).hueRotation(.degrees(48)).position(x: w * 0.92, y: h * 0.08)
                    .offset(x: drift ? -w * 0.06 : w * 0.02, y: drift ? h * 0.05 : 0)
                RadialGradient(colors: [.clear, .black.opacity(0.50)], center: UnitPoint(x: 0.5, y: 0.35), startRadius: w * 0.30, endRadius: w * 0.95)
                LinearGradient(stops: [.init(color: StageLook.background.opacity(0), location: 0), .init(color: StageLook.background.opacity(0.86), location: 0.72),
                                       .init(color: StageLook.background, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.62).frame(maxHeight: .infinity, alignment: .bottom)
                Image(nsImage: StageLook.grain).resizable(resizingMode: .tile).blendMode(.overlay).opacity(0.07)
            }
            .frame(width: w, height: h).clipped()
            .drawingGroup()   // one layer for the whole room: its gradients and grain are composited once, not each over the others every frame
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: drift)
        .onAppear { if !still { drift = true } }
        .animation(.easeInOut(duration: 0.55), value: artKey)
        .animation(.easeInOut(duration: 0.45), value: tint)
        .accessibilityHidden(true)
    }
}

struct StageView: View {
    @Bindable var model: AppModel
    @FocusState private var keys: Bool

    var body: some View {
        let games = model.stageGames()
        let shown = model.stageShown(games)
        let detail = model.gameDetail.flatMap { r in games.first { $0.isRef(r) } }
        let focus = detail ?? model.stageFocus(shown)
        let tint = focus.map { CoverArt.tint($0) } ?? (model.stageTab == .discover ? Color(red: 0.45, green: 0.30, blue: 0.80) : Color(red: 0.25, green: 0.35, blue: 0.75))
        ZStack {
            StageBackdrop(tint: tint, art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "", strength: detail == nil ? 1 : 0.45)
            // the game's key art behind its page, and behind Home's headline for the game in focus
            if let g = detail { GameKeyArt(game: g, banner: true).id(g.id).transition(.opacity) }
            else if model.stageTab == .home, let g = focus { GameKeyArt(game: g, coverFallback: false).id(g.id).transition(.opacity) }
            VStack(spacing: 0) {
                if detail == nil { StageTopBar(model: model) }
                Group {
                    if let g = detail {
                        StageGamePage(model: model, game: g)
                    } else if model.stageTab == .discover {
                        DiscoverView(model: model, state: model.discover)
                    } else if games.isEmpty {
                        StageEmpty(model: model)
                    } else if model.stageTab == .home {
                        StageHome(model: model, games: shown, focus: focus, total: games.count)
                    } else {
                        StageLibrary(model: model, all: games, games: shown, focus: focus)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                StageHints(model: model, focus: focus, detail: detail != nil)
            }
            if let o = model.playOptions {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.closePlayOptions() }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PlayOptionsPanel(model: model, state: o)
                }
                .padding(16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let s = model.caseViewer {
                CaseViewer(model: model, state: s).id(s.game.id).transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if let g = model.gallery {
                GalleryViewer(model: model, state: g).id(g.id).transition(.opacity)
            }
            if let m = model.manual {
                ManualViewer(model: model, state: m).id(m.id).transition(.opacity)
            }
            if let l = model.launching {
                LaunchScreen(model: model, launch: l, game: games.first { $0.isRef(l.ref) }).transition(.opacity)
            }
            if model.viewerOpen { ViewerKeys(model: model) }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.35), value: model.playOptions?.id)
        .animation(.easeInOut(duration: 0.3), value: model.launching?.id)
        .animation(.easeInOut(duration: 0.25), value: model.gallery?.id)
        .animation(.easeInOut(duration: 0.25), value: model.caseViewer?.game.id)
        .animation(.easeInOut(duration: 0.25), value: model.manual?.id)
        .animation(.easeInOut(duration: 0.25), value: model.gameDetail)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("NXForge")
        .focusable()
        .focused($keys)
        .focusEffectDisabled()
        .onAppear { keys = true }
        .onKeyPress(.leftArrow) { model.stagePad(.left); return .handled }
        .onKeyPress(.rightArrow) { model.stagePad(.right); return .handled }
        .onKeyPress(.upArrow) { model.stagePad(.up); return .handled }
        .onKeyPress(.downArrow) { model.stagePad(.down); return .handled }
        .onKeyPress(.return) { model.stagePad(.a); return .handled }
        .onKeyPress(.space) { model.stagePad(.y); return .handled }
        .onKeyPress(.escape) { model.stagePad(.b); return .handled }
        .onKeyPress(.tab) { model.stagePad(.r); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { _ in model.stagePad(.x); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in
            if let g = detail ?? focus { model.toggleFavorite(g) }
            return .handled
        }
        .task(id: coverTaskKey(games)) { model.fetchCovers(games) }
        .task(id: "\(model.settings.mediaInGameFolder)|\(CoverStore.shared.revision)|\(StoreInfoStore.shared.revision)|\(model.revision)|" + games.map { "\($0.id)\($0.app ?? "")" }.joined(separator: "|")) {
            GameFolderMediaSync.shared.schedule(model)
        }
        .task(id: games.map { "\($0.id)\($0.outdated)" }.joined(separator: "|") + "|\(model.playing.count)|\(model.revision)") { await model.refreshAttention(games) }
    }

    /// The key that restarts the cover fetch: the games' covers and the three art settings. It is built in steps so the compiler can type-check it.
    private func coverTaskKey(_ games: [StageGame]) -> String {
        let covers: String = games.map { $0.coverKey }.joined(separator: "|")
        let flags: String = [model.settings.downloadCovers, model.settings.downloadHeroes, model.settings.squareCovers].map { $0 ? "1" : "0" }.joined()
        return covers + flags
    }
}

struct StageTopBar: View {
    @Bindable var model: AppModel
    @Namespace private var marks

    var body: some View {
        // the logo at the left, the Home / Library / Converter switch in the middle, the rest at the right
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2).accessibilityHidden(true)
                Text("NXForge").font(.system(size: 18, weight: .heavy)).fontWidth(.expanded).tracking(-0.4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                ForEach(StageTab.allCases, id: \.self) { t in
                    tab(t.rawValue, on: model.frontEnd && model.stageTab == t) { model.showStage(t) }
                }
                tab("Converter", on: !model.frontEnd) { if model.frontEnd { model.showConverter() } }
                    .help("Convert, Game Files, Builds, Storage, Toolchain and Updates")
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            .animation(.spring(duration: 0.32), value: model.stageTab)
            .layoutPriority(1)
            HStack(spacing: 14) {
            Spacer(minLength: 0)
            if let pad = GCController.controllers().first?.vendorName {
                Label(pad, systemImage: "gamecontroller").font(.callout.weight(.medium)).foregroundStyle(StageLook.soft)
                    .padding(.horizontal, 12).frame(height: 36).glassEffect(.regular, in: .capsule)
            }
            if let s = search {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(StageLook.soft)
                    TextField(s.prompt, text: s.text).textFieldStyle(.plain).frame(width: 170)
                    if !s.text.wrappedValue.isEmpty {
                        Button { s.text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                            .buttonStyle(.plain).accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 14).frame(height: 36).glassEffect(.regular, in: .capsule)
            }
            round("arrow.up.left.and.arrow.down.right", "Full Screen") { model.toggleFullScreen() }
            round("slider.horizontal.3", "Settings") { model.stageSettings = true }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40).padding(.top, 6).padding(.bottom, 10)
        // under the converter's bar, a hairline between it and the page's own tabs
        .overlay(alignment: .bottom) {
            if !model.frontEnd { Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 32) }
        }
    }

    /// The one search field, for whichever list is on screen: the covers, the converter's game files or its builds.
    var search: (prompt: String, text: Binding<String>)? {
        if model.frontEnd { return model.stageTab == .library ? ("Search games", $model.stageSearch) : nil }
        // Discover, the converter's Game Files and Builds have their own search fields
        return nil
    }

    func tab(_ title: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).frame(height: 30)
                .foregroundStyle(on ? Color.black : Color(white: 0.92))
                .background { if on { Capsule().fill(convertAccent).matchedGeometryEffect(id: "tab", in: marks) } }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func round(_ symbol: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// The game in focus, large: what it is, when it was played, what it plays with, and Play.
struct StageHero: View {
    let model: AppModel
    let game: StageGame
    var first = false
    var titleSize: CGFloat = 52
    /// off on the game's own page
    var showDetails = true

    var body: some View {
        let _ = model.revision
        let g = game
        let list = g.app.map { LaunchSettings.load(app: $0) } ?? []
        let values = Dictionary(list.map { ($0.env, LaunchSettings.value($0, app: g.app ?? "")) }, uniquingKeysWith: { a, _ in a })
        let tint = CoverArt.tint(g)
        let playing = model.isPlaying(app: g.app ?? "")
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Circle().fill(g.app == nil ? Color(white: 0.6) : playing ? Color(red: 0.38, green: 0.65, blue: 0.98) : tint)
                    .brightness(g.app == nil ? 0 : 0.3).frame(width: 8, height: 8).shadow(color: tint.opacity(g.app == nil ? 0 : 0.9), radius: 6)
                Text(eyebrow).font(.system(size: 11.5, weight: .bold)).fontWidth(.expanded).kerning(1.8).foregroundStyle(StageLook.soft)
            }
            Text(g.name).font(.system(size: titleSize, weight: .heavy)).tracking(-1.4).lineLimit(2).minimumScaleFactor(0.6)
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 14, weight: .semibold))
                    Text(facts.joined(separator: "  ·  ")).lineLimit(1)
                }
                if let when { Text(when).lineLimit(1) }
            }
            .font(.system(size: 15.5, weight: .medium)).foregroundStyle(StageLook.soft)
            .shadow(color: .black.opacity(0.5), radius: 8)
            HStack(spacing: 10) {
                if g.app != nil {
                    Button { model.libraryFocus = g.id; model.playFromStage(g.ref) } label: { Label(playing ? "Resume" : "Play", systemImage: "play.fill").padding(.horizontal, 8) }
                        .buttonStyle(StageButton(primary: true, height: 54, glow: tint))
                    Button { model.libraryFocus = g.id; model.openPlayOptions(g.ref) } label: { Label("Play options", systemImage: "slider.horizontal.3") }
                        .buttonStyle(StageButton(height: 54, glass: true))
                    if playing {
                        Button { model.quitGame(app: g.app ?? "") } label: { Label("Quit game", systemImage: "xmark") }
                            .buttonStyle(StageButton(height: 54, glass: true)).help("Quits the running game, as its own Quit does")
                    }
                } else {
                    let st = model.status(g)
                    Button { model.fix(g) } label: { Label(st.action, systemImage: st.actionSymbol).padding(.horizontal, 8) }
                        .buttonStyle(StageButton(primary: true, height: 54, glow: tint)).disabled(st == .notBuilt && (model.run.running || model.batchRunning))
                        .help(st.detail)
                }
                if showDetails {
                    Button { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref } label: {
                        HStack(spacing: 8) { Text("Details"); Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)) }
                            .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 14).frame(height: 54).contentShape(.rect)
                    }
                    .buttonStyle(.plain).help("The game's page (Y)")
                }
                Button { model.toggleFavorite(g) } label: {
                    Image(systemName: g.favorite ? "star.fill" : "star").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(g.favorite ? Color(red: 1, green: 0.82, blue: 0.30) : Color.white).frame(width: 54, height: 54)
                        .glassEffect(.regular.interactive(), in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain).help(g.favorite ? "Remove from Favourites (F)" : "Add to Favourites (F)")
                .accessibilityLabel(g.favorite ? "Remove from Favourites" : "Add to Favourites")
            }
            .padding(.top, 8)
            if !list.isEmpty {
                let parts = [PlayOptions.current(settings: list, values: values).rawValue] + PlayOptions.summary(settings: list, values: values).map(\.value)
                Button { model.libraryFocus = g.id; model.openPlayOptions(g.ref) } label: {
                    Text(parts.joined(separator: "  ·  ")).font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.faint).lineLimit(1)
                        .padding(.vertical, 4).contentShape(.rect)
                }
                .buttonStyle(.plain).padding(.leading, 4).help("What the game starts with: opens Play options")
            }
        }
    }

    var eyebrow: String {
        if game.app == nil { return model.status(game).eyebrow }
        if model.isSuspended(app: game.app ?? "") { return "PAUSED · STILL RUNNING" }
        if model.isPlaying(app: game.app ?? "") { return "PLAYING NOW" }
        if model.randomPick == game.id { return "RANDOM PICK" }
        if game.last == nil { return "IN YOUR LIBRARY" }
        return first ? "CONTINUE PLAYING" : "RECENTLY PLAYED"
    }

    /// The line under the name: the console, then the playtime
    var facts: [String] {
        var out = [game.console.rawValue]
        if let v = game.version, !v.isEmpty, game.total == 0 { out.append("Version \(v)") }
        if game.total > 0 { out.append("\(Playtime.text(game.total)) played") }
        return out
    }

    /// The second line: when it was last played
    var when: String? {
        guard game.app != nil else { return model.status(game).detail }
        return game.last.map { "Last played \(relativeDay($0).lowercasedFirst)" } ?? "Not played yet"
    }
}

struct StageHome: View {
    @Bindable var model: AppModel
    let games: [StageGame]
    let focus: StageGame?
    let total: Int
    /// whether the game in focus has wide art or a screenshot filling the room (GameKeyArt); without one its 3D case stands on the right
    @State private var keyArt = false
    /// Your Week (HomeWeek.swift), read when the play records may have changed
    @State private var week: PlayWeek?
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        GeometryReader { geo in
            // the hero keeps the room it needs (a smaller title in a short window, as under the build strip), and the shelf's
            // covers take what is left, so the names under them never run into the hints
            let bigTitle = geo.size.width > 1100 && geo.size.height > 760
            let heroRoom: CGFloat = bigTitle ? 440 : 380
            let aspect = model.settings.squareCovers ? 1 : CoverSource.aspect
            let tile = min(max(min(geo.size.width * 0.112, (geo.size.height - heroRoom - 140) * aspect), 90), 190)
            let caseH = min(max(geo.size.height - tile / aspect - 150, 220), 560)
            let tileH = tile / aspect
            let shelf = tileH + 78
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    if let g = focus {
                        StageHero(model: model, game: g, first: AppModel.lastPlayed(games)?.id == g.id, titleSize: bigTitle ? 60 : 44)
                            .frame(maxWidth: 640, alignment: .leading)
                            .id(g.id)
                            .transition(.asymmetric(insertion: still ? .opacity : .opacity.combined(with: .offset(y: 14)), removal: .opacity))
                    }
                    Spacer(minLength: 0)
                    if let g = focus, geo.size.width > 980, !keyArt || solid {
                        GameCase(game: g).frame(width: caseH * 0.72, height: caseH).padding(.trailing, geo.size.width > 1250 ? 50 : 0)
                            .padding(.bottom, -caseH * 0.2)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 64)
                .frame(maxHeight: .infinity)
                .animation(.easeOut(duration: 0.32), value: focus?.id)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Your games").font(.system(size: 26, weight: .heavy)).tracking(-0.4)
                    Text("\(games.filter { $0.app != nil }.count) ready").font(.system(size: 16, weight: .medium)).foregroundStyle(StageLook.soft)
                    Spacer()
                    if let w = week, w.seconds > 0, geo.size.width > 900 { WeekStrip(week: w).padding(.trailing, 14) }
                    if games.filter({ $0.app != nil }).count > 1 {
                        Button { model.pickRandom(games) } label: {
                            HStack(spacing: 6) { Image(systemName: "shuffle").font(.system(size: 12, weight: .bold)); Text("Random Pick") }
                        }
                        .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(StageLook.soft).padding(.trailing, 14)
                        .help("Puts a built game you have not played this week in front of you")
                    }
                    Button { model.stageTab = .library } label: {
                        HStack(spacing: 6) { Text("See all \(total)"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                    }
                    .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(StageLook.soft)
                }
                .padding(.horizontal, 56)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 26) {
                            ForEach(games) { g in
                                VStack(alignment: .leading, spacing: 10) {
                                    CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil, attention: model.coverMark(g), status: g.app == nil ? model.status(g) : nil, square: model.settings.squareCovers).frame(width: tile)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(g.name).font(.system(size: 14.5, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                        Text(g.console.rawValue).font(.system(size: 13)).foregroundStyle(StageLook.faint).lineLimit(1)
                                    }
                                    .frame(width: tile - 8, alignment: .leading).padding(.leading, 4)
                                    .opacity(focus?.id == g.id ? 1 : 0.85)
                                }
                                .id(g.id)
                                .contentShape(.rect)
                                .onTapGesture(count: 2) { model.libraryFocus = g.id; model.playFromStage(g.ref) }
                                .simultaneousGesture(TapGesture().onEnded { model.libraryFocus = g.id })
                                .contextMenu { StageGameMenu(model: model, game: g) }
                                .accessibilityElement(children: .combine).accessibilityLabel(g.app == nil ? "\(g.name), \(model.status(g).text)" : g.name).accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.horizontal, 56).padding(.top, 20).frame(height: shelf + 20, alignment: .top)
                    }
                    .frame(height: shelf + 20)
                    .onChange(of: model.libraryFocus) { _, f in if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } } }
                }
                .padding(.bottom, 10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: keyArt)
        .task(id: "\(focus?.id ?? "")|\(CoverStore.shared.revision)|\(CoverStore.shared.showHeroes)") { keyArt = await GameKeyArt.hasArt(focus) }
        .task(id: "\(model.revision)|\(model.playing.count)") { week = await Task.detached(priority: .utility) { PlayWeek(Playtime.load()) }.value }
    }
}

struct StageLibrary: View {
    @Bindable var model: AppModel
    let all: [StageGame]
    let games: [StageGame]
    let focus: StageGame?
    @Namespace private var scopeMark
    static let cell: CGFloat = 142, gap: CGFloat = 28, side: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Library").font(.system(size: 32, weight: .heavy)).tracking(-0.6)
                scopes
                Text("\(games.count) game\(games.count == 1 ? "" : "s")").foregroundStyle(StageLook.soft).monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    ForEach(StageFilter.shown(model.stageScope), id: \.self) { f in
                        let on = model.stageFilter == f
                        Button { model.stageFilter = f } label: {
                            HStack(spacing: 7) {
                                Text(f.rawValue).font(.system(size: 13, weight: .semibold))
                                Text("\(count(f))").font(.system(size: 11.5, weight: .bold).monospacedDigit()).foregroundStyle(on ? Color(white: 0.35) : StageLook.faint)
                            }
                            .padding(.horizontal, 14).frame(height: 32)
                            .foregroundStyle(on ? Color.black : Color(white: 0.92))
                            .background(on ? AnyShapeStyle(Color.white.opacity(0.94)) : AnyShapeStyle(StageLook.card), in: .capsule)
                            .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(StageLook.edge), lineWidth: 1))
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.stageFilter == f ? .isSelected : [])
                    }
                }
                // boxes or square art (Settings › Square covers)
                Button { withAnimation(.spring(duration: 0.3)) { model.settings.squareCovers.toggle() } } label: {
                    Image(systemName: model.settings.squareCovers ? "rectangle.portrait" : "square").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32).background(StageLook.card, in: .circle).overlay(Circle().strokeBorder(StageLook.edge, lineWidth: 1))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(model.settings.squareCovers ? "Show boxes" : "Show square covers: more to a row")
                .accessibilityLabel(model.settings.squareCovers ? "Show Boxes" : "Show Square Covers")
            }
            .padding(.horizontal, Self.side).padding(.top, 8)
            if games.isEmpty {
                Text(model.stageSearch.isEmpty ? (model.stageScope == .built && model.stageFilter == .all ? "No game is built on this Mac yet. Owned has every game in your games folder." : "No games here.") : "Nothing matches “\(model.stageSearch)”.").foregroundStyle(StageLook.soft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell + 44), spacing: Self.gap, alignment: .top)], alignment: .leading, spacing: 28) {
                            ForEach(games) { g in
                                VStack(alignment: .leading, spacing: 9) {
                                    CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil, attention: model.coverMark(g), status: g.app == nil ? model.status(g) : nil, square: model.settings.squareCovers)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(g.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        status(g)
                                        // a short line under the game in focus, in its colour
                                        Capsule().fill(CoverArt.tint(g).mix(with: .white, by: 0.35)).frame(width: 30, height: 3).padding(.top, 4)
                                            .opacity(focus?.id == g.id ? 1 : 0).animation(.easeOut(duration: 0.18), value: focus?.id == g.id)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .id(g.id)
                                .contentShape(.rect)
                                .onTapGesture(count: 2) { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref }
                                .simultaneousGesture(TapGesture().onEnded { model.libraryFocus = g.id })
                                .contextMenu { StageGameMenu(model: model, game: g) }
                                .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.horizontal, Self.side).padding(.top, 22).padding(.bottom, 30)
                    }
                    // the covers fade out under the heading instead of being cut by it
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.035), .init(color: .black, location: 0.97),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .onChange(of: model.libraryFocus) { _, f in if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } } }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            model.stageColumns = max(Int((w - 2 * Self.side + Self.gap) / (Self.cell + Self.gap)), 1)
        }
    }

    /// The games in the collection on screen
    var inScope: [StageGame] { model.stageScope == .built ? all.filter { $0.app != nil } : all }

    func count(_ f: StageFilter) -> Int {
        let pool = inScope
        return switch f {
        case .all: pool.count
        case .favorites: pool.filter(\.favorite).count
        case .switch2: pool.filter { $0.console == .switch2 }.count
        case .switch1: pool.filter { $0.console == .switch1 }.count
        case .notBuilt: pool.filter { $0.app == nil }.count
        }
    }

    /// Owned | Built, with each collection's count: a pair like the top bar's tabs
    var scopes: some View {
        HStack(spacing: 2) {
            ForEach(StageScope.allCases, id: \.self) { sc in
                let on = model.stageScope == sc
                let n = sc == .built ? all.filter { $0.app != nil }.count : all.count
                Button {
                    model.stageScope = sc
                    if !StageFilter.shown(sc).contains(model.stageFilter) { model.stageFilter = .all }
                } label: {
                    HStack(spacing: 6) {
                        Text(sc.rawValue).font(.system(size: 13, weight: .semibold))
                        Text("\(n)").font(.system(size: 11.5, weight: .bold).monospacedDigit()).foregroundStyle(on ? Color(white: 0.35) : StageLook.faint)
                    }
                    .padding(.horizontal, 14).frame(height: 28)
                    .foregroundStyle(on ? Color.black : Color(white: 0.92))
                    .background { if on { Capsule().fill(.white.opacity(0.94)).matchedGeometryEffect(id: "scope", in: scopeMark) } }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(sc == .built ? "Only the games built and ready to play on this Mac" : "Every game in your games folder, built or not")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(duration: 0.3), value: model.stageScope)
    }

    func statusLine(_ g: StageGame, building: Bool, need: GameAttention?) -> (String, Color) {
        let blue = Color(red: 0.38, green: 0.65, blue: 0.98), amber = Color(red: 0.98, green: 0.75, blue: 0.14), green = Color(red: 0.29, green: 0.87, blue: 0.50)
        if building { return ("Building · \(Int((model.run.overall(now: Date()).fraction * 100).rounded()))%", amber) }
        if g.app == nil { let st = model.status(g); return (st.text, st == .notBuilt ? Color(white: 0.55) : st.color) }
        if model.isPlaying(app: g.app ?? "") { return ("Playing now", blue) }
        if let a = need { return (a.text, a.color) }
        if g.outdated { return ("Older engine", amber) }
        return (g.last == nil ? "Ready on Mac" : StageLook.played(g.last), green)
    }

    @ViewBuilder func status(_ g: StageGame) -> some View {
        let building = model.run.running && !model.run.planning && g.game.map { model.buildingDir == $0.path || model.buildingDir == $0.folder } == true
        let need = model.attention[g.id]?.first
        let (text, color) = statusLine(g, building: building, need: need)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(g.app == nil ? 0 : 0.8), radius: 4)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(g.app == nil ? StageLook.faint : StageLook.soft).lineLimit(1)
        }
        .help(need?.detail ?? (g.outdated ? "A newer NXForge can rebuild this game. It still plays as it is." : ""))
    }
}

/// A cover's menu
struct StageGameMenu: View {
    let model: AppModel
    let game: StageGame

    var body: some View {
        let g = game
        if g.app != nil {
            Button("Play") { model.playFromStage(g.ref) }
            Button("Play Options…") { model.openPlayOptions(g.ref) }
            Button("Play with the Game's Own Settings Window") { model.playWithOwnWindow(g.ref) }
        } else if g.game != nil {
            if game.app == nil { let st = model.status(game); Button(st.action) { model.fix(game) }.disabled(st == .notBuilt && (model.run.running || model.batchRunning)) }
        }
        Divider()
        Button("View Box") { model.openCaseViewer(g) }
        if let m = GameManual.find(g) {
            Button("Read Manual") { model.openManual(m, title: g.name) }
            if m == GameManual.added(g.coverKey) { Button("Remove Manual") { GameManual.remove(for: g) } }
            else { Button("Use Another Manual…") { GameManual.pick(for: g) } }
        } else {
            Button("Add Manual…") { GameManual.pick(for: g) }
        }
        if g.titleID != nil { Button("Cheats…") { model.cheatsFor = g.ref } }
        Button("Details") { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref }
        Button(g.favorite ? "Remove from Favourites" : "Add to Favourites") { model.toggleFavorite(g) }
        Divider()
        Menu("Change Box Art") {
            Button("Choose Front Cover…") { model.chooseCover(g, .front) }
            Button("Front Cover from a Link…") { model.coverFromLink(g, .front) }
            Divider()
            Button("Choose Back Cover…") { model.chooseCover(g, .back) }
            Button("Back Cover from a Link…") { model.coverFromLink(g, .back) }
            if CoverStore.shared.hasOwn(g.coverKey) {
                Divider()
                Button("Go Back to the Downloaded Covers") { CoverStore.shared.removeOwn(g.coverKey); GameFolderMediaSync.shared.ownCoversRemoved(g, model: model) }
            }
        }
        Divider()
        if let p = g.app ?? g.game?.path { Button("Show in Finder") { reveal(p) } }
        if g.app != nil, model.settings.mediaInGameFolder { Button("Show Media Folder") { GameFolderMediaSync.shared.show(g, model: model) } }
        Button("Manage in Converter") { model.showConverter(); model.page = .library; model.openGame(g.ref) }
    }
}

struct StageEmpty: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 54)).foregroundStyle(StageLook.soft)
            Text(model.libraryScanning ? "Looking for your games…" : "No games yet").font(.system(size: 30, weight: .heavy))
            Text("Choose the folder your games are in. Every game under it appears here, and the ones you have built are ready to play.")
                .foregroundStyle(StageLook.soft).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button("Choose Games Folder…") { model.chooseGamesRoot() }.buttonStyle(StageButton(primary: true))
                Button("Open the Converter") { model.showConverter() }.buttonStyle(StageButton())
            }
            .padding(.top, 6)
        }
    }
}

/// What the buttons do here, along the foot of the window.
struct StageHints: View {
    let model: AppModel
    let focus: StageGame?
    let detail: Bool

    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in hint(h.0, h.1) }
            Spacer(minLength: 0)
            hint(["+"], "Settings")
        }
        .padding(.horizontal, 40).frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.13)).frame(height: 1).padding(.horizontal, 24) }
    }

    /// One hint; a click does what its button does (the first of a pair, as L in L R)
    func hint(_ keys: [String], _ text: String) -> some View {
        Button { if let k = keys.first.flatMap(PadLabels.key) { model.stagePad(k) } } label: {
            HStack(spacing: 7) {
                ForEach(keys, id: \.self) { PadGlyph(text: $0, filled: $0 == "A") }
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    var hints: [([String], String)] {
        let built = focus?.app != nil
        let fix = focus.map { model.status($0).action } ?? "Build"
        if model.stageSettings { return [(["A"], "Change"), (["B"], "Close")] }
        if model.playOptions != nil { return [(["A"], "Play"), (["X"], "Play once"), (["Y"], "Next preset"), (["L", "R"], "Switch tab"), (["B"], "Done")] }
        if detail { return (built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], fix)]) + [(["Y"], "View box"), (["B"], "Back")] }
        if model.stageTab == .discover {
            if let d = model.discover.detail {
                return [(["A"], "Nintendo eShop"), (["Y"], Wishlist.shared.contains(d) ? "Remove from Wishlist" : "Wishlist"), (["B"], "Close")]
            }
            let wished = model.discover.focused.map { Wishlist.shared.contains($0) } ?? false
            return [(["A"], "View game"), (["Y"], wished ? "Remove from Wishlist" : "Wishlist"), (["X"], "Nintendo eShop"), (["L", "R"], "Genre"), (["B"], "Back")]
        }
        var h: [([String], String)] = built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], fix)]
        h.append((["Y"], "Details"))
        h.append((["−"], focus?.favorite == true ? "Unfavourite" : "Favourite"))
        h.append((["L", "R"], model.stageTab == .home ? "Library" : "Change filter"))
        if model.stageTab == .library { h.append((["B"], "Home")) }
        return h
    }
}

/// A thin bar with a light running along it: something is on its way, with no telling how far it is
struct RunningBar: View {
    var width: CGFloat = 380
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        if still {
            // Reduce Motion: the bar glows and fades in place instead of a light running along it
            TimelineView(.animation(minimumInterval: 1 / 20)) { t in
                let p = 0.5 + 0.5 * sin(t.date.timeIntervalSinceReferenceDate * 2.2)
                Capsule().fill(.white.opacity(0.18 + 0.32 * p)).frame(width: width, height: 4)
            }
            .accessibilityLabel("Starting")
        } else {
            running
        }
    }

    var running: some View {
        TimelineView(.animation) { t in
            let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 1.7
            Capsule().fill(.white.opacity(0.14)).frame(width: width, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0), .white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * 0.42, height: 4).offset(x: (width * 1.42) * p - width * 0.42)
                }
                .clipShape(.capsule)
        }
        .accessibilityLabel("Starting")
    }
}

/// Over the stage while a game starts: its box turning slowly in its own light, its name, and what it plays with.
struct LaunchScreen: View {
    let model: AppModel
    let launch: Launching
    let game: StageGame?

    var body: some View {
        ZStack {
            StageBackdrop(tint: game.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75),
                          art: game.flatMap { CoverArt.ambient($0) }, artKey: game?.id ?? "", strength: 1.1)
            GeometryReader { geo in
                let caseH = min(max(geo.size.height * 0.52, 240), 560)
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    if let g = game { GameCase(game: g).frame(width: caseH * 0.78, height: caseH).padding(.bottom, -caseH * 0.14).allowsHitTesting(false) }
                    Text(launch.name).font(.system(size: 40, weight: .heavy)).tracking(-0.9).lineLimit(2).multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                    if let f = launch.failure {
                        failure(f)
                    } else {
                        RunningBar()
                        VStack(spacing: 6) {
                            Text(launch.phase == .preparing ? "GETTING IT READY" : "STARTING THE GAME").font(.system(size: 11.5, weight: .bold)).fontWidth(.expanded).kerning(1.8).foregroundStyle(StageLook.soft)
                            if !launch.summary.isEmpty { Text(launch.summary).font(.system(size: 13.5, weight: .medium)).foregroundStyle(StageLook.soft) }
                            if let n = launch.note { Text(n).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.14)) }
                            if launch.slow {
                                Text("Taking longer than usual. A game's first start after a build prepares its shaders, which can take a minute.")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.faint).multilineTextAlignment(.center).frame(maxWidth: 460)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                    Button { model.launching = nil } label: {
                        HStack(spacing: 7) { PadGlyph(text: "B"); Text(launch.failure == nil ? "Hide" : "Close").font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft) }
                    }
                    .buttonStyle(.plain).padding(.bottom, 26)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
    }

    /// The game closed before its first picture: what happened, and the steps that help
    func failure(_ f: LaunchFailure) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 1, green: 0.55, blue: 0.45))
                Text(f.title).font(.system(size: 18, weight: .bold))
            }
            Text(f.detail).font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.soft).multilineTextAlignment(.center)
                .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { model.retryLaunch() } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                    .buttonStyle(StageButton(primary: true))
                if let label = f.fixLabel {
                    Button { model.launchFix(f) } label: { HStack(spacing: 8) { PadGlyph(text: "X"); Text(label) } }.buttonStyle(StageButton())
                }
                if let p = f.log, FileManager.default.fileExists(atPath: p) {
                    Button { reveal(p) } label: { HStack(spacing: 8) { PadGlyph(text: f.fixLabel == nil ? "X" : "Y"); Text("Show Log") } }.buttonStyle(StageButton())
                }
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The front end's own settings: a panel no taller than the window, with its title, a find field and the section jumps
/// pinned at the top, the folder buttons pinned at the foot, and the rows scrolling between them.
struct StageSettings: View {
    @Bindable var model: AppModel
    let openConverterSettings: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var solid

    enum Section: String, CaseIterable, Identifiable {
        case launching = "Launching", artwork = "Artwork", building = "Building", opens = "When NXForge Opens"
        var id: String { rawValue }
        var short: String { self == .opens ? "On Open" : rawValue }
    }

    // NXC_FIND: the snapshot hook starts the find field with that text
    @State private var query = ProcessInfo.processInfo.environment["NXC_FIND"] ?? ""
    @State private var contentHeight: CGFloat = 640
    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var tops: [Section: CGFloat] = [:]
    @State private var position = ScrollPosition(edge: .top)
    @FocusState private var findFocused: Bool
    @FocusState private var scrollFocused: Bool

    /// the section at the top of the scroll, lit in the jump row
    var current: Section {
        // scrolled to the end, the last section that shows is lit even though it never reaches the top
        if !moreBelow && moreAbove { return Section.allCases.last { (tops[$0] ?? .infinity) < offset + viewport - 40 } ?? .opens }
        return Section.allCases.last { (tops[$0] ?? .infinity) <= offset + 24 } ?? .launching
    }
    var moreAbove: Bool { offset > 2 }
    var moreBelow: Bool { offset + viewport < contentHeight - 2 }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                Rectangle().fill(.white.opacity(moreAbove ? 0.12 : 0)).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { sections }
                        .coordinateSpace(.named("settingsContent"))
                        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 18)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollPosition($position)
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: contentHeight)
                .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentOffset.y, $0.containerSize.height] } action: { _, v in
                    offset = v[0]; viewport = v[1]
                }
                // the keyboard: arrows, page up and down, space, home and end
                .focusable().focusEffectDisabled().focused($scrollFocused)
                .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .space, .home, .end]) { press in
                    scroll(press); return .handled
                }
                // a controller's row stays in view
                .onChange(of: model.settingsFocus) { _, f in
                    if let r = StageSettingRow(rawValue: f) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(AnyHashable(r), anchor: .center) } }
                }
                Rectangle().fill(.white.opacity(moreBelow ? 0.12 : 0)).frame(height: 1)
                footer
            }
        }
        .frame(width: 640)
        .background(StageLook.panel.opacity(solid ? 1 : 0.80), in: .rect(cornerRadius: 28))
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
        .onAppear { scrollFocused = true }
        // ⌘F finds a setting
        .background { Button("") { findFocused = true }.keyboardShortcut("f").hidden() }
    }

    func header(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Settings").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(StageLook.faint)
                    TextField("Find a setting", text: $query).textFieldStyle(.plain).font(.system(size: 13.5)).focused($findFocused)
                        .onSubmit { scrollFocused = true }
                        .onExitCommand { if query.isEmpty { model.stageSettings = false } else { query = "" } }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                            .buttonStyle(.plain).accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 12).frame(width: 210, height: 32)
                .background(StageLook.card, in: .capsule).overlay(Capsule().strokeBorder(StageLook.edge, lineWidth: 1))
                Button { model.stageSettings = false } label: {
                    Text("Done").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).frame(height: 32).background(.white, in: .capsule).contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            if query.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Section.allCases) { s in
                        let on = s == current
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(s, anchor: .top) }
                        } label: {
                            Text(s.short).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(on ? Color.black : StageLook.soft)
                                .padding(.horizontal, 12).frame(height: 26)
                                .background(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: .capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Spacer()
                }
                .animation(.easeOut(duration: 0.15), value: current)
            }
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 14)
    }

    var footer: some View {
        HStack(spacing: 10) {
            Button("Games Folder…") { model.chooseGamesRoot() }.buttonStyle(StageButton(height: 36))
            Button("Scan Again") { model.scanLibrary() }.buttonStyle(StageButton(height: 36)).disabled(model.libraryScanning)
            Spacer()
            Button("Converter Settings…") { openConverterSettings() }.buttonStyle(StageButton(height: 36))
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 22)
    }

    /// every row's title, by section, and the note under it: the find field looks in both
    static let titles: [Section: [String]] = [
        .launching: ["Play goes straight into the game", "Show Play options the first time", "Battery preset on battery", "Return here when a game quits", "Keep shaders on this Mac", "Show a recap when a game quits", "Rest while a game runs", "Controllers"],
        .artwork: ["Square covers", "Download box art", "Download wide art", "Download store details", "Keep media in each game's folder", "Artwork folder"],
        .building: ["Keys file (prod.keys)"],
        .opens: ["Open on"],
    ]
    static let notes: [String: String] = [
        "Play goes straight into the game": "Uses each game's saved Play options and still checks its cloud save. Its own settings window stays closed.",
        "Show Play options the first time": "A game you have not played yet opens its options once before it starts.",
        "Battery preset on battery": "Unplugged, a run takes the Battery preset. Your saved options are not changed.",
        "Return here when a game quits": "NXForge comes back to the front, ready for the next game. The game's sidebar also has Library, which quits to this game's page.",
        "Keep shaders on this Mac": "A game on another drive has its compiled shaders copied here once, so it starts sooner and uses less memory. Not done when it would leave under 10 GB free.",
        "Show a recap when a game quits": "How long you played this time and in total, with the game's peak memory.",
        "Rest while a game runs": "Behind a running game, NXForge shows a plain card and lets go of its artwork, so the game has the memory.",
        "Controllers": "See every button, stick and trigger as a game reads it, and try the rumble.",
        "Square covers": "Shows each game's square shop art instead of its box on Home and in the Library: smaller, so more fit in a row. The same as the Library's square button.",
        "Download box art": "Front and back covers from GameTDB, matched by the game's name; a download-only game gets a box made from its square art on Nintendo Life. Only a cover's ID or the game's name is sent.",
        "Download wide art": "The header art from each game's page on Nintendo Life, else the banner from Nintendo's European store, behind its page and Home. Found by name or title ID; only those are sent.",
        "Download store details": "A game's description, details and official screenshots from its store page, fetched when you open the game's page.",
        "Keep media in each game's folder": "A built game's covers, wide art, screenshots and manual go in a media folder beside its app, with game.md listing its details, links and build. Read back on a Mac that has no artwork for it yet.",
        "Artwork folder": "Your own covers and the downloaded art, kept on this Mac only.",
        "Keys file (prod.keys)": "Chosen once, used for every build and rebuild.",
        "Open on": "Where NXForge starts: Home, the Library or the Converter.",
    ]

    @ViewBuilder var sections: some View {
        group(.launching) {
            toggle("Play goes straight into the game", $model.settings.straightPlay, row: .straightPlay)
            toggle("Show Play options the first time", $model.settings.firstPlayOptions, row: .firstPlayOptions)
            toggle("Battery preset on battery", $model.settings.batteryPreset, row: .batteryPreset)
            toggle("Return here when a game quits", $model.settings.returnToLibrary, row: .returnToLibrary)
            toggle("Keep shaders on this Mac", $model.settings.localShaders, row: .localShaders)
            toggle("Show a recap when a game quits", $model.settings.sessionRecap, row: .sessionRecap)
            toggle("Rest while a game runs", $model.settings.lightWhilePlaying, row: .lightWhilePlaying)
            row("Controllers") {
                Button("Test…") { model.stageSettings = false; model.showControllerTest = true }.buttonStyle(StageButton(height: 32))
            }
        }
        group(.artwork) {
            toggle("Square covers", $model.settings.squareCovers, row: .squareCovers)
            toggle("Download box art", $model.settings.downloadCovers, row: .downloadCovers)
            toggle("Download wide art", $model.settings.downloadHeroes, row: .downloadHeroes)
            toggle("Download store details", $model.settings.downloadStoreInfo, row: .downloadStoreInfo)
            toggle("Keep media in each game's folder", $model.settings.mediaInGameFolder, row: .mediaInGameFolder)
            row("Artwork folder") {
                HStack(spacing: 8) {
                    Button("Look Again") { CoverStore.shared.lookAgain(); StoreInfoStore.shared.lookAgain(); model.fetchCovers(model.stageGames()) }.buttonStyle(StageButton(height: 32))
                    Button("Show") { try? FileManager.default.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(CoverStore.dir) }.buttonStyle(StageButton(height: 32))
                }
            }
        }
        group(.building) {
            row("Keys file (prod.keys)") {
                HStack(spacing: 8) {
                    if let k = model.settings.defaultKeys {
                        Text(k.tildePath).font(.system(size: 12.5)).foregroundStyle(StageLook.soft).lineLimit(1).truncationMode(.middle).frame(maxWidth: 210, alignment: .trailing)
                    }
                    Button(model.settings.defaultKeys == nil ? "Choose…" : "Change…") { model.chooseSavedKeys() }.buttonStyle(StageButton(height: 32))
                }
            }
            if query.isEmpty { KeysStatusRow(model: model, dark: true).padding(.bottom, 11) }
        }
        group(.opens) {
            row("Open on", focus: .startIn) {
                Picker("", selection: $model.settings.startIn) { ForEach(StartIn.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
        }
        if !query.isEmpty && !Section.allCases.contains(where: anyShown) {
            Text("No setting matches “\(query)”.").font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.faint)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }

    /// a row is shown when the find field is empty, or every word typed starts a word of its title or note
    /// ("art" finds box art and the artwork folder, not "starts")
    func matches(_ text: String) -> Bool {
        let typed = query.lowercased().split(separator: " ")
        if typed.isEmpty { return true }
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return typed.allSatisfy { t in words.contains { $0.hasPrefix(t) } }
    }
    func shown(_ title: String) -> Bool { matches(title + " " + (Self.notes[title] ?? "")) }
    func anyShown(_ s: Section) -> Bool { Self.titles[s, default: []].contains(where: shown) }

    /// The keyboard over the scroll: a line, a page, or an end at a time
    func scroll(_ press: KeyPress) {
        let page = max(viewport - 60, 80)
        let top = max(contentHeight - viewport, 0)
        var y = offset
        switch press.key {
        case .upArrow: y -= 48
        case .downArrow: y += 48
        case .pageUp: y -= page
        case .pageDown: y += page
        case .space: y += press.modifiers.contains(.shift) ? -page : page
        case .home: y = 0
        case .end: y = top
        default: return
        }
        withAnimation(.easeOut(duration: 0.18)) { position.scrollTo(y: min(max(y, 0), top)) }
    }

    func group<C: View>(_ section: Section, @ViewBuilder _ content: () -> C) -> some View {
        Group {
            if query.isEmpty || anyShown(section) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.rawValue.uppercased()).font(.system(size: 11, weight: .bold)).fontWidth(.expanded).kerning(1.6).foregroundStyle(StageLook.soft)
                    VStack(spacing: 0) { content() }
                        .padding(.horizontal, 18)
                        // the line under the last row of a card is covered by the card's own edge
                        .padding(.bottom, -1).clipped()
                        .background(StageLook.card, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StageLook.edge, lineWidth: 1))
                }
                .id(section)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("settingsContent")).minY } action: { tops[section] = $0 }
            }
        }
    }

    @ViewBuilder
    func row<C: View>(_ title: String, focus: StageSettingRow? = nil, @ViewBuilder _ control: () -> C) -> some View {
        // the row a controller is on is lit (only while one is connected: the pointer needs no mark)
        let lit = focus != nil && focus?.rawValue == model.settingsFocus && !GCController.controllers().isEmpty
        let note = Self.notes[title] ?? ""
        if shown(title) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        if !note.isEmpty { Text(note).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 8)
                    control()
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 8)
                .background(lit ? Color.white.opacity(0.10) : Color.clear, in: .rect(cornerRadius: 10))
                .padding(.horizontal, -8)
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            }
            .id(focus.map { AnyHashable($0) } ?? AnyHashable(title))
        }
    }

    func toggle(_ title: String, _ on: Binding<Bool>, row focus: StageSettingRow? = nil) -> some View {
        row(title, focus: focus) { Toggle(title, isOn: on).toggleStyle(.switch).labelsHidden().tint(.green) }
    }
}
