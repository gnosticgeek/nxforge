// Storage: everything NXForge keeps on disk, for every game the converter knows (the folders in builds.json and the one
// chosen now), with sizes and a way to free the space: each game's build cache, the app copies rebuilds kept, the apps,
// and the shared Metal cache. Deleting here is permanent (the Trash would keep the space taken until it is emptied).
import AppKit
import SwiftUI

struct StorageItem: Identifiable, Hashable {
    enum Kind: Hashable { case cache, backups, app, metal, gameFiles }
    var id: String { path }
    let kind: Kind
    let game: String
    let path: String
    let bytes: Int64
    /// written to in the last ten minutes: a build may be using it (one started from Terminal is invisible to the converter)
    var busy = false

    var title: String {
        switch kind {
        case .cache: "Build cache"
        case .backups: "Older app copies"
        case .app: "Mac app"
        case .metal: "Shared Metal shader cache"
        case .gameFiles: "Game files"
        }
    }

    var note: String {
        switch kind {
        case .cache: "The extracted game and compiled shaders. Deleting it makes the next build start over (about 30 to 50 minutes)."
        case .backups: "Apps a rebuild moved to app-backups. Restore one from Builds first if you still want it."
        case .app: "The game you play. Delete it from Builds (Move App to Trash)."
        case .metal: "Compiled shaders shared by every game. Deleting it makes the next shader stage compile everything again."
        case .gameFiles: "Your NSPs or other game files. The converter never deletes them."
        }
    }

    var symbol: String {
        switch kind {
        case .cache: "shippingbox"
        case .backups: "clock.arrow.circlepath"
        case .app: "macwindow"
        case .metal: "square.stack.3d.up"
        case .gameFiles: "doc.zipper"
        }
    }

    /// Only what the converter makes, and can make again, can be deleted here.
    var deletable: Bool { kind == .cache || kind == .backups || kind == .metal }
}

struct VolumeInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let free: Int64
    let total: Int64
}

enum Storage {
    /// Whether anything in a build folder, down to three levels, changed in the last ten minutes. The logs alone are not
    /// enough: a long stage (extracting a Switch 2 game's RomFS) writes its output for many minutes between log lines.
    static func recentlyWritten(_ build: String) -> Bool {
        let since = Date().addingTimeInterval(-600)
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: build), includingPropertiesForKeys: [.contentModificationDateKey]) else { return false }
        for case let u as URL in e {
            if e.level >= 3 { e.skipDescendants() }
            if let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > since { return true }
        }
        return false
    }

    /// Every item, measured (slow: run it off the main thread).
    static func scan(currentGame: String?) -> (items: [StorageItem], volumes: [VolumeInfo]) {
        let fm = FileManager.default
        var dirs: [String] = []
        // a Switch 2 game's record names its .nup: its build folder is beside it
        for d in ([currentGame].compactMap({ $0 }) + Engine.builds().map(\.gameDir)).map(Source.folder) where !dirs.contains(d) && fm.fileExists(atPath: d) { dirs.append(d) }
        var items: [StorageItem] = []
        var appDirs = Set<String>()
        for d in dirs {
            let game = GameInfo.read(d).name
            for b in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter({ $0.hasSuffix("_build") }) {
                items.append(StorageItem(kind: .cache, game: game, path: "\(d)/\(b)", bytes: Disk.size("\(d)/\(b)"), busy: recentlyWritten("\(d)/\(b)")))
            }
            let files = GameFiles.list(in: d.url)
            if !files.isEmpty { items.append(StorageItem(kind: .gameFiles, game: game, path: d, bytes: files.reduce(0) { $0 + Disk.size($1.path) })) }
            appDirs.insert(d)
        }
        for b in Engine.builds() where fm.fileExists(atPath: b.app) {
            let game = b.app.url.deletingPathExtension().lastPathComponent
            items.append(StorageItem(kind: .app, game: game, path: b.app, bytes: Disk.size(b.app)))
            appDirs.insert(b.app.url.deletingLastPathComponent().path)
        }
        for d in appDirs.sorted() {
            let bk = d + "/app-backups"
            if fm.fileExists(atPath: bk) { items.append(StorageItem(kind: .backups, game: d.lastComponent, path: bk, bytes: Disk.size(bk))) }
        }
        if fm.fileExists(atPath: Disk.cacheDir) { items.append(StorageItem(kind: .metal, game: "All games", path: Disk.cacheDir, bytes: Disk.size(Disk.cacheDir))) }
        // the volumes these live on
        var vols: [String: VolumeInfo] = [:]
        for p in [NSHomeDirectory()] + dirs {
            let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey]
            guard let v = try? p.url.resourceValues(forKeys: keys), let name = v.volumeLocalizedName else { continue }
            vols[name] = VolumeInfo(name: name, free: Disk.free(p) ?? 0, total: Int64(v.volumeTotalCapacity ?? 0))
        }
        return (items.sorted { $0.bytes > $1.bytes }, vols.values.sorted { $0.name < $1.name })
    }
}

