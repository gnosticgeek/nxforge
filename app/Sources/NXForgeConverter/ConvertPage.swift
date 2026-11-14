// Convert: the game (a folder of NSPs with its keys, or a Switch 2 game's .nup or dump folder), the Mac app's output, and the build's stages.
import AppKit
import SwiftUI

/// The script's stage names, as the window shows them.
let stageNames: [(String, String)] = [
    ("build nx_extract", "Extract tools"), ("extract", "Extract game files"), ("rewrite", "Rewrite executable"),
    ("shader split", "Split shaders"), ("Mac shaders", "Compile Metal shaders"), ("Mac host", "Build Mac host"), ("Mac app", "Package Mac app"),
]

/// Names for the stages only some builds have: a Switch 2 game's (a NUP is unpacked, a dump packed), an NVN game's pipeline archive, DLC, NSZ files, provisional checks.
let otherStageNames: [(String, String)] = [
    ("Pipeline archive", "Build pipeline archive"), ("Pipeline prebuild", "Prebuild pipelines"), ("unpack DLC", "Unpack DLC"), ("pack DLC", "Pack DLC"),
    ("extract DLC", "Extract DLC"), ("unpack", "Unpack game files"), ("pack", "Pack game files"), ("decompress NSZ", "Decompress NSZ files"),
    ("build ID lookup", "Read build IDs"), ("heap check", "Check memory layout"), ("address regions", "Map address regions"),
]

func friendly(_ name: String) -> String {
    (otherStageNames + stageNames).first { name.hasPrefix($0.0) }?.1 ?? name.prefix(1).uppercased() + name.dropFirst()
}

func mmss(_ s: Int) -> String { "\(s / 60):\(String(format: "%02d", s % 60))" }

struct ConvertPage: View {
    @Bindable var model: AppModel
    /// room for the two cards side by side; a narrow window stacks them
    var wide = true
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Convert", subtitle: "Create a native Mac app from your game files, or drop them here.")
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
            layout {
                SourceFilesCard(model: model)
                MacAppCard(model: model)
            }
            .fixedSize(horizontal: false, vertical: true)
            ActivityCard(model: model)
            // what the engine's profile says about this game, before a long build (idea 8)
            if !model.run.running, let dir = model.settings.gameDir, let tid = GameNeeds.titleID(Source.folder(of: dir)) ?? model.library?.games.first(where: { $0.path == dir })?.titleID,
               let repo = model.env?.repo, let n = GameInsights.notes(repo: repo, titleID: tid) {
                NotesCard(notes: n, verified: model.verified[tid])
            }
            LogView(lines: model.run.done.map(\.line) + model.run.log, running: model.run.running, file: model.run.logFile,
                    placeholder: model.settings.gameDir == nil ? "Choose a game to see its build steps…" : "The build's output shows here.") { copyToClipboard(model.logText) }
        }
        // a game folder, game files and prod.keys, in any mix (DropFiles)
        .dropDestination(for: URL.self) { urls, _ in model.drop(urls) } isTargeted: { dropTargeted = $0 && !model.run.running }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 16))
                    .overlay { Label("Drop a game folder, game files, a .nup or prod.keys", systemImage: "square.and.arrow.down").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    .allowsHitTesting(false)
            }
        }
    }
}

struct SourceFilesCard: View {
    @Bindable var model: AppModel

