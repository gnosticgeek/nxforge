// The pieces over the pages: Go to Anything (⌘K, idea 15), the quick preview (Space, 18), What's New (1), and the couch:
// the Library's covers full screen, driven by a controller (16). The controller works whenever the converter is the active app:
// the pad moves between games, A opens a game's page (and on its page plays it), B goes back, X plays, Y previews, and Menu
// (or ⇧⌘F) enters and leaves couch mode.
import AppKit
import GameController
import SwiftUI

extension AppModel {
    func toggleCouch() {
        couchMode.toggle()
        if couchMode {
            page = .library
            gameDetail = nil
            if libraryFocus == nil { moveLibraryFocus() }
        }
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) ?? NSApp.mainWindow ?? NSApp.keyWindow,
           w.styleMask.contains(.fullScreen) != couchMode {
            w.toggleFullScreen(nil)
        }
    }

    /// Play the game a reference points at, if it is built.
    func play(_ r: GameRef) {
        if let a = r.app ?? resolve(r).build?.app { openApp(a) }
    }
}

// MARK: controller

@MainActor
final class ControllerNav {
    static let shared = ControllerNav()
    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        GCController.shouldMonitorBackgroundEvents = false
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            let c = n.object as? GCController
            MainActor.assumeIsolated { if let c { self?.attach(c) } }
        })
        for c in GCController.controllers() { attach(c) }
        GCController.startWirelessControllerDiscovery {}
    }

    private func attach(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        c.handlerQueue = .main
        func on(_ b: GCControllerButtonInput, _ f: @escaping @MainActor (AppModel) -> Void) {
            b.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated {
                    guard NSApp.isActive, let m = self?.model else { return }
                    f(m)
                }
            }
        }
        // the front end takes every button (stagePad); the converter's pages keep the couch's
        func key(_ b: GCControllerButtonInput, _ k: PadKey, _ f: @escaping @MainActor (AppModel) -> Void) {
            on(b) { m in if m.frontEnd { m.stagePad(k) } else { f(m) } }
        }
        key(pad.dpad.left, .left) { $0.moveLibraryFocus(dx: -1) }
        key(pad.dpad.right, .right) { $0.moveLibraryFocus(dx: 1) }
        key(pad.dpad.up, .up) { $0.moveLibraryFocus(dy: -1) }
        key(pad.dpad.down, .down) { $0.moveLibraryFocus(dy: 1) }
        key(pad.leftThumbstick.left, .left) { $0.moveLibraryFocus(dx: -1) }
        key(pad.leftThumbstick.right, .right) { $0.moveLibraryFocus(dx: 1) }
        key(pad.leftThumbstick.up, .up) { $0.moveLibraryFocus(dy: -1) }
        key(pad.leftThumbstick.down, .down) { $0.moveLibraryFocus(dy: 1) }
        key(pad.buttonA, .a) { m in
            if let p = m.preview { m.openGame(p) }
            else if let g = m.gameDetail { m.play(g) }
            else if let r = m.focusedGame() { m.showConverter(); m.page = .library; m.openGame(r) }
        }
        key(pad.buttonB, .b) { m in
            if m.preview != nil { m.preview = nil }
            else if m.gameDetail != nil { m.goBack() }
            else if m.couchMode { m.toggleCouch() }
        }
        key(pad.buttonX, .x) { m in if let r = m.gameDetail ?? m.focusedGame() { m.play(r) } }
        key(pad.buttonY, .y) { m in m.preview = m.preview == nil ? m.focusedGame() : nil }
        key(pad.leftShoulder, .l) { _ in }
        key(pad.rightShoulder, .r) { _ in }
        key(pad.buttonMenu, .menu) { $0.toggleCouch() }
        // the right stick turns the box on screen (CaseModelView)
        pad.rightThumbstick.valueChangedHandler = { _, x, _ in CaseStick.x = NSApp.isActive ? Double(x) : 0 }
    }
}

// MARK: quick preview (Space)

struct PreviewSheet: View {
    let model: AppModel
    let ref: GameRef

