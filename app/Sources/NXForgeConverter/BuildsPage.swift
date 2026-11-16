// Builds: every app the converter built, a detail panel for the selected one, and the copies a rebuild kept.
import AppKit
import SwiftUI

struct BuildsPage: View {
    @Bindable var model: AppModel
    /// Review… › Show only these: the builds on an older engine
    @State private var olderOnly = false
    @FocusState private var listFocused: Bool

    var builds: [BuildRecord] {
        let _ = model.revision
        var b = Engine.builds().filter { FileManager.default.fileExists(atPath: $0.app) }
        let q = model.buildSearch.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { b = b.filter { TitleMatch.matches(q, [name($0), $0.engine.short]) } }
        switch model.buildConsole {
        case .all: break
        case .switch2: b = b.filter { Console.of($0) == .switch2 }
        case .switch1: b = b.filter { Console.of($0) == .switch1 }
        }
        if olderOnly { b = b.filter { model.engine != nil && !model.isCurrent($0) && $0.kept != true } }
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
            heading(list.count)
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 14)
            if let m = model.queueMessage, !m.isEmpty {
                HStack {
                    StatusDot(color: .red, text: m)
                    Spacer()
                    Button("Dismiss") { model.queueMessage = nil }.buttonStyle(.stage)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 10)
            }
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, Theme.gutter)
            if list.isEmpty {
                Group {
                    if !model.buildSearch.isEmpty { ContentUnavailableView.search(text: model.buildSearch) }
                    else if olderOnly { ContentUnavailableView("Every Build Is Current", systemImage: "checkmark.circle", description: Text("No build uses an older engine.")) }
                    else {
                        ContentUnavailableView(model.buildConsole != .all ? "No \(model.buildConsole.rawValue) Games Built" : "No Builds Yet",
                                               systemImage: "macwindow.badge.plus",
                                               description: Text("Convert a game to see its Mac app here."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if olderOnly { Button("Show every build") { olderOnly = false }.buttonStyle(.stage).frame(maxWidth: .infinity).padding(.bottom, 30) }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    // Switch 2 games first, then Switch games, each under its own heading when both are listed
                                    let groups = Console.allCases.map { c in (c, list.filter { Console.of($0) == c }) }.filter { !$0.1.isEmpty }
                                    ForEach(groups, id: \.0) { c, items in
                                        if groups.count > 1 {
                                            Text("\(c.rawValue) · \(items.count)").font(.system(size: 12, weight: .bold)).kerning(1).foregroundStyle(StageLook.faint)
                                                .padding(.leading, 18).padding(.top, 10).padding(.bottom, 4)
                                        }
                                        ForEach(items) { b in
                                            BuildRow(model: model, build: b, name: name(b), selected: b.app == selected?.app)
                                                .id(b.app)
                                                .onTapGesture(count: 2) { model.openGame(GameRef(libraryID: nil, app: b.app)) }
                                                .simultaneousGesture(TapGesture().onEnded { model.selectedBuild = b.app; listFocused = true })
                                        }
                                    }
                                }
                                .padding(.vertical, 12).padding(.trailing, 6)
                            }
                            .onChange(of: model.selectedBuild) { _, a in if let a { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(a) } } }
                        }
                        olderFooter
                    }
                    .frame(width: 400)
                    .focusable().focusEffectDisabled().focused($listFocused)
                    // arrow keys move the selection, Space a quick look, Return the game's page, ⌘⌫ moves the app to the Trash
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        guard let s = selected, let i = list.firstIndex(where: { $0.app == s.app }) else { return .ignored }
                        let j = press.key == .upArrow ? max(i - 1, 0) : min(i + 1, list.count - 1)
                        model.selectedBuild = list[j].app
                        return .handled
                    }
                    .onKeyPress(.space) {
                        guard let s = selected else { return .ignored }
                        model.preview = model.preview == nil ? GameRef(libraryID: nil, app: s.app) : nil
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard let s = selected else { return .ignored }
                        model.openGame(GameRef(libraryID: nil, app: s.app)); return .handled
                    }
                    .onDeleteCommand { if let s = selected { trashBuild(model, s, name(s)) } }
                    .padding(.leading, Theme.gutter - 8)
                    Rectangle().fill(.white.opacity(0.10)).frame(width: 1).padding(.leading, 16)
                    if let s = selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if model.offlineVolume(s.gameDir) != nil || !FileManager.default.fileExists(atPath: s.gameDir) { OfflineBanner(model: model, build: s) }
                                BuildDetail(model: model, build: s, name: name(s))
                                PreviousBuilds(model: model, build: s)
                                SaveSnapshotsCard(model: model, build: s)
                            }
                            .padding(.leading, 26).padding(.trailing, Theme.gutter).padding(.vertical, 26)
                        }
                        .frame(minWidth: 380, maxWidth: .infinity)
                    }
                }
            }
        }
        .task { listFocused = true }
    }

    /// "Builds  5 apps", then search, Platform and Sort
    func heading(_ n: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Builds").font(.system(size: 32, weight: .heavy)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                Text("\(n) app\(n == 1 ? "" : "s")").font(.system(size: 16)).foregroundStyle(StageLook.soft)
            }
            .fixedSize()
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(StageLook.faint)
                TextField("Search builds", text: $model.buildSearch).textFieldStyle(.plain)
                if !model.buildSearch.isEmpty {
                    Button { model.buildSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                        .buttonStyle(.plain).accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 14).frame(minWidth: 180, maxWidth: 420).frame(height: 34)
            .background(.white.opacity(0.06), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
            Menu {
                Picker("Platform", selection: $model.buildConsole) { ForEach(ConsoleFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.inline)
            } label: { filterLabel("Platform", model.buildConsole.rawValue) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Show the Switch 2 games, the Switch games, or both")
            Menu {
                Picker("Sort", selection: $model.buildSort) { ForEach(BuildSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.inline)
            } label: { filterLabel("Sort", model.buildSort.rawValue) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    func filterLabel(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(name):").foregroundStyle(StageLook.soft)
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(StageLook.soft).padding(.leading, 12)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14).frame(height: 34)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16)))
    }

    /// Under the list: how many builds use an older engine, with Review… (show only them, or rebuild them all)
    @ViewBuilder var olderFooter: some View {
        let outdated = model.outdatedBuilds
        if !outdated.isEmpty || !model.rebuildQueue.isEmpty || olderOnly {
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                HStack(spacing: 10) {
                    if model.queueMessage == "" {
                        ProgressView().controlSize(.small)
                        Text("Rebuilding all · \(model.rebuildQueue.count) to go").foregroundStyle(StageLook.soft)
                    } else {
                        Image(systemName: "info.circle").foregroundStyle(StageLook.soft)
                        Text(outdated.isEmpty ? "Every build is current" : "\(outdated.count) build\(outdated.count == 1 ? " uses" : "s use") an older engine").foregroundStyle(StageLook.soft)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button(olderOnly ? "Show Every Build" : "Show Only These") { olderOnly.toggle() }
                        Divider()
                        Button("Rebuild All on \(model.engine?.short ?? "the Current Engine") (\(outdated.count))") { model.rebuildAll() }
                            .disabled(model.run.running || !model.allOK || outdated.isEmpty)
                    } label: { Text("Review…").underline().foregroundStyle(convertAccent) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Show only the builds on an older engine, or rebuild them all one after another (a failure stops the rest)")
                }
                .font(.system(size: 14))
                .padding(.horizontal, 10).padding(.vertical, 14)
            }
        }
    }
}

/// Moves a built app to the Trash after asking (the row's menu and ⌘⌫)
@MainActor func trashBuild(_ model: AppModel, _ build: BuildRecord, _ name: String) {
    let size = Disk.size(build.app)
    guard model.confirm("Move \(name) to the Trash?", "The app (\(Disk.gb(size))) goes to the Trash and leaves this list. Its game files, build cache and saves stay where they are.", action: size > 0 ? "Move \(Disk.gb(size)) to Trash" : "Move to Trash") else { return }
    try? FileManager.default.trashItem(at: build.app.url, resultingItemURL: nil)
    Engine.forget(build.app)
    model.revision += 1
}

struct BuildRow: View {
    let model: AppModel
    let build: BuildRecord
    let name: String
    var selected = false

    var body: some View {
        HStack(spacing: 16) {
            AppIcon(path: build.app, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Text(build.date.map(relativeDay) ?? build.builtAt).font(.system(size: 14)).foregroundStyle(StageLook.soft).lineLimit(1)
            }
            Spacer(minLength: 4)
            if build.kept == true {
                Label("Kept", systemImage: "lock.fill").font(.caption.weight(.semibold)).foregroundStyle(StageLook.soft)
                    .help("Kept as it is: Rebuild all passes it by")
            } else if model.engine != nil && !model.isCurrent(build) {
                Text("Older engine").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.6))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.22), in: .rect(cornerRadius: 6))
                    .help("Built on \(build.engine.short); the engine is now \(model.engine?.short ?? "")")
            } else if model.isPlaying(app: build.app) {
                Text("Playing").font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(selected ? convertAccent.opacity(0.13) : .clear, in: .rect(cornerRadius: 12))
        .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(convertAccent.opacity(0.85), lineWidth: 1.5) } }
        .overlay(alignment: .bottom) { if !selected { Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 16) } }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Open") { model.openApp(build.app) }
            Button("Show in Finder") { reveal(build.app) }
            Button(model.isCurrent(build) ? "Rebuild" : "Rebuild on \(model.engine?.short ?? "the Current Engine")") { model.rebuildAsked(build) }
                .disabled(model.run.running || !model.allOK)
            Button("Rebuild from Scratch…") { model.rebuildAsked(build, scratch: true) }
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
    /// off on the game's page, which has its own name, icon and Play
    var header = true
    @AppStorage("buildDetailsOpen") private var detailsOpen = false

    var body: some View {
        // current: built on today's engine, or on an older one where nothing this game's build reads has changed since
        let current = model.isCurrent(build)
        let sameEngine = model.isSameEngine(build)
        // a kept build is not nudged towards a rebuild: Play stays the white button
        let nudge = !current && build.kept != true && model.engine != nil
        VStack(alignment: .leading, spacing: 0) {
            if header {
            HStack(alignment: .center, spacing: 26) {
                AppIcon(path: build.app, size: 160)
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.system(size: 34, weight: .bold)).tracking(-0.5).lineLimit(2)
                    Text("Nintendo \(Console.of(build).rawValue)").font(.system(size: 19)).foregroundStyle(StageLook.soft)
                    HStack(spacing: 8) {
                        if model.isPlaying(app: build.app) {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                            Text("Playing now").foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                        } else if nudge {
                            Image(systemName: "arrow.clockwise.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.black, .orange)
                            Text("Plays · built on an older engine").foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color(red: 0.2, green: 0.78, blue: 0.4))
                            Text("Ready to play").foregroundStyle(Color(red: 0.29, green: 0.87, blue: 0.50))
                        }
                    }
                    .font(.system(size: 19, weight: .medium))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 18) {
                Button { model.openApp(build.app) } label: { Label(model.isPlaying(app: build.app) ? "Resume" : "Play", systemImage: "play.fill").frame(minWidth: 150) }
                    .buttonStyle(StageButton(primary: !nudge, height: 50))
                    .keyboardShortcut(nudge ? nil : .defaultAction)
                if nudge {
                    Button { model.rebuildAsked(build) } label: { Label("Rebuild on \(model.engine?.short ?? "the current engine")", systemImage: "arrow.clockwise") }
                        .buttonStyle(StageButton(primary: true, height: 50)).keyboardShortcut(.defaultAction)
                        .disabled(!model.allOK || model.run.running)
                }
                Button { reveal(build.app) } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(StageButton(height: 44))
                Button { model.openGame(GameRef(libraryID: nil, app: build.app)) } label: {
                    HStack(spacing: 6) { Text("Game page").underline(); Image(systemName: "arrow.up.forward.square") }
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(convertAccent).contentShape(.rect)
                }
                .buttonStyle(.plain).help("Launch settings, playtime, notes and saves for this game (double-click or Return)")
            }
            .padding(.top, 26)
            if build.launched != true { FirstLaunchNote().padding(.top, 12) }
            rule.padding(.top, 26)
            }
            // "Built today at 21:11 · 2 min · Engine 0.40.0"
            HStack(spacing: 8) {
                Text(([builtText] + [build.seconds.map { duration(Double($0)) }].compactMap { $0 } + ["Engine \(build.engine.short)"]).joined(separator: "  ·  "))
                    .help("\(build.engine.commit.prefix(7)) · \(build.engine.subject)")
                if !current, model.engine != nil {
                    Text("older").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.25), in: .capsule)
                } else if !sameEngine, let now = model.engine {
                    Text("nothing it uses changed in \(now.short)").font(.caption).foregroundStyle(.secondary)
                        .help("The engine moved on from \(build.engine.short), but only in files this game's build does not read (notes, tests, the converter, other games' profiles), so a rebuild would make the same app")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 17)).foregroundStyle(StageLook.soft).padding(.vertical, 18)
            rule
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep this build").font(.system(size: 17))
                    if build.kept == true { Text("Rebuild all passes it by").font(.callout).foregroundStyle(StageLook.faint) }
                }
                Spacer()
                Toggle("Keep this build", isOn: Binding(get: { build.kept == true }, set: { model.setKept(build, $0) })).toggleStyle(.switch).labelsHidden()
            }
            .padding(.vertical, 16)
            .help("A kept build stays as it is when the engine updates: no \"older\" nudge and Rebuild all passes it by. Rebuild still replaces it, after asking.")
            rule
            Button { withAnimation(.easeInOut(duration: 0.2)) { detailsOpen.toggle() } } label: {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).rotationEffect(.degrees(detailsOpen ? 90 : 0))
                    Text("Build details").font(.system(size: 19, weight: .semibold))
                    Text("Files, location and build log").font(.system(size: 15)).foregroundStyle(StageLook.soft).padding(.leading, 26)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain).padding(.vertical, 16)
            if detailsOpen { details.padding(.leading, 28).padding(.bottom, 16) }
            rule
            Menu {
                Button("Rebuild from Scratch…") { model.rebuildAsked(build, scratch: true) }
            } label: { Text(current ? "Rebuild…" : "Rebuild on \(model.engine?.short ?? "the current engine")…") } primaryAction: { model.rebuildAsked(build) }
                .menuStyle(.button).buttonStyle(.glass).controlSize(.large).fixedSize()
                .disabled(!model.allOK || model.run.running)
                .help("Rebuild reuses the steps whose inputs have not changed. The menu has Rebuild from Scratch, which reuses none.")
                .padding(.top, 22)
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.6), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16)))
    }

    var rule: some View { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }

    /// "Built today at 21:11", "Built yesterday at 17:32", "Built on 3 Nov"
    var builtText: String {
        guard let d = build.date else { return "Built \(build.builtAt)" }
        let at = d.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(d) { return "Built today at \(at)" }
        if Calendar.current.isDateInYesterday(d) { return "Built yesterday at \(at)" }
        return "Built " + relativeDay(d).lowercasedFirst
    }

    /// Behind Build details: the game files, how it plays, its frame times, where it is, each step's time and the log
    @ViewBuilder var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            detail("Game files", build.gameFiles ?? Engine.describeFiles(build.gameDir))
            Divider()
            if let v = VerifiedGames.titleID(ofApp: build.app).flatMap({ model.verified[$0] }) {
                detail("On NXForge", v.summary).help("From docs/nxforge-games.tsv: the last time this game was played on NXForge. \(v.note)")
                Divider()
            }
            if let rec = FrameTimes.latest(app: build.app, titleID: VerifiedGames.titleID(ofApp: build.app)) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Frame times").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(rec.summary.line).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Button { reveal(rec.file.path) } label: { Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly) }.buttonStyle(.stage)
                }
                .padding(.vertical, 6)
                .help("The newest recording, \(rec.file.lastPathComponent): frames per second, the median and 99th-percentile frame time, frames over \(Int(FrameTimes.Summary.hitchMs)) ms and frames never shown. Record frame times is in the game's Quick settings › Performance.")
                Divider()
            }
            HStack {
                Text("Location").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(build.app.url.deletingLastPathComponent().path.tildePath).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { reveal(build.app) } label: { Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly) }.buttonStyle(.stage)
            }
            .padding(.vertical, 6)
            Divider()
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
                        Button { NSWorkspace.shared.open(log.url) } label: { Label("Open build log", systemImage: "doc.text") }.buttonStyle(.stage)
                        Button { reveal(log) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.stage)
                    }
                }
            }
            .padding(.top, 10)
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
    var gameName: String { build.app.url.deletingPathExtension().lastPathComponent }

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
                            Button { reveal(b.path) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.stage)
                            Menu {
                                Button("Open") { NSWorkspace.shared.open(b.path.url) }
                                Button("Restore this version") { restore(b) }
                                Divider()
                                Button("Move to Trash") {
                                    try? FileManager.default.trashItem(at: b.path.url, resultingItemURL: nil)
                                    model.revision += 1
                                }
                            } label: { Label("More", systemImage: "ellipsis").labelStyle(.iconOnly) }
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
            r.builtAt = b.date.map(Engine.builtAtFormat.string(from:)) ?? build.builtAt
            r.steps = nil; r.shaders = nil
            Engine.record(r)
        } catch {
            model.showBanner("Could not restore \(gameName)", detail: "\(error.localizedDescription)", tone: .failure)
            model.revision += 1
            return
        }
        model.revision += 1
        model.showBanner("Restored \(gameName) from \(b.engine)", detail: "The app it replaced is in app-backups.", tone: .success, symbol: "clock.arrow.circlepath")
    }
}

