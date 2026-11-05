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
                items.append(StorageItem(kind: .cache, game: game, path: "\(d)/\(b)", bytes: Disk.size("\(d)/\(b)")))
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
            let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            guard let v = try? p.url.resourceValues(forKeys: keys), let name = v.volumeLocalizedName else { continue }
            vols[name] = VolumeInfo(name: name, free: v.volumeAvailableCapacityForImportantUsage ?? 0, total: Int64(v.volumeTotalCapacity ?? 0))
        }
        return (items.sorted { $0.bytes > $1.bytes }, vols.values.sorted { $0.name < $1.name })
    }
}

struct StoragePage: View {
    @Bindable var model: AppModel
    @State private var items: [StorageItem] = []
    @State private var volumes: [VolumeInfo] = []
    @State private var scanning = false
    @State private var deleting: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Storage", subtitle: "What NXForge keeps on disk, and what can go.") {
                    Button { scan() } label: { Label("Measure again", systemImage: "arrow.clockwise").font(.title3) }
                        .buttonStyle(.glass).controlSize(.extraLarge).disabled(scanning)
                }
                HStack(spacing: 16) {
                    ForEach(volumes) { v in volumeCard(v) }
                    reclaimCard
                }
                .fixedSize(horizontal: false, vertical: true)
                if scanning && items.isEmpty {
                    Card { HStack { ProgressView().controlSize(.small); Text("Measuring the build caches and apps…").foregroundStyle(.secondary) } }
                } else {
                    InsetTable {
                        ForEach(items) { i in
                            if i.id != items.first?.id { Divider() }
                            row(i)
                        }
                    }
                }
                Text("Deleting here is permanent: files moved to the Trash keep using space until it is emptied.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .task(id: model.revision) { scan() }
    }

    var reclaimable: Int64 { items.filter(\.deletable).reduce(0) { $0 + $1.bytes } }

    func volumeCard(_ v: VolumeInfo) -> some View {
        Card(padding: 14, fillHeight: true) {
            Label(v.name, systemImage: "internaldrive").font(.headline)
            ProgressView(value: Double(max(v.total - v.free, 0)), total: Double(max(v.total, 1)))
                .tint(v.free < Disk.warnBelow ? .orange : .accentColor)
            Text("\(Disk.gb(v.free)) free of \(Disk.gb(v.total))").foregroundStyle(v.free < Disk.warnBelow ? .orange : .secondary)
        }
    }

    var reclaimCard: some View {
        Card(padding: 14, fillHeight: true) {
            Label("Can be deleted", systemImage: "trash").font(.headline)
            Text(scanning && items.isEmpty ? "…" : Disk.gb(reclaimable)).font(.title.weight(.semibold)).monospacedDigit()
            Text("Build caches, older app copies and the shader cache").foregroundStyle(.secondary).lineLimit(1)
        }
    }

    func row(_ i: StorageItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: i.symbol).font(.title3).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(i.title).font(.headline)
                    Text("· \(i.game)").foregroundStyle(.secondary).lineLimit(1)
                }
                Text(i.note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Text(i.path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Disk.gb(i.bytes)).font(.title3.weight(.semibold)).monospacedDigit().frame(width: 90, alignment: .trailing)
            Button { reveal(i.path) } label: { Image(systemName: "folder") }.buttonStyle(.glass).help("Show in Finder")
            if i.deletable {
                if deleting == i.path {
                    ProgressView().controlSize(.small).frame(width: 70)
                } else {
                    Button("Delete…") { delete(i) }.buttonStyle(.glass)
                        .disabled(deleting != nil || (model.run.running && i.kind != .backups))
                        .help(model.run.running && i.kind != .backups ? "Not while a build runs: it uses this" : "Delete permanently")
                        .frame(width: 70)
                }
            } else {
                Color.clear.frame(width: 70, height: 1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        let game = model.settings.gameDir
        Task.detached {
            let r = Storage.scan(currentGame: game)
            await MainActor.run { items = r.items; volumes = r.volumes; scanning = false }
        }
    }

    func delete(_ i: StorageItem) {
        guard model.confirm("Delete \(i.title.lowercased()) (\(Disk.gb(i.bytes)))?", "\(i.path.tildePath) is deleted permanently. \(i.note)", action: "Delete") else { return }
        deleting = i.path
        let path = i.path
        Task.detached {
            try? FileManager.default.removeItem(atPath: path)
            await MainActor.run { deleting = nil; model.revision += 1; model.measure() }
        }
    }
}
