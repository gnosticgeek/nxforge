// The front end: the games as covers on a dark stage lit by the focused game's colours, shown instead of the converter's
// pages (the Converter tab goes back to them). Home is a shelf under the game last played, Library every game in the games
// folder (the ones not built yet dimmed), a game's page has its box in 3D, and Play goes straight into the game
// (PlayOptions.swift). Everything works from a controller (ControllerNav → stagePad), the keyboard and the pointer.
import AppKit
import GameController
import SwiftUI

enum StageTab: String, CaseIterable { case home = "Home", library = "Library" }
enum StageFilter: String, CaseIterable { case all = "All", ready = "Ready to play", switch2 = "Switch 2", switch1 = "Switch", notBuilt = "Not built yet" }

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

    var coverKey: String { CoverStore.key(titleID: titleID, name: name) }
    func isRef(_ r: GameRef) -> Bool { (ref.libraryID != nil && ref.libraryID == r.libraryID) || (app != nil && app == r.app) }
}

enum StageLook {
    static let background = Color(red: 0.031, green: 0.035, blue: 0.047)
    static let soft = Color(white: 0.80)
    static let faint = Color(white: 0.66)
    static let panel = Color(red: 0.11, green: 0.118, blue: 0.15)

    static func played(_ d: Date?) -> String {
        guard let d else { return "Not played yet" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Played today" }
        if cal.isDateInYesterday(d) { return "Played yesterday" }
        return "Played \(d.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

enum PadKey { case left, right, up, down, a, b, x, y, l, r, menu }

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
        return out.sorted { a, b in
            if (a.app != nil) != (b.app != nil) { return a.app != nil }
            if a.last != b.last { return (a.last ?? .distantPast) > (b.last ?? .distantPast) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The games on screen: Home's shelf has the built ones (every game when none is built), Library the filter's.
    func stageShown(_ games: [StageGame]) -> [StageGame] {
        if stageTab == .home {
            let built = games.filter { $0.app != nil }
            return built.isEmpty ? games : built
        }
        var out = games
        switch stageFilter {
        case .all: break
        case .ready: out = out.filter { $0.app != nil }
        case .switch2: out = out.filter { $0.console == .switch2 }
        case .switch1: out = out.filter { $0.console == .switch1 }
        case .notBuilt: out = out.filter { $0.app == nil }
        }
        let q = stageSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { out = out.filter { $0.name.lowercased().contains(q) } }
        return out
    }

    func stageFocus(_ shown: [StageGame]) -> StageGame? {
        shown.first { $0.id == libraryFocus } ?? shown.first
    }

    func moveStageFocus(dx: Int = 0, dy: Int = 0) {
        let shown = stageShown(stageGames())
        guard !shown.isEmpty else { return }
        guard let i = shown.firstIndex(where: { $0.id == libraryFocus }) else { libraryFocus = shown.first?.id; return }
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
            if k == .b || k == .menu { stageSettings = false }
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
            }
            return
        }
        if let r = gameDetail {
            switch k {
            case .a: playFromStage(r)
            case .x: openPlayOptions(r)
            case .b: gameDetail = nil
            case .y: caseFlipped.toggle()
            case .menu: stageSettings = true
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
        case .menu: stageSettings = true
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: primary ? 17 : 15, weight: primary ? .bold : .semibold))
            .padding(.horizontal, primary ? 26 : 20).frame(height: height)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.12)), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(primary ? 0 : 0.18)))
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// The stage's light: the focused game's colour top left, a cooler turn of it top right, fading to black below.
struct StageBackdrop: View {
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                StageLook.background
                Circle().fill(RadialGradient(colors: [tint.opacity(0.62), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.48))
                    .frame(width: w * 0.96, height: w * 0.96).position(x: w * 0.22, y: h * 0.12)
                Circle().fill(RadialGradient(colors: [tint.opacity(0.30), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.40))
                    .frame(width: w * 0.8, height: w * 0.8).hueRotation(.degrees(48)).position(x: w * 0.92, y: h * 0.08)
                LinearGradient(colors: [StageLook.background.opacity(0), StageLook.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.55).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: tint)
        .accessibilityHidden(true)
    }
}

struct StageView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @FocusState private var keys: Bool

