// Health (Converter 0.14.0, from RetroReplay's Library Health): everything that is wrong or about to go wrong, on one page, each
// with what it means and the step that fixes it. Reading it changes nothing; a repair runs only when its button is pressed, and one
// that removes something asks first. Also the daily backups of NXForge's own data (DataBackup), with Back Up Now and Restore.
import AppKit
import SwiftUI

struct HealthFinding: Identifiable {
    enum Level: Int, Comparable {
        case problem, warning, note
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    let id: String
    let level: Level
    let symbol: String
    let title: String
    let detail: String
    /// the games or files it is about (the first few are listed)
    var items: [String] = []
    /// the repair's label, and what it does
    var repair: String? = nil
    var run: (@MainActor () -> Void)? = nil

    var color: Color {
        switch level {
        case .problem: Color(red: 1, green: 0.42, blue: 0.38)
        case .warning: Color(red: 0.98, green: 0.75, blue: 0.14)
        case .note: Color(red: 0.55, green: 0.75, blue: 1)
        }
    }
}

extension AppModel {
    private func logRevealer(_ t: String?) -> (@MainActor () -> Void)? {
        guard let t else { return nil }
        let path = "\(NSHomeDirectory())/Library/Logs/nxnative/\(t).log"
        return { reveal(path) }
    }

