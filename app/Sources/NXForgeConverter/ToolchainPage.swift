// Toolchain: every tool the conversion needs in a grouped table, the engine checkout, and diagnostics.
import AppKit
import SwiftUI

struct ToolchainPage: View {
    @Bindable var model: AppModel
    @State private var fullPython = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Toolchain", subtitle: "Everything needed to build native Mac apps.")
            statusBar
            toolsTable
            if let p = model.pythonSetup {
                HStack(spacing: 8) {
                    if p.running { ProgressView().controlSize(.small) }
                    else { StatusIcon(ok: !p.text.hasPrefix("No ") && !p.text.hasPrefix("Could") && !p.text.hasPrefix("pip")) }
                    Text(p.text).foregroundStyle(.secondary)
                }
            }
            engineCard
        }
    }

    /// Ready or not, on a tinted pane of glass, with when the tools were last looked for and Fix all when it helps.
    var statusBar: some View {
        let tint: Color = model.checking ? .accentColor : model.allOK ? .green : .orange
        return HStack(spacing: 14) {
            if model.checking { ProgressView().frame(width: 40) } else { StatusIcon(ok: model.allOK, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.checking ? "Checking…" : model.allOK ? "Ready to build" : "Not ready to build").font(.title3.weight(.bold))
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer()
            let fixable = model.fixable
            if !fixable.isEmpty {
                Button { model.fixAll() } label: { Label("Fix all (\(fixable.count))", systemImage: "wrench.adjustable") }
                    .buttonStyle(.stagePrimary).controlSize(.large).disabled(model.checking || model.pythonSetup?.running == true)
                    .help("Sets up the converter's own Python if it needs one, and runs every other fix in one Terminal window. The checks run again when you come back.")
            }
            if let t = model.lastChecked {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Label("Last checked \(t.timeIntervalSinceNow > -60 ? "just now" : t.formatted(.relative(presentation: .named)))", systemImage: "clock")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.35)))
    }

    var toolsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Tool").frame(width: 280, alignment: .leading)
                Text("Version or location").frame(maxWidth: .infinity, alignment: .leading)
                Text("Status").frame(width: 260, alignment: .leading)
            }
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
            ForEach(CheckGroup.allCases, id: \.self) { g in
                let rows = (model.checks ?? []).filter { $0.group == g && !($0.group == .system && $0.name == Toolchain.engineCheckName) }
                if !rows.isEmpty {
                    HStack(spacing: 10) {
                        groupIcon(g)
                        Text(g.rawValue).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Theme.tile.opacity(0.55))
                    ForEach(rows) { c in
                        if c.id != rows.first?.id { Divider().padding(.leading, 52) }
                        row(c)
                    }
                }
            }
            HStack {
                Button { model.recheck() } label: { Label("Run checks again", systemImage: "arrow.clockwise") }
                    .buttonStyle(.stage).disabled(model.checking)
                Spacer()
            }
            .padding(12)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder func groupIcon(_ g: CheckGroup) -> some View {
        switch g {
        case .system: Image(systemName: "apple.logo").foregroundStyle(.primary)
        case .build: Image(systemName: "shippingbox.fill").foregroundStyle(Color.accentColor)
        case .packaging: Image(systemName: "gearshape.fill").foregroundStyle(Color.accentColor)
        case .optional: Image(systemName: "star.fill").foregroundStyle(.yellow)
        }
    }

    /// The engine checkout: its version and folder, the environment builds run in, and the buttons to change or copy them.
    var engineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "gearshape.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engine").font(.title3.weight(.bold))
                    Text("Configure your engine and build settings.").foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { if let d = model.choose(folder: true, start: model.env?.repo) { model.settings.repo = d; model.recheck() } } label: {
                            Label("Change location", systemImage: "folder")
                        }
                        if model.updatesAvailable {
                            Button { model.engineAction(update: true) } label: { Label("Update engine", systemImage: "arrow.down.circle") }
                                .disabled(model.engineBusy || model.run.running || model.engine?.dirty == true)
                        } else {
                            Button { model.engineAction(update: false) } label: { Label("Check for updates", systemImage: "arrow.clockwise") }
                                .disabled(model.engineBusy || model.engine == nil)
                        }
                    }
                    .buttonStyle(.stage)
                }
            }
            if let m = model.engineMessage { Text(m.text).font(.callout).foregroundStyle(m.ok ? Color.secondary : Color.red) }
            if let n = model.updateNote { Label("New: \(n)", systemImage: "sparkles").font(.callout).foregroundStyle(.blue) }
            if let repoCheck = model.checks?.first(where: { $0.name == Toolchain.engineCheckName }), !repoCheck.ok, let fix = repoCheck.fix {
                HStack {
                    StatusDot(color: .red, text: "No NXForge engine checkout found")
                    Button("Clone it in Terminal") { model.runFix(fix) }.buttonStyle(.stage)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                engineDetails
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.well.opacity(0.6), in: .rect(cornerRadius: 12))
                VStack(alignment: .trailing, spacing: 12) {
                    advancedBox
                    Button { copyToClipboard(model.diagnostics) } label: { Label("Copy diagnostics", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.stage)
                        .help("The toolchain checks, versions and paths, for a bug report")
                }
                .frame(width: 330)
            }
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }

    var engineDetails: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
            GridRow {
                Text("Version").foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let e = model.engine {
                        Text(e.short).monospaced().help(e.label)
                        let (t, c): (String, Color) = model.updatesAvailable ? ("Update available", .blue) : e.dirty ? ("Local changes", .orange) : ("Current", .green)
                        Text(t).font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(c.opacity(0.22), in: .capsule).foregroundStyle(c)
                    } else {
                        Text(model.env?.repo == nil ? "No engine" : "Not a git checkout").foregroundStyle(.red)
                    }
                }
            }
            GridRow {
                Text("Source folder").foregroundStyle(.secondary)
                Text(model.env?.repo?.tildePath ?? "Not found").lineLimit(1).truncationMode(.middle).help(model.env?.repo ?? "")
            }
            GridRow(alignment: .firstTextBaseline) {
                Text("Python").foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let py = (model.settings.python ?? model.env?.python).map { fullPython ? $0 : $0.tildePath } ?? "None with the modules"
                    Text(py).lineLimit(fullPython ? nil : 1).truncationMode(.middle).textSelection(.enabled)
                    if model.settings.python == nil { Text("found automatically").font(.caption).foregroundStyle(.secondary) }
                    Button { fullPython.toggle() } label: {
                        Label(fullPython ? "Show less" : "Show full path", systemImage: fullPython ? "chevron.up" : "chevron.down").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.link).font(.callout)
                }
            }
            GridRow {
                Text("DOTNET_ROOT").foregroundStyle(.secondary)
                Text(model.env?.dotnetRoot ?? "None").monospaced().lineLimit(1).truncationMode(.middle)
            }
            GridRow(alignment: .top) {
                Text("Tool search path").foregroundStyle(.secondary)
                Text(model.env?.path ?? "").font(.callout.monospaced()).textSelection(.enabled).lineLimit(3)
            }
            GridRow(alignment: .top) {
                Text("Run by hand").foregroundStyle(.secondary)
                Text("The PATH, DOTNET_ROOT, Python and command the converter uses, to build the chosen game from Terminal: Copy environment.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var advancedBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill").font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40).background(Theme.tile, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Advanced configuration").font(.headline)
                    Text("Python, .NET and other environment settings.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if model.settings.python != nil {
                    Button("Find Python automatically") { model.settings.python = nil; model.recheck() }
                }
                Spacer(minLength: 0)
                Button("Choose Python…") { if let f = model.choose(folder: false) { model.settings.python = f; model.recheck() } }
            }
            .buttonStyle(.stage).controlSize(.small)
            Divider()
            HStack {
                Spacer()
                Button { copyToClipboard(model.environmentLine) } label: { Label("Copy environment", systemImage: "terminal") }
                    .buttonStyle(.stage).help(model.environmentLine)
            }
        }
        .padding(14)
        .background(Theme.well.opacity(0.6), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardStroke))
    }

    var summary: String {
        guard let c = model.checks else { return "Looking for the tools…" }
        let missing = c.filter { !$0.ok && (!$0.optional || model.needs[$0.name] != nil) }.map(\.name)
        return missing.isEmpty ? "All required tools are available\(model.needs.isEmpty ? "" : ", and those this game needs")." : "Missing: \(missing.joined(separator: ", "))."
    }

    func row(_ c: Check) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: c.symbol).font(.title3).foregroundStyle(.secondary).frame(width: 24)
                Text(c.name)
            }
            .frame(width: 280, alignment: .leading)
            Text(c.short).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).help(c.detail)
            HStack(spacing: 8) {
                // Python and nsz are fixed by the converter's own Python, set up here rather than in Terminal
                let python = c.name == "Python modules" || c.name == "nsz"
                if c.ok {
                    Image(systemName: "checkmark").foregroundStyle(c.optional ? Color.cyan : .green).fontWeight(.bold)
                    Text(c.optional ? "Available" : "Ready").fontWeight(.medium).foregroundStyle(c.optional ? Color.cyan : .green)
                    if c.name == "Python modules" && !model.ownPython {
                        Button("Set up own") { model.setUpPython() }.buttonStyle(.stage).controlSize(.small)
                            .disabled(model.pythonSetup?.running == true)
                            .help("Make the converter's own Python in Application Support, so it no longer uses \(model.env?.python ?? "another copy")")
                    }
                } else if c.optional, let why = model.needs[c.name] {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Needed for this game").foregroundStyle(.orange).help(why)
                    if let fix = c.fix { Button("Install") { model.runFix(fix) }.buttonStyle(.stage).controlSize(.small).help(fix) }
                } else {
                    Image(systemName: c.optional ? "minus" : "xmark").foregroundStyle(c.optional ? Color.secondary : .red).fontWeight(.semibold)
                    Text(c.optional ? "Not installed" : "Missing").foregroundStyle(c.optional ? Color.secondary : .red)
                    if python {
                        Button("Set up") { model.setUpPython() }.buttonStyle(.stage).controlSize(.small)
                            .disabled(model.pythonSetup?.running == true).help("Make the converter's own Python with the modules the script needs")
                    } else if let fix = c.fix {
                        Button("Fix") { model.runFix(fix) }.buttonStyle(.stage).controlSize(.small).help(fix)
                    }
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
            InfoButton(check: c)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

/// The ⓘ at a row's end: what the tool is for and exactly what was found.
struct InfoButton: View {
    let check: Check
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Label("About this check", systemImage: "info.circle").labelStyle(.iconOnly).foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .frame(width: 40)
            .help("About \(check.name)")
            .accessibilityLabel("About \(check.name)")
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(check.name).font(.headline)
                    Text("Used for: \(check.why)").fixedSize(horizontal: false, vertical: true)
                    Text(check.detail).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let f = check.fix, !check.ok { Text("Fix: \(f)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                .padding(14).frame(width: 340, alignment: .leading)
            }
    }
}
