// Saves (Converter 0.16.0): every built game's save on one page, after RecompLauncher's Saves screen (an idea only: that project is
// GPL-3.0, this is written fresh). The top says how much is kept and where, with the after-session switch and the snapshot folder;
// each game's row says when it last saved, on which Mac its newest snapshot was made, and how many snapshots it has. Opening a row
// shows the game's Save snapshots card (BuildsPage.swift), with Restore, Undo Restore, import, export and Git backup.
import AppKit
import SwiftUI

/// One game's line on the Saves page, read off the main thread.
struct SaveRow: Identifiable {
    var id: String { titleID }
    let build: BuildRecord
    let name: String
    let titleID: String
    let loc: SaveLocation
    let hasSave: Bool
    /// the newest change to any file of the save
    let lastSaved: Date?
    let snapshots: Int
    let bytes: Int64
    let newest: SaveSnapshot?

    static func read(_ b: BuildRecord, titleID: String) -> SaveRow {
        let loc = SaveSnapshots.location(app: b.app, titleID: titleID)
        let snaps = SaveSnapshots.list(loc)
        return SaveRow(build: b, name: b.app.url.deletingPathExtension().lastPathComponent, titleID: titleID, loc: loc,
                       hasSave: SaveSnapshots.hasSave(loc), lastSaved: newestChange(loc), snapshots: snaps.count,
                       bytes: snaps.reduce(0) { $0 + $1.bytes }, newest: snaps.first)
    }

    /// The newest modification time under the save and the device save.
    static func newestChange(_ loc: SaveLocation) -> Date? {
        let fm = FileManager.default
        var newest: Date?
        for (_, root) in loc.parts {
            guard let walk = fm.enumerator(at: root.url, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for case let u as URL in walk {
                guard let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), v.isRegularFile == true,
                      let d = v.contentModificationDate else { continue }
                if newest == nil || d > newest! { newest = d }
            }
        }
        return newest
    }
}

