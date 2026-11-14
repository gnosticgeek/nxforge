// The front end: the games as covers on a dark stage lit by the focused game's colours, shown instead of the converter's
// pages (the Converter tab goes back to them). Home is a shelf under the game last played, Library every game in the games
// folder (the ones not built yet dimmed), a game's page has its box in 3D, and Play goes straight into the game
// (PlayOptions.swift). Everything works from a controller (ControllerNav → stagePad), the keyboard and the pointer.
import AppKit
import GameController
import SwiftUI

enum StageTab: String, CaseIterable { case home = "Home", library = "Library" }
enum StageFilter: String, CaseIterable { case all = "All", favorites = "Favourites", ready = "Ready to play", switch2 = "Switch 2", switch1 = "Switch", notBuilt = "Not built yet" }

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
enum StageSettingRow: Int, CaseIterable { case straightPlay, firstPlayOptions, batteryPreset, returnToLibrary, downloadCovers, startIn }

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
        var out = games
        switch stageFilter {
        case .all: break
        case .favorites: out = out.filter(\.favorite)
        case .ready: out = out.filter { $0.app != nil }
        case .switch2: out = out.filter { $0.console == .switch2 }
        case .switch1: out = out.filter { $0.console == .switch1 }
        case .notBuilt: out = out.filter { $0.app == nil }
        }
        let q = stageSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { out = out.filter { $0.name.lowercased().contains(q) } }
        return out
    }

    /// The game in focus: the one picked, else on Home the one played last (Continue playing), else the first
    func stageFocus(_ shown: [StageGame]) -> StageGame? {
        shown.first { $0.id == libraryFocus } ?? (stageTab == .home ? Self.lastPlayed(shown) : nil) ?? shown.first
    }

    static func lastPlayed(_ games: [StageGame]) -> StageGame? {
        games.filter { $0.last != nil }.max { ($0.last ?? .distantPast) < ($1.last ?? .distantPast) }
    }

    func isFavorite(_ g: StageGame) -> Bool { settings.favorites.contains(g.favoriteKey) }

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
        if launching != nil {
            if k == .b { launching = nil }
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
            case .y: caseFlipped.toggle()
            case .menu: settingsFocus = 0; stageSettings = true
            case .options: if let g = stageGames().first(where: { $0.isRef(r) }) { toggleFavorite(g) }
            default: break
            }
            return
        }
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
        case .l:
            if stageTab == .library, let i = StageFilter.allCases.firstIndex(of: stageFilter), i > 0 { stageFilter = StageFilter.allCases[i - 1] } else { stageTab = .home }
        case .r:
            if stageTab == .home { stageTab = .library }
            else if let i = StageFilter.allCases.firstIndex(of: stageFilter), i + 1 < StageFilter.allCases.count { stageFilter = StageFilter.allCases[i + 1] }
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
        case .downloadCovers: flip(&settings.downloadCovers)
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
struct PadGlyph: View {
    let text: String
    var filled = false