    var body: some View {
        let games = model.stageGames()
        let shown = model.stageShown(games)
        let detail = model.gameDetail.flatMap { r in games.first { $0.isRef(r) } }
        let focus = detail ?? model.stageFocus(shown)
        let tint = focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
        ZStack {
            StageBackdrop(tint: tint)
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
            if model.stageSettings {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.stageSettings = false }
                StageSettings(model: model, openConverterSettings: { openSettings() }).transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            if let l = model.launching {
                LaunchScreen(model: model, launch: l, game: games.first { $0.isRef(l.ref) }).transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.35), value: model.playOptions?.id)
        .animation(.spring(duration: 0.3), value: model.stageSettings)
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
        .task(id: games.map(\.coverKey).joined(separator: "|") + (model.settings.downloadCovers ? "1" : "0")) { model.fetchCovers(games) }
    }
}

struct StageTopBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Text("NXForge").font(.system(size: 19, weight: .heavy))
            HStack(spacing: 4) {
                ForEach(StageTab.allCases, id: \.self) { t in
                    tab(t.rawValue, on: model.stageTab == t) { model.stageTab = t }
                }
                tab("Converter", on: false) { model.showConverter() }
                    .help("Convert, Builds, Storage, Toolchain and Updates")
            }
            .padding(4)
            .background(.white.opacity(0.08), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .padding(.leading, 14)
            if model.run.running && !model.run.planning {
                Button { model.showConverter(); model.page = .convert } label: {
                    HStack(spacing: 8) { Text("Building").font(.callout.weight(.semibold)); SidebarBuildProgress(run: model.run) }
                        .padding(.horizontal, 12).frame(height: 36).background(.white.opacity(0.08), in: .capsule)
                }
                .buttonStyle(.plain).help("Show the build")
            }
            Spacer(minLength: 0)
            if let pad = GCController.controllers().first?.vendorName {
                Label(pad, systemImage: "gamecontroller").font(.callout.weight(.medium)).foregroundStyle(StageLook.soft)
                    .padding(.horizontal, 12).frame(height: 36).background(.white.opacity(0.08), in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
            if model.stageTab == .library {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(StageLook.soft)
                    TextField("Search games", text: $model.stageSearch).textFieldStyle(.plain).frame(width: 170)
                }
                .padding(.horizontal, 14).frame(height: 36).background(.white.opacity(0.08), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
            round("arrow.up.left.and.arrow.down.right", "Full Screen") { model.toggleFullScreen() }
            round("slider.horizontal.3", "Settings") { model.stageSettings = true }
        }
        .padding(.horizontal, 40).padding(.top, 6).padding(.bottom, 10)
    }

    func tab(_ title: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).frame(height: 30)
                .foregroundStyle(on ? Color.black : Color(white: 0.9))
                .background(on ? Color.white.opacity(0.92) : Color.clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func round(_ symbol: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: .circle).overlay(Circle().strokeBorder(.white.opacity(0.12))).contentShape(.circle)
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

    var body: some View {
        let _ = model.revision
        let g = game
        let list = g.app.map { LaunchSettings.load(app: $0) } ?? []
        let values = Dictionary(list.map { ($0.env, LaunchSettings.value($0, app: g.app ?? "")) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).font(.system(size: 12, weight: .bold)).kerning(2.2).foregroundStyle(StageLook.soft)
            Text(g.name).font(.system(size: titleSize, weight: .heavy)).tracking(-1.2).lineLimit(2).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta).font(.system(size: 16)).foregroundStyle(StageLook.soft).lineLimit(2)
            if !list.isEmpty {
                HStack(spacing: 8) {
                    chip(PlayOptions.current(settings: list, values: values).rawValue)
                    ForEach(Array(PlayOptions.summary(settings: list, values: values).enumerated()), id: \.offset) { _, s in chip(s.value) }
                }
            }
            HStack(spacing: 10) {
                if g.app != nil {
                    Button { model.libraryFocus = g.id; model.playFromStage(g.ref) } label: { Label(model.isPlaying(app: g.app ?? "") ? "Resume" : "Play", systemImage: "play.fill") }
                        .buttonStyle(StageButton(primary: true, height: 52))
                    Button { model.libraryFocus = g.id; model.openPlayOptions(g.ref) } label: { Label("Play options", systemImage: "slider.horizontal.3") }
                        .buttonStyle(StageButton(height: 52))
                } else {
                    Button { model.playFromStage(g.ref) } label: { Label("Build", systemImage: "hammer.fill") }
                        .buttonStyle(StageButton(primary: true, height: 52)).disabled(model.run.running || model.batchRunning)
                }
                Button("Details") { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref }.buttonStyle(StageButton(height: 52))
            }
            .padding(.top, 6)
        }
    }

    var eyebrow: String {
        if game.app == nil { return "NOT BUILT YET" }
        if model.isPlaying(app: game.app ?? "") { return "PLAYING NOW" }
        if game.last == nil { return "IN YOUR LIBRARY" }
        return first ? "CONTINUE PLAYING" : "RECENTLY PLAYED"
    }

    var meta: String {
        var parts = [game.console.rawValue]
        if let v = game.version, !v.isEmpty { parts.append("Version \(v)") }
        if game.total > 0 { parts.append("Played \(Playtime.text(game.total))") }
        if game.app != nil { parts.append(game.last.map { "Last played \(relativeDay($0).lowercasedFirst)" } ?? "Not played yet") }
        return parts.joined(separator: " · ")
    }

    func chip(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 5)
            .background(.white.opacity(0.10), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14)))
    }
}

