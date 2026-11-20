// The pieces over the pages: Go to Anything (⌘K, idea 15), the quick preview (Space, 18), What's New (1), and the controller.
// The controller works whenever NXForge is the active app: on Theatre (Theatre.swift) and the front end every button goes to
// them (theatrePad, stagePad); on the converter's pages the pad moves between games, A opens a game's page (and on its page
// plays it), B goes back, X plays, Y previews, and Menu opens Theatre (as ⇧⌘F does).
import AppKit
import GameController
import SwiftUI

extension AppModel {
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
    /// a held direction repeats (after 0.42 s, every 0.13 s), as a list does under a held arrow key
    private var repeats: [ObjectIdentifier: Timer] = [:]
    /// buttons already down when NXForge could not take them (held as a game quit and NXForge came to the front, or while a
    /// sheet or a text field had the keyboard): they do nothing until they are let go (from RetroReplay's ControllerNavigation)
    private var awaitingRelease: Set<ObjectIdentifier> = []

    /// Whether the pad may act now: NXForge in front, no modal window or sheet over it, and no text being typed
    static func mayAct() -> Bool {
        guard NSApp.isActive, NSApp.modalWindow == nil else { return false }
        if let w = NSApp.keyWindow {
            if w.attachedSheet != nil { return false }
            if w.firstResponder is NSTextView { return false }
        }
        return true
    }

    /// Every button down now waits for its release (NXForge just came to the front)
    func holdPressed() {
        for c in GCController.controllers() {
            guard let p = c.extendedGamepad else { continue }
            for b in Self.buttons(p) where b.isPressed { awaitingRelease.insert(ObjectIdentifier(b)) }
        }
        for t in repeats.values { t.invalidate() }
        repeats.removeAll()
    }

    static func buttons(_ p: GCExtendedGamepad) -> [GCControllerButtonInput] {
        [p.buttonA, p.buttonB, p.buttonX, p.buttonY, p.leftShoulder, p.rightShoulder, p.leftTrigger, p.rightTrigger, p.buttonMenu,
         p.dpad.left, p.dpad.right, p.dpad.up, p.dpad.down, p.leftThumbstick.left, p.leftThumbstick.right, p.leftThumbstick.up, p.leftThumbstick.down,
         p.rightThumbstick.up, p.rightThumbstick.down]
            + [p.buttonOptions, p.rightThumbstickButton].compactMap { $0 }
    }

