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
                    Button(p.rawValue) { model.showConverter(); model.page = p }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
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
                Button("Rebuild All on Older Engines") { model.rebuildAll() }.disabled(model.run.running || !model.allOK || model.outdatedBuilds.isEmpty)
                Button("Build iPhone and iPad IPA…") { model.buildIPA() }.keyboardShortcut("b", modifiers: [.command, .option]).disabled(!model.ready)
                Divider()
                Button("Stop Build…") { model.stopBuild() }.keyboardShortcut(".").disabled(!model.run.running)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Go to Anything…") { model.commandPalette = true }.keyboardShortcut("k")
                Button(model.couchMode ? "Leave Couch Mode" : "Couch Mode") { model.toggleCouch() }.keyboardShortcut("f", modifiers: [.command, .shift])
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
        if let p = env["NXC_PAGE"], let page = Page.allCases.first(where: { $0.rawValue.lowercased() == p }) { model.page = page }
        // NXC_STAGE=home, library, game, back, options, settings or launch: the front end on that screen (game and the ones
        // after it: the first built game's)
        if let st = env["NXC_STAGE"] {
            model.frontEnd = true
            model.stageTab = st == "library" ? .library : .home
            try? await Task.sleep(for: .seconds(2))
            // NXC_GAME=<part of a name> picks the game instead
            let g = env["NXC_GAME"].flatMap { n in model.stageGames().first { $0.name.localizedCaseInsensitiveContains(n) } } ?? model.stageGames().first { $0.app != nil }
            if let g, ["game", "back", "options"].contains(st) { model.gameDetail = g.ref; model.caseFlipped = st == "back" }
            if let g, st == "options" { model.openPlayOptions(g.ref) }
            if st == "settings" { model.stageSettings = true }
            if let g, st == "launch", let a = g.app { model.launching = Launching(ref: g.ref, app: a, name: g.name, note: nil, summary: "Quality · 60 fps") }
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
        guard let view = w.contentView?.superview ?? w.contentView else { exit(1) }
        // the window's number for `screencapture -l`, which shows the glass the way the screen does; the picture below is the fallback
        try? String(w.windowNumber).write(toFile: out + ".wid", atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(4))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        exit(0)
    }
}