struct StageHome: View {
    @Bindable var model: AppModel
    let games: [StageGame]
    let focus: StageGame?
    let total: Int

    var body: some View {
        GeometryReader { geo in
            let tile = min(max(geo.size.height * 0.19, 92), 150)
            let shelf = tile / CoverSource.aspect + 50
            let caseH = min(max(geo.size.height - shelf - 70, 180), 470)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    if let g = focus {
                        StageHero(model: model, game: g, first: games.first?.id == g.id && g.last != nil, titleSize: geo.size.width > 1000 ? 54 : 40)
                            .frame(maxWidth: 700, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    if let g = focus, geo.size.width > 880 {
                        GameCase(game: g).frame(width: caseH * 0.82, height: caseH).padding(.trailing, geo.size.width > 1200 ? 70 : 10)
                    }
                }
                .padding(.horizontal, 56)
                .frame(maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Text("Your games").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("See all \(total)") { model.stageTab = .library }.buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(StageLook.soft)
                }
                .padding(.horizontal, 56)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 24) {
                            ForEach(games) { g in
                                CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil).frame(width: tile)
                                    .id(g.id)
                                    .onTapGesture(count: 2) { model.libraryFocus = g.id; model.playFromStage(g.ref) }
                                    .simultaneousGesture(TapGesture().onEnded { model.libraryFocus = g.id })
                                    .contextMenu { StageGameMenu(model: model, game: g) }
                                    .accessibilityLabel(g.name).accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.horizontal, 56).padding(.top, 26).padding(.bottom, 24)
                    }
                    .frame(height: shelf)
                    .onChange(of: model.libraryFocus) { _, f in if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } } }
                }
            }
        }
    }
}

struct StageLibrary: View {
    @Bindable var model: AppModel
    let all: [StageGame]
    let games: [StageGame]
    let focus: StageGame?
    static let cell: CGFloat = 136, gap: CGFloat = 26, side: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Library").font(.system(size: 32, weight: .heavy)).tracking(-0.6)
                Text("\(all.count) game\(all.count == 1 ? "" : "s") · \(all.filter { $0.app != nil }.count) ready to play").foregroundStyle(StageLook.soft)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    ForEach(StageFilter.allCases, id: \.self) { f in
                        Button { model.stageFilter = f } label: {
                            Text(f.rawValue).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 32)
                                .foregroundStyle(model.stageFilter == f ? Color.black : Color(white: 0.9))
                                .background(model.stageFilter == f ? Color.white.opacity(0.92) : Color.white.opacity(0.07), in: .capsule)
                                .overlay(Capsule().strokeBorder(.white.opacity(model.stageFilter == f ? 0 : 0.16)))
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
                                    CoverTile(game: g, focused: focus?.id == g.id, dim: g.app == nil)
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
                        .padding(.horizontal, Self.side).padding(.top, 18).padding(.bottom, 26)
                    }
                    .onChange(of: model.libraryFocus) { _, f in if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } } }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            model.stageColumns = max(Int((w - 2 * Self.side + Self.gap) / (Self.cell + Self.gap)), 1)
        }
    }

    @ViewBuilder func status(_ g: StageGame) -> some View {
        let building = model.run.running && g.game.map { model.settings.gameDir == $0.path || model.settings.gameDir == $0.folder } == true
        let (text, color): (String, Color) = building ? ("Building · \(Int((model.run.overall(now: Date()).fraction * 100).rounded())) %", Color(red: 0.38, green: 0.65, blue: 0.98))
            : g.app == nil ? ("Not built yet", Color(white: 0.55))
            : model.isPlaying(app: g.app ?? "") ? ("Playing now", Color(red: 0.38, green: 0.65, blue: 0.98))
            : g.outdated ? ("Update ready", Color(red: 0.98, green: 0.75, blue: 0.14))
            : (StageLook.played(g.last), Color(red: 0.29, green: 0.87, blue: 0.50))
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(g.app == nil ? StageLook.faint : StageLook.soft).lineLimit(1)
        }
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
        } else if g.game != nil {
            Button("Build") { model.playFromStage(g.ref) }.disabled(model.run.running || model.batchRunning)
        }
        Button("Details") { model.libraryFocus = g.id; model.caseFlipped = false; model.gameDetail = g.ref }
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
        .accessibilityHidden(true)
    }

    var hints: [([String], String)] {
        let built = focus?.app != nil
        if model.playOptions != nil { return [(["A"], "Play"), (["X"], "Play once"), (["Y"], "Next preset"), (["L", "R"], "Switch tab"), (["B"], "Done")] }
        if detail { return (built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], "Build")]) + [(["Y"], "Turn over"), (["B"], "Back")] }
        var h: [([String], String)] = built ? [(["A"], "Play"), (["X"], "Play options")] : [(["A"], "Build")]
        h.append((["Y"], "Details"))
        h.append((["L", "R"], model.stageTab == .home ? "Library" : "Change filter"))
        if model.stageTab == .library { h.append((["B"], "Home")) }
        return h
    }
}

