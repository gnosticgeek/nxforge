// One page per game (idea 4): what the Library knows (its files, name, icon, notes) and what Builds knows (its app, engine,
// saves) together, over a backdrop tinted with the game's own icon. It holds the launch settings (5), playtime (6), whether a
// rebuild is worth it (7), the profile's notes (8), saves with import, export and Git backup (13, 14) and the performance history
// (19). Opened by a double-click in the Library (grid or list) or Builds, Space's preview, Go to Anything and a controller's A.
import AppKit
import Charts
import SwiftUI

/// A game, as the Library or Builds names it.
struct GameRef: Hashable, Identifiable {
    var libraryID: String?
    var app: String?
    var id: String { (libraryID ?? "") + "|" + (app ?? "") }
}

extension AppModel {
    /// The Library game and the build a reference points at (either may be missing: a game not built, an app built from a folder
    /// outside the games folder).
    func resolve(_ r: GameRef) -> (game: LibraryGame?, build: BuildRecord?) {
        let games = library?.games ?? []
        var g = r.libraryID.flatMap { id in games.first { $0.id == id } }
        let records = Engine.builds()
        var b = r.app.flatMap { a in records.first { $0.app == a } }
        if g == nil, let a = r.app, let t = VerifiedGames.titleID(ofApp: a) { g = games.first { $0.titleID == t && !$0.shared } ?? games.first { $0.titleID == t } }
        if b == nil, let g {
            let lb = build(of: g, in: libraryBuilds())
            b = lb?.record ?? lb.flatMap { x in records.first { $0.app == x.app } }
        }
        return (g, b)
    }

    func openGame(_ r: GameRef) { preview = nil; gameDetail = r }

    func goBack() { gameDetail = nil }
}

/// A picture's average colour (its icon's mood), cached by path.
enum IconColor {
    @MainActor private static var cache: [String: NSColor] = [:]

    @MainActor static func of(_ path: String?) -> Color {
        guard let path else { return Color.accentColor }
        if let c = cache[path] { return Color(nsColor: c) }
        var color = NSColor.controlAccentColor
        if let img = NSImage(contentsOfFile: path) ?? (path.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: path) : nil),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            var px = [UInt8](repeating: 0, count: 4)
            if let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                color = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            }
        }
        cache[path] = color
        return Color(nsColor: color)
    }
}

struct GamePage: View {
    @Bindable var model: AppModel
    let ref: GameRef
    var wide = true