/// The page's type filter chips, in the table's order of kinds.
enum StorageFilter: String, CaseIterable {
    case all = "All", apps = "Mac Apps", caches = "Caches", copies = "Copies", gameFiles = "Game Files", shaders = "Shaders"

    var symbol: String {
        switch self {
        case .all: "square.3.layers.3d"
        case .apps: "laptopcomputer"
        case .caches: "shippingbox"
        case .copies: "clock.arrow.circlepath"
        case .gameFiles: "gamecontroller"
        case .shaders: "square.stack.3d.up"
        }
    }

    func matches(_ k: StorageItem.Kind) -> Bool {
        switch self {
        case .all: true
        case .apps: k == .app
        case .caches: k == .cache
        case .copies: k == .backups
        case .gameFiles: k == .gameFiles
        case .shaders: k == .metal
        }
    }
}

enum StorageSort: String, CaseIterable { case size = "Size", name = "Name", type = "Type" }

extension StorageItem.Kind {
    var badge: String {
        switch self { case .app: "Mac App"; case .backups: "Copy"; case .cache: "Cache"; case .gameFiles: "Game Files"; case .metal: "Shaders" }
    }
    var color: Color {
        switch self { case .app: .indigo; case .backups: .orange; case .cache: .green; case .gameFiles: .blue; case .metal: .pink }
    }
}

struct StoragePage: View {
    @Bindable var model: AppModel
    @State private var items: [StorageItem] = []
    @State private var volumes: [VolumeInfo] = []
    @State private var scanning = false
    @State private var deleting: Set<String> = []
    @State private var filter: StorageFilter = .all
    @State private var search = ""
    @State private var sort: StorageSort = .size
    @State private var selection: Set<String> = []

    var shown: [StorageItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let v = items.filter { filter.matches($0.kind) && (q.isEmpty || $0.game.lowercased().contains(q) || $0.title.lowercased().contains(q) || $0.path.lowercased().contains(q)) }
        switch sort {
        case .size: return v.sorted { $0.bytes > $1.bytes }
        case .name: return v.sorted { $0.game.localizedStandardCompare($1.game) == .orderedAscending }
        case .type: return v.sorted { ($0.kind.badge, -$0.bytes) < ($1.kind.badge, -$1.bytes) }
        }
    }