    var body: some View {
        let keyless = !model.needsKeys
        Card(title: "Source files", subtitle: "Select your game folder and prod.keys, or a Switch 2 game's .nup file or dump folder.", number: 1) {
            DropZone(model: model, keyless: keyless)

            if model.validating {
                HStack { ProgressView().controlSize(.small); Text(keyless ? "Reading the game's container…" : "Checking the game files against your keys…").foregroundStyle(.secondary) }
            } else if let v = model.validation {
                HStack {
                    StatusDot(color: v.ok ? .green : .red)
                    Text(v.ok ? (keyless ? "Game read · \(v.keysSummary)" : "Keys validated · \(v.keysSummary)") : "Validation failed\(v.keysSummary.isEmpty ? "" : " · \(v.keysSummary)")").foregroundStyle(.secondary)
                }
                ForEach(v.summary.filter { !$0.ok }, id: \.self) { l in
                    Label(l.text, systemImage: l.warn ? "exclamationmark.triangle.fill" : "xmark.octagon.fill").font(.callout).foregroundStyle(l.warn ? .orange : .red)
                }
            } else if model.settings.gameDir != nil && (keyless || model.settings.keys != nil) {
                Button("Validate") { model.validate() }.buttonStyle(.stage)
            }

            if let v = model.validation, !v.files.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.game?.name ?? "Game").font(.title3.weight(.semibold))
                    if let s = model.source {
                        Text("Switch 2 game · \(s.form)\(s.romfsBytes > 0 ? String(format: " · %.1f GB of game files", Double(s.romfsBytes) / 1e9) : model.sizing ? " · measuring the game files…" : "")").foregroundStyle(.secondary)
                    } else {
                        Text("\(v.files.count) game file\(v.files.count == 1 ? "" : "s") detected.").foregroundStyle(.secondary)
                    }
                }
                InsetTable {
                    tableRow("File", "Type", nil).font(.caption).foregroundStyle(.secondary).background(.quaternary.opacity(0.4))
                    ForEach(v.files) { f in
                        Divider()
                        tableRow(fileLabel(f), f.role, f).help(([f.name] + f.lines.map { "\($0.ok ? "✓" : "✗") \($0.text)" }).joined(separator: "\n"))
                        ForEach(f.lines.filter { !$0.ok }, id: \.self) { l in
                            Text(l.text).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
                        }
                    }
                }
            }

            ForEach(model.missingForGame) { c in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This game needs \(c.name)").font(.headline)
                        Text(model.needs[c.name].map { "\($0)." } ?? c.why).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.name == "nsz" && model.env?.python == nil {
                        Button("Set up Python") { model.setUpPython() }.buttonStyle(.stagePrimary).disabled(model.pythonSetup?.running == true)
                    } else if let fix = c.fix {
                        Button("Install") { model.runFix(fix) }.buttonStyle(.stagePrimary).help(fix)
                    }
                }
            }

            Divider()
            HStack {
                // the version and its state sit under the heading, where they have the card's width (beside it they were cut off)
                EngineStatus(model: model)
                    .help(model.updateNote.map { "New: \($0)" } ?? "")
                Spacer(minLength: 12)
                if model.updatesAvailable {
                    Button("Update engine") { model.engineAction(update: true) }.buttonStyle(.stage)
                        .disabled(model.run.running || model.engine?.dirty == true || model.engineBusy).fixedSize()
                } else {
                    Button { model.engineAction(update: false) } label: { Label("Check for updates…", systemImage: "arrow.clockwise") }.buttonStyle(.stage).disabled(model.run.running || model.engineBusy || model.engine == nil).fixedSize()
                }
            }
        }
    }

    func tableRow(_ file: String, _ type: String, _ f: FileReport?) -> some View {
        HStack(spacing: 10) {
            if f != nil { Image(systemName: "doc").foregroundStyle(.secondary).frame(width: 16) } else { Color.clear.frame(width: 16, height: 1) }
            Text(file).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(type).lineLimit(1).frame(width: 130, alignment: .leading)
            Group {
                if let f { StatusDot(color: f.ok ? .green : .red, text: f.ok ? "Ready" : "Failed") } else { Text("Status") }
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, f == nil ? 6 : 9)
    }

    /// "Base game.nsp", "Update.nsp", "DLC.nsp": the full name is in the row's tooltip. A NUP's or a dump's packages keep their names.
    func fileLabel(_ f: FileReport) -> String {
        let ext = (f.name as NSString).pathExtension
        if ext.isEmpty { return f.name }
        let word = f.role.hasPrefix("Update") ? "Update" : f.role.hasPrefix("Base") ? "Base game" : f.role.hasPrefix("DLC") ? "DLC" : (f.name as NSString).deletingPathExtension
        return "\(word).\(ext)"
    }
}

/// "● 49a670a · Current" in green, blue when updates wait, red when the check failed.
struct EngineStatus: View {
    let model: AppModel