    var body: some View {
        let _ = model.revision
        let (g, b) = model.resolve(ref)
        let tid = g?.titleID ?? b.flatMap { VerifiedGames.titleID(ofApp: $0.app) }
        let name = g?.displayName ?? b.map { $0.app.url.deletingPathExtension().lastPathComponent } ?? "Game"
        let icon = g?.icon ?? b?.app
        let tint = IconColor.of(icon)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(g, b, name: name, icon: icon, tid: tid)
                if let b, model.offlineVolume(b.gameDir) != nil || !FileManager.default.fileExists(atPath: b.gameDir) { OfflineBanner(model: model, build: b) }
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
                layout {
                    VStack(spacing: 16) {
                        if let b { LaunchSettingsCard(app: b.app) }
                        if let tid, let repo = model.env?.repo, let n = GameInsights.notes(repo: repo, titleID: tid) { NotesCard(notes: n, verified: model.verified[tid]) }
                        if let b, model.engine != nil, !model.isSameEngine(b) { ChangesCard(model: model, build: b, titleID: tid) }
                    }
                    VStack(spacing: 16) {
                        PlaytimeCard(model: model, app: b?.app, titleID: tid, name: name)
                        if let b { PerformanceCard(app: b.app, titleID: tid, name: name) }
                    }
                }
                if let b {
                    SaveSnapshotsCard(model: model, build: b)
                    BuildDetail(model: model, build: b, name: name)
                    PreviousBuilds(model: model, build: b)
                }
            }
            .padding(20)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 340).ignoresSafeArea().allowsHitTesting(false)
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.backward") }.help("Back (⌘[)")
            }
        }
    }

    func hero(_ g: LibraryGame?, _ b: BuildRecord?, name: String, icon: String?, tid: String?) -> some View {
        HStack(alignment: .center, spacing: 20) {
            if let i = g?.icon { GameIcon(url: i.url, size: 150) }
            else if let a = b?.app { AppIcon(path: a, size: 150) }
            else { GameIcon(url: nil, size: 150) }
            VStack(alignment: .leading, spacing: 8) {
                Text(name).font(.largeTitle.weight(.bold)).lineLimit(2)
                Text([g?.publisher, g?.version.map { "v\($0)" }, g?.console.rawValue ?? b.map { Console.of($0).rawValue }, tid].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let tid, let v = model.verified[tid] { Pill(text: v.result == "plays" ? "Plays" : v.result.capitalized, color: v.result == "plays" ? .green : .orange).help(v.summary) }
                    if let b {
                        if b.kept == true { Pill(text: "Kept", color: .secondary) }
                        else if model.engine != nil && !model.isCurrent(b) { Pill(text: "Older engine", color: .orange) }
                        else { Pill(text: "Built", color: .green) }
                    } else { Pill(text: "Not built", color: .secondary) }
                    if let b, model.isPlaying(app: b.app) { Pill(text: "Playing now", color: .blue) }
                }
                HStack(spacing: 10) {
                    if let b {
                        Button { model.openApp(b.app) } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 90) }
                            .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                        Button { model.rebuildAsked(b) } label: { Label("Rebuild", systemImage: "arrow.clockwise") }
                            .buttonStyle(.glass).disabled(model.run.running || !model.allOK)
                    }
                    if let g {
                        Button { model.convertFromLibrary(g) } label: { Label(b == nil ? "Convert" : "Open in Convert", systemImage: "macwindow.badge.plus") }
                            .modifier(GlassButton(prominent: b == nil)).disabled(model.run.running || model.batchRunning)
                    }
                    Button { reveal(b?.app ?? g.map { $0.shared ? "\($0.path)/\($0.files.first ?? "")" : $0.path } ?? "") } label: { Label("Show in Finder", systemImage: "folder") }
                        .buttonStyle(.glass)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

/// A small coloured capsule: a game's state.
struct Pill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(color == .secondary ? Color.primary : color)
            .background(color == .secondary ? AnyShapeStyle(.quaternary) : AnyShapeStyle(color.opacity(0.18)), in: .capsule)
    }
}

/// A build whose game files are on a drive or share that is away, or gone: Mount, or Locate the files.
struct OfflineBanner: View {
    let model: AppModel
    let build: BuildRecord

