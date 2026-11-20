// Library: every game under the games folder (Settings.gamesRoot), from GameLibrary's scan, with its own name and icon
// (read from its control data with prod.keys), what each one holds, whether it plays on NXForge, and whether and on which
// engine it is built. Shown as a list or as a grid of covers tinted with each game's icon (idea 3), sorted by name, by when it
// was last played (6) or by size, with Continue playing above. A double-click (or Return) opens the game's page (4), Space a
// quick preview, the arrow keys move between games (18). Ticked games build one after another, now or later (11); a move the
// Library made can be undone (17); a games folder on a drive that is away says so and offers to mount it (12).
// A game sharing its folder with others moves into a folder of its own first.
import AppKit
import SwiftUI

extension AppModel {
    func consoleOK(_ g: LibraryGame) -> Bool { libraryConsole == .all || g.console.rawValue == libraryConsole.rawValue }

    /// The games the Library shows now: filtered, searched and sorted as chosen.
    func libraryShown(_ builds: [String: LibraryBuild]) -> [LibraryGame] {
        let sorted = librarySorted(builds)
        // grouped: the Switch 2 section first, each in the chosen order, so the arrow keys walk the games as shown
        guard libraryGrouped else { return sorted }
        return sorted.filter { $0.console == .switch2 } + sorted.filter { $0.console != .switch2 }
    }

    /// The Library in a Switch 2 section and a Switch one: chosen, and both consoles on show.
    var libraryGrouped: Bool { settings.libraryGroupByConsole && libraryConsole == .all }

    /// Bigger Covers / Smaller Covers (⌘+ and ⌘−), in steps of 30 points.
    func resizeCovers(by step: Double) {
        let r = Settings.coverSizes
        settings.libraryCoverSize = min(max(settings.libraryCoverSize + step, r.lowerBound), r.upperBound)
        if settings.libraryLayout != .grid { settings.libraryLayout = .grid }
    }

    private func librarySorted(_ builds: [String: LibraryBuild]) -> [LibraryGame] {
        let all = library?.games ?? []
        let q = librarySearch.trimmingCharacters(in: .whitespaces)
        let games = all.filter { g in
            consoleOK(g) && matches(g, libraryFilter, builds)
                && (q.isEmpty || TitleMatch.matches(q, [g.displayName, g.name, g.titleID, g.publisher, g.path]))
        }
        switch settings.librarySort {
        case .name:
            return games.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .size:
            return games.sorted { $0.bytes > $1.bytes }
        case .recent:
            let plays = Playtime.load()
            func last(_ g: LibraryGame) -> Date {
                if let t = g.titleID, let d = plays[t]?.last { return d }
                if let a = build(of: g, in: builds)?.app, let d = plays[a]?.last { return d }
                return .distantPast
            }
            let pairs: [(game: LibraryGame, last: Date)] = games.map { ($0, last($0)) }
            let sorted = pairs.sorted { (a: (game: LibraryGame, last: Date), b: (game: LibraryGame, last: Date)) -> Bool in
                if a.last != b.last { return a.last > b.last }
                return a.game.displayName.localizedStandardCompare(b.game.displayName) == .orderedAscending
            }
            return sorted.map { $0.game }
        }
    }

    /// Arrow keys and a controller's pad: move the Library's focus by dx games, or dy rows of the grid.
    func moveLibraryFocus(dx: Int = 0, dy: Int = 0) {
        let games = libraryShown(libraryBuilds())
        guard !games.isEmpty else { return }
        let cols = settings.libraryLayout == .grid ? max(libraryColumns, 1) : 1
        let i = libraryFocus.flatMap { f in games.firstIndex { $0.id == f } }
        guard let i else { libraryFocus = games.first?.id; return }
        let j = min(max(i + dx + dy * cols, 0), games.count - 1)
        libraryFocus = games[j].id
    }

    func focusedGame() -> GameRef? {
        guard let f = libraryFocus, let g = library?.games.first(where: { $0.id == f }) else { return nil }
        return GameRef(libraryID: g.id, app: build(of: g, in: libraryBuilds())?.app)
    }
}

struct LibraryPage: View {
    @Bindable var model: AppModel
    @State private var laterSheet = false
    @State private var laterDate = BatchSchedule.tonight()
    @FocusState private var focused: Bool
    @State private var restoreScroll: String?
    /// Finder's type-to-select over the games shown (TitleMatch.swift)
    @State private var typed = TypeSelectBuffer()

    var grid: Bool { model.settings.libraryLayout == .grid }