    var body: some View {
        let (g, b) = model.resolve(ref)
        let tid = g?.titleID ?? b.flatMap { VerifiedGames.titleID(ofApp: $0.app) }
        let name = g?.displayName ?? b.map { $0.app.url.deletingPathExtension().lastPathComponent } ?? "Game"
        let tint = IconColor.of(g?.icon ?? b?.app)
        let notes = tid.flatMap { t in model.env?.repo.flatMap { GameInsights.notes(repo: $0, titleID: t) } }
        let played = model.playRecord(app: b?.app, titleID: tid)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                if let i = g?.icon { GameIcon(url: i.url, size: 96) } else if let a = b?.app { AppIcon(path: a, size: 96) } else { GameIcon(url: nil, size: 96) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title.weight(.bold)).lineLimit(2)
                    Text([g?.publisher, g?.version.map { "v\($0)" }, tid, g.map { Disk.gb($0.bytes) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let tid, let v = model.verified[tid] { Pill(text: v.result == "plays" ? "Plays" : v.result.capitalized, color: v.result == "plays" ? .green : .orange) }
                        if b != nil { Pill(text: "Built", color: .green) } else { Pill(text: "Not built") }
                        if let played { Pill(text: "\(Playtime.text(played.total)) played") }
                    }
                }
            }
            if let notes, !notes.summary.isEmpty { Text(notes.summary).foregroundStyle(.secondary).lineLimit(5) }
            if let notes, !notes.open.isEmpty {
                Label("\(notes.open.count) open issue\(notes.open.count == 1 ? "" : "s") in its profile", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                Text("Space or Esc closes").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if let b { Button { model.preview = nil; model.openApp(b.app) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.stage) }
                Button("Game Page") { model.openGame(ref) }.buttonStyle(.stagePrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 520)
        .background(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
        .onKeyPress(.space) { model.preview = nil; return .handled }
        .onExitCommand { model.preview = nil }
    }
}

// MARK: What's New

struct WhatsNewSheet: View {
    let model: AppModel
    let news: WhatsNew

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's New in NXForge").font(.title2.weight(.bold))
                    Text("Version \(news.version)").foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(news.entries, id: \.version) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.version).font(.headline)
                            ForEach(Array(e.body.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                                let l = String(line)
                                if l.hasPrefix("- ") {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("•").foregroundStyle(.secondary)
                                        Text(LocalizedStringKey(String(l.dropFirst(2))))
                                    }
                                } else if l.hasPrefix("### ") {
                                    Text(String(l.dropFirst(4))).font(.subheadline.weight(.semibold)).padding(.top, 4)
                                } else if !l.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(LocalizedStringKey(l))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)
            HStack {
                if model.converterUpdate != nil {
                    Button("Update Now…") { model.dismissWhatsNew(); model.updateConverter() }.buttonStyle(.stage)
                }
                Spacer()
                Button("Continue") { model.dismissWhatsNew() }.buttonStyle(.stagePrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 560)
    }
}

// MARK: Go to Anything (⌘K)

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    var icon: String? = nil
    let run: @MainActor () -> Void
}

struct CommandPalette: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var fieldFocused: Bool

    func items() -> [PaletteItem] {
        var out: [PaletteItem] = []
        let m = model
        for p in Page.allCases {
            out.append(PaletteItem(id: "page-\(p.rawValue)", title: p.title, detail: "Page", symbol: p.symbol) { m.showConverter(); m.page = p })
        }
        let builds = m.libraryBuilds()
        var seenApps = Set<String>()
        for g in m.library?.games ?? [] {
            let b = m.build(of: g, in: builds)
            if let a = b?.app { seenApps.insert(a) }
            out.append(PaletteItem(id: "game-\(g.id)", title: g.displayName, detail: [g.console.rawValue, b != nil ? "Built" : "Not built", g.titleID].compactMap { $0 }.joined(separator: " · "),
                                   symbol: "gamecontroller", icon: g.icon) { m.showConverter(); m.page = .library; m.openGame(GameRef(libraryID: g.id, app: b?.app)) })
        }
        for b in Engine.builds() where FileManager.default.fileExists(atPath: b.app) {
            let name = b.app.url.deletingPathExtension().lastPathComponent
            out.append(PaletteItem(id: "play-\(b.app)", title: "Play \(name)", detail: "Open the app", symbol: "play.fill", icon: b.app) { m.openApp(b.app) })
            if !seenApps.contains(b.app) {
                out.append(PaletteItem(id: "build-\(b.app)", title: name, detail: "Built app", symbol: "macwindow", icon: b.app) { m.showConverter(); m.page = .builds; m.openGame(GameRef(libraryID: nil, app: b.app)) })
            }
        }
        out.append(PaletteItem(id: "act-scan", title: "Scan Library Again", detail: "Action", symbol: "arrow.clockwise") { m.showConverter(); m.page = .library; m.scanLibrary() })
        out.append(PaletteItem(id: "act-ipa", title: "Build iPhone and iPad IPA…", detail: "Action", symbol: "iphone") { m.buildIPA() })
        out.append(PaletteItem(id: "act-couch", title: m.couchMode ? "Leave Couch Mode" : "Couch Mode", detail: "Action", symbol: "sofa") { m.toggleCouch() })
        out.append(PaletteItem(id: "act-check", title: "Check the Toolchain Again", detail: "Action", symbol: "checkmark.seal") { m.showConverter(); m.page = .toolchain; m.recheck() })
        out.append(PaletteItem(id: "act-updates", title: "Check for Updates", detail: "Action", symbol: "arrow.down.circle") { m.showConverter(); m.page = .updates; m.engineAction(update: false) })
        out.append(PaletteItem(id: "act-new", title: "What's New in NXForge", detail: "Action", symbol: "sparkles") { m.showWhatsNew() })
        if m.converterUpdate != nil {
            out.append(PaletteItem(id: "act-update", title: "Update NXForge…", detail: "Action", symbol: "arrow.down.circle") { m.updateConverter() })
        }
        let open = openSettings
        out.append(PaletteItem(id: "act-settings", title: "Settings…", detail: "Action", symbol: "gearshape") { open() })
        return out
    }

