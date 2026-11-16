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
                    else {
                        let k = model.settings.keys
                        line("key.fill", "Keys", k.map { $0.tildePath + ($0 == model.settings.defaultKeys ? " (saved in Settings)" : "") } ?? "Not chosen: set them once in Settings", dim: k == nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Image(systemName: "folder.badge.plus").font(.system(size: 40, weight: .light)).foregroundStyle(.white)
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
        .background(.white.opacity(hover ? 0.08 : 0.04), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.38), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(.rect)
        .onTapGesture { if game == nil { chooseGame() } }
        .onHover { hover = $0 }
        .disabled(model.run.running)
    }

    func line(_ symbol: String, _ label: String, _ value: String, dim: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(StageLook.soft).frame(width: 20)
            Text(label).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Text(value).foregroundStyle(dim ? .secondary : .primary).lineLimit(1).truncationMode(.middle).help(value)
        }
    }

    func chooseGame() { if let d = model.chooseGame(start: model.settings.gameDir) { model.setGameDir(d) } }
    /// A keys file for this game; the first one chosen is also saved in Settings for every build after it.
    func chooseKeys() {
        guard let f = model.choose(folder: false, start: model.gameFolder) else { return }
        model.settings.keys = f
        if model.settings.defaultKeys == nil { model.saveKeys(f) }
        model.validate()
    }
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
