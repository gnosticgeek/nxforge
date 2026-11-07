// Builds: every app the converter built, a detail panel for the selected one, and the copies a rebuild kept.
import AppKit
import SwiftUI

struct BuildsPage: View {
    @Bindable var model: AppModel

    var builds: [BuildRecord] {
        let _ = model.revision
        var b = Engine.builds().filter { FileManager.default.fileExists(atPath: $0.app) }
        let q = model.buildSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { b = b.filter { name($0).lowercased().contains(q) || $0.engine.short.contains(q) } }
        switch model.buildConsole {
        case .all: break
        case .switch2: b = b.filter { Console.of($0) == .switch2 }
        case .switch1: b = b.filter { Console.of($0) == .switch1 }
        }
        switch model.buildSort {
        case .newest: b.sort { $0.builtAt > $1.builtAt }
        case .oldest: b.sort { $0.builtAt < $1.builtAt }
        case .name: b.sort { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        }
        return b
    }

    func name(_ b: BuildRecord) -> String { b.app.url.deletingPathExtension().lastPathComponent }

    var body: some View {
        let list = builds
        let selected = list.first { $0.app == model.selectedBuild } ?? list.first
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Builds", subtitle: "Your native Mac apps, ready to play.") {
                let outdated = model.outdatedBuilds
                if !outdated.isEmpty || !model.rebuildQueue.isEmpty {
                    Button { model.rebuildAll() } label: {
                        Label(model.queueMessage == "" ? "Rebuilding All… \(model.rebuildQueue.count) to Go" : "Rebuild All on \(model.engine?.short ?? "Current Engine") (\(outdated.count))",
                              systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.run.running || !model.allOK)
                    .help("Rebuilds every app built on an older engine, one after another; a failure stops the rest")
                }
                Picker("Console", selection: $model.buildConsole) {
                    ForEach(ConsoleFilter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Show the Switch 2 games, the Switch games, or both")
                Picker("Sort", selection: $model.buildSort) {
                    ForEach(BuildSort.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.menu).fixedSize()
                .help("Sort the builds")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            if let m = model.queueMessage, !m.isEmpty {
                HStack {
                    StatusDot(color: .red, text: m)
                    Spacer()
                    Button("Dismiss") { model.queueMessage = nil }.buttonStyle(.glass)
                }
                .padding(.horizontal, 20).padding(.bottom, 10)
            }
            Divider()
            if list.isEmpty {
                Group {
                    if !model.buildSearch.isEmpty { ContentUnavailableView.search(text: model.buildSearch) }
                    else {
                        ContentUnavailableView(model.buildConsole != .all ? "No \(model.buildConsole.rawValue) Games Built" : "No Builds Yet",
                                               systemImage: "macwindow.badge.plus",
                                               description: Text("Convert a game to see its Mac app here."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // a real list: arrow keys move the selection, ⌘⌫ moves the app to the Trash, VoiceOver reads the rows
                    List(selection: Binding(get: { selected?.app }, set: { model.selectedBuild = $0 })) {
                        // Switch 2 games first, then Switch games, each under its own heading when both are listed
                        let groups = Console.allCases.map { c in (c, list.filter { Console.of($0) == c }) }.filter { !$0.1.isEmpty }
                        ForEach(groups, id: \.0) { c, items in
                            Section(groups.count > 1 ? "\(c.rawValue) · \(items.count)" : "") {
                                ForEach(items) { b in
                                    BuildRow(model: model, build: b, name: name(b)).tag(b.app)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .alternatingRowBackgrounds(.disabled)
                    .onDeleteCommand { if let s = selected { trashBuild(model, s, name(s)) } }
                    .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { apps in
                        if let a = apps.first { model.openApp(a) }   // double-click opens the app
                    }
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
                    if let s = selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                BuildDetail(model: model, build: s, name: name(s))
                                PreviousBuilds(model: model, build: s)
                                SaveSnapshotsCard(model: model, build: s)
                            }
                            .padding(20)
                        }
                        .frame(minWidth: 380, maxWidth: .infinity)
                    }
                }
            }
        }
        .searchable(text: $model.buildSearch, placement: .toolbar, prompt: "Search builds")
    }
}

/// Moves a built app to the Trash after asking (the row's menu and ⌘⌫)
@MainActor func trashBuild(_ model: AppModel, _ build: BuildRecord, _ name: String) {
    guard model.confirm("Move \(name) to the Trash?", "The app goes to the Trash and leaves this list. Its game files, build cache and saves stay where they are.", action: "Move to Trash") else { return }
    try? FileManager.default.trashItem(at: build.app.url, resultingItemURL: nil)
    Engine.forget(build.app)
    model.revision += 1
}

struct BuildRow: View {
    let model: AppModel
    let build: BuildRecord
    let name: String

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(path: build.app, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(1)
                Text("\(Console.of(build).rawValue) · \(build.date.map(relativeDay) ?? build.builtAt)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if build.kept == true {
                Label("kept", systemImage: "lock.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .help("Kept as it is: Rebuild all passes it by")
            } else if model.engine != nil && !model.isCurrent(build) {
                Text("older").font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.orange.opacity(0.25), in: .capsule)
                    .help("Built on \(build.engine.short); the engine is now \(model.engine?.short ?? "")")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Open") { model.openApp(build.app) }
            Button("Show in Finder") { reveal(build.app) }
            Button(model.isCurrent(build) ? "Rebuild" : "Rebuild on \(model.engine?.short ?? "the Current Engine")") { model.rebuildAsked(build) }
                .disabled(model.run.running || !model.allOK)
            Button(build.kept == true ? "Stop Keeping This Build" : "Keep This Build") { model.setKept(build, build.kept != true) }
            Divider()
            Button("Remove from List") { Engine.forget(build.app); model.revision += 1 }
            Button("Move App to Trash…") { trashBuild(model, build, name) }
        }
    }
}

struct BuildDetail: View {
    @Bindable var model: AppModel
    let build: BuildRecord
    let name: String
    @State private var detailsOpen = true

    var body: some View {
        // current: built on today's engine, or on an older one where nothing this game's build reads has changed since
        let current = model.isCurrent(build)
        let sameEngine = model.isSameEngine(build)
        // a kept build is not nudged towards a rebuild: Open stays the blue button
        let nudge = !current && build.kept != true && model.engine != nil
        Card {
            HStack(spacing: 16) {
                AppIcon(path: build.app, size: 96)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.title2.weight(.semibold)).lineLimit(2)
                    Text("Apple Silicon · Metal").foregroundStyle(.secondary)
                    StatusDot(color: .green, text: "Ready")
                }
            }
            HStack {
                Button { model.openApp(build.app) } label: { Label("Open app", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: !nudge))   // on an older engine Rebuild is the blue one, unless the build is kept
                    .keyboardShortcut(nudge ? nil : .defaultAction)   // Return acts on the blue button
                Button { reveal(build.app) } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            if build.launched != true { FirstLaunchNote() }
            VStack(spacing: 0) {
                detail("Built", (build.date.map(relativeDay) ?? build.builtAt) + (build.seconds.map { " · took \(duration(Double($0)))" } ?? ""))
                Divider()
                HStack {
                    Text("Engine").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(build.engine.short).help("\(build.engine.commit.prefix(7)) · \(build.engine.subject)")
                    if !current, model.engine != nil { Text("older").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.25), in: .capsule) }
                    else if !sameEngine, let now = model.engine {
                        Text("nothing it uses changed in \(now.short)").font(.caption).foregroundStyle(.secondary)
                            .help("The engine moved on from \(build.engine.short), but only in files this game's build does not read (notes, tests, the converter, other games' profiles), so a rebuild would make the same app")
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                Divider()
                HStack {
                    Text("Keep").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Toggle("Keep this build", isOn: Binding(get: { build.kept == true }, set: { model.setKept(build, $0) })).toggleStyle(.switch).labelsHidden()
                    Text(build.kept == true ? "Rebuild all passes it by" : "For a build that plays well").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
                .help("A kept build stays as it is when the engine updates: no \"older\" nudge and Rebuild all passes it by. Rebuild still replaces it, after asking.")
                Divider()
                detail("Game files", build.gameFiles ?? Engine.describeFiles(build.gameDir))
                Divider()
                if let v = VerifiedGames.titleID(ofApp: build.app).flatMap({ model.verified[$0] }) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("On NXForge").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        Text(v.summary).lineLimit(1).help(v.note)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .help("From docs/nxforge-games.tsv: the last time this game was played on NXForge. \(v.note)")
                    Divider()
                }
                if let rec = FrameTimes.latest(app: build.app, titleID: VerifiedGames.titleID(ofApp: build.app)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Frame times").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        Text(rec.summary.line).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Button { reveal(rec.file.path) } label: { Image(systemName: "folder") }.buttonStyle(.glass)
                    }
                    .padding(.vertical, 6)
                    .help("The newest recording, \(rec.file.lastPathComponent): frames per second, the median and 99th-percentile frame time, frames over \(Int(FrameTimes.Summary.hitchMs)) ms and frames never shown. Record frame times is in the game's Quick settings › Performance.")
                    Divider()
                }
                HStack {
                    Text("Location").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(build.app.url.deletingLastPathComponent().path.tildePath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { reveal(build.app) } label: { Image(systemName: "folder") }.buttonStyle(.glass)
                }
                .padding(.vertical, 6)
            }
            Button { model.rebuildAsked(build) } label: {
                Label(current ? "Rebuild app" : "Rebuild on \(model.engine?.short ?? "the current engine")", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .modifier(GlassButton(prominent: nudge)).controlSize(.large)
            .keyboardShortcut(nudge ? .defaultAction : nil)
            .disabled(!model.allOK || model.run.running)
            DisclosureGroup(isExpanded: $detailsOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    if let stages = build.stages, !stages.isEmpty {
                        // the build's own timeline: each step's share of the time, reused ones faint
                        TimelineBar(segments: stages.enumerated().map { i, st in
                            Segment(id: i, name: st.name, state: !st.ok ? .failed : st.reused ? .reused : .done, seconds: Double(st.seconds))
                        }, height: 12)
                        ForEach(Array(stages.enumerated()), id: \.offset) { _, st in
                            HStack {
                                StatusIcon(ok: st.ok, size: 15)
                                Text(friendly(st.name))
                                Spacer()
                                Text(st.reused ? "reused" : mmss(st.seconds)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.callout)
                        }
                    } else {
                        HStack { StatusIcon(ok: build.steps.map { $0 > 0 }); Text(build.steps.map { "\($0) steps completed" } ?? "Steps not recorded") }
                    }
                    HStack { StatusIcon(ok: build.shaders == nil ? nil : true); Text(build.shaders.map { "\($0) Metal shaders ready" } ?? "Metal shaders ready") }
                    Text(build.engine.subject).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let log = build.log, FileManager.default.fileExists(atPath: log) {
                        HStack {
                            Button { NSWorkspace.shared.open(log.url) } label: { Label("Open build log", systemImage: "doc.text") }.buttonStyle(.glass)
                            Button { reveal(log) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.glass)
                        }
                    }
                }
                .padding(.top, 6)
            } label: { Text("Build details").font(.headline) }
        }
    }

    func detail(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(v).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct PreviousBuilds: View {
    let model: AppModel
    let build: BuildRecord

    var body: some View {
        let _ = model.revision
        let backups = Engine.backups(of: build.app)
        Card(title: "Previous builds", subtitle: "Older versions of this game's native app.") {
            if backups.isEmpty {
                Text("None kept. A rebuild keeps the old app here\(model.settings.keepBackups ? "" : " when Keep previous app builds is on in Settings").").foregroundStyle(.secondary)
            } else {
                InsetTable {
                    HStack {
                        Text("Built").frame(width: 170, alignment: .leading)
                        Text("Engine").frame(width: 110, alignment: .leading)
                        Text("Game files").frame(width: 170, alignment: .leading)
                        Text("Location")
                        Spacer()
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary.opacity(0.4))
                    ForEach(backups) { b in
                        Divider()
                        HStack {
                            Text(b.date.map(relativeDay) ?? "Unknown").frame(width: 170, alignment: .leading)
                            Text(b.engine).frame(width: 110, alignment: .leading)
                            Text(build.gameFiles ?? Engine.describeFiles(build.gameDir)).frame(width: 170, alignment: .leading)
                            Text(b.path.url.deletingLastPathComponent().path.tildePath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { reveal(b.path) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.glass)
                            Menu {
                                Button("Open") { NSWorkspace.shared.open(b.path.url) }
                                Button("Restore this version") { restore(b) }
                                Divider()
                                Button("Move to Trash") {
                                    try? FileManager.default.trashItem(at: b.path.url, resultingItemURL: nil)
                                    model.revision += 1
                                }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.button).buttonStyle(.glass).fixedSize()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
            }
        }
    }

    /// Swap a kept copy back in: the current app goes to app-backups/ in its place.
    func restore(_ b: Backup) {
        guard model.confirm("Restore this version?", "The current app moves to app-backups and this copy takes its place.", action: "Restore") else { return }
        let current = Engine.builds().first { $0.app == build.app }?.engine
        do {
            // an older app may read the save differently: keep a checked copy of it first
            if let id = VerifiedGames.titleID(ofApp: build.app) {
                do { try SaveSnapshots.snapshot(SaveSnapshots.location(app: build.app, titleID: id), reason: .beforeAppRestore) }
                catch {
                    guard model.confirm("No save snapshot", "The save could not be copied (\(error)). Restore the older app anyway?", action: "Restore") else { return }
                }
            }
            _ = try Engine.backUp(build.app, engine: current)
            try FileManager.default.moveItem(atPath: b.path, toPath: build.app)
            // the record now describes the restored copy: its engine is the one its backup name carries
            var r = build
            r.engine = EngineVersion(commit: b.engine, subject: "Restored from app-backups", date: "", branch: "", dirty: false)
            r.builtAt = b.date.map { d in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d) } ?? build.builtAt
            r.steps = nil; r.shaders = nil
            Engine.record(r)
        } catch {
            _ = model.confirm("Could not restore", "\(error)", action: "OK")
        }
        model.revision += 1
    }
}

/// .glassProminent (the blue one) or .glass: the card's main action is blue, the open app when it is current, the rebuild when it is not
struct GlassButton: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
    }
}

/// The game's save snapshots: make one, put one back, show or remove one (SaveSnapshots).
struct SaveSnapshotsCard: View {
    let model: AppModel
    let build: BuildRecord
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false
    @State private var tick = 0

    var body: some View {
        let _ = (model.revision, tick)
        if let id = VerifiedGames.titleID(ofApp: build.app) {
            let loc = SaveSnapshots.location(app: build.app, titleID: id)
            let snaps = SaveSnapshots.list(loc)
            Card(title: "Save snapshots", subtitle: "Checked copies of this game's save, to go back to if a build or a session goes wrong.") {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive").foregroundStyle(.secondary)
                    Text(SaveSnapshots.hasSave(loc) ? "Save: \(loc.save.tildePath)" : "No save yet (it will be at \(loc.save.tildePath))")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if FileManager.default.fileExists(atPath: loc.save) {
                        Button { reveal(loc.save) } label: { Image(systemName: "folder") }.buttonStyle(.glass).help("Show the save in Finder")
                    }
                    Button { make(loc) } label: { Label("Snapshot now", systemImage: "camera") }
                        .buttonStyle(.glass).disabled(busy || !SaveSnapshots.hasSave(loc))
                        .help("Copies the save beside it, in save-snapshots, and checks every file of the copy")
                }
                if let m = message {
                    HStack(spacing: 6) {
                        StatusIcon(ok: m.ok, size: 15)
                        Text(m.text).font(.callout).foregroundStyle(m.ok ? Color.secondary : Color.red).textSelection(.enabled)
                    }
                }
                if snaps.isEmpty {
                    Text("None yet. A rebuild and Restore this version make one on their own; so does every restore, of the save it replaces.").foregroundStyle(.secondary)
                } else {
                    InsetTable {
                        HStack {
                            Text("Made").frame(width: 170, alignment: .leading)
                            Text("Why").frame(width: 200, alignment: .leading)
                            Text("Size").frame(width: 120, alignment: .leading)
                            Spacer()
                        }
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary.opacity(0.4))
                        ForEach(snaps) { s in
                            Divider()
                            HStack {
                                Text(relativeDay(s.created)).frame(width: 170, alignment: .leading).help(s.id)
                                Text(s.reason.label).frame(width: 200, alignment: .leading)
                                Text("\(s.files) files · \(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file))").frame(width: 120, alignment: .leading)
                                Spacer()
                                Button("Restore") { restore(s, loc) }.buttonStyle(.glass).disabled(busy)
                                Menu {
                                    Button("Show in Finder") { reveal(s.path) }
                                    Divider()
                                    Button("Move to Trash") { try? SaveSnapshots.trash(s); tick += 1 }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.button).buttonStyle(.glass).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                    Text("Automatic snapshots: the newest \(SaveSnapshots.keepAutomatic) stay. With Cloud saves on, start the game on this Mac after a restore so the restored save is the one that syncs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func make(_ loc: SaveLocation) {
        guard !SaveSnapshots.isRunning(app: build.app) || model.confirm("The game is running", "A save the game writes while it is copied is refused. Quit the game first for a clean copy.", action: "Try anyway") else { return }
        work { try SaveSnapshots.snapshot(loc, reason: .manual).map { "Snapshot made and checked: \($0.files) files" } ?? "No save to copy yet" }
    }

    private func restore(_ s: SaveSnapshot, _ loc: SaveLocation) {
        if SaveSnapshots.isRunning(app: build.app) {
            _ = model.confirm("Quit the game first", "The game is running: it would write over the restored save. Quit it, then restore.", action: "OK")
            return
        }
        guard model.confirm("Restore this snapshot?", "The save from \(relativeDay(s.created)) replaces the current one. The current save is kept as a snapshot first.", action: "Restore") else { return }
        work {
            let safety = try SaveSnapshots.restore(s, to: loc)
            return "Save restored from \(relativeDay(s.created))" + (safety.map { "; the one it replaced is snapshot \($0.id)" } ?? "")
        }
    }

    /// Run off the main thread (hashing a large save takes a while), then show the result.
    private func work(_ f: @escaping @Sendable () throws -> String) {
        busy = true; message = nil
        Task.detached {
            let r: (Bool, String)
            do { r = (true, try f()) } catch { r = (false, "\(error)") }
            await MainActor.run { message = r; busy = false; tick += 1 }
        }
    }
}