    var body: some View {
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
        let tint = focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
        ZStack {
            StageBackdrop(tint: tint, art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "")
            // the game's key art behind its page, and behind Home's headline for the game in focus
            if let g = detail { GameKeyArt(game: g).id(g.id).transition(.opacity) }
            else if model.stageTab == .home, let g = focus { GameKeyArt(game: g, coverFallback: false).id(g.id).transition(.opacity) }
            VStack(spacing: 0) {
                if detail == nil { StageTopBar(model: model) }
                Group {
                    if let g = detail {
                        StageGamePage(model: model, game: g)
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
            if let l = model.launching {
                LaunchScreen(model: model, launch: l, game: games.first { $0.isRef(l.ref) }).transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.35), value: model.playOptions?.id)
        .animation(.easeInOut(duration: 0.3), value: model.launching?.id)
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
        .task(id: games.map(\.coverKey).joined(separator: "|") + (model.settings.downloadCovers ? "1" : "0")) { model.fetchCovers(games) }
        .task(id: games.map { "\($0.id)\($0.outdated)" }.joined(separator: "|") + "|\(model.playing.count)|\(model.revision)") { await model.refreshAttention(games) }
    }
}

struct StageTopBar: View {
    @Bindable var model: AppModel
    @Namespace private var marks

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2).accessibilityHidden(true)
                Text("NXForge").font(.system(size: 18, weight: .heavy)).fontWidth(.expanded).tracking(-0.4)
            }
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
            .padding(.leading, 12)
            if model.run.running && !model.run.planning {
                Button { model.showConverter(); model.page = .convert } label: {
                    HStack(spacing: 8) { Text("Building").font(.callout.weight(.semibold)); SidebarBuildProgress(run: model.run) }
                        .padding(.horizontal, 12).frame(height: 36).glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain).help("Show the build")
            }
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
        .padding(.horizontal, 40).padding(.top, 6).padding(.bottom, 10)
    }

    /// The one search field, for whichever list is on screen: the covers, the converter's game files or its builds.
    var search: (prompt: String, text: Binding<String>)? {
        if model.frontEnd { return model.stageTab == .library ? ("Search games", $model.stageSearch) : nil }
        guard model.gameDetail == nil else { return nil }
        switch model.page {
        case .library: return ("Search games", $model.librarySearch)
        case .builds: return ("Search builds", $model.buildSearch)
        default: return nil
        }
    }

    func tab(_ title: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).frame(height: 30)
                .foregroundStyle(on ? Color.black : Color(white: 0.92))
                .background { if on { Capsule().fill(.white.opacity(0.94)).matchedGeometryEffect(id: "tab", in: marks) } }
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
                } else {
                    Button { model.playFromStage(g.ref) } label: { Label("Build", systemImage: "hammer.fill").padding(.horizontal, 8) }
                        .buttonStyle(StageButton(primary: true, height: 54, glow: tint)).disabled(model.run.running || model.batchRunning)
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
        if game.app == nil { return "NOT BUILT YET" }
        if model.isPlaying(app: game.app ?? "") { return "PLAYING NOW" }
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
        guard game.app != nil else { return "Not built yet" }
        return game.last.map { "Last played \(relativeDay($0).lowercasedFirst)" } ?? "Not played yet"
    }
}

struct StageHome: View {
    @Bindable var model: AppModel
    let games: [StageGame]
    let focus: StageGame?
    let total: Int
    /// whether the game in focus has a screenshot filling the room (GameKeyArt); without one its 3D case stands on the right
    @State private var keyArt = false
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        GeometryReader { geo in
            let tile = min(max(min(geo.size.width * 0.112, geo.size.height * 0.20), 100), 190)
            let caseH = min(max(geo.size.height - tile / CoverSource.aspect - 150, 220), 560)
            let tileH = tile / CoverSource.aspect
            let shelf = tileH + 78
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    if let g = focus {
                        StageHero(model: model, game: g, first: AppModel.lastPlayed(games)?.id == g.id, titleSize: geo.size.width > 1100 ? 60 : 44)
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
                                    CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil, attention: model.coverMark(g)).frame(width: tile)
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
                                .accessibilityElement(children: .combine).accessibilityLabel(g.name).accessibilityAddTraits(.isButton)
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
        .task(id: focus?.app) { keyArt = await GameKeyArt.hasShot(app: focus?.app) }
    }
}