    var body: some View {
        let vol = model.offlineVolume(build.gameDir)
        HStack(spacing: 10) {
            Image(systemName: vol != nil ? "externaldrive.badge.xmark" : "questionmark.folder").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(vol.map { "Game files offline: “\($0)” is not connected" } ?? "Game files not found").font(.headline)
                Text("\(build.gameDir.tildePath). The app plays without them; a rebuild needs them.").font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let vol, model.settings.remounts[vol] != nil {
                Button("Mount \(vol)") { _ = model.mount(vol) }.buttonStyle(.glassProminent)
            }
            Button("Locate Game Files…") { model.locateGameFiles(build) }.buttonStyle(.glass)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// The game's launch settings, as its own settings window has them (LaunchSettings).
struct LaunchSettingsCard: View {
    let app: String
    @State private var values: [String: String] = [:]
    @State private var settings: [LaunchSetting] = []
    @State private var advanced = false
    @State private var showWindow = true

    var body: some View {
        Card(title: "Launch settings", subtitle: "What the game starts with. The same choices as its own settings window.") {
            if settings.isEmpty {
                Text("This app has no settings list (built before launcher.json, or a game with none).").foregroundStyle(.secondary)
            } else {
                Toggle("Show the game's settings window at launch", isOn: Binding(get: { showWindow }, set: { showWindow = $0; LaunchSettings.setShowsWindow($0, app: app) }))
                    .help("Off: the game opens straight in with these choices. Hold Option while it opens to see its window anyway.")
                ForEach(settings.filter { $0.basic || advanced }.filter { LaunchSettings.visible($0, values: values) }) { s in row(s) }
                HStack {
                    Toggle("Advanced settings", isOn: $advanced).toggleStyle(.checkbox)
                    Spacer()
                    Button("Reset to Tested Defaults") {
                        LaunchSettings.reset(app: app, settings: settings); load()
                    }
                    .buttonStyle(.glass).disabled(settings.allSatisfy { $0.isDefault(values[$0.env] ?? $0.def) })
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: app) { load() }
    }

    func load() {
        settings = LaunchSettings.load(app: app)
        values = Dictionary(uniqueKeysWithValues: settings.map { ($0.env, LaunchSettings.value($0, app: app)) })
        showWindow = LaunchSettings.showsWindow(app: app)
        if settings.allSatisfy({ !$0.basic }) { advanced = true }
    }

    func binding(_ s: LaunchSetting) -> Binding<String> {
        Binding(get: { values[s.env] ?? s.def }, set: { values[s.env] = $0; LaunchSettings.set(s, $0, app: app) })
    }

    @ViewBuilder func row(_ s: LaunchSetting) -> some View {
        LabeledContent {
            switch s.kind {
            case "choice":
                Picker("", selection: binding(s)) { ForEach(s.options ?? [], id: \.self) { o in Text(o.count > 1 ? o[1] : o[0]).tag(o[0]) } }
                    .labelsHidden().fixedSize()
            case "toggle":
                Toggle("", isOn: Binding(get: { (values[s.env] ?? s.def) == s.onValue }, set: { binding(s).wrappedValue = $0 ? s.onValue : s.offValue }))
                    .toggleStyle(.switch).labelsHidden()
            case "range":
                HStack {
                    Slider(value: Binding(get: { Double(values[s.env] ?? s.def) ?? 0 },
                                          set: { binding(s).wrappedValue = String(format: (s.step ?? 1) < 1 ? "%.2f" : "%.0f", $0) }),
                           in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05).frame(width: 160)
                    Text(values[s.env] ?? s.def).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            default:
                TextField("", text: binding(s)).frame(width: 160)
            }
        } label: {
            Text(s.label)
            if !s.note.isEmpty { Text(s.note).lineLimit(2) }
        }
        .padding(.vertical, 2)
    }
}

/// The profile's notes: how the game plays and what is still open.
struct NotesCard: View {
    let notes: ProfileNotes
    let verified: VerifiedGame?
    @State private var all = false

    var body: some View {
        Card(title: "NXForge notes", subtitle: verified?.summary ?? "From the game's profile in the engine.") {
            if !notes.summary.isEmpty { Text(notes.summary).fixedSize(horizontal: false, vertical: true) }
            if notes.open.isEmpty {
                Label("No open issues recorded\(notes.resolved > 0 ? "; \(notes.resolved) resolved" : "")", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            } else {
                Text("Open issues").font(.headline)
                ForEach(all ? notes.open : Array(notes.open.prefix(3)), id: \.self) { o in
                    Label(o, systemImage: "exclamationmark.circle").font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if notes.open.count > 3 { Button(all ? "Show fewer" : "Show all \(notes.open.count)") { all.toggle() }.buttonStyle(.link) }
            }
            Button { NSWorkspace.shared.open(notes.readme.url) } label: { Label("Open the profile's README", systemImage: "doc.text") }.buttonStyle(.glass)
        }
    }
}

/// What changed in the engine since the build, and whether a rebuild is worth it.
struct ChangesCard: View {
    let model: AppModel
    let build: BuildRecord
    let titleID: String?
    @State private var advice: RebuildAdvice?
    @State private var all = false

    var body: some View {
        Card(title: "Since this build", subtitle: "Engine changes that touch what this game's build reads.") {
            if let a = advice {
                Label(a.verdict, systemImage: a.worth ? "arrow.clockwise.circle.fill" : "checkmark.circle").foregroundStyle(a.worth ? Color.blue : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(all ? a.changes : Array(a.changes.prefix(6))) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(c.hash).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(c.subject).font(.callout).lineLimit(2)
                        if c.ownProfile { Pill(text: "this game", color: .blue) }
                        Spacer(minLength: 0)
                        Text(c.date).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if a.changes.count > 6 { Button(all ? "Show fewer" : "Show all \(a.changes.count)") { all.toggle() }.buttonStyle(.link) }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading the engine's history…").foregroundStyle(.secondary) }
            }
        }
        .task(id: build.engine.commit + (model.engine?.commit ?? "")) {
            guard let repo = model.env?.repo else { return }
            let commit = build.engine.commit, t = titleID, secs = build.seconds
            let r = await Task.detached { GameInsights.changes(since: commit, repo: repo, titleID: t) }.value
            advice = r.map { GameInsights.advice($0, lastSeconds: secs) }
                ?? RebuildAdvice(changes: [], verdict: "The engine's history does not have this build's commit, so what changed cannot be told.", worth: true)
        }
    }
}

/// Time played: the total, the last session and the last eight weeks.
struct PlaytimeCard: View {
    let model: AppModel
    let app: String?
    let titleID: String?
    let name: String

    var body: some View {
        let r = model.playRecord(app: app, titleID: titleID)
        Card(title: "Playtime", subtitle: "Timed while the converter is open, however the game is started.") {
            if let r, !r.sessions.isEmpty {
                HStack(spacing: 24) {
                    stat("Total", Playtime.text(r.total))
                    stat("Sessions", "\(r.sessions.count)")
                    stat("Last played", r.last.map(relativeDay) ?? "—")
                }
                Chart(Playtime.weekly(r), id: \.week) { w in
                    BarMark(x: .value("Week", w.week, unit: .weekOfYear), y: .value("Minutes", w.minutes))
                        .foregroundStyle(Color.accentColor.gradient).cornerRadius(3)
                }
                .chartYAxisLabel("minutes")
                .frame(height: 110)
            } else {
                Text(app == nil ? "Build it to start counting." : "Not played yet while the converter was open.").foregroundStyle(.secondary)
            }
        }
    }

    func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.title3.weight(.semibold)).lineLimit(1)
        }
    }
}

/// Frame-time recordings over time (Record frame times in the game's sidebar).
struct PerformanceCard: View {
    let app: String
    let titleID: String?
    let name: String
    @State private var copied = false

    var body: some View {
        let runs = FrameTimes.all(app: app, titleID: titleID)
        Card(title: "Performance history", subtitle: "From each Record frame times session (the game's sidebar › FPS › Advanced).") {
            if runs.isEmpty {
                Text("No recordings yet.").foregroundStyle(.secondary)
            } else {
                Chart(Array(runs.enumerated()), id: \.offset) { i, r in
                    LineMark(x: .value("Session", i + 1), y: .value("fps", r.summary.fps)).interpolationMethod(.monotone)
                    PointMark(x: .value("Session", i + 1), y: .value("fps", r.summary.fps))
                        .foregroundStyle(r.summary.hitches > 0 ? Color.orange : Color.accentColor)
                }
                .chartYAxisLabel("fps")
                .chartXAxisLabel("recording")
                .frame(height: 120)
                ForEach(Array(runs.suffix(3).reversed().enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(relativeDay(r.date)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(r.summary.line).lineLimit(1).truncationMode(.tail)
                    }
                    .font(.callout)
                }
                HStack {
                    Button { copyToClipboard(FrameTimes.report(name: name, runs)); copied = true } label: { Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.clipboard") }
                        .buttonStyle(.glass)
                    if let f = runs.last?.file { Button { reveal(f.path) } label: { Label("Show Recordings", systemImage: "folder") }.buttonStyle(.glass) }
                }
            }
        }
    }
}
