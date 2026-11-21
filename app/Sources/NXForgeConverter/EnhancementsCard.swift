// The Enhancements card (game page, its own sheet) and tab (Play options), over Enhancements.swift: the game's enhancements with
// a switch each, Get from Library (NXForge's GitHub library for the title), New (a file to fill in) and Show Folder. A switch
// writes the file's `on:` line and at once what the game reads at its next launch.
import AppKit
import SwiftUI

/// One built game's enhancements while a card or the Play options tab shows them
@MainActor @Observable
final class EnhancementsState {
    let app: String
    let titleID: String
    let build: String?
    let folder: URL
    var list: [Enhancement] = []
    var library: [(Enhancements.LibraryItem, Enhancement)]?
    var looking = false
    var note: String?

    init?(app: String) {
        guard let tid = VerifiedGames.titleID(ofApp: app) else { return nil }
        self.app = app
        titleID = tid
        build = GameExtras.buildID(app: app)
        folder = Enhancements.folder(app: app, titleID: tid)
        reload()
    }

    func reload() { list = Enhancements.load(folder: folder) }

    func set(_ e: Enhancement, _ on: Bool) {
        let before = list
        do { try Enhancements.setOn(e, on, folder: folder) } catch { note = "Could not save: \(error.localizedDescription)"; return }
        reload()
        note = Enhancements.apply(list, titleID: titleID, app: app, previous: before)
    }

    /// The library's files this game does not have yet
    var fresh: [(Enhancements.LibraryItem, Enhancement)] {
        let have = Set(list.map { $0.file.lowercased() })
        return (library ?? []).filter { !have.contains($0.0.file.lowercased()) }
    }

    func lookUp() {
        looking = true; note = nil
        Task {
            let found = await Enhancements.library(titleID: titleID)
            looking = false
            if let found { library = found; if found.isEmpty { note = "The library has no enhancements for this game yet." } }
            else { note = "Could not reach NXForge's library on GitHub." }
        }
    }

    func install(_ item: Enhancements.LibraryItem) {
        Task {
            do { try await Enhancements.install(item, folder: folder); reload(); note = "Added, switched off." }
            catch { note = "Could not add it: \(error.localizedDescription)" }
        }
    }

    /// A new enhancement to fill in, opened in the Markdown editor
    func newFile() {
        let fm = FileManager.default
        var name = "My enhancement", i = 2
        while fm.fileExists(atPath: folder.appending(path: Enhancements.fileName(name)).path) { name = "My enhancement \(i)"; i += 1 }
        let text = """
        ---
        nxforge_enhancement: 1
        name: \(MiniYAML.quote(name))
        title_id: \(MiniYAML.quote(titleID))
        builds: \(MiniYAML.quote(build ?? ""))
        on: false
        source: "Me"
        ---
        # \(name)

        What it changes, in a sentence or two (shown under its switch).

        Keep only the blocks you need: launch settings, an Atmosphère code, or mods to switch on.

        ```env
        # DM_FPS_TARGET=60
        ```

        ```dmnt
        ```

        ```mods
        ```

        """
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let u = folder.appending(path: Enhancements.fileName(name))
            try Data(text.utf8).write(to: u, options: .atomic)
            reload()
            NSWorkspace.shared.open(u)
        } catch { note = "Could not make the file: \(error.localizedDescription)" }
    }

    func showFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

/// One enhancement's row: its switch, name, what it changes and its summary
struct EnhancementRow: View {
    let e: Enhancement
    let build: String?
    var disabled = false
    let set: (Bool) -> Void