    var body: some View {
        let builds = model.libraryBuilds()
        let all = model.library?.games ?? []
        let games = model.libraryShown(builds)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        heading(all.count)
                        offlineCard
                        if showsRootCard { rootCard }
                        undoCard
                        batchCard
                    }
                    if let l = model.library, l.root == model.settings.gamesRoot, !l.games.isEmpty {
                        filterBar(all, builds, l, shown: games.count)
                        if games.isEmpty {
                            Group {
                                if model.librarySearch.isEmpty {
                                    ContentUnavailableView("No Matching Games", systemImage: "line.3.horizontal.decrease.circle", description: Text("No game matches these filters."))
                                } else { ContentUnavailableView.search(text: model.librarySearch) }
                            }
                            .padding(.top, 24)
                        } else {
                            ForEach(sections(games)) { sec in
                                if !sec.title.isEmpty {
                                    HStack(spacing: 8) {
                                        Text(sec.title).font(.title3.weight(.bold))
                                        Text("\(sec.games.count)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                            .padding(.horizontal, 7).padding(.vertical, 1).background(.quaternary, in: .capsule)
                                    }
                                    .padding(.top, 4)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isHeader)
                                }
                                if grid {
                                    let min: CGFloat = CGFloat(model.settings.libraryCoverSize)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: min, maximum: min * 1.4), spacing: 18)], alignment: .leading, spacing: 20) {
                                        ForEach(sec.games) { g in GameTile(model: model, game: g, build: model.build(of: g, in: builds),
                                                                                    focus: model.libraryFocus == g.id, picked: model.librarySelection.contains(g.id)).id(g.id) }
                                    }
                                    .onGeometryChange(for: Int.self) { Int(($0.size.width + 18) / (min + 18)) } action: { model.libraryColumns = max($0, 1) }
                                } else {
                                    VStack(spacing: 0) {
                                        tableHeader(sec.games)
                                        ForEach(sec.games) { g in
                                            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                                            row(g, build: model.build(of: g, in: builds)).id(g.id)
                                        }
                                    }
                                    .background(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.6), in: .rect(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
                                    .clipShape(.rect(cornerRadius: 14))
                                }
                            }
                        }
                        Text(summary(l, shown: games.count)).font(.callout).foregroundStyle(StageLook.faint)
                    } else if !model.libraryScanning, let root = model.settings.gamesRoot, model.offlineVolume(root) == nil {
                        ContentUnavailableView {
                            Label("No Games Found", systemImage: "questionmark.folder")
                        } description: {
                            Text("Nothing to build in \(root.tildePath). The scan looks for .nsp, .xci, .nsz and .xcz files, Switch 2 .nup files and dump folders, in every folder up to \(GameLibrary.maxDepth) levels down.")
                        } actions: {
                            Button("Scan Again") { model.scanLibrary() }
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 28)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar(all, builds).padding(.horizontal, Theme.gutter - 4).padding(.bottom, 14)
            }
            .onChange(of: model.libraryFocus) { _, f in
                if let f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) } }
            }
            // back where it was: the game the Library was on last time is scrolled into view (idea 10)
            // The scroll itself happens in onChange: called from the task, the proxy can be reached while SwiftUI is still
            // updating the views ("ScrollViewProxy may not be accessed during view updates"), which ends the app.
            .task {
                guard let f = model.libraryFocus else { return }
                try? await Task.sleep(for: .milliseconds(150))
                restoreScroll = f
            }
            .onChange(of: restoreScroll) { _, f in if let f { proxy.scrollTo(f, anchor: .center) } }
        }
        // the keyboard: arrows move between games, Return opens the game's page, Space a quick look
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(characters: CharacterSet(charactersIn: "=")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.resizeCovers(by: 30)
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return]) { press in
            switch press.key {
            case .leftArrow: model.moveLibraryFocus(dx: -1)
            case .rightArrow: model.moveLibraryFocus(dx: 1)
            case .upArrow: model.moveLibraryFocus(dy: -1)
            case .downArrow: model.moveLibraryFocus(dy: 1)
            case .space:
                if typed.active() { return typeSelect(" ") }
                if let r = model.focusedGame() { model.preview = model.preview == nil ? r : nil } else { return .ignored }
            case .return: if let r = model.focusedGame() { model.openGame(r) } else { return .ignored }
            default: return .ignored
            }
            return .handled
        }
        // letters typed quickly jump to the first game whose name starts with them, as in Finder
        .onKeyPress(characters: .alphanumerics) { press in
            guard press.modifiers.isEmpty || press.modifiers == .shift, let c = press.characters.first else { return .ignored }
            return typeSelect(c)
        }
        // first visit with a folder chosen, or a list over a day old: scan; names and icons not read yet: read them
        .task {
            model.scanIfStale()
            if !model.libraryScanning { model.readLibraryDetails() }
            focused = true
        }
        .sheet(isPresented: $laterSheet) { laterPicker }
    }

    func typeSelect(_ c: Character) -> KeyPress.Result {
        let prefix = typed.type(c)
        let shown = model.libraryShown(model.libraryBuilds())
        guard let g = TypeSelectBuffer.first(shown, prefix: prefix, title: { $0.displayName }) else { return .handled }
        model.libraryFocus = g.id
        return .handled
    }

    // MARK: the heading, the bar along the foot

    /// "Game Files  65 games", with the games folder and Scan again at the right
    func heading(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Game Files").font(.system(size: 32, weight: .heavy)).tracking(-0.6).accessibilityAddTraits(.isHeader)
            if count > 0 { Text("\(count) game\(count == 1 ? "" : "s")").font(.system(size: 16)).foregroundStyle(StageLook.soft) }
            Spacer(minLength: 8)
            Button { model.chooseGamesRoot() } label: { Label(model.settings.gamesRoot == nil ? "Choose folder…" : "Change folder…", systemImage: "folder") }
                .buttonStyle(.stage).disabled(model.libraryScanning || model.batchRunning)
                .help(model.settings.gamesRoot.map { "Games folder: \($0.tildePath)" } ?? "Choose the folder that holds your games")
            if model.libraryScanning {
                Button { model.stopLibraryScan() } label: { Label("Stop scan", systemImage: "stop.fill") }.buttonStyle(.plain).help("Stop the scan")
            } else {
                Button { model.scanLibrary() } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Scan the games folder again").disabled(model.settings.gamesRoot == nil)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.top, 8)
    }

    /// The games folder's card: only while there is something to say (no folder yet, a scan or a read running, a warning)
    var showsRootCard: Bool {
        model.settings.gamesRoot == nil || model.libraryProgress != nil || model.libraryDetails != nil || model.libraryMessage != nil
            || (model.library.map { $0.root == model.settings.gamesRoot && !$0.skipped.isEmpty } ?? false)
    }

    /// Along the foot: the ticked games with Build, else the game in focus with Show in Finder, Details, Play and Convert
    @ViewBuilder func actionBar(_ all: [LibraryGame], _ builds: [String: LibraryBuild]) -> some View {
        if !model.librarySelection.isEmpty {
            selectionBar(all, builds)
        } else if let g = model.libraryFocus.flatMap({ f in all.first { $0.id == f } }) ?? model.libraryShown(builds).first {
            let b = model.build(of: g, in: builds)
            HStack(spacing: 14) {
                if let icon = g.icon { GameIcon(url: icon.url, size: 52) } else { GameIcon(url: nil, size: 52) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.displayName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        let (word, color) = statusWord(g, b)
                        Text(word).foregroundStyle(color).fontWeight(.semibold)
                        Text("·  \(g.contents)").foregroundStyle(StageLook.soft)
                    }
                    .font(.system(size: 13.5)).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button { reveal(revealPath(g)) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.stage)
                Button { model.openGame(GameRef(libraryID: g.id, app: b?.app)) } label: { Label("Details", systemImage: "info.circle") }.buttonStyle(.stage)
                // the main button is the next step: Play a current build, Rebuild an old one, else Convert
                if let b, let r = b.record, model.outdated(b) {
                    Button { model.openApp(b.app) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.stage)
                    Button { model.rebuildAsked(r) } label: { Label("Rebuild", systemImage: "arrow.clockwise") }
                        .buttonStyle(StageButton(primary: true, height: 40)).disabled(model.run.running || model.batchRunning || !model.allOK)
                        .help("Builds it again on the current engine, reusing every step whose inputs have not changed")
                } else if let b {
                    Button("Convert…") { model.convertFromLibrary(g) }.buttonStyle(.stage)
                        .disabled(model.run.running || model.batchRunning).help("Open it on the Convert page")
                    Button { model.openApp(b.app) } label: { Label(model.isPlaying(app: b.app) ? "Resume" : "Play", systemImage: "play.fill") }
                        .buttonStyle(StageButton(primary: true, height: 40))
                } else {
                    Button("Convert…") { model.convertFromLibrary(g) }
                        .buttonStyle(StageButton(primary: true, height: 40))
                        .disabled(model.run.running || model.batchRunning)
                        .help(model.run.running ? "Not while a build runs" : "Make this the game on the Convert page")
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        }
    }

    /// The status column's word and colour
    func statusWord(_ g: LibraryGame, _ b: LibraryBuild?) -> (String, Color) {
        guard let b else { return ("Not built yet", StageLook.soft) }
        if model.isPlaying(app: b.app) { return ("Playing now", Color(red: 0.38, green: 0.65, blue: 0.98)) }
        if model.outdated(b) { return ("Older engine", .orange) }
        return ("Built", Color(red: 0.29, green: 0.87, blue: 0.50))
    }

    /// The table's head: tick every game shown, then the columns
    func tableHeader(_ games: [LibraryGame]) -> some View {
        let ids = Set(games.map(\.id))
        let all = !ids.isEmpty && ids.isSubset(of: model.librarySelection)
        return HStack(spacing: 14) {
            Toggle("", isOn: Binding(get: { all }, set: { on in if on { model.librarySelection.formUnion(ids) } else { model.librarySelection.subtract(ids) } }))
                .toggleStyle(.checkbox).labelsHidden().disabled(model.batchRunning).help(all ? "Deselect all" : "Select every game shown")
                .frame(width: 24)
            sortHead("Game", .name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 58)
            Text("Contents").frame(width: Self.contentsW, alignment: .leading)
            sortHead("Size", .size).frame(width: Self.sizeW, alignment: .leading)
            Text("Status").frame(width: Self.statusW, alignment: .leading)
        }
        .font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.soft)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    /// A column heading that sorts by it, with a mark when it does
    func sortHead(_ title: String, _ sort: LibrarySort) -> some View {
        Button { model.settings.librarySort = sort } label: {
            HStack(spacing: 5) {
                Text(title)
                if model.settings.librarySort == sort { Image(systemName: sort == .size ? "chevron.down" : "chevron.up").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(model.settings.librarySort == sort ? Color.white : StageLook.soft).contentShape(.rect)
        }
        .buttonStyle(.plain).help("Sort by \(title.lowercased())")
    }

    static let contentsW: CGFloat = 230, sizeW: CGFloat = 100, statusW: CGFloat = 170

    // MARK: cards over the list

    /// The games folder is on a drive or share that is not connected: the list shown is the last scan.
    @ViewBuilder var offlineCard: some View {
        if let root = model.settings.gamesRoot, let vol = model.offlineVolume(root) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.xmark").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(vol)” is not connected").font(.headline)
                    Text("The games below are from the last scan. Building needs the drive; built apps still play.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.settings.remounts[vol] != nil {
                    Button("Mount \(vol)") { _ = model.mount(vol) }.buttonStyle(.stagePrimary)
                }
            }
            .padding(14)
            .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 16))
        }
    }

    var rootCard: some View {
        Card(padding: 14) {
            PathField(label: "Games folder", symbol: "externaldrive.connected.to.line.below", value: model.settings.gamesRoot?.tildePath, button: model.settings.gamesRoot == nil ? "Choose…" : "Change…") {
                model.chooseGamesRoot()
            }
            .disabled(model.libraryScanning || model.batchRunning)
            if let p = model.libraryProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning · \(p.folders) folder\(p.folders == 1 ? "" : "s") · \(p.found) game\(p.found == 1 ? "" : "s") found").foregroundStyle(.secondary)
                    Text(p.current.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
            } else if let d = model.libraryDetails {
                HStack(spacing: 8) {
                    ProgressView(value: Double(d.done), total: Double(max(d.total, 1))).frame(width: 120)
                    Text("Reading names and icons · \(d.done) of \(d.total)").foregroundStyle(.secondary)
                }
            } else if model.settings.gamesRoot == nil {
                Text("Choose the folder that holds your games, such as a drive or a network share. Every folder inside it is searched, and it is scanned again when the drive or share connects.").foregroundStyle(.secondary)
            }
            if let m = model.libraryMessage {
                Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let l = model.library, l.root == model.settings.gamesRoot, !l.skipped.isEmpty, !model.libraryScanning {
                Label("\(l.skipped.count) folder\(l.skipped.count == 1 ? "" : "s") did not answer and \(l.skipped.count == 1 ? "was" : "were") skipped", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary).help(l.skipped.map(\.tildePath).joined(separator: "\n"))
            }
        }
    }

    /// The last move the Library made, with Undo (also Edit › Undo).
    @ViewBuilder var undoCard: some View {
        if let m = model.lastMove {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
                Text(m.label).lineLimit(1)
                Text("· \(m.files.count) file\(m.files.count == 1 ? "" : "s") · \(relativeDay(m.when).lowercasedFirst)").foregroundStyle(.secondary)
                Spacer()
                Button("Undo") { model.undoMove() }.buttonStyle(.stage).disabled(model.run.running || model.batchRunning)
                    .help("Move the files back where they were")
                Button { model.lastMove = nil } label: { Label("Hide", systemImage: "xmark").labelStyle(.iconOnly) }.buttonStyle(.borderless).help("Hide")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    /// Build selected: waiting to start, the game building now and the ones to go (in an order that can change), then what
    /// happened to each.
    @ViewBuilder var batchCard: some View {
        if model.batchRunning || !model.batchResults.isEmpty || model.batchStart != nil {
            Card(padding: 14) {
                HStack(spacing: 8) {
                    if let start = model.batchStart {
                        let missed: Bool = { if case .at(let d) = start { return d < Date() }; return false }()
                        Image(systemName: missed ? "clock.badge.exclamationmark" : start == .onPower ? "powerplug" : "moon.zzz").foregroundStyle(missed ? Color.orange : Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(missed ? "Build selected did not start" : "Build selected is waiting").font(.headline)
                            Text(missed ? "Its time passed while the converter was closed." : "\(start.text). The Mac stays awake until then; on battery, keep the lid open.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Start Now") { model.startWaitingBatch() }.buttonStyle(.stagePrimary).disabled(model.run.running)
                        Button("Clear") { model.cancelWaitingBatch() }.buttonStyle(.stage)
                    } else if let g = model.batchCurrent {
                        ProgressView().controlSize(.small)
                        Text("Building \(g.displayName)").font(.headline)
                        Text(model.batchQueue.isEmpty ? "· last one" : "· \(model.batchQueue.count) to go").foregroundStyle(.secondary)
                        Spacer()
                        Button("Show build") { model.page = .convert }.buttonStyle(.stage)
                        Button("Stop…") { model.stopBatch() }.buttonStyle(.stage)
                    } else {
                        Text(model.batchMessage ?? "Build selected finished").font(.headline)
                        Spacer()
                        Button("Dismiss") { model.batchResults = []; model.batchMessage = nil }.buttonStyle(.stage)
                    }
                }
                if !model.batchQueue.isEmpty {
                    InsetTable {
                        ForEach(Array(model.batchQueue.enumerated()), id: \.element.id) { i, g in
                            if i > 0 { Divider() }
                            HStack(spacing: 8) {
                                Text("\(i + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                Text(g.displayName).lineLimit(1)
                                Spacer()
                                Button { model.moveInQueue(g, by: -1) } label: { Label("Build Sooner", systemImage: "chevron.up").labelStyle(.iconOnly) }.buttonStyle(.borderless).disabled(i == 0).help("Build sooner")
                                Button { model.moveInQueue(g, by: 1) } label: { Label("Build Later", systemImage: "chevron.down").labelStyle(.iconOnly) }.buttonStyle(.borderless).disabled(i == model.batchQueue.count - 1).help("Build later")
                                Button { model.removeFromQueue(g) } label: { Label("Take Out of the Queue", systemImage: "minus.circle").labelStyle(.iconOnly) }.buttonStyle(.borderless).help("Take out of the queue")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                        }
                    }
                }
                ForEach(model.batchResults) { r in
                    Label { Text(r.name).fontWeight(.medium) + Text(" · \(r.text)").foregroundStyle(.secondary) } icon: { StatusIcon(ok: r.ok, size: 14) }
                        .lineLimit(2)
                }
            }
        }
    }

    /// The games played last, newest first: one click plays.
    @ViewBuilder var continuePlaying: some View {
        let recent = model.recentlyPlayed()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Continue Playing").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recent, id: \.key) { r in
                            let tint = IconColor.of(r.record.app)
                            Button { model.openApp(r.record.app) } label: {
                                HStack(spacing: 12) {
                                    AppIcon(path: r.record.app, size: 52)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.record.name).font(.headline).lineLimit(1)
                                        Text(r.record.last.map { "Played \(relativeDay($0).lowercasedFirst)" } ?? "").font(.caption).foregroundStyle(.secondary)
                                        Text("\(Playtime.text(r.record.total)) in all").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: model.isPlaying(app: r.record.app) ? "gamecontroller.fill" : "play.fill").foregroundStyle(.white)
                                        .frame(width: 30, height: 30).background(tint.opacity(0.9), in: .circle)
                                }
                                .padding(10).frame(width: 290, alignment: .leading)
                                .background(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.08)], startPoint: .leading, endPoint: .trailing), in: .rect(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.35)))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help("Play \(r.record.name)")
                            .accessibilityLabel("Play \(r.record.name), played \(r.record.last.map { relativeDay($0).lowercasedFirst } ?? "before")")
                            .contextMenu {
                                Button("Game Page") { model.openGame(GameRef(libraryID: nil, app: r.record.app)) }
                                Button("Show App in Finder") { reveal(r.record.app) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: filters and selection

    func filterBar(_ all: [LibraryGame], _ builds: [String: LibraryBuild], _ l: LibraryScan, shown: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(StageLook.faint)
                TextField("Search game files", text: $model.librarySearch).textFieldStyle(.plain)
                if !model.librarySearch.isEmpty {
                    Button { model.librarySearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                        .buttonStyle(.plain).accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 12).frame(width: 300, height: 34)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16)))
            BoxMenu {
                Picker("Platform", selection: $model.libraryConsole) {
                    ForEach(ConsoleFilter.allCases, id: \.self) { c in Text("\(c.rawValue) (\(all.filter { c == .all || $0.console.rawValue == c.rawValue }.count))").tag(c) }
                }
                .pickerStyle(.inline)
            } label: { menuLabel("Platform", model.libraryConsole.rawValue) }
            .fixedSize()
            BoxMenu {
                Picker("Status", selection: $model.libraryFilter) {
                    ForEach(LibraryFilter.allCases, id: \.self) { f in
                        Text("\(f.rawValue) (\(all.filter { model.matches($0, f, builds) && model.consoleOK($0) }.count))").tag(f)
                    }
                }
                .pickerStyle(.inline)
            } label: { menuLabel("Status", model.libraryFilter == .all ? "All" : model.libraryFilter.rawValue) }
            .fixedSize()
            Spacer()
            if model.settings.libraryLayout == .grid {
                Slider(value: $model.settings.libraryCoverSize, in: Settings.coverSizes).frame(width: 100).controlSize(.small)
                    .accessibilityLabel("Cover size").help("Cover size (⌘+ and ⌘−)")
            }
            Picker("Layout", selection: $model.settings.libraryLayout) {
                Label("List", systemImage: "list.bullet").labelStyle(.iconOnly).tag(LibraryLayout.list).help("List")
                Label("Covers", systemImage: "square.grid.2x2").labelStyle(.iconOnly).tag(LibraryLayout.grid).help("Covers")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            BoxMenu {
                Picker("Sort by", selection: $model.settings.librarySort) {
                    ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Group by Console", isOn: $model.settings.libraryGroupByConsole)
                    .disabled(model.libraryConsole != .all)
            } label: { menuLabel("Sort", model.settings.librarySort.rawValue) }
            .fixedSize()
        }
    }

    /// "Platform:  All  ⌄" on a bordered box, as the mock-up has them
    func menuLabel(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(name):").foregroundStyle(StageLook.soft)
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(StageLook.soft).padding(.leading, 10)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14).frame(height: 34)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16)))
    }

    func selectionBar(_ all: [LibraryGame], _ builds: [String: LibraryBuild]) -> some View {
        let picked = all.filter { model.librarySelection.contains($0.id) }
        let need = model.batchNeed(picked, builds: builds)
        let short = need.contains { $0.need > $0.free }
        let busy = model.run.running || model.batchRunning || !model.rebuildQueue.isEmpty || model.batchStart != nil
        return HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(picked.count) game\(picked.count == 1 ? "" : "s") selected").font(.headline)
                Text(need.map { "about \(Disk.gb($0.need)) needed on \($0.volume), \(Disk.gb($0.free)) free" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(short ? .orange : .secondary)
            }
            Spacer()
            Button("Clear") { model.librarySelection = [] }.buttonStyle(.stage)
            Menu {
                Button("Tonight at 2:00") { model.buildSelected(start: .at(BatchSchedule.tonight())) }
                Button("At a Time…") { laterDate = BatchSchedule.tonight(); laterSheet = true }
                Button("When the Mac Is on Power") { model.buildSelected(start: .onPower) }
            } label: {
                Text("Build \(picked.count) game\(picked.count == 1 ? "" : "s")")
            } primaryAction: {
                model.buildSelected()
            }
            .menuStyle(.button).buttonStyle(.glassProminent).fixedSize().disabled(busy)
            .help(model.run.running ? "Not while a build runs" : "Build them one after another, now or later; a failed one is noted and the next one starts")
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.white.opacity(0.08)), in: .rect(cornerRadius: 14))
    }

    var laterPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build the selected games later").font(.title3.weight(.bold))
            Text("The queue waits, and the Mac stays awake until it starts. It is kept if the converter quits.").foregroundStyle(.secondary)
            DatePicker("Start at", selection: $laterDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
            HStack {
                Spacer()
                Button("Cancel") { laterSheet = false }.keyboardShortcut(.cancelAction)
                Button("Build Later") { laterSheet = false; model.buildSelected(start: .at(laterDate)) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 420)
    }

    func summary(_ l: LibraryScan, shown n: Int) -> String {
        let s = n == l.games.count ? "\(n) game\(n == 1 ? "" : "s")" : "\(n) of \(l.games.count) games"
        let when = relativeDay(l.scanned)
        let at = l.scanned.formatted(date: .omitted, time: .shortened)
        let day = when.hasPrefix("Today") ? "today at \(at)" : when.hasPrefix("Yesterday") ? "yesterday at \(at)" : "on \(when)"
        return (n == l.games.count ? "" : "Showing \(s) · ") + "Last scanned \(day)"
    }

    // MARK: the list's rows

    func row(_ g: LibraryGame, build b: LibraryBuild?) -> some View {
        let picked = model.librarySelection.contains(g.id)
        let focus = model.libraryFocus == g.id
        let (word, color) = statusWord(g, b)
        return HStack(spacing: 14) {
            Toggle("", isOn: Binding(get: { picked }, set: { on in if on { model.librarySelection.insert(g.id) } else { model.librarySelection.remove(g.id) } }))
                .toggleStyle(.checkbox).labelsHidden().disabled(model.batchRunning).frame(width: 24)
            HStack(spacing: 14) {
                if let icon = g.icon {
                    GameIcon(url: icon.url, size: 44)
                } else {
                    Image(systemName: g.kind == .nup ? "shippingbox" : g.kind == .dump ? "folder.badge.gearshape" : "gamecontroller")
                        .font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(g.displayName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if let v = g.titleID.flatMap({ model.verified[$0] }), v.result == "plays" { GameBadge(text: "Plays", color: .green).help(v.summary) }
                    }
                    Text(g.console.rawValue).font(.system(size: 13)).foregroundStyle(StageLook.faint)
                    if g.shared {
                        Label("Shares its folder with other games: Convert first moves its \(g.fileCount == 1 ? "file" : "\(g.fileCount) files") into a folder of its own", systemImage: "folder.badge.plus")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.newerUpdate(g, b) {
                        Label("A newer update is here than the one the app was built with: rebuild to play it", systemImage: "arrow.up.circle.fill").font(.caption).foregroundStyle(.blue)
                    }
                    ForEach(g.notes, id: \.self) { n in
                        HStack(spacing: 6) {
                            Label(n, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                            if n.contains("not used: the build reads"), g.stray?.isEmpty == false {
                                Button("Move beside the game…") { model.moveStray(g) }.buttonStyle(.link).font(.caption).disabled(model.run.running || model.batchRunning)
                            }
                        }
                    }
                    ForEach(g.duplicates ?? [], id: \.self) { d in
                        HStack(spacing: 6) {
                            Label("The same game is also in “\(d.lastComponent)”", systemImage: "square.on.square").font(.caption).foregroundStyle(.secondary)
                            Button("Show") { reveal(d) }.buttonStyle(.link).font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(g.contents.replacingOccurrences(of: "Base game", with: "Base").replacingOccurrences(of: " + \(g.dlc) DLC", with: " · \(g.dlc) DLC"))
                .lineLimit(1).frame(width: Self.contentsW, alignment: .leading)
            Text(g.bytes > 0 ? Disk.gb(g.bytes) : "–").monospacedDigit().frame(width: Self.sizeW, alignment: .leading)
            HStack(spacing: 8) {
                Group {
                    if b == nil { Image(systemName: "hammer").foregroundStyle(StageLook.soft) }
                    else if word == "Older engine" { Image(systemName: "arrow.clockwise.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.black, color) }
                    else { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.black, color) }
                }
                .font(.system(size: 18))
                Text(word).foregroundStyle(b == nil ? StageLook.soft : .white)
            }
            .frame(width: Self.statusW, alignment: .leading)
            .help(b.map { model.outdated($0) ? "\($0.app.lastComponent) was built on \($0.record?.engine.short ?? "an older engine"): rebuild for the newest fixes" : $0.app } ?? "")
        }
        .font(.system(size: 15))
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(focus ? convertAccent.opacity(0.10) : picked ? Color.white.opacity(0.05) : .clear)
        .overlay { if focus { RoundedRectangle(cornerRadius: 10).strokeBorder(convertAccent.opacity(0.85), lineWidth: 1.5) } }
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.openGame(GameRef(libraryID: g.id, app: b?.app)) }
        .simultaneousGesture(TapGesture().onEnded { model.libraryFocus = g.id })
        .contextMenu { LibraryGameMenu(model: model, game: g, build: b) }
        .help(g.path.tildePath)
    }

    /// The games under their console's heading when grouped, else one untitled section.
    func sections(_ games: [LibraryGame]) -> [LibrarySection] {
        guard model.libraryGrouped else { return [LibrarySection(title: "", games: games)] }
        let two = games.filter { $0.console == .switch2 }
        let one = games.filter { $0.console != .switch2 }
        return [LibrarySection(title: Console.switch2.rawValue, games: two), LibrarySection(title: Console.switch1.rawValue, games: one)].filter { !$0.games.isEmpty }
    }

    func revealPath(_ g: LibraryGame) -> String { g.shared ? "\(g.path)/\(g.files.first ?? "")" : g.path }
}

/// The menu of a game in the Library (row, cover, Continue playing).
struct LibraryGameMenu: View {
    let model: AppModel
    let game: LibraryGame
    let build: LibraryBuild?

    var body: some View {
        let g = game, picked = model.librarySelection.contains(g.id)
        Button("Game Page") { model.openGame(GameRef(libraryID: g.id, app: build?.app)) }
        Button("Quick Look") { model.preview = GameRef(libraryID: g.id, app: build?.app) }
        if let b = build { Button("Play") { model.openApp(b.app) } }
        if g.titleID != nil { Button("Cheats…") { model.cheatsFor = GameRef(libraryID: g.id, app: build?.app) } }
        if build != nil, g.titleID != nil { Button("Enhancements…") { model.enhancementsFor = GameRef(libraryID: g.id, app: build?.app) } }
        Divider()
        Button("Convert") { model.convertFromLibrary(g) }.disabled(model.run.running || model.batchRunning)
        Button(picked ? "Deselect" : "Select for Build Selected") { if picked { model.librarySelection.remove(g.id) } else { model.librarySelection.insert(g.id) } }
        if g.shared { Button("Move into Its Own Folder") { model.moveToOwnFolder(g) } }
        if g.stray?.isEmpty == false { Button("Move Update and DLC Beside the Game…") { model.moveStray(g) } }
        Divider()
        Button("Show in Finder") { reveal(g.shared ? "\(g.path)/\(g.files.first ?? "")" : g.path) }
        if let b = build { Button("Show App in Finder") { reveal(b.app) } }
        if let t = g.titleID { Button("Copy Title ID") { copyToClipboard(t) } }
    }
}

/// A small word on a capsule: the console, Built, Plays.
struct GameBadge: View {
    let text: String
    var color: Color? = nil

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color ?? .primary)
            .background(color.map { AnyShapeStyle($0.opacity(0.15)) } ?? AnyShapeStyle(.quaternary), in: .capsule)
    }
}

/// Whether it plays on NXForge, and whether and on which engine it is built.
struct StatusBadges: View {
    let model: AppModel
    let game: LibraryGame
    let build: LibraryBuild?

    var body: some View {
        if let v = game.titleID.flatMap({ model.verified[$0] }) {
            let (t, c): (String, Color) = v.result == "plays" ? ("Plays", .green) : v.result == "boots" ? ("Boots", .orange) : v.result == "broken" ? ("Broken", .red) : (v.result, .secondary)
            GameBadge(text: t, color: c).help(v.summary + (v.note.isEmpty || v.note == "-" ? "" : "\n\(v.note)"))
        } else if model.hasProfile(game) {
            GameBadge(text: "Profile", color: .blue).help("NXForge has a profile for this game, but it is not listed as tested yet")
        }
        if let b = build {
            if model.outdated(b) {
                let c = b.record.flatMap { model.rebuildCost($0) }
                GameBadge(text: c.map { "Older engine · \($0.short)" } ?? "Older engine", color: .orange)
                    .help("\(b.app.lastComponent) was built on \(b.record?.engine.short ?? "an older engine"): rebuild for the newest fixes." + (c.map { " \($0.title): \($0.detail)" } ?? ""))
            }
            else { GameBadge(text: "Built", color: .green).help(b.app) }
        }
    }
}

/// A game's cover in the grid: its icon large on a backdrop of its own colour, its name and state under it. Hover shows Play
/// (built) or Convert; a click focuses it, a double-click opens its page.
struct GameTile: View {
    let model: AppModel
    let game: LibraryGame
    let build: LibraryBuild?
    /// the tile's own focus and tick, from the grid: a tile that looked them up in the model would redraw, with every other tile,
    /// each time the focus moved
    var focus = false
    var picked = false
    var big = false
    @State private var hover = false

    var body: some View {
        let g = game
        let tint = IconColor.of(g.icon)
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let i = g.icon, let img = IconImage.load(i) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: g.kind == .nup ? "shippingbox" : "gamecontroller").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
                }
                if hover && !big {
                    Color.black.opacity(0.35)
                    HStack(spacing: 8) {
                        if let b = build {
                            Button { model.openApp(b.app) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.stagePrimary)
                        } else {
                            Button("Convert") { model.convertFromLibrary(g) }.buttonStyle(.stagePrimary).disabled(model.run.running || model.batchRunning)
                        }
                    }
                }
                VStack {
                    HStack {
                        if picked || (hover && !big) {
                            Toggle("", isOn: Binding(get: { picked }, set: { on in if on { model.librarySelection.insert(g.id) } else { model.librarySelection.remove(g.id) } }))
                                .toggleStyle(.checkbox).labelsHidden().disabled(model.batchRunning).padding(6)
                        }
                        Spacer()
                        if let b = build {
                            Image(systemName: model.isPlaying(app: b.app) ? "gamecontroller.fill" : model.outdated(b) ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                                .symbolRenderingMode(.palette).foregroundStyle(.white, model.outdated(b) ? Color.orange : Color.green)
                                .font(.title3).padding(6)
                                .help(model.outdated(b) ? "Built on an older engine" : "Built")
                        }
                    }
                    Spacer()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: big ? 22 : 16))
            .overlay(RoundedRectangle(cornerRadius: big ? 22 : 16).strokeBorder(focus ? Color.white : picked ? Color.white.opacity(0.6) : .white.opacity(0.08), lineWidth: focus ? 4 : picked ? 2 : 1))
            .shadow(color: (focus ? tint : .black).opacity(focus ? 0.6 : 0.25), radius: focus ? 14 : 5, y: 3)
            .scaleEffect(focus && big ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: focus)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.displayName).font(big ? .title3.weight(.semibold) : .headline).lineLimit(1)
                HStack(spacing: 4) {
                    GameBadge(text: g.console.rawValue)
                    if let v = g.titleID.flatMap({ model.verified[$0] }), v.result == "plays" { GameBadge(text: "Plays", color: .green) }
                }
            }
        }
        .contentShape(.rect)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { model.openGame(GameRef(libraryID: g.id, app: build?.app)) }
        .simultaneousGesture(TapGesture().onEnded { model.libraryFocus = g.id })
        .contextMenu { LibraryGameMenu(model: model, game: g, build: build) }
        .help(g.path.tildePath)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tileLabel)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.libraryFocus = g.id }
        .accessibilityAction(named: build == nil ? "Convert" : "Play") {
            if let b = build { model.openApp(b.app) } else { model.convertFromLibrary(g) }
        }
        .accessibilityAction(named: picked ? "Deselect" : "Select") {
            if picked { model.librarySelection.remove(g.id) } else { model.librarySelection.insert(g.id) }
        }
        .accessibilityAction(named: "Open Game Page") { model.openGame(GameRef(libraryID: g.id, app: build?.app)) }
    }
}

/// A heading's games in the Library (one untitled section when it is not grouped).
struct LibrarySection: Identifiable {
    var id: String { title }
    let title: String
    let games: [LibraryGame]
}

extension GameTile {
    /// "Super Mario Odyssey, Switch, plays on NXForge, built on an older engine"
    var tileLabel: String {
        var parts = [game.displayName, game.console.rawValue]
        if let v = game.titleID.flatMap({ model.verified[$0] }), v.result == "plays" { parts.append("plays on NXForge") }
        if let b = build { parts.append(model.isPlaying(app: b.app) ? "playing now" : model.outdated(b) ? "built on an older engine" : "built") }
        else { parts.append("not built") }
        return parts.joined(separator: ", ")
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