struct StageLibrary: View {
    @Bindable var model: AppModel
    let all: [StageGame]
    let games: [StageGame]
    let focus: StageGame?
    static let cell: CGFloat = 142, gap: CGFloat = 28, side: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Library").font(.system(size: 32, weight: .heavy)).tracking(-0.6)
                Text("\(all.count) game\(all.count == 1 ? "" : "s") · \(all.filter { $0.app != nil }.count) ready to play").foregroundStyle(StageLook.soft)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    ForEach(StageFilter.allCases, id: \.self) { f in
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
            }
            .padding(.horizontal, Self.side).padding(.top, 8)
            if games.isEmpty {
                Text(model.stageSearch.isEmpty ? "No games here." : "Nothing matches “\(model.stageSearch)”.").foregroundStyle(StageLook.soft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell + 44), spacing: Self.gap, alignment: .top)], alignment: .leading, spacing: 28) {
                            ForEach(games) { g in
                                VStack(alignment: .leading, spacing: 9) {
                                    CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil, attention: model.coverMark(g))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(g.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        status(g)
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

    func count(_ f: StageFilter) -> Int {
        switch f {
        case .all: all.count
        case .favorites: all.filter(\.favorite).count
        case .ready: all.filter { $0.app != nil }.count
        case .switch2: all.filter { $0.console == .switch2 }.count
        case .switch1: all.filter { $0.console == .switch1 }.count
        case .notBuilt: all.filter { $0.app == nil }.count
        }
    }

    func statusLine(_ g: StageGame, building: Bool, need: GameAttention?) -> (String, Color) {
        let blue = Color(red: 0.38, green: 0.65, blue: 0.98), amber = Color(red: 0.98, green: 0.75, blue: 0.14), green = Color(red: 0.29, green: 0.87, blue: 0.50)
        if building { return ("Building · \(Int((model.run.overall(now: Date()).fraction * 100).rounded())) %", blue) }
        if g.app == nil { return ("Not built yet", Color(white: 0.55)) }
        if model.isPlaying(app: g.app ?? "") { return ("Playing now", blue) }
        if let a = need { return (a.kind == .update && g.last != nil ? StageLook.played(g.last) : a.text, a.color) }
        if g.outdated && g.last == nil { return ("Update ready", amber) }
        return (StageLook.played(g.last), g.outdated ? amber : green)
    }

    @ViewBuilder func status(_ g: StageGame) -> some View {
        let building = model.run.running && g.game.map { model.settings.gameDir == $0.path || model.settings.gameDir == $0.folder } == true
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
            Button("Build") { model.playFromStage(g.ref) }.disabled(model.run.running || model.batchRunning)
        }
        Button("Details") { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref }
        Button(g.favorite ? "Remove from Favourites" : "Add to Favourites") { model.toggleFavorite(g) }
        Divider()
        Button("Choose Front Cover…") { model.chooseCover(g, .front) }
        Button("Choose Back Cover…") { model.chooseCover(g, .back) }
        if CoverStore.shared.hasOwn(g.coverKey) { Button("Remove My Covers") { CoverStore.shared.removeOwn(g.coverKey) } }
        Divider()
        if let p = g.app ?? g.game?.path { Button("Show in Finder") { reveal(p) } }
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
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in
                HStack(spacing: 7) {
                    ForEach(h.0, id: \.self) { PadGlyph(text: $0, filled: $0 == "A") }
                    Text(h.1).font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) { PadGlyph(text: "+"); Text("Settings").font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft) }
        }
        .padding(.horizontal, 40).frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.13)).frame(height: 1).padding(.horizontal, 24) }
        .accessibilityHidden(true)
    }

    var hints: [([String], String)] {
        let built = focus?.app != nil
        if model.stageSettings { return [(["A"], "Change"), (["B"], "Close")] }
        if model.playOptions != nil { return [(["A"], "Play"), (["X"], "Play once"), (["Y"], "Next preset"), (["L", "R"], "Switch tab"), (["B"], "Done")] }
        if detail { return (built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], "Build")]) + [(["Y"], "Turn over"), (["−"], focus?.favorite == true ? "Unfavourite" : "Favourite"), (["B"], "Back")] }
        var h: [([String], String)] = built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], "Build")]
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
                    RunningBar()
                    VStack(spacing: 6) {
                        Text("STARTING THE GAME").font(.system(size: 11.5, weight: .bold)).fontWidth(.expanded).kerning(1.8).foregroundStyle(StageLook.soft)
                        if !launch.summary.isEmpty { Text(launch.summary).font(.system(size: 13.5, weight: .medium)).foregroundStyle(StageLook.soft) }
                        if let n = launch.note { Text(n).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.14)) }
                    }
                    Spacer(minLength: 0)
                    Button { model.launching = nil } label: {
                        HStack(spacing: 7) { PadGlyph(text: "B"); Text("Hide").font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft) }
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
}