    var body: some View {
        let fits = e.fits(build: build)
        HStack(alignment: .top, spacing: 10) {
            Toggle(e.name, isOn: Binding(get: { e.on }, set: set)).toggleStyle(.switch).controlSize(.small).labelsHidden()
                .disabled(disabled || (!fits && !e.on)).accessibilityLabel(e.name)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.name).fontWeight(.medium).lineLimit(1)
                    ForEach(e.kinds, id: \.self) { Pill(text: $0, color: $0 == "Game code" ? .orange : .secondary) }
                    if !fits { Pill(text: "Other version", color: .orange).help("Written for build \(e.builds.joined(separator: ", ")); this app is \(build ?? "an unknown build").") }
                }
                if !e.summary.isEmpty { Text(e.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The library's results and the card's buttons, shared by the card and the Play options tab
struct EnhancementsActions: View {
    @Bindable var state: EnhancementsState
    /// in Play options, over the front end's dark stage: its own buttons
    var stage = false

    var body: some View {
        if state.library != nil, !state.fresh.isEmpty {
            Divider()
            Text("In NXForge's library").font(.headline)
            ForEach(state.fresh, id: \.0.id) { item, e in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) { Text(e.name).fontWeight(.medium); ForEach(e.kinds, id: \.self) { Pill(text: $0) } }
                        if !e.summary.isEmpty { Text(e.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer()
                    if stage { Button("Add") { state.install(item) }.buttonStyle(StageButton(height: 34)) }
                    else { Button("Add") { state.install(item) } }
                }
            }
        }
        HStack(spacing: 8) { buttons }
            .modifier(StageButtons(on: stage))
        if let n = state.note { Text(n).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }

    @ViewBuilder var buttons: some View {
            Button { state.lookUp() } label: { Label(state.looking ? "Looking…" : "Get from Library", systemImage: "books.vertical") }
                .disabled(state.looking).help("Lists this game's enhancements in NXForge's library on GitHub. Nothing is added until you choose.")
            Button { state.addCodeMods() } label: { Label("Add Code Mod…", systemImage: "chevron.left.forwardslash.chevron.right") }
                .help("Adds a 60 fps, resolution or graphics patch made for the Switch: a .pchtxt or .ips file from a mod's exefs folder. It is added switched off.")
            Button { state.newFile() } label: { Label("New…", systemImage: "plus") }.help("Makes a new enhancement file in the game's folder and opens it.")
            Button { state.showFolder() } label: { Label("Show Folder", systemImage: "folder") }
            Spacer(minLength: 0)
    }
}

/// The front end's button look for the actions in Play options; the system's elsewhere
private struct StageButtons: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.buttonStyle(StageButton(height: 36)) } else { content }
    }
}

struct EnhancementsCard: View {
    let model: AppModel
    let app: String
    @State private var state: EnhancementsState?

    var body: some View {
        let playing = model.isPlaying(app: app)
        Card(title: "Enhancements", subtitle: "Improvements made for this game: steadier frame rates, 60 fps patches, fixes and mods. Each is a Markdown file in the game's folder, apart from its cheats. Switches apply at the next launch.") {
            if let state {
                if state.list.isEmpty {
                    Text("No enhancements for this game yet. Get from Library looks in NXForge's collection; Add Code Mod takes a 60 fps or resolution patch you have.").foregroundStyle(.secondary)
                }
                ForEach(state.list) { e in EnhancementRow(e: e, build: state.build, disabled: playing) { state.set(e, $0) } }
                if playing { Text("The game is running: changes apply when it next starts.").font(.caption).foregroundStyle(.secondary) }
                EnhancementsActions(state: state)
            } else {
                Text("This app does not say which game it is, so its enhancements cannot be found.").foregroundStyle(.secondary)
            }
        }
        .task(id: app) { state = EnhancementsState(app: app) }
        .onChange(of: model.revision) { state?.reload() }
    }
}

/// The Enhancements card over the window, from the front end's game page
struct EnhancementsSheet: View {
    let model: AppModel
    let ref: GameRef

    var body: some View {
        let (g, b) = model.resolve(ref)
        let name = g?.displayName ?? b.map { $0.app.url.deletingPathExtension().lastPathComponent } ?? "Game"
        VStack(alignment: .leading, spacing: 14) {
            Text(name).font(.title2.weight(.bold)).lineLimit(1)
            ScrollView {
                if let b { EnhancementsCard(model: model, app: b.app) }
                else { Text("Build the game first: enhancements apply to a built game.").foregroundStyle(.secondary) }
            }
            HStack { Spacer(); Button("Done") { model.enhancementsFor = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 640, height: 560)
    }
}

/// Play options' Enhancements tab, in the panel's own look
struct EnhancementsTab: View {
    @Bindable var state: EnhancementsState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.list) { e in
                    EnhancementRow(e: e, build: state.build) { state.set(e, $0) }
                        .tint(.green).padding(.vertical, 6).padding(.horizontal, 10)
                }
                Text("Each enhancement is a file in the game's enhancements folder. Switches apply at the next launch, whichever way the game is opened.")
                    .font(.system(size: 12)).foregroundStyle(StageLook.faint)
                if state.list.isEmpty { Text("No enhancements for this game yet. Get from Library looks in NXForge's collection; Add Code Mod takes a 60 fps or resolution patch you have.").font(.system(size: 13)).foregroundStyle(StageLook.soft) }
                EnhancementsActions(state: state, stage: true)
            }
        }
        .scrollIndicators(.never)
    }
}
