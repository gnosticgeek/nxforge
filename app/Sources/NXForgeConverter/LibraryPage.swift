// Library: every game under the games folder (Settings.gamesRoot), from GameLibrary's scan, with its own name and icon
// (read from its control data with prod.keys), what each one holds, whether it plays on NXForge, and whether and on which
// engine it is built. Convert makes a game the one on the Convert page; ticked games build one after another (Build selected).
// A game sharing its folder with others moves into a folder of its own first.
import AppKit
import SwiftUI

struct LibraryPage: View {
    @Bindable var model: AppModel

    var body: some View {
        let builds = model.libraryBuilds()
        let all = model.library?.games ?? []
        let games = filtered(all, builds)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Library", subtitle: "Every game in your games folder, ready to build.") {
                    if model.libraryScanning {
                        Button { model.stopLibraryScan() } label: { Label("Stop Scan", systemImage: "stop.fill") }
                            .help("Stop the scan")
                    } else {
                        Button { model.scanLibrary() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                            .help("Scan the games folder again").disabled(model.settings.gamesRoot == nil)
                    }
                }
                rootCard
                batchCard
                if let l = model.library, l.root == model.settings.gamesRoot, !l.games.isEmpty {
                    HStack(spacing: 12) {
                        Picker("", selection: $model.libraryConsole) {
                            ForEach(ConsoleFilter.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        Picker("", selection: $model.libraryFilter) {
                            ForEach(LibraryFilter.allCases, id: \.self) { f in
                                Text("\(f.rawValue) (\(all.filter { model.matches($0, f, builds) && consoleOK($0) }.count))").tag(f)
                            }
                        }
                        .labelsHidden().fixedSize()
                        Spacer()
                        Text(summary(l, shown: games.count)).foregroundStyle(.secondary)
                    }
                    if !model.librarySelection.isEmpty { selectionBar(all, builds) }
                    if games.isEmpty {
                        Group {
                            if model.librarySearch.isEmpty {
                                ContentUnavailableView("No Matching Games", systemImage: "line.3.horizontal.decrease.circle", description: Text("No game matches these filters."))
                            } else { ContentUnavailableView.search(text: model.librarySearch) }
                        }
                        .padding(.top, 24)
                    } else {
                        InsetTable {
                            ForEach(games) { g in
                                if g.id != games.first?.id { Divider() }
                                row(g, build: model.build(of: g, in: builds))
                            }
                        }
                    }
                } else if !model.libraryScanning, let root = model.settings.gamesRoot {
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
            .padding(20)
        }
        .searchable(text: $model.librarySearch, placement: .toolbar, prompt: "Search games")
        // first visit with a folder chosen, or a list over a day old: scan; names and icons not read yet: read them
        .task {
            model.scanIfStale()
            if !model.libraryScanning { model.readLibraryDetails() }
        }
    }

    func consoleOK(_ g: LibraryGame) -> Bool { model.libraryConsole == .all || g.console.rawValue == model.libraryConsole.rawValue }

    func filtered(_ all: [LibraryGame], _ builds: [String: LibraryBuild]) -> [LibraryGame] {
        let q = model.librarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { g in
            consoleOK(g) && model.matches(g, model.libraryFilter, builds)
                && (q.isEmpty || g.displayName.lowercased().contains(q) || g.name.lowercased().contains(q) || g.titleID?.lowercased().contains(q) == true
                    || g.publisher?.lowercased().contains(q) == true || g.path.lowercased().contains(q))
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

    /// Build selected: the game building now and the ones to go, then what happened to each.
    @ViewBuilder var batchCard: some View {
        if model.batchRunning || !model.batchResults.isEmpty {
            Card(padding: 14) {
                HStack {
                    if let g = model.batchCurrent {
                        ProgressView().controlSize(.small)
                        Text("Building \(g.displayName)").font(.headline)
                        Text(model.batchQueue.isEmpty ? "· last one" : "· \(model.batchQueue.count) to go").foregroundStyle(.secondary)
                        Spacer()
                        Button("Show build") { model.page = .convert }.buttonStyle(.glass)
                        Button("Stop…") { model.stopBatch() }.buttonStyle(.glass)
                    } else {
                        Text(model.batchMessage ?? "Build selected finished").font(.headline)
                        Spacer()
                        Button("Dismiss") { model.batchResults = []; model.batchMessage = nil }.buttonStyle(.glass)
                    }
                }
                ForEach(model.batchResults) { r in
                    Label { Text(r.name).fontWeight(.medium) + Text(" · \(r.text)").foregroundStyle(.secondary) } icon: { StatusIcon(ok: r.ok, size: 14) }
                        .lineLimit(2)
                }
            }
        }
    }

    func selectionBar(_ all: [LibraryGame], _ builds: [String: LibraryBuild]) -> some View {
        let picked = all.filter { model.librarySelection.contains($0.id) }
        let need = model.batchNeed(picked, builds: builds)
        let short = need.contains { $0.need > $0.free }
        return HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(picked.count) game\(picked.count == 1 ? "" : "s") selected").font(.headline)
                Text(need.map { "about \(Disk.gb($0.need)) needed on \($0.volume), \(Disk.gb($0.free)) free" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(short ? .orange : .secondary)
            }
            Spacer()
            Button("Clear") { model.librarySelection = [] }.buttonStyle(.glass)
            Button("Build \(picked.count) game\(picked.count == 1 ? "" : "s")") { model.buildSelected() }
                .buttonStyle(.glassProminent).disabled(model.run.running || model.batchRunning || !model.rebuildQueue.isEmpty)
                .help(model.run.running ? "Not while a build runs" : "Build them one after another; a failed one is noted and the next one starts")
        }
        .padding(12)
        .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.5)))
    }

    func summary(_ l: LibraryScan, shown n: Int) -> String {
        let s = n == l.games.count ? "\(n) game\(n == 1 ? "" : "s")" : "\(n) of \(l.games.count) games"
        let when = relativeDay(l.scanned)
        return "\(s) · scanned \(when.hasPrefix("Today") || when.hasPrefix("Yesterday") ? when.lowercasedFirst : "on \(when)")"
    }

    func badge(_ text: String, _ color: Color? = nil) -> some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color ?? .primary)
            .background(color.map { AnyShapeStyle($0.opacity(0.15)) } ?? AnyShapeStyle(.quaternary), in: .capsule)
    }

    @ViewBuilder func statusBadges(_ g: LibraryGame, _ b: LibraryBuild?) -> some View {
        if let v = g.titleID.flatMap({ model.verified[$0] }) {
            let (t, c): (String, Color) = v.result == "plays" ? ("Plays", .green) : v.result == "boots" ? ("Boots", .orange) : v.result == "broken" ? ("Broken", .red) : (v.result, .secondary)
            badge(t, c).help(v.summary + (v.note.isEmpty || v.note == "-" ? "" : "\n\(v.note)"))
        } else if model.hasProfile(g) {
            badge("Profile", .blue).help("NXForge has a profile for this game, but it is not listed as tested yet")
        }
        if let b {
            if model.outdated(b) { badge("Built · older engine", .orange).help("\(b.app.lastComponent) was built on \(b.record?.engine.short ?? "an older engine"): rebuild for the newest fixes") }
            else { badge("Built", .green).help(b.app) }
        }
    }

    func row(_ g: LibraryGame, build b: LibraryBuild?) -> some View {
        let picked = model.librarySelection.contains(g.id)
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { picked }, set: { on in if on { model.librarySelection.insert(g.id) } else { model.librarySelection.remove(g.id) } }))
                .toggleStyle(.checkbox).labelsHidden().disabled(model.batchRunning)
            if let icon = g.icon {
                GameIcon(url: icon.url, size: 44)
            } else {
                Image(systemName: g.kind == .nup ? "shippingbox" : g.kind == .dump ? "folder.badge.gearshape" : "gamecontroller")
                    .font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(g.displayName).font(.headline).lineLimit(1)
                    badge(g.console.rawValue)
                    statusBadges(g, b)
                }
                Text(([g.contents, g.version.map { "v\($0)" }, g.publisher.flatMap { $0.isEmpty ? nil : $0 }, g.titleID, g.bytes > 0 ? Disk.gb(g.bytes) : nil].compactMap { $0 }).joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
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
                Text(g.path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { reveal(revealPath(g)) } label: { Image(systemName: "folder") }.buttonStyle(.glass).help("Show in Finder")
            if let b {
                Button { model.openApp(b.app) } label: { Image(systemName: "play.fill") }.buttonStyle(.glass).help("Open \(b.app.lastComponent)")
            }
            Button("Convert") { model.convertFromLibrary(g) }
                .buttonStyle(.glass).disabled(model.run.running || model.batchRunning)
                .help(model.run.running ? "Not while a build runs" : "Make this the game on the Convert page")
                .frame(minWidth: 86)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(picked ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(.rect)
        .onTapGesture(count: 2) { if !model.run.running && !model.batchRunning { model.convertFromLibrary(g) } }
        .contextMenu {
            Button("Convert") { model.convertFromLibrary(g) }.disabled(model.run.running || model.batchRunning)
            Button(picked ? "Deselect" : "Select for Build Selected") { if picked { model.librarySelection.remove(g.id) } else { model.librarySelection.insert(g.id) } }
            if g.shared { Button("Move into Its Own Folder") { model.moveToOwnFolder(g) } }
            if g.stray?.isEmpty == false { Button("Move Update and DLC Beside the Game…") { model.moveStray(g) } }
            Divider()
            Button("Show in Finder") { reveal(revealPath(g)) }
            if let b { Button("Show App in Finder") { reveal(b.app) } }
            if let t = g.titleID { Button("Copy Title ID") { copyToClipboard(t) } }
        }
    }

    func revealPath(_ g: LibraryGame) -> String { g.shared ? "\(g.path)/\(g.files.first ?? "")" : g.path }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