    /// A press that may act: false (and the button waits for its release) when it was held over from before or NXForge cannot take it now
    private func accept(_ b: GCControllerButtonInput, pressed: Bool) -> Bool {
        let id = ObjectIdentifier(b)
        guard pressed else { awaitingRelease.remove(id); return false }
        if awaitingRelease.contains(id) { return false }
        guard Self.mayAct() else { awaitingRelease.insert(id); return false }
        return true
    }

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        GCController.shouldMonitorBackgroundEvents = false
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            let c = n.object as? GCController
            MainActor.assumeIsolated {
                if let c { self?.attach(c) }
                TheatreWatch.shared.check()   // a controller picked up while a TV is plugged in: Theatre is offered then
            }
        })
        observers.append(nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PadLabels.shared.refresh() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.holdPressed() }
        })
        for c in GCController.controllers() { attach(c) }
        GCController.startWirelessControllerDiscovery {}
    }

    private func attach(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        c.handlerQueue = .main
        PadLabels.shared.refresh()
        for b in Self.buttons(pad) where b.isPressed { awaitingRelease.insert(ObjectIdentifier(b)) }
        func on(_ b: GCControllerButtonInput, _ f: @escaping @MainActor (AppModel) -> Void) {
            b.pressedChangedHandler = { [weak self] btn, _, pressed in
                MainActor.assumeIsolated {
                    guard let self, self.accept(btn, pressed: pressed), let m = self.model else { return }
                    f(m)
                }
            }
        }
        func held(_ b: GCControllerButtonInput, _ f: @escaping @MainActor (AppModel) -> Void) {
            b.pressedChangedHandler = { [weak self] btn, _, pressed in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let id = ObjectIdentifier(btn)
                    self.repeats[id]?.invalidate()
                    self.repeats[id] = nil
                    guard self.accept(btn, pressed: pressed), let m = self.model else { return }
                    f(m)
                    let t = Timer(timeInterval: 0.13, repeats: true) { [weak self] t in
                        MainActor.assumeIsolated {
                            guard ControllerNav.mayAct(), let m = self?.model else { t.invalidate(); return }
                            f(m)
                        }
                    }
                    t.fireDate = Date().addingTimeInterval(0.42)
                    RunLoop.main.add(t, forMode: .common)
                    self.repeats[id] = t
                }
            }
        }
        // the front end takes every button (stagePad); the converter's pages keep the old pad map
        func key(_ b: GCControllerButtonInput, _ k: PadKey, repeating: Bool = false, _ f: @escaping @MainActor (AppModel) -> Void) {
            let act: @MainActor (AppModel) -> Void = { m in
                if m.controllerTest { return }
                if m.theatre { m.theatrePad(k) }
                else if m.theatreOffer != nil { m.offerPad(k) }
                else if m.frontEnd { m.stagePad(k) } else { f(m) }
            }
            if repeating { held(b, act) } else { on(b, act) }
        }
        key(pad.dpad.left, .left, repeating: true) { $0.moveLibraryFocus(dx: -1) }
        key(pad.dpad.right, .right, repeating: true) { $0.moveLibraryFocus(dx: 1) }
        key(pad.dpad.up, .up, repeating: true) { $0.moveLibraryFocus(dy: -1) }
        key(pad.dpad.down, .down, repeating: true) { $0.moveLibraryFocus(dy: 1) }
        key(pad.leftThumbstick.left, .left, repeating: true) { $0.moveLibraryFocus(dx: -1) }
        key(pad.leftThumbstick.right, .right, repeating: true) { $0.moveLibraryFocus(dx: 1) }
        key(pad.leftThumbstick.up, .up, repeating: true) { $0.moveLibraryFocus(dy: -1) }
        key(pad.leftThumbstick.down, .down, repeating: true) { $0.moveLibraryFocus(dy: 1) }
        key(pad.buttonA, .a) { m in
            if let p = m.preview { m.openGame(p) }
            else if let g = m.gameDetail { m.play(g) }
            else if let r = m.focusedGame() { m.showConverter(); m.page = .library; m.openGame(r) }
        }
        key(pad.buttonB, .b) { m in
            if m.preview != nil { m.preview = nil }
            else if m.gameDetail != nil { m.goBack() }

        }
        key(pad.buttonX, .x) { m in if let r = m.gameDetail ?? m.focusedGame() { m.play(r) } }
        key(pad.buttonY, .y) { m in m.preview = m.preview == nil ? m.focusedGame() : nil }
        key(pad.leftShoulder, .l) { _ in }
        key(pad.rightShoulder, .r) { _ in }
        // Theatre: the triggers switch the theme, the right stick's press mutes and up and down set the volume
        key(pad.leftTrigger, .zl) { _ in }
        key(pad.rightTrigger, .zr) { _ in }
        if let r3 = pad.rightThumbstickButton { key(r3, .r3) { _ in } }
        // Theatre: the left stick's press spins for a game to play
        if let l3 = pad.leftThumbstickButton { key(l3, .l3) { _ in } }
        key(pad.rightThumbstick.up, .volUp, repeating: true) { _ in }
        key(pad.rightThumbstick.down, .volDown, repeating: true) { _ in }
        key(pad.buttonMenu, .menu) { $0.enterTheatre() }
        // − (Options / View): Favourites on the front end
        if let o = pad.buttonOptions { key(o, .options) { _ in } }
        // the right stick turns the box on screen (CaseModelView)
        pad.rightThumbstick.valueChangedHandler = { _, x, y in
            CaseStick.x = NSApp.isActive ? Double(x) : 0
            CaseStick.y = NSApp.isActive ? Double(y) : 0
        }
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
    /// when the game was last played, for the order among equal matches
    var last: Date? = nil
    let run: @MainActor () -> Void
}