    /// What Health shows, most pressing first. Reads only.
    func healthFindings() -> [HealthFinding] {
        var out: [HealthFinding] = []
        let fm = FileManager.default
        let games = stageGames()

        // the games folder
        if let root = settings.gamesRoot, !fm.fileExists(atPath: root) {
            let vol = GameStatus.offlineVolume(root)
            out.append(HealthFinding(id: "root", level: .problem, symbol: "externaldrive.badge.xmark",
                                     title: vol.map { "\($0) is not connected" } ?? "The games folder has gone",
                                     detail: "The library reads your games from \(root.tildePath). Games already built still play; the others wait until it is back.",
                                     repair: "Check Again", run: { [weak self] in self?.revision += 1; if fm.fileExists(atPath: root) { self?.scanLibrary() } }))
        }

        // keys
        let keysGone = settings.defaultKeys.map { !fm.fileExists(atPath: $0) } ?? false
        let needKeys = games.filter { $0.app == nil && status($0) == .keysNeeded }
        if keysGone {
            out.append(HealthFinding(id: "keys-gone", level: .problem, symbol: "key.slash",
                                     title: "The saved keys file is not there", detail: "Settings points at \(settings.defaultKeys!.tildePath), which has moved or is on a drive that is away. Builds of Switch games need it.",
                                     repair: "Choose Keys…", run: { [weak self] in _ = self?.chooseKeysForBuild() }))
        } else if !needKeys.isEmpty {
            out.append(HealthFinding(id: "keys", level: .warning, symbol: "key.fill",
                                     title: "\(needKeys.count) game\(needKeys.count == 1 ? " needs" : "s need") keys to build", detail: "No prod.keys is saved in Settings or beside their files.",
                                     items: needKeys.map(\.name), repair: "Choose Keys…", run: { [weak self] in _ = self?.chooseKeysForBuild() }))
        }

        // games whose files are away or gone
        var offline: [String: [String]] = [:], missing: [String] = []
        for g in games where g.app == nil {
            switch status(g) {
            case .driveOffline(let d): offline[d, default: []].append(g.name)
            case .filesMissing: missing.append(g.name)
            default: break
            }
        }
        for (d, names) in offline.sorted(by: { $0.key < $1.key }) where settings.gamesRoot.map({ GameStatus.offlineVolume($0) != d }) ?? true {
            out.append(HealthFinding(id: "offline-\(d)", level: .warning, symbol: "externaldrive.badge.xmark",
                                     title: "\(names.count) game\(names.count == 1 ? " is" : "s are") on \(d), which is not connected", detail: "Connect it and they are back. Nothing is lost.",
                                     items: names, repair: "Check Again", run: { [weak self] in self?.revision += 1 }))
        }
        if !missing.isEmpty {
            out.append(HealthFinding(id: "missing", level: .warning, symbol: "questionmark.folder.fill",
                                     title: "\(missing.count) game\(missing.count == 1 ? "'s files have" : "s' files have") gone", detail: "The last scan found them in folders that are not there now. Scanning again forgets the ones that went and finds any that moved.",
                                     items: missing, repair: "Scan Library Again", run: { [weak self] in self?.scanLibrary() }))
        }

        // build records whose app has gone
        let gone = Engine.builds().filter { !fm.fileExists(atPath: $0.app) }
        if !gone.isEmpty {
            out.append(HealthFinding(id: "records", level: .note, symbol: "list.bullet.rectangle",
                                     title: "\(gone.count) build record\(gone.count == 1 ? " points" : "s point") at an app that has gone",
                                     detail: "The apps were deleted or moved outside NXForge. Forgetting the records tidies the Builds page; the game files and any app elsewhere are not touched.",
                                     items: gone.map { $0.app.url.deletingPathExtension().lastPathComponent },
                                     repair: "Forget Them…", run: { [weak self] in
                                         guard let self, self.confirm("Forget \(gone.count) build record\(gone.count == 1 ? "" : "s")?", "Only the converter's notes of these builds go. No file is deleted.", action: "Forget", destructive: true) else { return }
                                         for b in gone { Engine.forget(b.app) }
                                         self.revision += 1
                                     }))
        }

        // what the built games need a look at
        let crashed = games.filter { attention[$0.id]?.contains { $0.kind == .crashed } == true }
        if !crashed.isEmpty {
            let one = crashed.count == 1 ? crashed[0] : nil
            out.append(HealthFinding(id: "crashed", level: .problem, symbol: "exclamationmark.triangle.fill",
                                     title: "\(crashed.count) game\(crashed.count == 1 ? "'s" : "s'") last run crashed", detail: "The game stopped on a signal. Its log in ~/Library/Logs/nxnative says where; the game's page has its details.",
                                     items: crashed.map(\.name), repair: one?.titleID != nil ? "Show Log" : nil,
                                     run: logRevealer(one?.titleID)))
        }
        let unsaved = games.filter { attention[$0.id]?.contains { $0.kind == .unsaved } == true }
        if !unsaved.isEmpty {
            out.append(HealthFinding(id: "unsaved", level: .warning, symbol: "externaldrive.badge.exclamationmark",
                                     title: "\(unsaved.count) save\(unsaved.count == 1 ? " is" : "s are") only on this Mac", detail: "No Cloud saves and no snapshot. Take a snapshot on the game's page, or turn on Cloud saves in its settings.",
                                     items: unsaved.map(\.name)))
        }
        let outdated = games.filter(\.outdated)
        if !outdated.isEmpty {
            out.append(HealthFinding(id: "outdated", level: .note, symbol: "arrow.clockwise",
                                     title: "\(outdated.count) game\(outdated.count == 1 ? " was" : "s were") built with an older NXForge", detail: "They still play as they are. Rebuilding brings this release's fixes.",
                                     items: outdated.map(\.name), repair: "Open Builds", run: { [weak self] in self?.showConverter(); self?.page = .builds }))
        }

        // the toolchain and room to build
        if let c = checks, !allOK {
            let failed = c.filter { !$0.ok && !$0.optional }.map(\.name)
            if !failed.isEmpty {
                out.append(HealthFinding(id: "toolchain", level: .warning, symbol: "wrench.and.screwdriver",
                                         title: "The toolchain is missing \(failed.count) thing\(failed.count == 1 ? "" : "s")", detail: "Builds need them. The Toolchain page has a Fix for each.",
                                         items: failed, repair: "Open Toolchain", run: { [weak self] in self?.showConverter(); self?.page = .toolchain }))
            }
        }
        var drives: [String: Int64] = [:]
        for p in ["/", settings.outDir, settings.gamesRoot].compactMap({ $0 }) where fm.fileExists(atPath: p) {
            if let f = Disk.free(p) { drives[Disk.volumeName(p)] = f }
        }
        for (name, free) in drives.sorted(by: { $0.key < $1.key }) where free < Disk.warnBelow {
            out.append(HealthFinding(id: "disk-\(name)", level: free < Disk.stopBelow ? .problem : .warning, symbol: "internaldrive",
                                     title: "\(name) has \(Disk.gb(free)) free", detail: "A build stops under \(Disk.gb(Disk.stopBelow)). Storage shows what NXForge keeps and what can go.",
                                     repair: "Open Storage", run: { [weak self] in self?.showConverter(); self?.page = .storage }))
        }

        // the backups of NXForge's own data
        if dataBackupFailed {
            out.append(HealthFinding(id: "backup-failed", level: .warning, symbol: "externaldrive.badge.exclamationmark",
                                     title: "Today's backup of NXForge's data did not complete", detail: "A copy did not match its file, or the support folder could not be written.",
                                     repair: "Back Up Now", run: { [weak self] in self?.backUpData(force: true) }))
        } else if lastDataBackup.map({ Date().timeIntervalSince($0) > 3 * 86400 }) ?? true, !backupRunning {
            out.append(HealthFinding(id: "backup-old", level: .note, symbol: "clock.badge.exclamationmark",
                                     title: lastDataBackup == nil ? "NXForge's data has not been backed up yet" : "NXForge's data was last backed up \(lastDataBackup!.formatted(.relative(presentation: .named)))",
                                     detail: "Your time played, favourites, settings and own covers are copied and checked once a day.",
                                     repair: "Back Up Now", run: { [weak self] in self?.backUpData(force: true) }))
        }
        return out.enumerated().sorted { a, b in a.element.level != b.element.level ? a.element.level < b.element.level : a.offset < b.offset }.map(\.element)
    }
}

struct HealthPage: View {
    @Bindable var model: AppModel
    @State private var backups: [DataBackupEntry] = []

