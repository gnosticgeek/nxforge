// Saves (Converter 0.18.0): every built game's save on one page, after RecompLauncher's Saves screen (an idea only: that project is
// GPL-3.0, this is written fresh). The top says how much is kept and where, with the after-session switch and the snapshot folder;
// each game's row says when it last saved, on which Mac its newest snapshot was made, and how many snapshots it has. Opening a row
// shows the game's Save snapshots card (BuildsPage.swift), with Restore, Undo Restore, import, export and Git backup.
// Converter 0.22.0: the page is in the top bar, beside Home and Discover, with Cloud saves for every game at the top (CloudSaves.swift),
// and each row says where the game's save syncs, what the cloud folder holds and how many quick-save slots it has.
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
    /// the folder the game's save syncs through (its cloudSaves.folder), nil: Cloud saves off
    var cloudFolder: String? = nil
    var cloud: CloudCopy? = nil
    /// quick-save slots in use (<save's folder>/save-slots/<n>)
    var slots = 0

    static func read(_ b: BuildRecord, titleID: String) -> SaveRow {
        let loc = SaveSnapshots.location(app: b.app, titleID: titleID)
        let snaps = SaveSnapshots.list(loc)
        let folder = CloudSaves.folder(app: b.app)
        let slots = ((try? FileManager.default.contentsOfDirectory(atPath: loc.folder + "/save-slots")) ?? [])
            .filter { FileManager.default.fileExists(atPath: "\(loc.folder)/save-slots/\($0)/manifest.json") }.count
        return SaveRow(build: b, name: b.app.url.deletingPathExtension().lastPathComponent, titleID: titleID, loc: loc,
                       hasSave: SaveSnapshots.hasSave(loc), lastSaved: newestChange(loc), snapshots: snaps.count,
                       bytes: snaps.reduce(0) { $0 + $1.bytes }, newest: snaps.first,
                       cloudFolder: folder, cloud: folder.map { CloudSaves.copy(folder: $0, titleID: titleID, save: loc.save) }, slots: slots)
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
                    Text("Every game's save in one place: where it syncs, the snapshots to go back to and its quick-save slots. Open a game to restore, undo a restore, import or export.")
                        .foregroundStyle(.secondary)
                }
                cloudCard
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

    // MARK: Cloud saves for every game

    private var cloudCard: some View {
        let s = model.settings
        let list = rows ?? []
        let folder = s.cloudSavesFolder ?? CloudSaves.suggestedFolder(chosen: nil, apps: list.map(\.build.app))
        let own = list.filter { $0.cloudFolder != nil && $0.cloudFolder != (s.cloudSavesAll ? s.cloudSavesFolder : nil) }
        let synced = list.filter { $0.cloud?.state == .present || $0.cloud?.state == .notDownloaded }.count
        let iCloud = CloudSaves.inICloud(folder)
        let driveOff = iCloud && !CloudSaves.iCloudDriveOn
        return Card {
            HStack(spacing: 14) {
                Image(systemName: s.cloudSavesAll ? "icloud.fill" : "icloud").font(.system(size: 26)).frame(width: 40)
                    .foregroundStyle(s.cloudSavesAll ? Color(red: 0.45, green: 0.72, blue: 1) : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud saves for every game").font(.title3.weight(.semibold))
                    Text(s.cloudSavesAll
                         ? "On. Each game brings its save in when it starts and sends it after every save. \(synced) of \(list.count) game\(list.count == 1 ? " has" : "s have") a copy there."
                         : "Off. Turn it on to keep every game's save in \(iCloud ? "iCloud" : "one folder"), so another Mac or the iPhone app can carry on.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Cloud saves for every game", isOn: Binding(get: { model.settings.cloudSavesAll }, set: { model.setCloudSavesForAll($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.large)
            }
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Image(systemName: iCloud ? "icloud" : "folder").foregroundStyle(.secondary).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(CloudSaves.shown(folder)).lineLimit(1).truncationMode(.middle).help(folder)
                }
                Spacer()
                Button(s.cloudSavesFolder == nil ? "Choose Location…" : "Change…") { model.chooseCloudSavesFolder() }.buttonStyle(.stage)
                if FileManager.default.fileExists(atPath: folder) {
                    Button { reveal(folder) } label: { Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly) }.buttonStyle(.stage).help("Show in Finder")
                }
            }
            if driveOff {
                Label("iCloud Drive is off on this Mac (System Settings › Apple Account › iCloud), so nothing syncs until it is on. Or choose another folder.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if !own.isEmpty {
                Text(s.cloudSavesAll
                     ? "\(names(own)) still \(own.count == 1 ? "uses its" : "use their") own folder; \(own.count == 1 ? "it moves" : "they move") here at \(own.count == 1 ? "its" : "their") next start."
                     : "\(names(own)) already \(own.count == 1 ? "syncs" : "sync") through \(own.count == 1 ? "its own folder" : "their own folders"), set in \(own.count == 1 ? "its" : "their") settings window. Turning this on moves \(own.count == 1 ? "it" : "them") here; turning it off later turns every game's off.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Each game keeps its own folder in there, named after its title ID. A save that is replaced is kept in the save's backups first, and when both sides changed the game asks which to keep.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func names(_ r: [SaveRow]) -> String {
        let n = r.map(\.name)
        return n.count <= 2 ? n.joined(separator: " and ") : "\(n.prefix(2).joined(separator: ", ")) and \(n.count - 2) more"
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
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snapshot after every session")
                        Text("When a game quits with a changed save. The newest \(SaveSnapshots.keepAutomatic) of these stay for each game.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Snapshot after every session", isOn: $model.settings.snapshotAfterPlay).toggleStyle(.switch).labelsHidden()
                }
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
                cloudChip(r)
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
        if let c = r.cloud, c.state == .present, let d = c.saved {
            parts.append("cloud copy \(lowerFirst(relativeDay(d)))\(c.device.map { " from \($0)" } ?? "")")
        } else if r.cloud?.state == .notDownloaded {
            parts.append("cloud copy not downloaded yet")
        } else if let n = r.newest { parts.append("newest snapshot on \(n.device ?? "this Mac")") }
        if r.slots > 0 { parts.append("\(r.slots) quick-save slot\(r.slots == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func cloudChip(_ r: SaveRow) -> some View {
        if let f = r.cloudFolder {
            let i = CloudSaves.inICloud(f)
            let waiting = r.cloud?.state == .some(.none) && r.hasSave
            Label(waiting ? "Sends at next start" : i ? "iCloud" : "Synced folder", systemImage: waiting ? "icloud.and.arrow.up" : i ? "icloud" : "folder")
                .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1)).background(Color(red: 0.45, green: 0.72, blue: 1).opacity(0.14), in: .capsule)
                .help("Syncs through \(CloudSaves.shown(f))")
        }
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