struct CommandPalette: View {
    @Bindable var model: AppModel
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
        let plays = Playtime.load()
        var seenApps = Set<String>()
        for g in m.library?.games ?? [] {
            let b = m.build(of: g, in: builds)
            if let a = b?.app { seenApps.insert(a) }
            out.append(PaletteItem(id: "game-\(g.id)", title: g.displayName, detail: [g.console.rawValue, b != nil ? "Built" : "Not built", g.titleID].compactMap { $0 }.joined(separator: " · "),
                                   symbol: "gamecontroller", icon: g.icon, last: (g.titleID.flatMap { plays[$0] } ?? b.flatMap { plays[$0.app] })?.last) { m.showConverter(); m.page = .library; m.openGame(GameRef(libraryID: g.id, app: b?.app)) })
        }
        for b in Engine.builds() where FileManager.default.fileExists(atPath: b.app) {
            let name = b.app.url.deletingPathExtension().lastPathComponent
            let lastPlayed = (VerifiedGames.titleID(ofApp: b.app).flatMap { plays[$0] } ?? plays[b.app])?.last
            out.append(PaletteItem(id: "play-\(b.app)", title: "Play \(name)", detail: "Open the app", symbol: "play.fill", icon: b.app, last: lastPlayed) { m.openApp(b.app) })
            if !seenApps.contains(b.app) {
                out.append(PaletteItem(id: "build-\(b.app)", title: name, detail: "Built app", symbol: "macwindow", icon: b.app) { m.showConverter(); m.page = .builds; m.openGame(GameRef(libraryID: nil, app: b.app)) })
            }
        }
        out.append(PaletteItem(id: "act-scan", title: "Refresh Library", detail: "Action", symbol: "arrow.clockwise") { m.showConverter(); m.page = .library; m.scanLibrary() })
        out.append(PaletteItem(id: "act-ipa", title: "Build iPhone and iPad IPA…", detail: "Action", symbol: "iphone") { m.buildIPA() })
        out.append(PaletteItem(id: "act-theatre", title: m.theatre ? "Leave Theatre" : "Theatre", detail: "Action", symbol: "tv") { m.toggleTheatre() })
        out.append(PaletteItem(id: "act-check", title: "Check the Toolchain Again", detail: "Action", symbol: "checkmark.seal") { m.showConverter(); m.page = .toolchain; m.recheck() })
        out.append(PaletteItem(id: "act-updates", title: "Check for Updates", detail: "Action", symbol: "arrow.down.circle") { m.showConverter(); m.page = .updates; m.engineAction(update: false) })
        out.append(PaletteItem(id: "act-new", title: "What's New in NXForge", detail: "Action", symbol: "sparkles") { m.showWhatsNew() })
        if m.converterUpdate != nil {
            out.append(PaletteItem(id: "act-update", title: "Update NXForge…", detail: "Action", symbol: "arrow.down.circle") { m.updateConverter() })
        }
        out.append(PaletteItem(id: "act-settings", title: "Settings…", detail: "Action", symbol: "gearshape") { m.openSettings() })
        return out
    }

    /// Words in any order, each found in the title or its detail, with case and accents folded ("pokemon" finds Pokémon); a title
    /// that starts with them first (a leading "The" passed over), then one with a later word that does, then the game played last.
    /// With nothing typed: the pages and actions, after the games played most recently.
    func results() -> [PaletteItem] {
        let all = items()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !TitleMatch.fold(q).isEmpty else {
            let recent = all.filter { $0.id.hasPrefix("game-") && $0.last != nil }.sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }.prefix(5)
            return Array(recent) + all.filter { $0.id.hasPrefix("page-") || $0.id.hasPrefix("act-") }
        }
        let hits = all.filter { TitleMatch.matches(q, [$0.title, $0.detail]) }
        // "Play X" ranks by X
        return TitleMatch.sorted(hits, query: q, title: { $0.title.hasPrefix("Play ") ? String($0.title.dropFirst(5)) : $0.title }, last: \.last)
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
