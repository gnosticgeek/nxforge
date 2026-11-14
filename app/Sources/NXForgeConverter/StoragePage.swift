// Storage: everything NXForge keeps on disk, for every game the converter knows (the folders in builds.json and the one
// chosen now), with sizes and a way to free the space: each game's build cache, the app copies rebuilds kept, the apps,
// and the shared Metal cache. Deleting here frees the space (the Trash would keep it taken until it is emptied), after
// a short while in which Undo puts it back (PendingDeletes, in UIExtras).
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
    enum Kind: Hashable { case startup, internalDrive, external, network }
    var id: String { path }
    let name: String
    let free: Int64
    let total: Int64
    var path = "/"
    var kind: Kind = .startup

    var symbol: String {
        switch kind { case .startup, .internalDrive: "internaldrive"; case .external: "externaldrive"; case .network: "server.rack" }
    }
    var kindText: String {
        switch kind { case .startup: "Startup disk"; case .internalDrive: "Internal"; case .external: "External drive"; case .network: "Network share" }
    }
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
            let home = Disk.buildHome(d)
            for b in ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter({ $0.hasSuffix("_build") }) {
                items.append(StorageItem(kind: .cache, game: game, path: "\(home)/\(b)", bytes: Disk.size("\(home)/\(b)"), busy: recentlyWritten("\(home)/\(b)")))
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
        return (items.sorted { $0.bytes > $1.bytes }, volumes(also: [NSHomeDirectory()] + dirs))
    }

    /// The startup disk, every drive and share plugged in now (USB, Thunderbolt, SD cards, SMB), and the drives the games are
    /// on: the startup disk first, then by name.
    static func volumes(also paths: [String] = []) -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeIsInternalKey, .volumeIsLocalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeURLKey]
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var vols: [String: VolumeInfo] = [:]
        for u in mounted + paths.map(\.url) {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), let name = v.volumeLocalizedName,
                  let root = v.volume?.path ?? (u.path == "/" ? "/" : nil) else { continue }
            if v.volumeIsBrowsable == false { continue }   // system volumes (Preboot, VM, Recovery)
            let total = Int64(v.volumeTotalCapacity ?? 0)
            guard total > 0, vols[root] == nil else { continue }
            let kind: VolumeInfo.Kind = v.volumeIsRootFileSystem == true || root == "/" ? .startup
                : v.volumeIsLocal == false ? .network : v.volumeIsInternal == true ? .internalDrive : .external
            vols[root] = VolumeInfo(name: name, free: Disk.free(root) ?? 0, total: total, path: root, kind: kind)
        }
        // the Data volume and "/" are one disk to the user: keep the startup one
        if let startup = vols.values.first(where: { $0.kind == .startup }) {
            vols = vols.filter { $0.value.kind != .internalDrive || $0.value.name != startup.name }
        }
        return vols.values.sorted { ($0.kind == .startup ? 0 : 1, $0.name.localizedLowercase) < ($1.kind == .startup ? 0 : 1, $1.name.localizedLowercase) }
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
    @State private var sortOrder = [KeyPathComparator(\StorageItem.bytes, order: .reverse)]
    @State private var selection: Set<String> = []

    var shown: [StorageItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let v = items.filter { filter.matches($0.kind) && (q.isEmpty || $0.game.lowercased().contains(q) || $0.title.lowercased().contains(q) || $0.path.lowercased().contains(q)) }
        return v.sorted(using: sortOrder)
    }

    var body: some View {
        let list = shown
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeroHeader(symbol: "internaldrive", title: "Storage", subtitle: "What NXForge keeps on disk, and what can go.")
                // every drive plugged in, two or three to a row, the space to reclaim last
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(volumes) { v in volumeCard(v) }
                    reclaimCard
                }
                filterBar
                if scanning && items.isEmpty {
                    Card { HStack { ProgressView().controlSize(.small); Text("Measuring the build caches and apps…").foregroundStyle(.secondary) } }
                } else {
                    table(list)
                }
                Label("Deleting here frees the space without the Trash. For \(Int(PendingDeletes.undoSeconds)) seconds, Undo (⌘Z) puts it back.", systemImage: "info.circle")
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
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in scan() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in scan() }
    }

    var deletableItems: [StorageItem] { items.filter { $0.deletable && canDelete($0) } }
    var reclaimable: Int64 { items.filter(\.deletable).reduce(0) { $0 + $1.bytes } }

    func canDelete(_ i: StorageItem) -> Bool { i.deletable && !i.busy && !(model.run.running && i.kind != .backups) && !deleting.contains(i.path) }

    func volumeCard(_ v: VolumeInfo) -> some View {
        let used = max(v.total - v.free, 0)
        let low = v.free < Disk.warnBelow
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(v.name, systemImage: v.symbol).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(Disk.gb(v.total)) total").foregroundStyle(.secondary)
            }
            if v.kind != .startup {
                Text(v.kindText).font(.caption).foregroundStyle(.secondary).padding(.top, -10)
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
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.open(v.path.url) } }
        .help(v.path)
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 7) { Circle().fill(c).frame(width: 9, height: 9); Text(t) }
    }

    var reclaimCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Reclaimable space").font(.title3.weight(.semibold)) } icon: { Image(systemName: "leaf.fill").foregroundStyle(.green) }
                Text(scanning && items.isEmpty ? "…" : Disk.gb(reclaimable)).font(.largeTitle.weight(.bold)).monospacedDigit()
                Text("Build caches, older app copies and the shader cache.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { cleanUp() } label: { Label("Clean Up…", systemImage: "wand.and.sparkles") }
                .buttonStyle(.glassProminent).controlSize(.extraLarge)
                .disabled(deletableItems.isEmpty || !deleting.isEmpty)
                .help(deletableItems.isEmpty ? "Nothing can be deleted now" : "Delete every build cache, older app copy and the shader cache that no build is using")
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
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
                if !search.isEmpty { Button { search = "" } label: { Label("Clear Search", systemImage: "xmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).frame(width: 190, height: 32)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
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

    /// A Mac table (idea 2): click a heading to sort by it (again to reverse), drag the edges to resize, click, ⌘-click or
    /// ⇧-click to pick rows, ⌘A for all, ⌫ to delete them, right-click for the rest.
    func table(_ list: [StorageItem]) -> some View {
        let picked = items.filter { selection.contains($0.id) }
        let deletable = picked.filter(canDelete)
        return VStack(spacing: 0) {
            if list.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Nothing Here" : "No Matches", systemImage: "internaldrive",
                                       description: Text(search.isEmpty ? "Nothing of this type is on disk." : "Nothing matches “\(search)”."))
                    .padding(.vertical, 20)
            } else {
                Table(list, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Item", value: \.game) { i in itemCell(i) }
                        .width(min: 260, ideal: 460)
                    TableColumn("Size", value: \.bytes) { i in
                        Group {
                            if deleting.contains(i.path) { ProgressView().controlSize(.small) }
                            else { Text(Disk.gb(i.bytes)).font(.headline).monospacedDigit() }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 70, ideal: 90, max: 130)
                    TableColumn("Type", value: \.kind.badge) { i in
                        Text(i.kind.badge).font(.caption.weight(.semibold)).foregroundStyle(i.kind.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(i.kind.color.opacity(0.2), in: .capsule)
                    }
                    .width(min: 80, ideal: 100, max: 140)
                    TableColumn("") { i in
                        Button { reveal(i.path) } label: { Label("Show \(i.title) in Finder", systemImage: "folder").labelStyle(.iconOnly) }
                            .buttonStyle(.borderless).help("Show in Finder")
                    }
                    .width(32)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let rows = items.filter { ids.contains($0.id) }
                    if rows.count == 1, let i = rows.first {
                        Button("Show in Finder") { reveal(i.path) }
                        Button("Copy Path") { copyToClipboard(i.path) }
                    } else if !rows.isEmpty {
                        Button("Copy Paths") { copyToClipboard(rows.map(\.path).joined(separator: "\n")) }
                    }
                    let can = rows.filter(canDelete)
                    if !can.isEmpty {
                        Divider()
                        Button("Delete \(Disk.gb(can.reduce(0) { $0 + $1.bytes }))…") { deleteMany(can) }
                    }
                } primaryAction: { ids in
                    if let i = items.first(where: { ids.contains($0.id) }) { reveal(i.path) }
                }
                .onDeleteCommand { deleteMany(deletable) }
                .scrollContentBackground(.hidden)
                .alternatingRowBackgrounds(.disabled)
                .frame(height: min(max(CGFloat(list.count) * 62 + 30, 200), 620))
            }
            Divider()
            HStack(spacing: 14) {
                Text("\(picked.count) item\(picked.count == 1 ? "" : "s") selected")
                Divider().frame(height: 18)
                Text("Total size: ").foregroundStyle(.secondary) + Text(Disk.gb(picked.reduce(0) { $0 + $1.bytes })).fontWeight(.semibold)
                if picked.count > deletable.count {
                    Text("· \(picked.count - deletable.count) can't be deleted here").foregroundStyle(.secondary)
                        .help("Apps and game files are not deleted here, and nothing a build is using")
                }
                Spacer()
                Button { deleteMany(deletable) } label: {
                    Label(deletable.isEmpty ? "Delete Selected…" : "Delete \(Disk.gb(deletable.reduce(0) { $0 + $1.bytes }))…", systemImage: "trash")
                }
                .buttonStyle(.glass).controlSize(.large).disabled(deletable.isEmpty || !deleting.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
        .clipShape(.rect(cornerRadius: 16))
    }

    func itemCell(_ i: StorageItem) -> some View {
        let c = i.kind.color
        return HStack(spacing: 12) {
            Image(systemName: i.symbol).font(.title3.weight(.medium)).foregroundStyle(c)
                .frame(width: 38, height: 38)
                .background(c.opacity(0.18), in: .rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(c.opacity(0.35)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(i.title).font(.headline)
                    Text("· \(i.game)").lineLimit(1)
                    if i.busy { Text("In use").font(.caption).foregroundStyle(.orange).help("A build wrote to it in the last ten minutes") }
                }
                Text(i.note).font(.callout).foregroundStyle(.secondary).lineLimit(1).help(i.note)
                Text(i.path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        let game = model.settings.gameDir
        Task.detached {
            let r = Storage.scan(currentGame: game)
            await MainActor.run {
                items = r.items; volumes = r.volumes; scanning = false
                selection = selection.intersection(Set(r.items.map(\.id)))
            }
        }
    }

    /// Everything that can go now, after one question.
    func cleanUp() {
        let all = deletableItems
        guard !all.isEmpty else { return }
        let total = all.reduce(0) { $0 + $1.bytes }
        guard model.confirm("Clean up \(Disk.gb(total))?", "Deletes \(all.map { "\($0.title.lowercased()) · \($0.game)" }.joined(separator: ", ")). The next build of each game starts over (about 30 to 50 minutes), and shaders compile again. Apps and game files stay. Undo puts it all back for \(Int(PendingDeletes.undoSeconds)) seconds.", action: "Delete \(Disk.gb(total))") else { return }
        remove(all)
    }

    func deleteMany(_ list: [StorageItem]) {
        let ok = list.filter(canDelete)
        guard !ok.isEmpty else { return }
        let total = ok.reduce(0) { $0 + $1.bytes }
        let what = ok.count == 1 ? "\(ok[0].title.lowercased()) (\(Disk.gb(total)))" : "\(ok.count) items (\(Disk.gb(total)))"
        let undo = "Undo puts \(ok.count == 1 ? "it" : "them") back for \(Int(PendingDeletes.undoSeconds)) seconds; then the space is free."
        let detail = ok.count == 1 ? "\(ok[0].path.tildePath) is deleted. \(ok[0].note) \(undo)" : ok.map { $0.path.tildePath }.joined(separator: "\n") + "\n\n\(undo)"
        guard model.confirm("Delete \(what)?", detail, action: "Delete \(Disk.gb(total))") else { return }
        remove(ok)
    }

    /// Moves each one aside under a hidden name (instant), then the model offers Undo and deletes them once it is over.
    func remove(_ list: [StorageItem]) {
        let paths = list.map(\.path)
        deleting.formUnion(paths)
        selection.subtract(paths)
        let rows = list.map { (path: $0.path, bytes: $0.bytes, label: "\($0.title) · \($0.game)") }
        Task.detached {
            var held: [PendingDelete] = [], failed: [String] = []
            for r in rows {
                do { held.append(try PendingDeletes.hide(r.path, bytes: r.bytes, label: r.label)) } catch { failed.append(r.label) }
            }
            let h = held, f = failed
            await MainActor.run { deleting.subtract(paths); model.holdDeletes(h, failed: f) }
        }
    }
}