/// The front end's own settings.
struct StageSettings: View {
    @Bindable var model: AppModel
    let openConverterSettings: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                Spacer()
                Button { model.stageSettings = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                        .background(.white.opacity(0.10), in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
            }
            group("LAUNCHING") {
                toggle("Play goes straight into the game", "Uses each game's saved Play options and still checks its cloud save. Its own settings window stays closed.", $model.settings.straightPlay, row: .straightPlay)
                toggle("Show Play options the first time", "A game you have not played yet opens its options once before it starts.", $model.settings.firstPlayOptions, row: .firstPlayOptions)
                toggle("Battery preset on battery", "Unplugged, a run takes the Battery preset. Your saved options are not changed.", $model.settings.batteryPreset, row: .batteryPreset)
                toggle("Return here when a game quits", "NXForge comes back to the front, ready for the next game. The game's sidebar also has Library, which quits to this game's page.", $model.settings.returnToLibrary, last: true, row: .returnToLibrary)
            }
            group("COVERS") {
                toggle("Download box art", "Front and back covers from GameTDB, matched by the game's name. Only a cover's ID is sent.", $model.settings.downloadCovers, row: .downloadCovers)
                row("Covers folder", "Your own covers and the downloaded ones.", last: true) {
                    HStack(spacing: 8) {
                        Button("Look Again") { CoverStore.shared.lookAgain(); model.fetchCovers(model.stageGames()) }.buttonStyle(StageButton(height: 32))
                        Button("Show") { try? FileManager.default.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(CoverStore.dir) }.buttonStyle(StageButton(height: 32))
                    }
                }
            }
            group("WHEN NXFORGE OPENS") {
                row("Open on", "", last: true, focus: .startIn) {
                    Picker("", selection: $model.settings.startIn) { ForEach(StartIn.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                }
            }
            HStack(spacing: 10) {
                Button("Games Folder…") { model.chooseGamesRoot() }.buttonStyle(StageButton(height: 38))
                Button("Scan Again") { model.scanLibrary() }.buttonStyle(StageButton(height: 38)).disabled(model.libraryScanning)
                Spacer()
                Button("Converter Settings…") { openConverterSettings() }.buttonStyle(StageButton(height: 38))
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(StageLook.panel.opacity(solid ? 1 : 0.80), in: .rect(cornerRadius: 28))
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
    }

    func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).fontWidth(.expanded).kerning(1.6).foregroundStyle(StageLook.soft)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 18)
                .background(StageLook.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StageLook.edge, lineWidth: 1))
        }
    }

    func row<C: View>(_ title: String, _ note: String, last: Bool = false, focus: StageSettingRow? = nil, @ViewBuilder _ control: () -> C) -> some View {
        // the row a controller is on is lit (only while one is connected: the pointer needs no mark)
        let lit = focus != nil && focus?.rawValue == model.settingsFocus && !GCController.controllers().isEmpty
        return VStack(spacing: 0) {
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
            if !last { Rectangle().fill(.white.opacity(0.10)).frame(height: 1) }
        }
    }

    func toggle(_ title: String, _ note: String, _ on: Binding<Bool>, last: Bool = false, row focus: StageSettingRow? = nil) -> some View {
        row(title, note, last: last, focus: focus) { Toggle(title, isOn: on).toggleStyle(.switch).labelsHidden().tint(.green) }
    }
}
