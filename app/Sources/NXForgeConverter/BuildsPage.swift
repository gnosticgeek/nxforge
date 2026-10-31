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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Builds", subtitle: "Your native Mac apps, ready to play.") {
                    let outdated = model.outdatedBuilds
                    if !outdated.isEmpty || !model.rebuildQueue.isEmpty {
                        Button { model.rebuildAll() } label: {
                            Label(model.queueMessage == "" ? "Rebuilding all… \(model.rebuildQueue.count) to go" : "Rebuild all on \(model.engine?.short ?? "the current engine") (\(outdated.count))",
                                  systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(model.run.running || !model.allOK)
                        .help("Rebuilds every app built on an older engine, one after another; a failure stops the rest")
                    }
                    Picker("Sort", selection: $model.buildSort) {
                        ForEach(BuildSort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.menu).fixedSize()
                }
                if let m = model.queueMessage, !m.isEmpty {
                    HStack {
                        StatusDot(color: .red, text: m)
                        Spacer()
                        Button("Dismiss") { model.queueMessage = nil }.buttonStyle(.glass)
                    }
                }
                if list.isEmpty {
                    Card { Text(model.buildSearch.isEmpty ? "Nothing built yet. Convert a game to see it here." : "No builds match “\(model.buildSearch)”.").foregroundStyle(.secondary) }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        Card(padding: 8) {
                            VStack(spacing: 4) {
                                ForEach(list) { b in
                                    BuildRow(model: model, build: b, name: name(b), selected: b.app == selected?.app)
                                        .onTapGesture { model.selectedBuild = b.app }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        if let s = selected { BuildDetail(model: model, build: s, name: name(s)).frame(maxWidth: .infinity) }
                    }
                    if let s = selected { PreviousBuilds(model: model, build: s) }
                }
            }
            .padding(24)
        }
    }
}

struct BuildRow: View {
    let model: AppModel
    let build: BuildRecord
    let name: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(path: build.app, size: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.weight(.semibold)).lineLimit(2)
                Text(build.date.map(relativeDay) ?? build.builtAt).foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatusDot(color: .green, text: "Ready")
                if build.kept == true {
                    Label("kept · \(build.engine.short)", systemImage: "lock.fill").font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.secondary.opacity(selected ? 0.45 : 0.18), in: .capsule)
                        .help("Kept as it is: Rebuild all passes it by")
                } else if model.engine != nil && !model.isCurrent(build) {
                    Text("older · \(build.engine.short)").font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.orange.opacity(selected ? 0.55 : 0.25), in: .capsule)
                        .help("Built on \(build.engine.short); the engine is now \(model.engine?.short ?? "")")
                } else {
                    Text("Apple Silicon").foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
            }
        }
        .padding(10)
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(build.app.url) }
            Button("Show in Finder") { reveal(build.app) }
            Button(model.isCurrent(build) ? "Rebuild" : "Rebuild on \(model.engine?.short ?? "the current engine")") { model.rebuildAsked(build) }
                .disabled(model.run.running || !model.allOK)
            Button(build.kept == true ? "Stop Keeping This Build" : "Keep This Build") { model.setKept(build, build.kept != true) }
            Divider()
            Button("Remove from List") { Engine.forget(build.app); model.revision += 1 }
            Button("Move App to Trash…") {
                guard model.confirm("Move \(name) to the Trash?", "The app goes to the Trash and leaves this list. Its game files, build cache and saves stay where they are.", action: "Move to Trash") else { return }
                try? FileManager.default.trashItem(at: build.app.url, resultingItemURL: nil)
                Engine.forget(build.app)
                model.revision += 1
            }
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
                AppIcon(path: build.app, size: 128)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.title.weight(.bold)).lineLimit(2)
                    Text("Apple Silicon · Metal").foregroundStyle(.secondary)
                    StatusDot(color: .green, text: "Ready")
                }
            }
            HStack {
                Button { NSWorkspace.shared.open(build.app.url) } label: { Label("Open app", systemImage: "play.fill").font(.title3).frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: !nudge))   // on an older engine Rebuild is the blue one, unless the build is kept
                Button { reveal(build.app) } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
            }
            .controlSize(.extraLarge)
            VStack(spacing: 0) {
                detail("Built", build.date.map(relativeDay) ?? build.builtAt)
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
                HStack {
                    Text("Location").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(build.app.url.deletingLastPathComponent().path.tildePath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { reveal(build.app) } label: { Image(systemName: "folder") }.buttonStyle(.glass)
                }
                .padding(.vertical, 6)
            }
            Button { model.rebuildAsked(build) } label: {
                Label(current ? "Rebuild app" : "Rebuild on \(model.engine?.short ?? "the current engine")", systemImage: "arrow.clockwise").font(nudge ? .title3 : .body).frame(maxWidth: .infinity)
            }
            .modifier(GlassButton(prominent: nudge)).controlSize(nudge ? .extraLarge : .large)
            .disabled(!model.allOK || model.run.running)
            DisclosureGroup(isExpanded: $detailsOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { StatusIcon(ok: build.steps.map { $0 > 0 }); Text(build.steps.map { "\($0) steps completed" } ?? "Steps not recorded") }
                    HStack { StatusIcon(ok: build.shaders == nil ? nil : true); Text(build.shaders.map { "\($0) Metal shaders ready" } ?? "Metal shaders ready") }
                    Text(build.engine.subject).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