    var body: some View {
        let _ = model.revision
        let found = model.healthFindings()
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health").font(.title2.weight(.bold))
                Text(found.isEmpty ? "Nothing needs a look." : "\(found.count) thing\(found.count == 1 ? "" : "s") to look at. Nothing here changes until you press a repair.")
                    .foregroundStyle(.secondary)
            }
            if found.isEmpty {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(Color(red: 0.29, green: 0.87, blue: 0.50))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All clear").font(.headline)
                            Text("Every game's files are where the library found them, the keys are there, and NXForge's data is backed up.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(found) { f in row(f) }
            backupsCard
        }
        .onAppear { model.noteHealth(found) }
        .onChange(of: found.map(\.id)) { model.noteHealth(found) }
        .task(id: "\(model.lastDataBackup?.timeIntervalSince1970 ?? 0)|\(model.revision)") {
            backups = await Task.detached(priority: .utility) { DataBackup.list() }.value
        }
    }

    func row(_ f: HealthFinding) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: f.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(f.color).frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(f.title).font(.headline)
                    Text(f.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !f.items.isEmpty {
                        let shown = f.items.prefix(6).joined(separator: ", ")
                        Text(f.items.count > 6 ? "\(shown) and \(f.items.count - 6) more" : shown)
                            .font(.callout).foregroundStyle(StageLook.soft).lineLimit(3)
                    }
                }
                Spacer(minLength: 8)
                if let r = f.repair, let run = f.run {
                    Button(r) { run() }.controlSize(.large)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(f.level == .problem ? "Problem" : f.level == .warning ? "Warning" : "Note"): \(f.title)")
        }
    }

    var backupsCard: some View {
        Card(title: "Backups of NXForge's data", subtitle: "Time played, settings and favourites, build records, the library list and your own covers: copied and checked once a day, the last \(DataBackup.keep) kept.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(model.backupRunning ? "Backing Up…" : "Back Up Now") { model.backUpData(force: true) }.disabled(model.backupRunning)
                    Button("Show in Finder") { try? FileManager.default.createDirectory(at: DataBackup.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(DataBackup.dir) }
                    Spacer()
                    if let d = model.lastDataBackup { Text("Last: \(d.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
                }
                if !backups.isEmpty {
                    InsetTable {
                        ForEach(Array(backups.prefix(10).enumerated()), id: \.element.id) { i, e in
                            HStack(spacing: 10) {
                                Image(systemName: e.manifest.verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(e.manifest.verified ? Color.green : Color.orange)
                                    .accessibilityLabel(e.manifest.verified ? "Checked" : "Not complete")
                                Text(e.manifest.made.formatted(date: .abbreviated, time: .shortened))
                                if e.name.contains("before-restore") { Text("before a restore").foregroundStyle(.secondary) }
                                Spacer()
                                Text("\(e.manifest.files.count) files · \(ByteCountFormatter.string(fromByteCount: e.manifest.files.reduce(0) { $0 + $1.bytes }, countStyle: .file))").foregroundStyle(.secondary)
                                Button("Restore…") { model.restoreData(e) }.disabled(!e.manifest.verified)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            if i < min(backups.count, 10) - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }
}