    var body: some View {
        if let e = model.engine {
            let failed = model.engineMessage?.ok == false
            HStack(spacing: 7) {
                if model.engineBusy { ProgressView().controlSize(.mini) }
                StatusDot(color: failed ? .red : model.updatesAvailable ? .blue : .green)
                Text("Engine \(e.short)\(e.dirty ? "+" : "")").fontWeight(.medium)
                Text("· \(failed ? "Check failed" : model.engineMessage?.text ?? "Current")").foregroundStyle(failed ? .red : model.updatesAvailable ? .blue : .green)
            }
            .lineLimit(1)
            .help("\(model.env?.repo ?? "") on \(e.branch)\n\(e.subject)\n\(model.engineMessage?.text ?? "")")
        } else {
            StatusDot(color: .red, text: model.env?.repo == nil ? "No engine" : "Not a git checkout")
        }
    }
}

struct MacAppCard: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.revision
        Card(title: "Mac app", subtitle: "Build settings for your native Mac application.", number: 2) {
            HStack(spacing: 16) {
                GameIcon(url: model.game?.icon, size: 116)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.game?.name ?? "No game selected").font(.title3.weight(.semibold)).lineLimit(2)
                    Text(model.source == nil ? "Apple Silicon · Metal" : "Apple Silicon · Metal · Switch 2").foregroundStyle(.secondary)
                    Text("A native macOS version built with NXForge.").foregroundStyle(.secondary)
                }
            }
            PathField(label: "Output folder", labelWidth: 100, symbol: "folder", value: model.outputFolder?.lastComponent) {
                if let d = model.choose(folder: true, start: model.outputFolder) { model.settings.outDir = d == model.gameFolder ? nil : d }
            }
            .disabled(model.run.running)
            // the same choice as Settings › After a build: on deletes <id>_build once the app is built and signed
            Toggle(isOn: Binding(get: { model.settings.cleanup == .all }, set: { model.settings.cleanup = $0 ? .all : .off })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remove build folder after building")
                    Text(model.settings.cleanup == .all
                         ? "Frees the space once the app is ready. A rebuild then starts over (about 30 to 50 minutes) and needs the game files again."
                         : "Kept, so a rebuild reuses its finished steps.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(model.run.running)
            .help("Deletes the game's _build folder (extracted files and compiled shaders) after a successful build. Also in Settings › After a build.")

            if model.run.running {
                HStack {
                    Button { } label: {
                        Label(model.run.planning ? "Checking…" : "Building…", systemImage: model.run.planning ? "list.bullet.clipboard" : "hammer.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.stagePrimary).controlSize(.large).disabled(true)
                    Button("Stop") { model.stopBuild() }.buttonStyle(.stage).controlSize(.large)
                }
            } else {
                Button { model.build() } label: {
                    Label("Build Mac app", systemImage: "hammer.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.stagePrimary).controlSize(.large)
                .keyboardShortcut(.defaultAction)   // Return builds: the page's one default button
                .disabled(!model.ready)
                .help(model.ready ? "" : !model.missingForGame.isEmpty ? "This game needs \(model.missingForGame.map(\.name).joined(separator: ", ")): install it above" : !model.allOK ? "Some toolchain checks failed: see Toolchain" : model.needsKeys ? "Choose a game folder and keys that validate" : "Choose a .nup or a dump folder that reads")
                if model.buildCache != nil {
                    // a build reuses every step whose inputs are unchanged: Preview says which, From scratch reuses none
                    HStack {
                        Button { model.build(rebuild: latestApp?.0, plan: true) } label: {
                            Label("Preview build", systemImage: "list.bullet.clipboard").frame(maxWidth: .infinity)
                        }
                        .help("Lists which steps a build would reuse and which it would redo, with how long each took last time; builds nothing")
                        Button { model.scratchAsked(app: latestApp?.0) } label: {
                            Label("From scratch…", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .help("Empties this game's build folder and runs every step again. A normal build reuses the steps whose inputs have not changed, so this is for a build that looks wrong.")
                    }
                    .buttonStyle(.stage).controlSize(.large).disabled(!model.ready)
                }
            }
            if model.run.planning, !model.run.running, let r = model.run.result {
                switch r {
                case .success where !model.run.plan.isEmpty:
                    PlanList(rows: model.run.plan)
                case .success(let plan):   // an engine from before the plan's rows: its text
                    Text(plan).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                case .failure(let e):
                    Text("Preview failed: \(e.description)").font(.callout).foregroundStyle(.red).textSelection(.enabled).lineLimit(4)
                }
            }
            if let d = model.run.running ? nil : model.diskNeed {
                HStack(spacing: 6) {
                    Image(systemName: d.short ? "exclamationmark.triangle.fill" : "internaldrive").foregroundStyle(d.short ? .orange : .secondary)
                    Text(d.text).font(.callout).foregroundStyle(d.short ? .orange : .secondary)
                }
                .help(model.source == nil ? "A first build extracts the game and compiles its shaders: allow about twice the game files' size plus 10 GB. A rebuild needs room for a second copy of the app while it builds, and the shared Metal cache can grow to 12 GB. While a build runs, the converter stops it if free space drops below \(Disk.gb(Disk.stopBelow))."
                      : "A Switch 2 game's first build unpacks its files into one image, compiles its shaders and makes a pipeline archive: allow about twice the game files' size plus 20 GB (Ocarina of Time, a 26 GB .nup, peaked near 76 GB). The build folder goes beside the .nup, so choose a .nup on a drive with room. While a build runs, the converter stops it if free space drops below \(Disk.gb(Disk.stopBelow)).")
                if d.short {
                    Button { model.page = .storage } label: { Label("Free up space…", systemImage: "internaldrive") }.buttonStyle(.stage)
                }
            }

            Divider()
            if !model.run.planning, case .failure(let e)? = model.run.result { BuildFailure(model: model, error: e.description) }
            if let (app, b) = latestApp {
                let current = b.map { $0.engine.commit == model.engine?.commit && $0.engine.local == model.engine?.local && model.engine?.dirty == false } ?? false
                HStack(alignment: .top, spacing: 10) {
                    StatusDot(color: current ? .green : .orange).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current ? "Latest build ready" : "Built on an older engine").font(.headline)
                        Text(b.map { "\($0.date.map(relativeDay) ?? $0.builtAt) · Engine \($0.engine.short)" } ?? "Engine unknown: built before the converter recorded engines")
                            .foregroundStyle(.secondary).help(b?.engine.subject ?? "")
                        if !current, let c = b.flatMap({ model.rebuildCost($0) }) {
                            Text("\(c.title): \(c.detail)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if b?.launched != true { FirstLaunchNote() }
                HStack {
                    Button { model.openApp(app) } label: { Label("Open app", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    Button { reveal(app) } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.stage).controlSize(.large)
                if !current {
                    Button { model.build(rebuild: app) } label: {
                        Label("Rebuild on \(model.engine?.short ?? "the current engine")", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.stage).controlSize(.large).disabled(!model.ready)   // Build Mac app above stays the one blue button
                    .help(model.settings.keepBackups ? "Moves this app to app-backups/ and builds it again on the current engine" : "Builds this app again on the current engine; the old one goes to the Trash")
                }
            } else if !model.run.running {
                Text("No Mac app in this folder yet.").foregroundStyle(.secondary)
            }
        }
    }

    /// The newest game app in the game or output folder, with its recorded build.
    var latestApp: (String, BuildRecord?)? {
        let dirs = Set([model.gameFolder, model.settings.outDir].compactMap { $0 })
        let apps = dirs.flatMap { Engine.apps(in: $0) }
        let mt = { (p: String) in (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date ?? .distantPast }
        return apps.max { mt($0.app) < mt($1.app) }.map { ($0.app, $0.build) }
    }
}

/// A Preview build's steps: reused, done again (with why and how long it took last time), or after the step the check stopped at.
struct PlanList: View {
    let rows: [PlanRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: r.state == .reused ? "checkmark.circle.fill" : r.state == .redo ? "arrow.clockwise.circle.fill" : "questionmark.circle")
                        .foregroundStyle(r.state == .reused ? Color.green : r.state == .redo ? Color.orange : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(friendly(r.stage))
                        Text(r.state == .reused ? "Reused" : r.state == .redo ? "Redone: \(r.why)" : "Redone only if a step above changes what it reads")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    if r.state != .reused, let s = r.seconds { Text(duration(s)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).help("How long this step took the last time it did its work") }
                }
                .accessibilityElement(children: .combine)
            }
            Divider()
            Text(PlanRow.total(rows)).font(.callout.weight(.semibold))
            Text("Nothing was built or changed.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}

struct ActivityCard: View {
    let model: AppModel
    /// the stage table, behind "Show every step"; opens by itself when a build fails
    @AppStorage("activityDetails") private var details = false

    var body: some View {
        let run = model.run
        Card {
            HStack(alignment: .center, spacing: 14) {
                IconTile(symbol: "square.stack.3d.up", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build activity").font(.title3.weight(.bold))
                    Text(run.planning ? "What a build would reuse and redo; nothing is built." : "Converting your game to a native Mac application.").foregroundStyle(.secondary)
                }
                Spacer()
                state
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.tile, in: .capsule)
            }
            StepTiles(model: model)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                summary(now: ctx.date)
            }
            DisclosureGroup(isExpanded: $details) {
                stages.padding(.top, 8)
            } label: {
                Text(details ? "Hide steps" : "Show every step with its time").font(.headline)
                    .contentShape(.rect).onTapGesture { withAnimation { details.toggle() } }
            }
        }
        .onChange(of: run.result?.isFailure) { _, failed in if failed == true { details = true } }
    }

    /// The bar and the time left: what most people need. While idle, the steps a build of this game takes and how long.
    @ViewBuilder func summary(now: Date) -> some View {
        let run = model.run
        let o = run.overall(now: now)
        if run.running {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.stage.name.isEmpty ? "Starting…" : friendly(run.stage.name)).font(.title3.weight(.semibold))
                    Text(run.stage.step.isEmpty ? "Step \(max(run.stage.k, 1)) of \(max(run.stage.n, 1))" : "Step \(run.stage.k) of \(run.stage.n) · \(run.stage.step)")
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(o.remaining.map(timeLeft) ?? "Estimating time left…").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(o.remaining.map { "Done around \(now.addingTimeInterval($0).formatted(date: .omitted, time: .shortened))" } ?? "First build of this kind: no history yet")
                        .foregroundStyle(.secondary)
                }
            }
            TimelineBar(segments: o.segments, height: 16)
            HStack(spacing: 8) {
                Text("\(Int(o.fraction * 100))%").monospacedDigit().fontWeight(.semibold)
                Text("· \(mmss(Int(o.elapsed))) elapsed").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                liveness(now: now)
            }
            .font(.callout)
            if let w = model.diskWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(w).foregroundStyle(.orange).font(.callout)
                    Spacer()
                    Button("Storage…") { model.page = .storage }.buttonStyle(.stage)
                }
            }
        } else if !run.done.isEmpty {
            TimelineBar(segments: o.segments, height: 16)
            HStack {
                Text(run.result?.isFailure == true ? "Stopped at step \(run.done.count) of \(run.done.last?.n ?? run.done.count)" : "\(run.done.count) steps")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total time: \(mmss(run.done.map(\.seconds).reduce(0, +)))").foregroundStyle(.secondary)
            }
            .font(.callout)
        } else {
            let plan = Estimates.plan(model.expected)
            if plan.isEmpty {
                if model.settings.gameDir != nil {
                    Text("A first build takes 20 to 60 minutes, depending on the game. The bar shows the time left once it starts.").foregroundStyle(.secondary)
                }
            } else {
                let total = plan.map(\.seconds).reduce(0, +)
                HStack {
                    Text("A full build of this game takes about \(duration(total))").foregroundStyle(.secondary)
                    Spacer()
                    Text("Unchanged steps are reused, so a rebuild is usually quicker").font(.callout).foregroundStyle(.tertiary)
                }
                TimelineBar(segments: plan.enumerated().map { Segment(id: $0.offset, name: $0.element.name, state: .pending, seconds: $0.element.seconds) }, height: 12)
            }
        }
    }

    /// The newest log line, or, after a quiet minute, a word that the step is still working.
    @ViewBuilder func liveness(now: Date) -> some View {
        let run = model.run
        let quiet = run.lastActivity.map { now.timeIntervalSince($0) } ?? 0
        if quiet > 60 {
            Label("No output for \(duration(quiet)): long steps are quiet, it is still working", systemImage: "hourglass")
                .foregroundStyle(.secondary).lineLimit(1)
        } else if let line = run.log.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            Text(line).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }

    /// The header's one-line state: ready, building, complete or failed.
    @ViewBuilder var state: some View {
        let run = model.run
        if run.running {
            HStack(spacing: 7) { ProgressView().controlSize(.small); Text("\(run.planning ? "Checking" : "Building") · step \(run.stage.k) of \(run.stage.n)").foregroundStyle(.secondary) }
        } else if run.planning, let r = run.result {
            switch r {
            case .success: StatusDot(color: .blue, text: "Preview · nothing built")
            case .failure: StatusDot(color: .red, text: "Preview failed")
            }
        } else if let r = run.result {
            switch r {
            case .success: StatusDot(color: .green, text: "\(run.done.filter(\.ok).count) of \(run.done.last?.n ?? 7) complete")
            case .failure(let e): StatusDot(color: e.description == "stopped" ? .orange : .red, text: e.description == "stopped" ? "Stopped" : e.description.hasPrefix("Stopped: not enough space") ? "Stopped: disk almost full" : "Build failed")
            }
        } else {
            StatusDot(color: model.ready ? .green : .gray, text: model.ready ? "Ready to build" : "Not ready")
        }
    }

    /// Every step with its time and result, and the running one with its count, time in the step and the script's ETA.
    @ViewBuilder var stages: some View {
        let run = model.run
        InsetTable {
            if run.done.isEmpty && !run.running {
                let plan = Estimates.plan(model.expected)
                if plan.isEmpty {
                    ForEach(Array(stageNames.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider() }
                        row(i + 1, state: nil, name: s.1, time: "–", status: "Not run", color: .secondary)
                    }
                } else {
                    ForEach(Array(plan.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider() }
                        row(i + 1, state: nil, name: friendly(s.name), time: "~" + mmss(Int(s.seconds)), status: "Not run", color: .secondary)
                    }
                }
            } else {
                ForEach(run.done) { s in
                    if s.k != run.done.first?.k { Divider() }
                    row(s.k, state: s.ok, name: friendly(s.name), time: mmss(s.seconds), status: !s.ok ? "Failed" : s.redo ? "Would redo" : s.reused ? "Reused" : "Complete",
                        color: !s.ok ? .red : s.redo ? .orange : s.reused ? .secondary : .green)
                }
                if run.running && run.done.last?.k != run.stage.k {
                    if !run.done.isEmpty { Divider() }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 12) {
                            number(run.stage.k)
                            ProgressView().controlSize(.small).frame(width: 18)
                            Text(friendly(run.stage.name))
                            if !run.stage.step.isEmpty { Text("· \(run.stage.step)").foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            Text(([run.stage.detail] + [run.stage.eta.map { "ETA \(mmss(Int($0)))" }].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            if let f = run.stage.fraction { ProgressView(value: f).frame(width: 140) } else { ProgressView().progressViewStyle(.linear).frame(width: 140) }
                            Text(run.stageStartedAt.map { mmss(Int(ctx.date.timeIntervalSince($0))) } ?? "").foregroundStyle(.secondary).monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                }
            }
        }
    }

    func number(_ k: Int) -> some View {
        Text("\(k)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .frame(width: 22, height: 20).background(.quaternary, in: .rect(cornerRadius: 5))
    }

    func row(_ k: Int, state: Bool?, name: String, time: String, status: String, color: Color) -> some View {
        HStack(spacing: 12) {
            number(k)
            StatusIcon(ok: state, size: 17)
            Text(name)
            Spacer()
            Text(time).foregroundStyle(.secondary).monospacedDigit().frame(width: 60, alignment: .trailing)
            Text(status).foregroundStyle(color).frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
    }
}

/// A failed build: what it means and what to do next (BuildDiagnosis), the script's own error, and a summary to paste into a report.
struct BuildFailure: View {
    let model: AppModel
    let error: String
    @State private var copied = false

    var body: some View {
        let run = model.run
        let d = BuildDiagnosis.diagnose(error: error, log: run.log)
        HStack(alignment: .top, spacing: 10) {
            StatusDot(color: d.code == .stopped ? .orange : .red).padding(.top, 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(d.title).font(.headline)
                Text(d.fix).font(.callout).fixedSize(horizontal: false, vertical: true)
                if d.code != .stopped {
                    Text(error).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled).lineLimit(4)
                }
                HStack {
                    if let p = d.page, p != .convert {
                        Button { model.page = p } label: { Label("Open \(p.rawValue)", systemImage: p.symbol) }.buttonStyle(.stage)
                    }
                    if d.code == .signing {
                        SettingsLink { Label("Open Settings", systemImage: "gearshape") }.buttonStyle(.stage)
                    }
                    if d.code != .stopped {
                        Button {
                            copyToClipboard(summary(d)); copied = true
                        } label: { Label(copied ? "Copied" : "Copy error summary", systemImage: copied ? "checkmark" : "doc.on.clipboard") }
                        .buttonStyle(.stage)
                        .help("The diagnosis, the failed step, your Mac, Xcode and engine versions, and the log's red lines, with key values, your keys file and your home folder taken out")
                    }
                }
                .controlSize(.small)
            }
        }
        .onChange(of: error) { copied = false }
    }

    func summary(_ d: Diagnosis) -> String { model.errorSummary(error, diagnosis: d) }
}

/// Under a freshly built app: its first launch is slow, so a quiet minute does not look like a hang.
struct FirstLaunchNote: View {
    var body: some View {
        Label("The first launch prepares the game's shaders and can take a minute or more before anything shows. Later launches are quicker.", systemImage: "hourglass")
            .font(.callout).foregroundStyle(.secondary)
    }
}

extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

/// Where a game goes: drop it here or choose it; once chosen, the game and its keys with Change buttons.
struct DropZone: View {
    @Bindable var model: AppModel
    let keyless: Bool
    @State private var hover = false

    var body: some View {
        let game = model.settings.gameDir
        VStack(spacing: 12) {
            if let game {
                VStack(alignment: .leading, spacing: 8) {
                    line(game.isNupFileish ? "shippingbox.fill" : "folder.fill", "Game", game.tildePath)
                    if keyless { line("key", "Keys", "Not needed: a .nup or a dump folder is not encrypted", dim: true) }
                    else { line("key.fill", "Keys", model.settings.keys?.tildePath ?? "Not chosen", dim: model.settings.keys == nil) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Image(systemName: "folder.badge.plus").font(.system(size: 40, weight: .light)).foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical).accessibilityHidden(true)
                Text("Drag and drop your game folder, or click to choose").font(.headline)
            }
            HStack(spacing: 12) {
                Button { chooseGame() } label: { Label(game == nil ? "Choose Game…" : "Change Game…", systemImage: "folder") }
                if !keyless {
                    Button { chooseKeys() } label: { Label(model.settings.keys == nil ? "Choose Keys…" : "Change Keys…", systemImage: "key") }
                }
            }
            .buttonStyle(.stage).controlSize(.large)
            RecentSourcesRow(model: model)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(hover ? 0.10 : 0.05), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(.rect)
        .onTapGesture { if game == nil { chooseGame() } }
        .onHover { hover = $0 }
        .disabled(model.run.running)
    }

    func line(_ symbol: String, _ label: String, _ value: String, dim: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(label).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Text(value).foregroundStyle(dim ? .secondary : .primary).lineLimit(1).truncationMode(.middle).help(value)
        }
    }

    func chooseGame() { if let d = model.chooseGame(start: model.settings.gameDir) { model.setGameDir(d) } }
    func chooseKeys() { if let f = model.choose(folder: false, start: model.gameFolder) { model.settings.keys = f; model.validate() } }
}

/// The seven steps of a build as numbered tiles: done ones ticked, the running one lit, a failed one red.
struct StepTiles: View {
    let model: AppModel

    static let symbols: [String: String] = [
        "Extract tools": "square.and.arrow.down", "Extract game files": "doc", "Rewrite executable": "gearshape",
        "Split shaders": "square.3.layers.3d", "Compile Metal shaders": "chevron.left.forwardslash.chevron.right",
        "Build Mac host": "hammer", "Package Mac app": "shippingbox",
    ]

    enum TileState { case pending, running, done, failed, skipped }

    /// The script's stages each tile stands for (prefixes of stage names): a Switch 2 game's unpack is its "Extract game
    /// files", and the pipeline archive is part of packaging. A stage none of these name falls to the tile its own name gives.
    static let members: [String: [String]] = [
        "Extract tools": ["build nx_extract", "decompress NSZ", "build ID lookup"],
        "Extract game files": ["extract", "unpack", "pack", "check "],
        "Package Mac app": ["Pipeline prebuild", "Pipeline archive", "Mac app"],
    ]

    /// The tile a stage belongs to (its friendly name), or nil for one no tile shows.
    static func tile(of stage: String) -> String? {
        if let t = members.first(where: { $0.value.contains { stage.hasPrefix($0) } })?.key { return t }
        let f = friendly(stage)
        return stageNames.contains { $0.1 == f } ? f : nil
    }

    var body: some View {
        let run = model.run
        HStack(spacing: 8) {
            ForEach(Array(stageNames.enumerated()), id: \.offset) { i, s in
                let name = s.1
                let st = state(name, run)
                if i > 0 { Circle().fill(.secondary.opacity(0.4)).frame(width: 3, height: 3) }
                tile(i + 1, name, st)
            }
        }
        .padding(.top, 10)
    }

    func state(_ name: String, _ run: BuildRun) -> TileState { Self.state(name, run) }

    static func state(_ name: String, _ run: BuildRun) -> TileState {
        if run.running && tile(of: run.stage.name) == name { return .running }
        let done = run.done.filter { tile(of: $0.name) == name }
        if done.contains(where: { !$0.ok }) { return .failed }
        if !done.isEmpty { return .done }
        // a step this build has no stage for (a Switch 2 game needs no extract tools) once a later step has started: not needed, not waiting
        guard let i = stageNames.firstIndex(where: { $0.1 == name }) else { return .pending }
        let later = Set(stageNames[(i + 1)...].map(\.1))
        let reached = run.done.compactMap { tile(of: $0.name) } + (run.running ? [tile(of: run.stage.name)].compactMap { $0 } : [])
        return reached.contains(where: later.contains) ? .skipped : .pending
    }

    func tile(_ n: Int, _ name: String, _ st: TileState) -> some View {
        let tint: Color = st == .failed ? .red : st == .done ? .green : .accentColor
        let lit = st != .pending && st != .skipped
        return VStack(spacing: 6) {
            Image(systemName: st == .done ? "checkmark.circle" : st == .skipped ? "minus.circle" : st == .failed ? "xmark.octagon" : Self.symbols[name] ?? "circle")
                .font(.system(size: 22)).foregroundStyle(lit ? tint : st == .skipped ? Color.secondary : Color.primary.opacity(0.85))
                .symbolEffect(.pulse, isActive: st == .running)
            Text(name).font(.callout.weight(.medium)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            if st == .skipped { Text("Not needed").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .top)
        .padding(.horizontal, 6)
        .background(lit ? tint.opacity(0.14) : Theme.tile.opacity(0.6), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(lit ? tint.opacity(0.9) : Theme.cardStroke, lineWidth: lit ? 1.5 : 1))
        .overlay(alignment: .top) { NumberBadge(n: n, color: lit ? tint : Color.secondary.opacity(0.7), size: 20).offset(y: -10) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(n), \(name), \(st == .done ? "done" : st == .running ? "running" : st == .failed ? "failed" : st == .skipped ? "not needed for this game" : "not run")")
    }
}

extension String {
    /// a Switch 2 package file rather than a folder
    var isNupFileish: Bool { Source.isNupFile(self) }
}
