// Convert (Converter 0.16.0, to Tom's mock-up): one card that reads top to bottom as one job. The game, where its app goes, the
// build's options folded under one line, then whether it is ready, with the space and time it needs beside one Build button.
// The game's wide art lies faintly behind the card. The build's progress and log come in below the card once a build starts.
import AppKit
import SwiftUI

/// The light lilac of the page's marks: the sub-tab underline and the ready tick
let convertAccent = Color(red: 0.78, green: 0.70, blue: 1.0)

struct ConvertPage: View {
    @Bindable var model: AppModel
    var wide = true
    @State private var dropTargeted = false

    var body: some View {
        let run = model.run
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Convert").font(.system(size: 40, weight: .heavy)).tracking(-0.8).accessibilityAddTraits(.isHeader)
                Text("Turn your game into a Mac app.").font(.system(size: 17)).foregroundStyle(StageLook.soft)
            }
            .padding(.top, 14)
            ConvertCard(model: model, wide: wide)
            if model.settings.gameDir != nil && !run.running {
                Text("Or drop another game here").foregroundStyle(StageLook.faint)
            }
            // what the engine's profile says about this game, before a long build (idea 8)
            if !run.running, let dir = model.settings.gameDir, let tid = GameNeeds.titleID(Source.folder(of: dir)) ?? model.library?.games.first(where: { $0.path == dir })?.titleID,
               let repo = model.env?.repo, let n = GameInsights.notes(repo: repo, titleID: tid) {
                NotesCard(notes: n, verified: model.verified[tid])
            }
            // the build itself: under the card once one has started, ended or been previewed
            if run.running || !run.done.isEmpty || run.result != nil || !run.log.isEmpty {
                ActivityCard(model: model)
                LogView(lines: run.done.map(\.line) + run.log, running: run.running, file: run.logFile,
                        placeholder: "The build's output shows here.") { copyToClipboard(model.logText) }
            }
        }
        .frame(maxWidth: 1140)
        .frame(maxWidth: .infinity)
        // a game folder, game files and prod.keys, in any mix (DropFiles)
        .dropDestination(for: URL.self) { urls, _ in model.drop(urls) } isTargeted: { dropTargeted = $0 && !model.run.running }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18).strokeBorder(.white, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 18))
                    .overlay { Label("Drop a game folder, game files, a .nup or prod.keys", systemImage: "square.and.arrow.down").font(.title2.weight(.semibold)).foregroundStyle(.white) }
                    .allowsHitTesting(false)
            }
        }
    }
}

extension AppModel {
    /// The game on the Convert page as the front end knows it (its cover, wide art and colour), else one made from what was read.
    var convertStageGame: StageGame? {
        guard let dir = settings.gameDir else { return nil }
        let lib = library?.games.first { $0.path == dir || $0.folder == dir || $0.folder == Source.folder(of: dir) }
        let games = stageGames()
        if let lib, let g = games.first(where: { $0.game?.id == lib.id || ($0.titleID != nil && $0.titleID == lib.titleID) }) { return g }
        let tid = lib?.titleID ?? GameNeeds.titleID(Source.folder(of: dir))
        if let tid, let g = games.first(where: { $0.titleID == tid }) { return g }
        return StageGame(id: dir, ref: GameRef(libraryID: nil, app: nil), name: lib?.displayName ?? game?.name ?? dir.lastComponent,
                         console: source != nil || tid?.hasPrefix("04") == true ? .switch2 : .switch1, titleID: tid, icon: game?.icon?.path, app: nil, version: nil, last: nil)
    }
}

