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
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Convert game", subtitle: "Create a native Mac app from your game files, or drop them here.")
            HStack(alignment: .top, spacing: 16) {
                SourceFilesCard(model: model)
                MacAppCard(model: model)
            }
            .fixedSize(horizontal: false, vertical: true)
            ActivityCard(model: model)
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
        Card(title: "Source files", subtitle: "Select your game folder and prod.keys, or a Switch 2 game's .nup file or dump folder.") {
            PathField(label: "Game", labelWidth: 100, symbol: model.settings.gameDir.map(Source.isNupFile) == true ? "shippingbox" : "folder", value: model.settings.gameDir?.tildePath) {
                if let d = model.chooseGame(start: model.settings.gameDir) { model.setGameDir(d) }
            }
            .disabled(model.run.running)
            if keyless {
                HStack(spacing: 10) {
                    Text("Keys file").frame(width: 100, alignment: .leading)
                    Text("Not needed: a .nup or a dump folder is not encrypted").foregroundStyle(.secondary)
                }
            } else {
                PathField(label: "Keys file", labelWidth: 100, symbol: "doc", value: model.settings.keys?.tildePath) {
                    if let f = model.choose(folder: false, start: model.gameFolder) { model.settings.keys = f; model.validate() }
                }
                .disabled(model.run.running)
            }

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
                Button("Validate") { model.validate() }.buttonStyle(.glass)
            }

            if let v = model.validation, !v.files.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.game?.name ?? "Game").font(.title3.weight(.semibold))
                    if let s = model.source {
                        Text("Switch 2 game · \(s.form)\(s.romfsBytes > 0 ? String(format: " · %.1f GB of game files", Double(s.romfsBytes) / 1e9) : "")").foregroundStyle(.secondary)
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
                        Button("Set up Python") { model.setUpPython() }.buttonStyle(.glassProminent).disabled(model.pythonSetup?.running == true)
                    } else if let fix = c.fix {
                        Button("Install") { model.runFix(fix) }.buttonStyle(.glassProminent).help(fix)
                    }
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Engine").font(.headline)
                    Text("NXForge engine version").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                EngineStatus(model: model)
                    .layoutPriority(1)   // the version and its state get their full width before the gap shrinks
                    .help(model.updateNote.map { "New: \($0)" } ?? "")
                if model.updatesAvailable {
                    Button("Update engine") { model.engineAction(update: true) }.buttonStyle(.glassProminent)
                        .disabled(model.run.running || model.engine?.dirty == true || model.engineBusy)
                } else {
                    Button("Check for updates…") { model.engineAction(update: false) }.buttonStyle(.glass).disabled(model.run.running || model.engineBusy || model.engine == nil)
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
                StatusDot(color: failed ? .red : model.updatesAvailable ? .blue : .green,
                          text: "\(e.short)\(e.dirty ? "+" : "") · \(failed ? "Check failed" : model.engineMessage?.text ?? "Current")")
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
        Card(title: "Mac app", subtitle: "Build settings for your native Mac application.") {
            HStack(spacing: 16) {
                GameIcon(url: model.game?.icon, size: 116)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.game?.name ?? "No game selected").font(.title2.weight(.bold)).lineLimit(2)
                    Text(model.source == nil ? "Apple Silicon · Metal" : "Apple Silicon · Metal · Switch 2").foregroundStyle(.secondary)
                    Text("A native macOS version built with NXForge.").foregroundStyle(.secondary)
                }
            }
            PathField(label: "Output folder", labelWidth: 100, symbol: "folder", value: model.outputFolder?.lastComponent) {
                if let d = model.choose(folder: true, start: model.outputFolder) { model.settings.outDir = d == model.gameFolder ? nil : d }
            }
            .disabled(model.run.running)

            if model.run.running {
                HStack {
                    Button { } label: {
                        Label(model.run.planning ? "Checking…" : "Building…", systemImage: model.run.planning ? "list.bullet.clipboard" : "hammer.fill").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.glassProminent).controlSize(.extraLarge).disabled(true)
                    Button("Stop") { model.stopBuild() }.buttonStyle(.glass).controlSize(.extraLarge)
                }
            } else {
                Button { model.build() } label: {
                    Label("Build Mac app", systemImage: "hammer.fill").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glassProminent).controlSize(.extraLarge)
                .disabled(!model.ready)
                .help(model.ready ? "" : !model.missingForGame.isEmpty ? "This game needs \(model.missingForGame.map(\.name).joined(separator: ", ")): install it above" : !model.allOK ? "Some toolchain checks failed: see Toolchain" : model.needsKeys ? "Choose a game folder and keys that validate" : "Choose a .nup or a dump folder that reads")
                if model.buildCache != nil {
                    Button { model.build(rebuild: latestApp?.0, plan: true) } label: {
                        Label("Preview build", systemImage: "list.bullet.clipboard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass).controlSize(.large).disabled(!model.ready)
                    .help("Lists which steps a build would reuse and which it would redo, with how long each took last time; builds nothing")
                }
            }
            if model.run.planning, !model.run.running, let r = model.run.result {
                switch r {
                case .success(let plan):
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
                    Button { model.page = .storage } label: { Label("Free up space…", systemImage: "internaldrive") }.buttonStyle(.glass)
                }
            }

            Divider()
            if !model.run.planning, case .failure(let e)? = model.run.result { BuildFailure(model: model, error: e.description) }
            if let (app, b) = latestApp {
                let current = b.map { $0.engine.commit == model.engine?.commit && model.engine?.dirty == false } ?? false
                HStack(alignment: .top, spacing: 10) {
                    StatusDot(color: current ? .green : .orange).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current ? "Latest build ready" : "Built on an older engine").font(.headline)
                        Text(b.map { "\($0.date.map(relativeDay) ?? $0.builtAt) · Engine \($0.engine.short)" } ?? "Engine unknown: built before the converter recorded engines")
                            .foregroundStyle(.secondary).help(b?.engine.subject ?? "")
                    }
                }
                if b?.launched != true { FirstLaunchNote() }
                HStack {
                    Button { model.openApp(app) } label: { Label("Open app", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    Button { reveal(app) } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.glass).controlSize(.large)
                if !current {
                    Button { model.build(rebuild: app) } label: {
                        Label("Rebuild on \(model.engine?.short ?? "the current engine")", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.extraLarge).disabled(!model.ready)
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

struct ActivityCard: View {
    let model: AppModel
    /// the stage table and the log, behind "Show details"; opens by itself when a build fails
    @AppStorage("activityDetails") private var details = false

    var body: some View {
        let run = model.run
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build activity").font(.title2.weight(.semibold))
                    Text(run.planning ? "What a build would reuse and redo; nothing is built." : "Converting your game to a native Mac application.").foregroundStyle(.secondary)
                }
                Spacer()
                state
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                summary(now: ctx.date)
            }
            DisclosureGroup(isExpanded: $details) {
                VStack(alignment: .leading, spacing: 12) {
                    stages
                    LogView(lines: run.done.map(\.line) + run.log, running: run.running, file: run.logFile) { copyToClipboard(model.logText) }
                }
                .padding(.top, 8)
            } label: {
                Text(details ? "Hide details" : "Show details: every step and the log").font(.headline)
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
                    Button("Storage…") { model.page = .storage }.buttonStyle(.glass)
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
                Text(model.settings.gameDir == nil ? "Choose a game to see its build steps." : "A first build takes 20 to 60 minutes, depending on the game. The bar shows the time left once it starts.")
                    .foregroundStyle(.secondary)
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
                        Button { model.page = p } label: { Label("Open \(p.rawValue)", systemImage: p.symbol) }.buttonStyle(.glassProminent)
                    }
                    if d.code != .stopped {
                        Button {
                            copyToClipboard(summary(d)); copied = true
                        } label: { Label(copied ? "Copied" : "Copy error summary", systemImage: copied ? "checkmark" : "doc.on.clipboard") }
                        .buttonStyle(.glass)
                        .help("The diagnosis, the failed step, your Mac, Xcode and engine versions, and the log's red lines, with key values, your keys file and your home folder taken out")
                    }
                }
                .controlSize(.small)
            }
        }
        .onChange(of: error) { copied = false }
    }

    func summary(_ d: Diagnosis) -> String {
        let run = model.run
        let failed = run.done.last { !$0.ok }.map(\.line) ?? (run.stage.name.isEmpty ? nil : "[\(run.stage.k)/\(run.stage.n)] \(run.stage.name)")
        let title = model.settings.gameDir.flatMap { dir in Engine.apps(in: dir).first.flatMap { VerifiedGames.titleID(ofApp: $0.app) } }
        let game = model.game.map { g in title.map { "\(g.name) (\($0))" } ?? g.name }
        return BuildDiagnosis.summary(d, error: error, log: run.log, failedStep: failed, game: game, engine: model.engine?.label,
                                      xcode: model.checks?.first { $0.name == "Xcode" }?.detail, keysPath: model.settings.keys)
    }
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