/// Over the stage while a game starts: its cover, its name, and what it plays with.
struct LaunchScreen: View {
    let model: AppModel
    let launch: Launching
    let game: StageGame?

    var body: some View {
        ZStack {
            StageLook.background
            if let g = game, let img = CoverArt.front(g) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).blur(radius: 60).opacity(0.75)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
            RadialGradient(colors: [StageLook.background.opacity(0.25), StageLook.background.opacity(0.9)], center: .center, startRadius: 80, endRadius: 760)
            VStack(spacing: 26) {
                if let g = game { CoverTile(game: g).frame(width: 210) }
                Text(launch.name).font(.system(size: 40, weight: .heavy)).tracking(-0.8).lineLimit(2).multilineTextAlignment(.center)
                ProgressView().progressViewStyle(.linear).tint(.white).frame(width: 380)
                VStack(spacing: 6) {
                    Text("Starting the game").font(.system(size: 15, weight: .semibold))
                    if !launch.summary.isEmpty { Text(launch.summary).font(.system(size: 13)).foregroundStyle(StageLook.soft) }
                    if let n = launch.note { Text(n).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.14)) }
                }
            }
            .padding(40)
            VStack {
                Spacer()
                Button { model.launching = nil } label: {
                    HStack(spacing: 7) { PadGlyph(text: "B"); Text("Hide").font(.system(size: 13, weight: .medium)).foregroundStyle(StageLook.soft) }
                }
                .buttonStyle(.plain).padding(.bottom, 26)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.system(size: 26, weight: .heavy))
                Spacer()
                Button { model.stageSettings = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                        .background(.white.opacity(0.10), in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
            }
            group("LAUNCHING") {
                toggle("Play goes straight into the game", "Uses each game's saved Play options. Its own settings window stays closed.", $model.settings.straightPlay)
                toggle("Show Play options the first time", "A game you have not played yet opens its options once before it starts.", $model.settings.firstPlayOptions)
                toggle("Battery preset on battery", "Unplugged, a run takes the Battery preset. Your saved options are not changed.", $model.settings.batteryPreset)
                toggle("Return here when a game quits", "NXForge comes back to the front, ready for the next game.", $model.settings.returnToLibrary, last: true)
            }
            group("COVERS") {
                toggle("Download box art", "Front and back covers from GameTDB, matched by the game's name. Only a cover's ID is sent.", $model.settings.downloadCovers)
                row("Covers folder", "Your own covers and the downloaded ones.", last: true) {
                    HStack(spacing: 8) {
                        Button("Look Again") { CoverStore.shared.lookAgain(); model.fetchCovers(model.stageGames()) }.buttonStyle(StageButton(height: 32))
                        Button("Show") { try? FileManager.default.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(CoverStore.dir) }.buttonStyle(StageButton(height: 32))
                    }
                }
            }
            group("WHEN NXFORGE OPENS") {
                row("Open on", "", last: true) {
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
        .background(StageLook.panel.opacity(0.92), in: .rect(cornerRadius: 26))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
    }

    func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold)).kerning(1.6).foregroundStyle(StageLook.soft)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 18)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.10)))
        }
    }

    func row<C: View>(_ title: String, _ note: String, last: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
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
            if !last { Rectangle().fill(.white.opacity(0.10)).frame(height: 1) }
        }
    }

    func toggle(_ title: String, _ note: String, _ on: Binding<Bool>, last: Bool = false) -> some View {
        row(title, note, last: last) { Toggle(title, isOn: on).toggleStyle(.switch).labelsHidden().tint(.green) }
    }
}