/// The white capsule or the translucent one: the card's main action is white, the open app when it is current, the rebuild when it is not
struct GlassButton: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.stagePrimary) } else { content.buttonStyle(.stage) }
    }
}

/// The game's save snapshots: make one, put one back, show or remove one (SaveSnapshots).
struct SaveSnapshotsCard: View {
    let model: AppModel
    let build: BuildRecord
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false
    @State private var tick = 0
    @State private var importing: SaveImport?

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
                        Button { reveal(loc.save) } label: { Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly) }.buttonStyle(.stage).help("Show the save in Finder")
                    }
                    Button { make(loc) } label: { Label("Snapshot now", systemImage: "camera") }
                        .buttonStyle(.stage).disabled(busy || !SaveSnapshots.hasSave(loc))
                        .help("Copies the save beside it, in save-snapshots, and checks every file of the copy")
                    Menu {
                        Button("Import Save…") { pickImport(loc) }
                        Button("Export Save…") { export(loc) }.disabled(!SaveSnapshots.hasSave(loc))
                        Divider()
                        if model.settings.saveBackupRepo != nil {
                            Button("Back Up to Git Now") { model.backUpSave(app: build.app, name: gameName) }.disabled(!SaveSnapshots.hasSave(loc))
                        } else {
                            Button("Set Up Git Backup…") { model.chooseSaveBackupRepo() }
                        }
                    } label: { Label("Move", systemImage: "arrow.up.arrow.down.square") }
                    .menuStyle(.button).buttonStyle(.glass).fixedSize().disabled(busy)
                    .help("Bring a save in from another Mac or an emulator, take this one out as a zip, or back it up to a Git repository")
                }
                if let b = model.backupStatus[id] {
                    HStack(spacing: 6) {
                        StatusIcon(ok: b.ok, size: 14)
                        Text("Git backup: \(b.text)").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else if let repo = model.settings.saveBackupRepo {
                    Text("Backed up to \(repo.tildePath) each time the game quits\(model.settings.saveBackupPush ? ", and pushed" : "").").font(.caption).foregroundStyle(.secondary)
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
                                Button("Restore") { restore(s, loc) }.buttonStyle(.stage).disabled(busy)
                                Menu {
                                    Button("Show in Finder") { reveal(s.path) }
                                    Divider()
                                    Button("Move to Trash") { try? SaveSnapshots.trash(s); tick += 1 }
                                } label: { Label("More", systemImage: "ellipsis").labelStyle(.iconOnly) }
                                .menuStyle(.button).buttonStyle(.glass).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                    Text("Automatic snapshots: the newest \(SaveSnapshots.keepAutomatic) stay. With Cloud saves on, start the game on this Mac after a restore so the restored save is the one that syncs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .sheet(item: $importing) { importSheet($0) }
        }
    }

    var gameName: String { build.app.url.deletingPathExtension().lastPathComponent }

    /// A zip, a folder holding save/ (and save_device/), a snapshot, or a save folder itself; then a preview of both sides.
    private func pickImport(_ loc: SaveLocation) {
        if SaveSnapshots.isRunning(app: build.app) {
            model.showBanner("Quit \(gameName) first", detail: "The game is running: it would write over the imported save. Quit it, then import.", tone: .warning)
            return
        }
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = false
        p.message = "Choose a save: an exported .zip, a folder with save (and save_device) in it, or the save folder itself"
        guard p.runModal() == .OK, let src = p.url?.path else { return }
        busy = true; message = nil
        Task.detached {
            let r: Result<SaveImport, Error> = Result { try SaveTransfer.prepare(src, loc: loc) }
            await MainActor.run {
                busy = false
                switch r {
                case .success(let i): importing = i
                case .failure(let e): message = (false, "\(e)")
                }
            }
        }
    }

    private func export(_ loc: SaveLocation) {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.prompt = "Export Here"; p.message = "Choose where the save's zip goes"
        p.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let folder = p.url?.path else { return }
        let name = gameName
        work {
            let zip = try SaveTransfer.export(loc, name: name, to: folder)
            DispatchQueue.main.async { reveal(zip) }
            return "Exported to \(zip.tildePath)"
        }
    }

    func importSheet(_ i: SaveImport) -> some View {
        let newer: String? = {
            guard let a = i.from.newest, let b = i.to.newest else { return nil }
            return a > b ? "The save you are importing is newer." : a < b ? "The save on this Mac is newer: importing goes back to an older save." : nil
        }()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Import this save?").font(.title3.weight(.bold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("From").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) { Text(i.source.lastComponent).fontWeight(.medium); Text(i.from.text).foregroundStyle(.secondary) }
                }
                GridRow {
                    Text("Replaces").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) { Text("This Mac's save").fontWeight(.medium); Text(i.to.text).foregroundStyle(.secondary) }
                }
            }
            if let newer { Label(newer, systemImage: newer.contains("older") ? "exclamationmark.triangle.fill" : "checkmark.circle").foregroundStyle(newer.contains("older") ? .orange : .green) }
            Text("The save is checked first and kept as a snapshot; the save it replaces is kept as one too.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { if let t = i.temp { try? FileManager.default.removeItem(atPath: t) }; importing = nil }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    importing = nil
                    work { try SaveTransfer.apply(i) }
                }
                .keyboardShortcut(.defaultAction).disabled(i.from.files == 0)
            }
        }
        .padding(22).frame(width: 480)
    }

    private func make(_ loc: SaveLocation) {
        guard !SaveSnapshots.isRunning(app: build.app) || model.confirm("The game is running", "A save the game writes while it is copied is refused. Quit the game first for a clean copy.", action: "Try anyway") else { return }
        work { try SaveSnapshots.snapshot(loc, reason: .manual).map { "Snapshot made and checked: \($0.files) files" } ?? "No save to copy yet" }
    }

    private func restore(_ s: SaveSnapshot, _ loc: SaveLocation) {
        if SaveSnapshots.isRunning(app: build.app) {
            model.showBanner("Quit \(gameName) first", detail: "The game is running: it would write over the restored save. Quit it, then restore.", tone: .warning)
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