struct ConvertCard: View {
    @Bindable var model: AppModel
    var wide = true
    /// the game's files, behind "2 files"
    @AppStorage("convertFilesOpen") private var filesOpen = false
    @AppStorage("convertOptionsOpen") private var optionsOpen = false
    /// Build options › Rebuild from scratch: the Build button empties the build folder first (asked once more)
    @State private var scratch = false

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 0) {
            section { gameSection }.padding(.bottom, 18)
            rule
            section { saveSection }.padding(.vertical, 16)
            rule
            section { optionsSection }.padding(.vertical, 14)
            if !model.run.running, let (app, b) = latestApp {
                rule
                appSection(app, b).padding(.vertical, 16)
            }
            if !model.run.planning, case .failure(let e)? = model.run.result {
                rule
                BuildFailure(model: model, error: e.description).padding(.vertical, 16)
            }
            rule
            footer.padding(.top, 18)
        }
        .padding(.horizontal, 32).padding(.top, 26).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.72), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16)))
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onChange(of: model.settings.gameDir) { scratch = false }
        .onAppear { if ProcessInfo.processInfo.environment["NXC_OPTIONS"] != nil { optionsOpen = true } }   // snapshot hook
    }

    func section<C: View>(@ViewBuilder _ c: () -> C) -> some View { VStack(alignment: .leading, spacing: 0) { c() }.frame(maxWidth: .infinity, alignment: .leading) }

    var rule: some View { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }

    func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).kerning(1.4).foregroundStyle(StageLook.faint).padding(.bottom, 12)
    }

    // MARK: the game's wide art, faint, behind the card (as the game pages have it)

    @ViewBuilder var backdrop: some View {
        if let g = model.convertStageGame, let art = CoverStore.shared.hero(g.coverKey) ?? CoverArt.wide(g) {
            let sharp = CoverStore.shared.hero(g.coverKey) != nil
            GeometryReader { geo in
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width * 0.68, height: min(geo.size.height, 380)).clipped()
                    .opacity(sharp ? 0.17 : 0.13)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)], startPoint: .leading, endPoint: .trailing))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
            }
            .id(g.coverKey + (sharp ? "-hero" : "-wide")).transition(.opacity)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    // MARK: Game

    @ViewBuilder var gameSection: some View {
        let keyless = !model.needsKeys
        heading("GAME")
        if let dir = model.settings.gameDir {
            HStack(alignment: .center, spacing: 22) {
                GameIcon(url: model.game?.icon ?? model.convertStageGame?.icon.map { URL(fileURLWithPath: $0) }, size: 128)
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.convertStageGame?.name ?? model.game?.name ?? dir.lastComponent)
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4).lineLimit(2)
                    Text(kindLine).font(.system(size: 16)).foregroundStyle(StageLook.soft).lineLimit(1)
                    HStack(spacing: 8) {
                        Image(systemName: dir.isNupFileish ? "shippingbox" : "folder").foregroundStyle(StageLook.soft)
                        Text(shortPath(dir)).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 15)).foregroundStyle(StageLook.soft).help(dir.tildePath)
                    if !keyless {
                        let k = model.settings.keys
                        HStack(spacing: 8) {
                            Image(systemName: k == nil ? "key.slash" : "key").foregroundStyle(k == nil ? Color.orange : StageLook.faint)
                            Text(k.map { $0 == model.settings.defaultKeys ? "Keys saved in Settings" : $0.tildePath } ?? "No keys chosen: set them once in Settings")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .font(.system(size: 13)).foregroundStyle(k == nil ? Color.orange : StageLook.faint).help(k?.tildePath ?? "")
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Change game…") { chooseGame() }.buttonStyle(.stage).controlSize(.large)
                    if !keyless {
                        Button(model.settings.keys == nil ? "Choose keys…" : "Change keys…") { chooseKeys() }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(StageLook.soft)
                    }
                }
                .disabled(model.run.running)
            }
            HStack(spacing: 12) {
                filesToggle
                Spacer(minLength: 8)
                recentMenu
            }
            .padding(.top, 14)
            if filesOpen, let v = model.validation, !v.files.isEmpty { filesTable(v).padding(.top, 10) }
            if let v = model.validation {
                ForEach(v.summary.filter { !$0.ok }, id: \.self) { l in
                    Label(l.text, systemImage: l.warn ? "exclamationmark.triangle.fill" : "xmark.octagon.fill").font(.callout)
                        .foregroundStyle(l.warn ? .orange : .red).padding(.top, 8)
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
                .padding(.top, 10)
            }
        } else {
            DropZone(model: model, keyless: keyless)
        }
    }

    /// "Nintendo Switch · Base game + update", or a Switch 2 game's container
    var kindLine: String {
        if let s = model.source { return "Nintendo Switch 2 · \(s.form)\(s.romfsBytes > 0 ? String(format: " · %.1f GB", Double(s.romfsBytes) / 1e9) : "")" }
        guard let v = model.validation, !v.files.isEmpty else { return "Nintendo Switch" }
        let roles = v.files.map(\.role)
        let updates = roles.filter { $0.hasPrefix("Update") }.count, dlc = roles.filter { $0.hasPrefix("DLC") }.count
        var parts: [String] = roles.contains { $0.hasPrefix("Base") } ? ["Base game"] : []
        if updates > 0 { parts.append(updates == 1 ? "update" : "\(updates) updates") }
        if dlc > 0 { parts.append("DLC") }
        if let first = parts.first { parts[0] = first.prefix(1).uppercased() + first.dropFirst() }
        return "Nintendo Switch · " + parts.joined(separator: " + ")
    }

    /// "Switch 1 / Gravity Circuit": the game's folder and the one it sits in
    func shortPath(_ p: String) -> String {
        let u = p.url
        let parent = u.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty || parent == "/" ? u.lastPathComponent : "\(parent) / \(u.lastPathComponent)"
    }

    /// "› 2 files", with the check's state beside it
    @ViewBuilder var filesToggle: some View {
        if model.validating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.needsKeys ? "Checking the game files against your keys…" : "Reading the game's container…").foregroundStyle(StageLook.soft)
            }
        } else if let v = model.validation, !v.files.isEmpty {
            Button { withAnimation(.easeInOut(duration: 0.2)) { filesOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).rotationEffect(.degrees(filesOpen ? 90 : 0))
                    Text("\(v.files.count) file\(v.files.count == 1 ? "" : "s")").font(.system(size: 16))
                    if !v.keysSummary.isEmpty {
                        Text("· \(v.keysSummary)").font(.callout).foregroundStyle(StageLook.faint).lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(filesOpen ? "Hide the game's files" : "Show the game's files and what each one is")
        } else if model.validation == nil, model.settings.gameDir != nil, !model.needsKeys || model.settings.keys != nil {
            Button("Check the game files") { model.validate() }.buttonStyle(.stage)
        }
    }

    @ViewBuilder var recentMenu: some View {
        let list = model.settings.recentSources.filter { $0 != model.settings.gameDir }
        if !list.isEmpty {
            let fm = FileManager.default
            BoxMenu {
                ForEach(list, id: \.self) { p in
                    Button { model.setGameDir(p) } label: {
                        Text(model.library?.games.first(where: { $0.path == p })?.displayName ?? p.lastComponent)
                        Text(fm.fileExists(atPath: p) ? p.url.deletingLastPathComponent().path.tildePath : "Offline: its drive may be away")
                    }
                    .disabled(!fm.fileExists(atPath: p))
                }
                Divider()
                Button("Clear Recent Games") { model.settings.recentSources = model.settings.gameDir.map { [$0] } ?? [] }
            } label: {
                HStack(spacing: 6) { Text("Recent games"); Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)) }
                    .font(.system(size: 15)).foregroundStyle(StageLook.soft)
            }
            .fixedSize()
            .disabled(model.run.running)
        }
    }

    func filesTable(_ v: Validation) -> some View {
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

    func chooseGame() { if let d = model.chooseGame(start: model.settings.gameDir) { model.setGameDir(d) } }
    func chooseKeys() {
        guard let f = model.choose(folder: false, start: model.gameFolder) else { return }
        model.settings.keys = f
        if model.settings.defaultKeys == nil { model.saveKeys(f) }
        model.validate()
    }

    // MARK: Save app to

    @ViewBuilder var saveSection: some View {
        heading("SAVE APP TO")
        HStack(spacing: 14) {
            Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(StageLook.soft).frame(width: 30)
            if let out = model.outputFolder {
                VStack(alignment: .leading, spacing: 3) {
                    Text(out.lastComponent).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(whereLine(out)).font(.system(size: 13)).foregroundStyle(StageLook.faint).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .help(out)
            } else {
                Text("Choose a game first: its app goes beside it unless you pick a folder").foregroundStyle(StageLook.faint)
            }
            Spacer(minLength: 12)
            Button("Change…") {
                if let d = model.choose(folder: true, start: model.outputFolder) { model.settings.outDir = d == model.gameFolder ? nil : d }
            }
            .buttonStyle(.stage).controlSize(.large)
            .disabled(model.run.running)
            .contextMenu {
                if let out = model.outputFolder { Button("Show in Finder") { reveal(out) } }
                if model.settings.outDir != nil { Button("Save Beside the Game Again") { model.settings.outDir = nil } }
            }
        }
    }

    /// "On Games · /Volumes/Games/Switch 1/Gravity Circuit": the drive by name, then the whole path
    func whereLine(_ p: String) -> String {
        let drive = (try? p.url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
        let path = p.tildePath + (model.settings.outDir == nil ? "  (beside the game)" : "")
        return drive.map { "On \($0) · \(path)" } ?? path
    }

    // MARK: Build options

    @ViewBuilder var optionsSection: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { optionsOpen.toggle() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).rotationEffect(.degrees(optionsOpen ? 90 : 0))
                Text("Build options").font(.system(size: 17, weight: .semibold))
                Text(optionsSummary).font(.system(size: 14)).foregroundStyle(StageLook.soft).lineLimit(1).padding(.leading, 16)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Clean-up after the build, rebuilding from scratch, Preview build and the engine")
        if optionsOpen {
            VStack(alignment: .leading, spacing: 14) {
                // the same choice as Settings › After a build: on deletes <id>_build once the app is built and signed
                Toggle(isOn: Binding(get: { model.settings.cleanup.cleansUp }, set: { model.settings.cleanup = $0 ? .shaders : .off })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clean up build files")
                        Text(model.settings.cleanup == .all
                             ? "Frees the space once the app is ready. A rebuild then starts over (about 30 to 50 minutes) and needs the game files again."
                             : model.settings.cleanup == .shaders
                             ? "Frees the game-file copies once the app is ready and keeps the shader work, so a rebuild skips the shader steps while they are unchanged. It needs the game files again."
                             : "Kept, so a rebuild reuses its finished steps.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Deletes the game's _build folder (extracted files and compiled shaders) after a successful build. Also in Settings › After a build.")
                if model.buildCache != nil {
                    Toggle(isOn: $scratch) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Rebuild from scratch")
                            Text(scratch ? "The build folder is emptied first and every step runs again. You are asked once more before it starts."
                                         : "Off: steps whose inputs have not changed are reused. Turn on only for a build that looks wrong.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(spacing: 10) {
                    EngineStatus(model: model).help(model.updateNote.map { "New: \($0)" } ?? "")
                    Spacer(minLength: 12)
                    if model.buildCache != nil {
                        Button { model.build(rebuild: latestApp?.0, plan: true) } label: { Label("Preview build", systemImage: "list.bullet.clipboard") }
                            .disabled(!model.ready)
                            .help("Lists which steps a build would reuse and which it would redo, with how long each took last time; builds nothing")
                    }
                    if model.updatesAvailable {
                        Button("Update engine") { model.engineAction(update: true) }
                            .disabled(model.run.running || model.engine?.dirty == true || model.engineBusy)
                    } else {
                        Button { model.engineAction(update: false) } label: { Label("Check for updates…", systemImage: "arrow.clockwise") }
                            .disabled(model.run.running || model.engineBusy || model.engine == nil)
                    }
                }
                .buttonStyle(.stage)
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
            }
            .toggleStyle(.switch)
            .disabled(model.run.running)
            .padding(.top, 14).padding(.leading, 26)
        }
    }

    /// "Clean up build files: On · Reuses finished steps · Engine update available"
    var optionsSummary: String {
        var parts = ["Clean up build files: \(model.settings.cleanup == .all ? "On" : model.settings.cleanup == .shaders ? "On, shader work kept" : "Off")"]
        parts.append(model.buildCache == nil ? "Every step runs (no build folder kept)" : scratch ? "Rebuild from scratch: On" : "Rebuild from scratch: Off")
        if model.updatesAvailable { parts.append("Engine update available") }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: the app already built

    func appSection(_ app: String, _ b: BuildRecord?) -> some View {
        let current = b.map { $0.engine.commit == model.engine?.commit && $0.engine.local == model.engine?.local && model.engine?.dirty == false } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                AppIcon(path: app, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        StatusDot(color: current ? .green : .orange)
                        Text(current ? "Latest build ready" : "Built on an older engine").font(.headline)
                    }
                    Text(b.map { "\($0.date.map(relativeDay) ?? $0.builtAt) · Engine \($0.engine.short)" } ?? "Engine unknown: built before the converter recorded engines")
                        .font(.callout).foregroundStyle(.secondary).help(b?.engine.subject ?? "")
                    if !current, let c = b.flatMap({ model.rebuildCost($0) }) {
                        Text("\(c.title): \(c.detail)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Button { model.openApp(app) } label: { Label("Open app", systemImage: "play.fill") }
                Button { reveal(app) } label: { Label("Show in Finder", systemImage: "folder") }
            }
            .buttonStyle(.stage)
            if b?.launched != true { FirstLaunchNote() }
        }
    }

    /// The newest game app in the game or output folder, with its recorded build.
    var latestApp: (String, BuildRecord?)? {
        let dirs = Set([model.gameFolder, model.settings.outDir].compactMap { $0 })
        let apps = dirs.flatMap { Engine.apps(in: $0) }
        let mt = { (p: String) in (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date ?? .distantPast }
        return apps.max { mt($0.app) < mt($1.app) }.map { ($0.app, $0.build) }
    }

    // MARK: Ready to build

    enum Readiness { case ready, working, warn, blocked }

    var footer: some View {
        let (state, title, detail) = readiness
        return HStack(alignment: .center, spacing: 14) {
            Group {
                switch state {
                case .working: ProgressView().controlSize(.small)
                case .ready: Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.black, convertAccent)
                case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .blocked: Image(systemName: "circle.dashed").foregroundStyle(StageLook.faint)
                }
            }
            .font(.system(size: 26)).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 14)).foregroundStyle(state == .warn ? Color.orange : StageLook.soft).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .help(spaceHelp)
            Spacer(minLength: 12)
            if model.diskNeed?.short == true, !model.run.running {
                Button { model.page = .storage } label: { Label("Free up space…", systemImage: "internaldrive") }.buttonStyle(.stage)
            }
            if model.run.running {
                Button(model.run.held ? "Resume" : "Pause") { model.pauseBuild() }.buttonStyle(StageButton(height: 50))
                    .disabled(model.run.paused && !model.run.held)
                    .help(model.run.held ? "Carry on from where the build was paused" : "Hold the build where it is. Nothing is lost, and Resume carries on from the same point.")
                Button("Stop") { model.stopBuild() }.buttonStyle(StageButton(height: 50))
            } else {
                Button {
                    if scratch { model.scratchAsked(app: latestApp?.0) } else { model.build() }
                } label: { Label(scratch ? "Rebuild from scratch" : "Build Mac app", systemImage: "hammer.fill") }
                .buttonStyle(StageButton(primary: true, height: 50, glow: model.convertStageGame.map { CoverArt.tint($0) }))
                .keyboardShortcut(.defaultAction)   // Return builds: the page's one default button
                .disabled(!model.ready)
                .opacity(model.ready ? 1 : 0.45)
                .help(model.ready ? "" : blockedReason)
            }
        }
    }

    /// The footer's mark, line and detail: ready with the space and time it takes, or what is in the way
    var readiness: (Readiness, String, String) {
        let run = model.run
        if run.running { return (.working, run.planning ? "Checking what a build would redo…" : "\(run.paused ? "Paused" : "Building") · step \(max(run.stage.k, 1)) of \(max(run.stage.n, 1))", run.stage.name.isEmpty ? "Starting…" : friendly(run.stage.name)) }
        if model.settings.gameDir == nil { return (.blocked, "Choose a game to start", "A folder of game files with prod.keys, a Switch 2 game's .nup or dump folder, or a Game Boy Advance game") }
        if model.validating { return (.working, "Checking the game files…", "") }
        if let d = model.diskNeed, d.short { return (.warn, "Not enough space", d.text) }
        if model.ready { return (.ready, "Ready to build", needLine) }
        return (.blocked, "Not ready", blockedReason)
    }

    /// "2.3 GB needed · 92 GB available · about 35 min"
    var needLine: String {
        var parts: [String] = []
        if let d = model.diskNeed { parts += ["\(Disk.gb(d.need)) needed", "\(Disk.gb(d.free)) available"] }
        let total = Estimates.plan(model.expected).map(\.seconds).reduce(0, +)
        if total > 0 { parts.append("about \(duration(total))\(model.buildCache != nil && !scratch ? " at most" : "")") }
        else { parts.append("about 20 to 60 min") }
        return parts.joined(separator: " · ")
    }

    var blockedReason: String {
        if !model.missingForGame.isEmpty { return "This game needs \(model.missingForGame.map(\.name).joined(separator: ", ")): install it above" }
        if !model.allOK { return "Some toolchain checks failed: see Toolchain" }
        if model.validation?.ok == false { return "The game files did not pass the check: see above" }
        if model.needsKeys && model.settings.keys == nil { return "Choose keys for this game" }
        return model.needsKeys ? "Choose a game folder and keys that validate" : "Choose a .nup or a dump folder that reads"
    }

    var spaceHelp: String {
        model.source == nil
            ? "A first build extracts the game and compiles its shaders: allow about twice the game files' size plus 10 GB. A rebuild needs room for a second copy of the app while it builds, and the shared Metal cache can grow to 12 GB. While a build runs and space gets low, the converter clears what it can make again, and pauses the build below \(Disk.gb(Disk.stopBelow)) until there is room. The time is from earlier builds of this game, else of games its size."
            : "A Switch 2 game's first build unpacks its files into one image, compiles its shaders and makes a pipeline archive: allow about twice the game files' size plus 20 GB (Ocarina of Time, a 26 GB .nup, peaked near 76 GB). The build folder goes beside the .nup, so choose a .nup on a drive with room. While a build runs, the converter pauses it below \(Disk.gb(Disk.stopBelow)) free until there is room."
    }
}
