// Library: every game under the games folder (Settings.gamesRoot), from GameLibrary's scan, with what each one holds and
// whether it has been built. Convert makes a game the one on the Convert page; a game sharing its folder with others moves
// into a folder of its own first.
import AppKit
import SwiftUI

struct LibraryPage: View {
    @Bindable var model: AppModel

    var games: [LibraryGame] {
        let q = model.librarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return (model.library?.games ?? []).filter { g in
            (model.libraryConsole == .all || g.console.rawValue == model.libraryConsole.rawValue)
                && (q.isEmpty || g.name.lowercased().contains(q) || g.titleID?.lowercased().contains(q) == true || g.path.lowercased().contains(q))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Library", subtitle: "Every game in your games folder, ready to build.") {
                    if model.libraryScanning {
                        Button { model.stopLibraryScan() } label: { Label("Stop", systemImage: "stop.fill").font(.title3) }
                            .buttonStyle(.glass).controlSize(.extraLarge)
                    } else {
                        Button { model.scanLibrary() } label: { Label("Scan again", systemImage: "arrow.clockwise").font(.title3) }
                            .buttonStyle(.glass).controlSize(.extraLarge).disabled(model.settings.gamesRoot == nil)
                    }
                }
                rootCard
                if let l = model.library, l.root == model.settings.gamesRoot, !l.games.isEmpty {
                    HStack {
                        Picker("", selection: $model.libraryConsole) {
                            ForEach(ConsoleFilter.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        Spacer()
                        Text(summary(l)).foregroundStyle(.secondary)
                    }
                    if games.isEmpty {
                        Text("No game matches “\(model.librarySearch)”.").foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        let records = Engine.builds()
                        InsetTable {
                            ForEach(games) { g in
                                if g.id != games.first?.id { Divider() }
                                row(g, app: model.builtApp(g, records: records))
                            }
                        }
                    }
                } else if !model.libraryScanning, let root = model.settings.gamesRoot {
                    Card {
                        Label("No games found in \(root.tildePath)", systemImage: "questionmark.folder").font(.headline)
                        Text("The scan looks for .nsp, .xci, .nsz and .xcz files, Switch 2 .nup files and dump folders, in every folder up to \(GameLibrary.maxDepth) levels down.").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        // first visit with a folder chosen and no list for it yet
        .task { if let r = model.settings.gamesRoot, model.library?.root != r, !model.libraryScanning { model.scanLibrary() } }
    }

    var rootCard: some View {
        Card(padding: 14) {
            PathField(label: "Games folder", symbol: "externaldrive.connected.to.line.below", value: model.settings.gamesRoot?.tildePath, button: model.settings.gamesRoot == nil ? "Choose…" : "Change…") {
                model.chooseGamesRoot()
            }
            .disabled(model.libraryScanning)
            if let p = model.libraryProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning · \(p.folders) folder\(p.folders == 1 ? "" : "s") · \(p.found) game\(p.found == 1 ? "" : "s") found").foregroundStyle(.secondary)
                    Text(p.current.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
            } else if model.settings.gamesRoot == nil {
                Text("Choose the folder that holds your games, such as a drive or a network share. Every folder inside it is searched.").foregroundStyle(.secondary)
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

    func summary(_ l: LibraryScan) -> String {
        let n = games.count
        let shown = n == l.games.count ? "\(n) game\(n == 1 ? "" : "s")" : "\(n) of \(l.games.count) games"
        let when = relativeDay(l.scanned)
        return "\(shown) · scanned \(when.hasPrefix("Today") || when.hasPrefix("Yesterday") ? when.lowercasedFirst : "on \(when)")"
    }

    func row(_ g: LibraryGame, app: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: g.kind == .nup ? "shippingbox" : g.kind == .dump ? "folder.badge.gearshape" : "gamecontroller")
                .font(.title3).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(g.name).font(.headline).lineLimit(1)
                    Text(g.console.rawValue).font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                    if app != nil { StatusDot(color: .green, text: "Built") .font(.caption) }
                }
                Text(([g.contents, g.titleID, g.bytes > 0 ? Disk.gb(g.bytes) : nil].compactMap { $0 }).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                if g.shared {
                    Label("Shares its folder with other games: Convert first moves its \(g.fileCount == 1 ? "file" : "\(g.fileCount) files") into a folder of its own", systemImage: "folder.badge.plus")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(g.notes, id: \.self) { n in
                    Label(n, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                Text(g.path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { reveal(g.shared ? "\(g.path)/\(g.files.first ?? "")" : g.path) } label: { Image(systemName: "folder") }.buttonStyle(.glass).help("Show in Finder")
            if let app {
                Button { NSWorkspace.shared.open(app.url) } label: { Image(systemName: "play.fill") }.buttonStyle(.glass).help("Open \(app.lastComponent)")
            }
            Button("Convert") { model.convertFromLibrary(g) }
                .buttonStyle(.glassProminent).disabled(model.run.running)
                .help(model.run.running ? "Not while a build runs" : "Make this the game on the Convert page")
                .frame(minWidth: 86)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture(count: 2) { if !model.run.running { model.convertFromLibrary(g) } }
        .contextMenu {
            Button("Convert") { model.convertFromLibrary(g) }.disabled(model.run.running)
            if g.shared { Button("Move into Its Own Folder") { model.moveToOwnFolder(g) } }
            Button("Show in Finder") { reveal(g.shared ? "\(g.path)/\(g.files.first ?? "")" : g.path) }
            if let t = g.titleID { Button("Copy Title ID") { copyToClipboard(t) } }
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