    /// Words in any order, each found in the title or its detail; titles that start with the query first.
    func results() -> [PaletteItem] {
        let all = items()
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(all.filter { $0.id.hasPrefix("page-") || $0.id.hasPrefix("act-") }) }
        let q = query.lowercased()
        return all.filter { i in let t = (i.title + " " + i.detail).lowercased(); return words.allSatisfy { t.contains($0) } }
            .sorted { a, b in
                let sa = a.title.lowercased().hasPrefix(q), sb = b.title.lowercased().hasPrefix(q)
                return sa != sb ? sa : a.title.count < b.title.count
            }
            .prefix(40).map { $0 }
    }

    var body: some View {
        let list = results()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("Go to a game, a page or an action", text: $query)
                    .textFieldStyle(.plain).font(.title2)
                    .focused($fieldFocused)
                    .onSubmit { run(list) }
                    .onKeyPress(.downArrow) { selected = min(selected + 1, max(list.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            HStack(spacing: 10) {
                                if let ic = item.icon {
                                    if ic.hasSuffix(".app") { AppIcon(path: ic, size: 26) } else { GameIcon(url: ic.url, size: 26).shadow(radius: 0) }
                                } else {
                                    Image(systemName: item.symbol).frame(width: 26)
                                }
                                Text(item.title).lineLimit(1)
                                Spacer()
                                Text(item.detail).font(.callout).foregroundStyle(i == selected ? Color.white.opacity(0.8) : Color.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(i == selected ? Color.white : Color.primary)
                            .background(i == selected ? Color.accentColor : .clear, in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                            .onTapGesture { selected = i; run(list) }
                            .id(i)
                        }
                        if list.isEmpty { Text("Nothing matches “\(query)”").foregroundStyle(.secondary).padding(20) }
                    }
                    .padding(8)
                }
                .onChange(of: selected) { _, s in proxy.scrollTo(s) }
            }
            .frame(height: 340)
        }
        .frame(width: 600)
        .onChange(of: query) { selected = 0 }
        .onAppear { fieldFocused = true }
        .onExitCommand { model.commandPalette = false }
    }

    func run(_ list: [PaletteItem]) {
        guard list.indices.contains(selected) else { return }
        let item = list[selected]
        model.commandPalette = false
        DispatchQueue.main.async { MainActor.assumeIsolated { item.run() } }
    }
}

/// Beside the pages: a newer app or engine release; it opens the Updates page.
struct UpdateCapsule: View {
    let model: AppModel

    var text: String? {
        if model.converterUpdating { return "Updating…" }
        if let u = model.converterUpdate { return "NXForge app \(u.version) available" }
        if let e = model.engineUpdate { return e.release.map { "NXForge \($0) available" } ?? "Engine updates available" }
        return nil
    }

    var body: some View {
        if let text {
            Button { model.page = .updates } label: { Label(text, systemImage: "arrow.down.circle.fill") }
                .buttonStyle(.stagePrimary).controlSize(.small)
                .disabled(model.converterUpdating)
                .help("Show the Updates page")
        }
    }
}
