// The app and its one window. NXC_SNAPSHOT=<file.png> saves a picture of the window a few seconds after it
// opens and quits (NXC_PAGE=library, builds, storage or toolchain for another page; NXC_AUTOBUILD=1 builds the chosen
// folder first, NXC_CONFIRM=1 puts a delete confirmation over it), for checking the layout without a screen capture.
import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        // run straight from the build folder (not a bundle), the process must ask to be a regular app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            Notify.registerCategories()
        }
    }
    /// A notification's button (Play, Show in Finder, Copy Error Summary) or the notification itself
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let action = r.actionIdentifier, cat = r.notification.request.content.categoryIdentifier
        let path = r.notification.request.content.userInfo["path"] as? String
        await MainActor.run { if let m = AppModel.shared { Notify.handle(action, category: cat, path: path, model: m) } }
    }
    /// Shown while the converter is in front too
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    /// Closing the window while a build runs leaves the build going (the Dock icon shows its progress and a notification
    /// says when it ends); otherwise the app quits with its window.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        MainActor.assumeIsolated { AppModel.shared?.run.running != true }
    }
    /// Quitting while a build runs asks first, then stops the build cleanly (its finished steps are kept) before quitting.
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let model = AppModel.shared, model.run.running else { return .terminateNow }
            let kept = model.run.done.filter(\.ok).count
            guard model.confirm("Quit and stop the build?", "\(kept > 0 ? "The \(kept) finished step\(kept == 1 ? " is" : "s are") kept, so building again carries on from there." : "Nothing has finished yet.") To keep building, close the window instead: the build goes on and the Dock icon shows its progress.", action: "Stop and Quit") else { return .terminateCancel }
            model.run.cancel()
            Task { @MainActor in
                for _ in 0..<100 where model.run.running { try? await Task.sleep(for: .milliseconds(200)) }   // up to 20 s for the script to end its stage
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
    /// The Dock icon's menu: recently played games with Play and Rebuild, and the build running now (idea 9)
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated { AppModel.shared?.dockMenu() }
    }
    /// A game folder dropped on the Dock icon (Info.plist lists folders as a document type)
    func application(_ app: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppModel.shared?.openDropped(urls) }
    }
}

