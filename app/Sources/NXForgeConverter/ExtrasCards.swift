// The game page's Cheats and Mods cards (0.12.0), over GameExtras.swift: this build's cheats with a switch each and Get Cheats
// (the public collections, by title ID and build ID), and the game's mods with a switch each, their load order, the files two of
// them both replace, drop-to-install and a GameBanana browser. Both change what the next launch reads; the game's sidebar shows
// the same cheats and mods while it runs.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Cheats

struct CheatsCard: View {
    let model: AppModel
    let app: String
    let titleID: String
    let name: String
    @State private var entries: [CheatEntry] = []
    @State private var on: Set<String> = []
    @State private var found: CheatSources.Found?
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var note: String?
    @State private var showAll = false

    var build: String? { GameExtras.buildID(app: app) }
    var dir: String { GameExtras.cheatsDir(titleID: titleID) }

    var body: some View {
        let playing = model.isPlaying(app: app)
        Card(title: "Cheats", subtitle: build.map { "For this build (\($0)). Switches apply at the next launch; the game's sidebar changes them while it runs." }
             ?? "This app does not say which build it is, so cheats cannot be matched to it. Rebuild it to use cheats.") {
            if let build {
                let keys = CheatFile.keys(entries)
                let rows = Array(zip(entries, keys)).filter { !$0.0.master && !$0.0.name.isEmpty }
                if rows.isEmpty {
                    Text("No cheats yet for this build.").foregroundStyle(.secondary)
                } else {
                    let textEnd = GameExtras.textEnd(app: app)
                    ForEach(showAll ? rows : Array(rows.prefix(8)), id: \.1) { e, key in
                        HStack(spacing: 8) {
                            Toggle(isOn: Binding(get: { on.contains(key) }, set: { set(key, $0, build: build, order: keys) })) {
                                Text(e.name).lineLimit(1).truncationMode(.middle)
                            }
                            .toggleStyle(.switch).controlSize(.small).disabled(playing)
                            if e.patchesCode(textEnd: textEnd) { Pill(text: "Changes game code", color: .orange).help("This cheat rewrites the game's instructions. Such codes are the ones that crash a game when they are for another version.") }
                            Spacer(minLength: 0)
                        }
                    }
                    if rows.count > 8 { Button(showAll ? "Show fewer" : "Show all \(rows.count)") { showAll.toggle() }.buttonStyle(.link) }
                    if playing { Text("The game is running: use its sidebar (Esc) to switch cheats now.").font(.caption).foregroundStyle(.secondary) }
                }
                if let f = found { results(f, build: build) }
                HStack(spacing: 8) {
                    Button { fetch(build) } label: { Label(busy ? "Looking…" : "Get Cheats", systemImage: "arrow.down.circle") }
                        .buttonStyle(.stagePrimary).disabled(busy)
                        .help("Looks this game and build up in switch-cheats-db and NX-60FPS-RES-GFX-Cheats on GitHub. Nothing is added until you choose.")
                    Button { openFolder() } label: { Label("Show Folder", systemImage: "folder") }.buttonStyle(.stage)
                    if !on.isEmpty { Button("All Off") { on = []; save(build, order: keys) }.buttonStyle(.stage).disabled(playing) }
                    Spacer()
                    if let note { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: app) { found = nil; note = nil; load() }
        .onChange(of: model.revision) { load() }
    }

    @ViewBuilder func results(_ f: CheatSources.Found, build: String) -> some View {
        let fresh = CheatFile.additions(to: entries, from: f.cheats)
        let textEnd = GameExtras.textEnd(app: app)
        Divider()
        if fresh.isEmpty {
            Text(f.cheats.isEmpty
                 ? (f.otherBuilds.isEmpty ? "Neither collection has cheats for this game." : "The collections have cheats for other versions of this game (\(f.otherBuilds.prefix(4).joined(separator: ", "))), none for this build. Codes for another version would not work here.")
                 : "You already have every cheat the collections list for this build.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("\(fresh.count) cheat\(fresh.count == 1 ? "" : "s") found for this build").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(fresh) { e in
                        HStack(spacing: 8) {
                            Toggle(isOn: Binding(get: { picked.contains(e.id) }, set: { if $0 { picked.insert(e.id) } else { picked.remove(e.id) } })) {
                                Text(e.name).lineLimit(1).truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            if e.patchesCode(textEnd: textEnd) { Pill(text: "Changes game code", color: .orange) }
                            Spacer(minLength: 0)
                            Text(e.source).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            HStack(spacing: 8) {
                Button("Add \(picked.count) Selected") { add(fresh.filter { picked.contains($0.id) }, build: build) }.buttonStyle(.stagePrimary).disabled(picked.isEmpty)
                Button(picked.count == fresh.count ? "Select None" : "Select All") { picked = picked.count == fresh.count ? [] : Set(fresh.map(\.id)) }.buttonStyle(.stage)
                Button("Close") { found = nil }.buttonStyle(.stage)
                Spacer()
                Text("Added cheats start switched off.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if !f.failed.isEmpty { Label("Could not reach \(f.failed.joined(separator: " and ")).", systemImage: "wifi.exclamationmark").font(.callout).foregroundStyle(.orange) }
    }

    func load() {
        guard let build else { entries = []; on = []; return }
        entries = CheatFile.load(dir: dir, build: build)
        on = CheatFile.enabled(dir: dir, build: build)
    }

    func set(_ key: String, _ value: Bool, build: String, order: [String]) {
        if value { on.insert(key) } else { on.remove(key) }
        save(build, order: order)
    }

    func save(_ build: String, order: [String]) {
        do { try CheatFile.setEnabled(on, order: order, dir: dir, build: build) } catch { note = "Could not save: \(error.localizedDescription)" }
    }

    func fetch(_ build: String) {
        busy = true; note = nil
        let t = titleID
        Task {
            let f = await CheatSources.fetch(titleID: t, build: build)
            found = f
            // instruction patches are left for the player to tick
            let textEnd = GameExtras.textEnd(app: app)
            picked = Set(CheatFile.additions(to: entries, from: f.cheats).filter { !$0.patchesCode(textEnd: textEnd) }.map(\.id))
            busy = false
        }
    }

    func add(_ list: [CheatEntry], build: String) {
        do {
            let n = try CheatFile.add(list, dir: dir, build: build)
            note = "Added \(n) cheat\(n == 1 ? "" : "s")."
            picked = []; found = nil; load()
        } catch { note = "Could not add: \(error.localizedDescription)" }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir.url)
    }
}

// MARK: - Mods

struct ModsCard: View {
    let model: AppModel
    let app: String
    let titleID: String
    let name: String
    @State private var mods: [ModInfo] = []
    @State private var state = ModState()
    @State private var note: (ok: Bool, text: String)?
    @State private var busy = false
    @State private var dropping = false
    @State private var browsing = false
    @State private var removing: ModInfo?

    var dir: String { GameExtras.modsDir(titleID: titleID) }

    var body: some View {
        let playing = model.isPlaying(app: app)
        Card(title: "Mods", subtitle: "Replacement game files, overlaid when the game starts. No rebuild needed. The first mod in the list wins a file two mods both replace.") {
            if mods.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension").font(.title2).foregroundStyle(.secondary)
                    Text("Drop a mod here (a folder, or a zip, 7z or rar archive), or browse GameBanana.").foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(Array(mods.enumerated()), id: \.element.id) { i, m in row(i, m, playing: playing) }
                let clash = Mods.clashes(mods.filter { state.on.contains($0.name) })
                if !clash.isEmpty {
                    let pairs = Dictionary(grouping: clash, by: { $0.winner + " over " + $0.losers.joined(separator: ", ") })
                    ForEach(pairs.keys.sorted(), id: \.self) { k in
                        Label("\(k): \(pairs[k]!.count) file\(pairs[k]!.count == 1 ? "" : "s") in both (\(pairs[k]!.prefix(2).map { ($0.file as NSString).lastPathComponent }.joined(separator: ", "))\(pairs[k]!.count > 2 ? ", …" : "")). Move a mod up to make it win.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if playing { Text("The game is running: changes apply the next time it starts.").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Button { pick() } label: { Label("Add Mod…", systemImage: "plus") }.buttonStyle(.stagePrimary).disabled(busy)
                Button { browsing = true } label: { Label("Browse GameBanana", systemImage: "globe") }.buttonStyle(.stage)
                Button { openFolder() } label: { Label("Show Folder", systemImage: "folder") }.buttonStyle(.stage)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if let note { Label(note.text, systemImage: note.ok ? "checkmark.circle" : "exclamationmark.triangle").font(.callout).foregroundStyle(note.ok ? Color.secondary : Color.orange).lineLimit(2) }
            }
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .dropDestination(for: URL.self) { urls, _ in
            let paths = urls.filter(\.isFileURL).map(\.path)
            guard !paths.isEmpty else { return false }
            install(paths, note: nil)
            return true
        } isTargeted: { dropping = $0 }
        .sheet(isPresented: $browsing) {
            GameBananaSheet(gameName: name, installed: Set(mods.compactMap { Mods.note(dir: dir, name: $0.name) })) { path, modName, source in
                install([path], name: modName, note: source)
            }
        }
        .confirmationDialog("Remove “\(removing?.name ?? "")”?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { m in
            Button("Move to Trash", role: .destructive) { remove(m) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("The mod's folder goes to the Trash.") }
        .onAppear(perform: load)
        .onChange(of: app) { note = nil; load() }
    }

    func row(_ i: Int, _ m: ModInfo, playing: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { state.on.contains(m.name) }, set: { v in
                if v { if !state.on.contains(m.name) { state.on.append(m.name) } } else { state.on.removeAll { $0 == m.name } }
                save()
            })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.name).lineLimit(1).truncationMode(.middle)
                    Text("\(m.files.count) file\(m.files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: m.bytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            if m.hasCode { Pill(text: "Code patches not loaded", color: .orange).help("This mod also carries patches to the game's program (exefs). NXForge loads a mod's game files only, so that part does nothing.") }
            Spacer(minLength: 0)
            Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0).help("Load earlier (wins over the mods below)")
            Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(i == mods.count - 1).help("Load later")
            Menu {
                Button("Show in Finder") { reveal(dir + "/" + m.name) }
                if let n = Mods.note(dir: dir, name: m.name), let u = URL(string: n.split(separator: "\n").first.map(String.init) ?? ""), u.scheme == "https" {
                    Button("Open Its Page") { NSWorkspace.shared.open(u) }
                }
                Divider()
                Button("Remove…", role: .destructive) { removing = m }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    func load() {
        let names = Mods.names(dir: dir)
        state = ModState.load(app: app)
        let order = Mods.ordered(names, saved: state.order)
        let d = dir, t = titleID
        mods = order.map { ModInfo(name: $0) }
        Task {
            let infos = await Task.detached { order.map { Mods.info(dir: d, name: $0, titleID: t) } }.value
            if infos.map(\.name) == mods.map(\.name) { mods = infos }
        }
    }

    func save() {
        state.on = state.on.filter { n in mods.contains { $0.name == n } }
        state.order = mods.map(\.name)
        state.save(app: app)
    }

    func move(_ i: Int, _ by: Int) {
        let j = i + by
        guard mods.indices.contains(i), mods.indices.contains(j) else { return }
        mods.swapAt(i, j)
        save()
    }

    func pick() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.message = "Choose a mod: a folder, or a zip, 7z or rar archive"
        p.prompt = "Add"
        if p.runModal() == .OK { install(p.urls.map(\.path), note: nil) }
    }

    func install(_ paths: [String], name: String? = nil, note source: String?) {
        busy = true; note = nil
        let t = titleID, d = dir
        Task {
            var added: [String] = [], failed: [String] = []
            for p in paths {
                let r = await Task.detached { () -> Result<String, Error> in
                    do { return .success(try Mods.install(from: p, titleID: t, name: name, note: source, modsDir: d)) } catch { return .failure(error) }
                }.value
                switch r {
                case .success(let n): added.append(n)
                case .failure(let e): failed.append("\((p as NSString).lastPathComponent): \(e.localizedDescription)")
                }
            }
            busy = false
            load()
            // a new mod starts switched on, loading after the ones already there
            for n in added where !state.on.contains(n) { state.on.append(n) }
            if !added.isEmpty { state.order = Mods.ordered(Mods.names(dir: d), saved: state.order); state.save(app: app) }
            if let f = failed.first { note = (false, f) }
            else if !added.isEmpty { note = (true, "Added \(added.joined(separator: ", ")). On at the next launch.") }
        }
    }

    func remove(_ m: ModInfo) {
        do {
            try FileManager.default.trashItem(at: (dir + "/" + m.name).url, resultingItemURL: nil)
            state.on.removeAll { $0 == m.name }; state.order.removeAll { $0 == m.name }
            state.save(app: app)
            note = (true, "Removed \(m.name).")
        } catch { note = (false, "Could not remove \(m.name): \(error.localizedDescription)") }
        removing = nil
        load()
    }

    func openFolder() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir.url)
    }
}

// MARK: - GameBanana

/// GameBanana's mods for the game, a page at a time. Install downloads the mod's file, checks it and hands it to the Mods card.
struct GameBananaSheet: View {
    let gameName: String
    /// the "NXForge mod.txt" notes of the mods installed already (their first line is the mod's page)
    let installed: Set<String>
    let install: (_ path: String, _ name: String, _ source: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var games: [GameBanana.Game] = []
    @State private var game: GameBanana.Game?
    @State private var mods: [GameBanana.Mod] = []
    @State private var total = 0
    @State private var page = 1
    @State private var search = ""
    @State private var loading = true
    @State private var failed = false
    @State private var working: Int?
    @State private var done: Set<Int> = []
    @State private var message: String?
    @State private var choosing: (mod: GameBanana.Mod, files: [GameBanana.File])?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mods on GameBanana").font(.title2.weight(.bold))
                    Text(game.map { "\($0.name) · \(total) mod\(total == 1 ? "" : "s")" } ?? gameName).foregroundStyle(.secondary)
                }
                Spacer()
                if games.count > 1 {
                    Picker("", selection: Binding(get: { game }, set: { game = $0; page = 1; Task { await loadMods() } })) {
                        ForEach(games) { Text($0.name).tag(Optional($0)) }
                    }
                    .labelsHidden().fixedSize()
                }
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                    .onSubmit { page = 1; Task { await loadMods() } }
                Button("Done") { dismiss() }.buttonStyle(.stagePrimary).keyboardShortcut(.cancelAction)
            }
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Asking GameBanana…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("GameBanana did not answer", systemImage: "wifi.exclamationmark", description: Text("Check the connection and try again."))
            } else if game == nil {
                ContentUnavailableView("Not on GameBanana", systemImage: "puzzlepiece.extension", description: Text("GameBanana lists no game named “\(GameBanana.searchName(gameName))”."))
            } else if mods.isEmpty {
                ContentUnavailableView("No mods found", systemImage: "puzzlepiece.extension")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(mods) { row($0) } }
                }
                HStack {
                    Button { page -= 1; Task { await loadMods() } } label: { Image(systemName: "chevron.left") }.buttonStyle(.stage).disabled(page <= 1)
                    Text("Page \(page) of \(max(1, (total + 14) / 15))").foregroundStyle(.secondary).monospacedDigit()
                    Button { page += 1; Task { await loadMods() } } label: { Image(systemName: "chevron.right") }.buttonStyle(.stage).disabled(page * 15 >= total)
                    Spacer()
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            Text("Mods are their authors' work, under the licence on each mod's page. Many are made for one version of a game, and mods that change the game's program are not loaded.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .task { await start() }
        .confirmationDialog("Which file?", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), presenting: choosing?.files) { files in
            ForEach(files) { f in
                Button("\(f.name) (\(ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file)))") { if let m = choosing?.mod { get(m, f) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("This mod has more than one download.") }
    }

    func row(_ m: GameBanana.Mod) -> some View {
        let has = done.contains(m.id) || installed.contains { $0.hasPrefix(m.page) }
        return HStack(spacing: 12) {
            AsyncImage(url: m.thumb) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Rectangle().fill(.quaternary) }
                .frame(width: 112, height: 63).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.name).font(.headline).lineLimit(1)
                    if m.obsolete { Pill(text: "Obsolete", color: .orange) }
                }
                Text([m.category, m.author.isEmpty ? "" : "by \(m.author)", m.version.isEmpty ? "" : "v\(m.version)", m.updated.formatted(.dateTime.day().month(.abbreviated).year())]
                    .filter { !$0.isEmpty }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { if let u = URL(string: m.page) { NSWorkspace.shared.open(u) } } label: { Image(systemName: "safari") }.buttonStyle(.stage).help("Open the mod's page")
            if working == m.id { ProgressView().controlSize(.small).frame(width: 80) }
            else {
                Button(has ? "Installed" : "Install") { choose(m) }.buttonStyle(.stagePrimary).disabled(has || working != nil).frame(width: 80)
            }
        }
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 12))
    }

    func start() async {
        games = await GameBanana.games(named: gameName)
        game = GameBanana.best(games, for: gameName)
        await loadMods()
    }

    func loadMods() async {
        guard let g = game else { loading = false; return }
        loading = true; failed = false
        if let p = await GameBanana.mods(game: g.id, page: page, search: search.trimmingCharacters(in: .whitespaces)) {
            mods = p.mods; total = p.total
        } else { mods = []; failed = true }
        loading = false
    }

    func choose(_ m: GameBanana.Mod) {
        working = m.id; message = nil
        Task {
            let files = await GameBanana.files(mod: m.id).filter(\.clean)
            let ok = files.filter { Mods.archiveTypes.contains(($0.name as NSString).pathExtension.lowercased()) }
            if ok.isEmpty { working = nil; message = "“\(m.name)” has no archive NXForge can open. Its page has the files." }
            else if ok.count == 1 { get(m, ok[0]) }
            else { working = nil; choosing = (m, ok) }
        }
    }

    func get(_ m: GameBanana.Mod, _ f: GameBanana.File) {
        working = m.id; message = nil; choosing = nil
        Task {
            do {
                let path = try await GameBanana.download(f)
                install(path, m.name, "\(m.page)\n\(m.name)\(m.author.isEmpty ? "" : " by \(m.author)") · \(f.name)")
                done.insert(m.id)
                message = "Installed “\(m.name)”."
            } catch { message = "“\(m.name)”: \(error.localizedDescription)" }
            working = nil
        }
    }
}