    var body: some View {
        let list = shown
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeroHeader(symbol: "internaldrive", title: "Storage", subtitle: "What NXForge keeps on disk, and what can go.")
                HStack(alignment: .top, spacing: 16) {
                    ForEach(volumes) { v in volumeCard(v) }
                    reclaimCard
                }
                .fixedSize(horizontal: false, vertical: true)
                filterBar
                if scanning && items.isEmpty {
                    Card { HStack { ProgressView().controlSize(.small); Text("Measuring the build caches and apps…").foregroundStyle(.secondary) } }
                } else {
                    table(list)
                }
                Label("Deleting here is permanent: files moved to the Trash keep using space until it is emptied.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { scan() } label: { Label("Measure Again", systemImage: "arrow.clockwise") }
                    .help("Measure the caches and apps again").disabled(scanning)
            }
        }
        .task(id: model.revision) { scan() }
    }

    var deletableItems: [StorageItem] { items.filter { $0.deletable && canDelete($0) } }
    var reclaimable: Int64 { items.filter(\.deletable).reduce(0) { $0 + $1.bytes } }

    func canDelete(_ i: StorageItem) -> Bool { i.deletable && !i.busy && !(model.run.running && i.kind != .backups) && !deleting.contains(i.path) }

    func volumeCard(_ v: VolumeInfo) -> some View {
        let used = max(v.total - v.free, 0)
        let low = v.free < Disk.warnBelow
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(v.name, systemImage: "internaldrive").font(.title3.weight(.semibold))
                Spacer()
                Text("\(Disk.gb(v.total)) total").foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tile)
                    Capsule().fill(LinearGradient(colors: low ? [.orange, .red] : [.cyan, .accentColor], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(Double(used) / Double(max(v.total, 1))))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("\(Disk.gb(used)) used of \(Disk.gb(v.total))")
            HStack(spacing: 22) {
                legend(low ? .orange : .accentColor, "\(Disk.gb(used)) used")
                legend(.secondary, "\(Disk.gb(v.free)) free (\(Int((Double(v.free) / Double(max(v.total, 1)) * 100).rounded()))%)")
            }
            .foregroundStyle(low ? .orange : .primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 7) { Circle().fill(c).frame(width: 9, height: 9); Text(t) }
    }

    var reclaimCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Reclaimable space").font(.title3.weight(.semibold)) } icon: { Image(systemName: "leaf.fill").foregroundStyle(.green) }
                Text(scanning && items.isEmpty ? "…" : Disk.gb(reclaimable)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                Text("Build caches, older app copies and the shader cache.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { cleanUp() } label: { Label("Clean Up…", systemImage: "wand.and.sparkles") }
                .buttonStyle(.glassProminent).controlSize(.extraLarge)
                .disabled(deletableItems.isEmpty || !deleting.isEmpty)
                .help(deletableItems.isEmpty ? "Nothing can be deleted now" : "Delete every build cache, older app copy and the shader cache that no build is using")
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }

    /// Chips, then search and sort, on one row when they fit; on a narrow window the search and sort move to a row of their own
    /// rather than squeezing the chips into truncated labels.
    var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { chips; Spacer(minLength: 8); searchAndSort }
            VStack(alignment: .leading, spacing: 10) { chips; HStack { Spacer(); searchAndSort } }
            VStack(alignment: .leading, spacing: 10) { ScrollView(.horizontal, showsIndicators: false) { chips }; HStack { Spacer(); searchAndSort } }
        }
    }

    var chips: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(StorageFilter.allCases, id: \.self) { f in chip(f).fixedSize() }
            }
        }
        .fixedSize()
    }

    var searchAndSort: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search storage…", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).frame(width: 190, height: 32)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            Menu {
                Picker("Sort by", selection: $sort) { ForEach(StorageSort.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.inline)
            } label: { Image(systemName: "slider.horizontal.3") }
            .menuStyle(.button).buttonStyle(.glass).fixedSize()
            .help("Sort the list")
        }
        .fixedSize()
    }

    func chip(_ f: StorageFilter) -> some View {
        let n = items.filter { f.matches($0.kind) }.count
        let on = filter == f
        return Button { filter = f } label: {
            Label("\(f.rawValue) (\(n))", systemImage: f.symbol)
        }
        .modifier(GlassButton(prominent: on))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func table(_ list: [StorageItem]) -> some View {
        let selectable = list.filter(canDelete)
        let picked = items.filter { selection.contains($0.id) }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { !selectable.isEmpty && selectable.allSatisfy { selection.contains($0.id) } },
                                         set: { on in if on { selection.formUnion(selectable.map(\.id)) } else { selection.subtract(list.map(\.id)) } }))
                    .toggleStyle(.checkbox).labelsHidden().disabled(selectable.isEmpty)
                    .help("Select everything here that can be deleted")
                Text("Item").padding(.leading, 50)
                Spacer()
                Button { sort = .size } label: { HStack(spacing: 3) { Text("Size"); if sort == .size { Image(systemName: "arrow.down") } } }
                    .buttonStyle(.plain).frame(width: 90, alignment: .trailing)
                Button { sort = .type } label: { HStack(spacing: 3) { Text("Type"); if sort == .type { Image(systemName: "arrow.down") } } }
                    .buttonStyle(.plain).frame(width: 100, alignment: .leading)
                Color.clear.frame(width: 96, height: 1)
            }
            .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if list.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Nothing Here" : "No Matches", systemImage: "internaldrive",
                                       description: Text(search.isEmpty ? "Nothing of this type is on disk." : "Nothing matches “\(search)”."))
                    .padding(.vertical, 20)
            }
            ForEach(list) { i in
                row(i)
                Divider().opacity(i.id == list.last?.id ? 0 : 1)
            }
            Divider()
            HStack(spacing: 14) {
                Text("\(picked.count) item\(picked.count == 1 ? "" : "s") selected")
                Divider().frame(height: 18)
                Text("Total size: ").foregroundStyle(.secondary) + Text(Disk.gb(picked.reduce(0) { $0 + $1.bytes })).fontWeight(.semibold)
                Spacer()
                Button { deleteMany(picked) } label: { Label("Delete Selected…", systemImage: "trash") }
                    .buttonStyle(.glass).controlSize(.large).disabled(picked.isEmpty || !deleting.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
        .clipShape(.rect(cornerRadius: 16))
    }

    func row(_ i: StorageItem) -> some View {
        let c = i.kind.color
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { selection.contains(i.id) }, set: { on in if on { selection.insert(i.id) } else { selection.remove(i.id) } }))
                .toggleStyle(.checkbox).labelsHidden().disabled(!canDelete(i))
                .help(!i.deletable ? "The converter does not delete this here" : i.busy ? "In use: a build wrote to it in the last ten minutes" : model.run.running && i.kind != .backups ? "Not while a build runs: it uses this" : "Select to delete")
            Image(systemName: i.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(c)
                .frame(width: 38, height: 38)
                .background(c.opacity(0.18), in: .rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(c.opacity(0.35)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(i.title).font(.headline)
                    Text("· \(i.game)").lineLimit(1)
                }
                Text(i.note).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Text(i.path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if deleting.contains(i.path) {
                ProgressView().controlSize(.small).frame(width: 90, alignment: .trailing)
            } else {
                Text(Disk.gb(i.bytes)).font(.headline).monospacedDigit().frame(width: 90, alignment: .trailing)
            }
            Text(i.kind.badge).font(.caption.weight(.semibold)).foregroundStyle(c)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(c.opacity(0.2), in: .capsule)
                .frame(width: 100, alignment: .leading)
            HStack(spacing: 6) {
                Button { reveal(i.path) } label: { Image(systemName: "folder") }.buttonStyle(.glass).help("Show in Finder")
                Menu {
                    Button("Show in Finder") { reveal(i.path) }
                    Button("Copy Path") { copyToClipboard(i.path) }
                    if i.deletable {
                        Divider()
                        Button("Delete…", role: .destructive) { deleteMany([i]) }.disabled(!canDelete(i))
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.glass).fixedSize()
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(selection.contains(i.id) ? Color.accentColor.opacity(0.08) : .clear)
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        let game = model.settings.gameDir
        Task.detached {
            let r = Storage.scan(currentGame: game)
            await MainActor.run {
                items = r.items; volumes = r.volumes; scanning = false
                selection = selection.intersection(Set(r.items.filter { $0.deletable }.map(\.id)))
            }
        }
    }

    /// Everything that can go now, after one question.
    func cleanUp() {
        let all = deletableItems
        guard !all.isEmpty else { return }
        let total = all.reduce(0) { $0 + $1.bytes }
        guard model.confirm("Clean up \(Disk.gb(total))?", "Deletes permanently: \(all.map { "\($0.title.lowercased()) · \($0.game)" }.joined(separator: ", ")). The next build of each game starts over (about 30 to 50 minutes), and shaders compile again. Apps and game files stay.", action: "Delete") else { return }
        remove(all)
    }

    func deleteMany(_ list: [StorageItem]) {
        let ok = list.filter(canDelete)
        guard !ok.isEmpty else { return }
        let total = ok.reduce(0) { $0 + $1.bytes }
        let what = ok.count == 1 ? "\(ok[0].title.lowercased()) (\(Disk.gb(total)))" : "\(ok.count) items (\(Disk.gb(total)))"
        let detail = ok.count == 1 ? "\(ok[0].path.tildePath) is deleted permanently. \(ok[0].note)" : ok.map { $0.path.tildePath }.joined(separator: "\n") + "\n\nThese are deleted permanently."
        guard model.confirm("Delete \(what)?", detail, action: "Delete") else { return }
        remove(ok)
    }

    func remove(_ list: [StorageItem]) {
        let paths = list.map(\.path)
        deleting.formUnion(paths)
        selection.subtract(paths)
        Task.detached {
            for p in paths { try? FileManager.default.removeItem(atPath: p) }
            await MainActor.run { deleting.subtract(paths); model.revision += 1; model.measure() }
        }
    }
}