struct ConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("NXForge", id: "main") {
            RootView(model: model)
                .frame(minWidth: 820, minHeight: 580)
                .task { await snapshotIfAsked() }
        }
        .defaultSize(width: 1200, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            // About shows the Converter's own version (converter-vX.Y.Z); the engine's NXForge release is its build number
            CommandGroup(replacing: .appInfo) {
                Button("About NXForge") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "NXForge",
                        .applicationVersion: CONVERTER_VERSION,
                        .version: model.engine.map { "engine NXForge \($0.short)" } ?? "",
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Choose Game Folder…") {
                    if let d = model.chooseGame(start: model.settings.gameDir) { model.openDropped([d.url]) }
                }
                .keyboardShortcut("o")
                .disabled(model.run.running)
            }
            // View: the pages on ⌘1…⌘5, above the sidebar and toolbar items
            CommandGroup(before: .sidebar) {
                Button("Games") { model.showStage(.home) }.keyboardShortcut("g")
                Button("Converter") { model.showConverter() }.keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                    Button(p.title) { model.showConverter(); model.page = p }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("NXForge Help") { NSWorkspace.shared.open(helpURL) }
                Button("What's New in NXForge") { model.showWhatsNew() }
                Button("Check for Updates…") { model.page = .updates; model.engineAction(update: false) }.disabled(model.engineBusy || model.engine == nil)
                if model.converterUpdate != nil {
                    Button("Update NXForge…") { model.updateConverter() }
                }
            }
            CommandMenu("Build") {
                Button("Build Mac App") { model.build() }.keyboardShortcut("b").disabled(!model.ready)
                Button("Rebuild") { model.rebuildCurrent() }.keyboardShortcut("r").disabled(model.run.running || !model.allOK)
                Button("Rebuild from Scratch…") { model.rebuildCurrent(scratch: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.run.running || !model.allOK)
                Button("Rebuild All on Older Engines") { model.rebuildAll() }.disabled(model.run.running || !model.allOK || model.outdatedBuilds.isEmpty)
                Button("Build iPhone and iPad IPA…") { model.buildIPA() }.keyboardShortcut("b", modifiers: [.command, .option]).disabled(!model.ready)
                Divider()
                Button("Stop Build…") { model.stopBuild() }.keyboardShortcut(".").disabled(!model.run.running)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Go to Anything…") { model.commandPalette = true }.keyboardShortcut("k")
                Button(model.theatre ? "Leave Theatre" : "Theatre") { model.toggleTheatre() }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(model.gameDetail == nil)
                Divider()
                Button("Bigger Covers") { model.page = .library; model.resizeCovers(by: 30) }.keyboardShortcut("+")
                    .disabled(model.settings.libraryLayout == .grid && model.settings.libraryCoverSize >= Settings.coverSizes.upperBound)
                Button("Smaller Covers") { model.page = .library; model.resizeCovers(by: -30) }.keyboardShortcut("-")
                    .disabled(model.settings.libraryLayout == .grid && model.settings.libraryCoverSize <= Settings.coverSizes.lowerBound)
                Toggle("Group Library by Console", isOn: Binding(get: { model.settings.libraryGroupByConsole }, set: { model.settings.libraryGroupByConsole = $0 }))
            }
        }
        // Settings… (⌘,) in the app menu
        SwiftUI.Settings {
            SettingsPage(model: model)
        }
    }

    @MainActor
    private func snapshotIfAsked() async {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["NXC_SNAPSHOT"] else { return }
        if let p = env["NXC_PAGE"], let page = Page.allCases.first(where: { $0.rawValue.lowercased() == p }) { model.frontEnd = false; model.page = page }
        // NXC_STAGE=home, library, game, back, options, settings, launch, box, gallery or manual: the front end on that screen (game and the ones
        // after it: the first built game's)
        // NXC_STAGE=theatre: Theatre (NXC_THEATRE=carousel, cinema or shelf, NXC_GAME's game in focus; NXC_THEATREMENU=1 its menu); NXC_OFFER=<name>: the TV offer
        if env["NXC_STAGE"] == "theatre" {
            try? await Task.sleep(for: .seconds(2))
            model.enterTheatre(on: nil)
            model.theatreTheme = TheatreTheme(rawValue: (env["NXC_THEATRE"] ?? "").capitalized) ?? .carousel
            if let n = env["NXC_GAME"], let g = model.stageGames().first(where: { $0.name.localizedCaseInsensitiveContains(n) }) { model.theatreFocus = g.id }
            if env["NXC_THEATREMENU"] != nil { model.theatreMenu = TheatreMenuRow.leave.rawValue }
        }
        if let n = env["NXC_OFFER"] { model.theatreOffer = TVScreen(id: 0, name: n) }
        if let st = env["NXC_STAGE"], st != "theatre" {
            model.frontEnd = true
            model.stageTab = st == "library" || st == "discover" ? .discover : .home
            // NXC_BROWSE=all or a genre's name; NXC_QUERY=<words>: what Discover shows
            if st == "library" || st == "discover" {
                if let b = env["NXC_BROWSE"] { model.discover.browse = b == "all" ? .all : .genre(b) }
                if let q = env["NXC_QUERY"] { model.stageSearch = q }
            }
            try? await Task.sleep(for: .seconds(2))
            // NXC_GAME=<part of a name> picks the game instead
            let g = env["NXC_GAME"].flatMap { n in model.stageGames().first { $0.name.localizedCaseInsensitiveContains(n) } } ?? model.stageGames().first { $0.app != nil }
            if let g, ["game", "back", "options"].contains(st) { model.gameDetail = g.ref; model.caseFlipped = st == "back" }
            if let g, st == "options" { model.openPlayOptions(g.ref) }
            if st == "settings" { model.stageSettings = true }
            if let g, st == "launch", let a = g.app { model.launching = Launching(ref: g.ref, app: a, name: g.name, note: nil, summary: "Quality · 60 fps") }
            // launchslow, launchfail: the launch screen taking longer, and after the game closed while starting
            if let g, st == "launchslow" || st == "launchfail", let a = g.app {
                var l = Launching(ref: g.ref, app: a, name: g.name, note: nil, summary: "Quality · 60 fps")
                l.slow = true
                if st == "launchfail" {
                    l.failure = LaunchDiagnosis.diagnose("[dm] [nvn-mtl] [RED] GPU memory guard: 17300 MB, against Metal's working set of 18186 MB: stopping the game before the driver cannot wire more\nlauncher: the host exited with 1\n",
                                                         log: g.titleID.map { LaunchDiagnosis.logPath(titleID: $0) })
                }
                model.launching = l
            }
            // box, gallery (NXC_INDEX=<n>: which picture or trailer; the store's, else the game's screenshots) and manual: the viewers
            if let g, ["box", "gallery", "manual"].contains(st) {
                model.gameDetail = g.ref
                if st == "box" {
                    model.openCaseViewer(g)
                    if env["NXC_BACK"] != nil { model.caseCommand(.back) }
                    // NXC_TURN=<radians>: turned and tipped back a little, to see the edges
                    if let t = env["NXC_TURN"].flatMap(Double.init) { try? await Task.sleep(for: .seconds(1)); model.caseCommand(.turn(t, -0.3)) }
                    if let z = env["NXC_ZOOM"].flatMap(Double.init) { try? await Task.sleep(for: .seconds(1)); model.caseCommand(.zoom(z)) }
                }
                if st == "manual", let m = GameManual.find(g) { model.openManual(m, title: g.name) }
                if st == "gallery" {
                    let store = StoreInfoStore.shared
                    store.load(key: g.coverKey, titleID: g.titleID, name: g.name)
                    for _ in 0..<60 where store.shots(g.coverKey).count < 2 || store.info(g.coverKey)?.trailers == nil { try? await Task.sleep(for: .milliseconds(500)) }
                    var items: [GalleryItem] = store.videos(g.coverKey).map { .video($0.video, thumb: $0.thumb) } + store.shots(g.coverKey).map { .image($0) }
                    if items.isEmpty, let a = g.app { items = GameCaptures.screenshots(app: a).map { .image($0) } }
                    model.openGallery(items, at: Int(env["NXC_INDEX"] ?? "") ?? 0, title: "\(g.name) · From the store")
                    if let z = env["NXC_ZOOM"], let n = Int(z) { for _ in 0..<n { model.gallery?.zoomIn = true; model.gallery?.zoomStep += 1; try? await Task.sleep(for: .milliseconds(300)) } }
                }
            }
        }
        // NXC_CONVERT=<part of a name>: that Game Files game on the Convert page (settings are not saved while it is set);
        // NXC_OPTIONS=1 opens Build options, NXC_FOCUS=<part of a name> focuses a Game Files row
        if let n = env["NXC_CONVERT"], let g = model.library?.games.first(where: { $0.displayName.localizedCaseInsensitiveContains(n) }) {
            model.setGameDir(g.path)
            try? await Task.sleep(for: .seconds(3))
        }
        if let n = env["NXC_FOCUS"], let g = model.library?.games.first(where: { $0.displayName.localizedCaseInsensitiveContains(n) }) { model.libraryFocus = g.id }
        // NXC_SCOPE=built: Discover's Built collection
        if env["NXC_SCOPE"] == "built" { model.stageScope = .built }
        // NXC_BUILDSTRIP=1: a build running (pretend: nothing runs) for the strip along the foot of the window, on NXC_GAME's game
        if env["NXC_BUILDSTRIP"] != nil, !model.run.running {
            try? await Task.sleep(for: .seconds(1))
            if let g = env["NXC_GAME"].flatMap({ n in model.library?.games.first { $0.displayName.localizedCaseInsensitiveContains(n) } }) ?? model.library?.games.first(where: { g in !model.stageGames().contains { $0.game?.id == g.id && $0.app != nil } }) {
                model.snapshotBuildDir = g.path
            }
            let r = model.run
            r.running = true
            r.expected = ["Mac shaders": 2400, "Mac host": 240, "Mac app": 180, "Pipeline archive": 900]
            r.startedAt = Date().addingTimeInterval(-1260)
            r.stageStartedAt = Date().addingTimeInterval(-300)
            r.stage = Stage(k: 5, n: 9, name: "Mac shaders", step: "compiling", fraction: 0.36, detail: "1240/3412 shaders", eta: 1150)
        }
        // NXC_DETAIL=1 with NXC_PAGE=library or builds: the converter's page of the first built game
        if env["NXC_DETAIL"] != nil, env["NXC_STAGE"] == nil {
            try? await Task.sleep(for: .seconds(2))
            if let g = model.stageGames().first(where: { $0.app != nil }) { model.openGame(g.ref) }
        }
        // NXC_SHEET=controllers, keeps, recap or cheats: that sheet (or the recap card) over the window
        switch env["NXC_SHEET"] {
        case "controllers": model.showControllerTest = true
        case "keeps": model.showLeftovers = true
        case "recap": model.recap = SessionRecap.sample
        // cheats: the Cheats sheet of NXC_GAME's game (else the first one with a title ID)
        case "cheats":
            try? await Task.sleep(for: .seconds(2))
            let games = model.stageGames()
            if let g = env["NXC_GAME"].flatMap({ n in games.first { $0.name.localizedCaseInsensitiveContains(n) } }) ?? games.first(where: { $0.titleID != nil }) { model.cheatsFor = g.ref }
        default: break
        }
        try? await Task.sleep(for: .seconds(5))
        // NXC_CONFIRM=1 puts a delete confirmation over the window, to check how its buttons draw
        if env["NXC_CONFIRM"] != nil {
            DispatchQueue.main.async { [model] in
                _ = model.confirm("Delete shared metal shader cache (14 GB)?", "~/Library/Caches/NXForge is deleted permanently. Compiled shaders shared by every game.", action: "Delete")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        if env["NXC_AUTOBUILD"] != nil {
            while !model.ready && model.run.result == nil { try? await Task.sleep(for: .milliseconds(300)) }
            model.build()
            // a successful build clears its result as it hands the app to Builds, so wait for the run to end instead
            try? await Task.sleep(for: .seconds(1))
            while model.run.running { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(1))
        }
        // the window can be ordered out for a moment when the app starts behind another one: bring it back rather than give up
        guard let w = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first(where: { $0.contentView != nil }) else { exit(1) }
        if !w.isVisible { NSApp.unhide(nil); w.orderFrontRegardless(); try? await Task.sleep(for: .seconds(1)) }
        // NXC_WINSIZE=<w>x<h>: the window at that size, e.g. a short one to check that the Settings panel scrolls
        if let sz = env["NXC_WINSIZE"]?.split(separator: "x").compactMap({ Double($0) }), sz.count == 2 {
            w.setContentSize(NSSize(width: sz[0], height: sz[1])); try? await Task.sleep(for: .seconds(1))
        }
        // NXC_SETTINGSROW=<n>: the Settings panel scrolled to the nth row, as a controller moving down it does
        if let n = env["NXC_SETTINGSROW"].flatMap(Int.init) { model.settingsFocus = n; try? await Task.sleep(for: .seconds(1)) }
        // a sheet over the window (NXC_SHEET) is a window of its own: picture that
        let shown = env["NXC_SHEET"] != nil ? (w.attachedSheet ?? w) : w
        guard let view = shown.contentView?.superview ?? shown.contentView else { exit(1) }
        // the window's number for `screencapture -l`, which shows the glass the way the screen does; the picture below is the fallback
        try? String(shown.windowNumber).write(toFile: out + ".wid", atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(4))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        exit(0)
    }
}