struct SavesPage: View {
    @Bindable var model: AppModel
    @State private var rows: [SaveRow]?
    @State private var open: String?
    @State private var openName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saves").font(.largeTitle.weight(.bold))
                    Text("Every game's save, with checked snapshots to go back to. Open a game to restore, undo a restore, import or export.")
                        .foregroundStyle(.secondary)
                }
                summary
                games
            }
            .pagePadding()
        }
        .task(id: model.revision) { await load() }
        .onAppear {
            // NXC_SAVES_OPEN=<part of a game's name>: the screenshot hook opens that game's snapshots
            if open == nil, let n = ProcessInfo.processInfo.environment["NXC_SAVES_OPEN"] { openName = n }
        }
    }

    private func load() async {
        let builds = Engine.builds()
        let r = await Task.detached { () -> [SaveRow] in
            var seen = Set<String>()
            return builds.compactMap { b -> SaveRow? in
                guard let t = VerifiedGames.titleID(ofApp: b.app), seen.insert(t).inserted else { return nil }
                return SaveRow.read(b, titleID: t)
            }
        }.value
        // games that saved most recently first, then the rest by name
        let sorted = r.sorted { a, b in
            switch (a.lastSaved, b.lastSaved) {
            case let (x?, y?): x > y
            case (_?, nil): true
            case (nil, _?): false
            default: a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        rows = sorted
        if let n = openName, let hit = sorted.first(where: { $0.name.localizedCaseInsensitiveContains(n) }) { open = hit.id; openName = nil }
    }

    // MARK: the top

    private var summary: some View {
        let list = rows ?? []
        let withSave = list.filter(\.hasSave)
        let count = list.reduce(0) { $0 + $1.snapshots }
        let bytes = list.reduce(Int64(0)) { $0 + $1.bytes }
        let away = model.settings.saveSnapshotsFolder != nil && SaveSnapshots.usableRoot == nil
        return HStack(alignment: .top, spacing: 16) {
            Card(fillHeight: true) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title2).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snapshots").font(.headline)
                        Text("\(withSave.count) game\(withSave.count == 1 ? "" : "s") with a save · \(count) snapshot\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.title3.weight(.semibold)).monospacedDigit()
                }
                Toggle(isOn: $model.settings.snapshotAfterPlay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snapshot after every session")
                        Text("When a game quits with a changed save. The newest \(SaveSnapshots.keepAutomatic) of these stay for each game.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).frame(maxWidth: .infinity, alignment: .leading)
            }
            Card(fillHeight: true) {
                HStack(spacing: 12) {
                    Image(systemName: away ? "externaldrive.badge.exclamationmark" : "folder").font(.title2).frame(width: 36)
                        .foregroundStyle(away ? Color.orange : Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where they are kept").font(.headline)
                        Text(model.settings.saveSnapshotsFolder?.tildePath ?? "Beside each game's save")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                Text(away ? "That folder is not there now (a drive or share away?), so new snapshots go beside each save until it is back."
                          : "Choose a folder on another drive, a NAS or iCloud Drive, so a snapshot survives the drive its save is on.")
                    .font(.caption).foregroundStyle(away ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Choose Folder…") { model.chooseSnapshotFolder() }.buttonStyle(.stage)
                    if let f = model.settings.saveSnapshotsFolder {
                        Button { reveal(f) } label: { Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly) }.buttonStyle(.stage)
                        Button("Keep Beside Each Save") { model.setSnapshotFolder(nil) }.buttonStyle(.stage)
                    }
                    Spacer()
                    if let repo = model.settings.saveBackupRepo {
                        Label("Git backup on", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary).help("Each save is also committed to \(repo.tildePath) when its game quits")
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: the games

    @ViewBuilder private var games: some View {
        if let rows {
            let saved = rows.filter { $0.hasSave || $0.snapshots > 0 }
            let none = rows.count - saved.count
            if rows.isEmpty {
                Text("No games built yet. Build one on the Convert page; its save shows here once it has played.").foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(saved) { r in
                    VStack(alignment: .leading, spacing: 0) {
                        row(r)
                        if open == r.id {
                            SaveSnapshotsCard(model: model, build: r.build).padding(.horizontal, 10).padding(.bottom, 10)
                        }
                    }
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
                }
            }
            if none > 0 {
                Text(none == 1 ? "1 more game has no save yet. Play it once and it shows here."
                               : "\(none) more games have no save yet. Play them once and they show here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func row(_ r: SaveRow) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { open = open == r.id ? nil : r.id }
        } label: {
            HStack(spacing: 14) {
                AppIcon(path: r.build.app, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.name).font(.headline).lineLimit(1)
                    Text(detail(r)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.isPlaying(app: r.build.app) {
                    chip("Playing", Color.green)
                } else if !r.hasSave {
                    chip("Only snapshots", Color.orange)
                } else if let n = r.newest, let s = r.lastSaved, s > n.created.addingTimeInterval(5) {
                    chip("Changed since the last snapshot", Color.orange)
                } else if r.newest != nil {
                    chip("Snapshot up to date", Color.green)
                } else {
                    chip("No snapshot yet", Color.secondary)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(r.snapshots) snapshot\(r.snapshots == 1 ? "" : "s")").font(.callout.weight(.semibold))
                    if r.snapshots > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .frame(minWidth: 96, alignment: .trailing)
                Image(systemName: "chevron.down").rotationEffect(.degrees(open == r.id ? 180 : 0)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(r.name), \(detail(r)), \(r.snapshots) snapshots")
    }

    private func detail(_ r: SaveRow) -> String {
        var parts: [String] = []
        parts.append(r.lastSaved.map { "Last saved \(lowerFirst(relativeDay($0)))" } ?? "No save on this Mac")
        if let n = r.newest { parts.append("newest snapshot on \(n.device ?? "this Mac")") }
        return parts.joined(separator: " · ")
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(color).background(color.opacity(0.14), in: .capsule)
            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

/// "Today at 21:40" → "today at 21:40" inside a sentence; a date ("Nov 16, 2026 at …") stays as it is.
func lowerFirst(_ s: String) -> String {
    guard s.hasPrefix("Today") || s.hasPrefix("Yesterday") else { return s }
    return s.prefix(1).lowercased() + s.dropFirst()
}
