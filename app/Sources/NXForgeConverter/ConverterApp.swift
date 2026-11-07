// The app and its one window. NXC_SNAPSHOT=<file.png> saves a picture of the window a few seconds after it
// opens and quits (NXC_PAGE=library, builds, storage or toolchain for another page, settings for the Settings window; NXC_AUTOBUILD=1 builds the chosen
// folder first), for checking the layout without a screen capture.
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        // run straight from the build folder (not a bundle), the process must ask to be a regular app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
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
    /// A game folder dropped on the Dock icon (Info.plist lists folders as a document type)
    func application(_ app: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppModel.shared?.openDropped(urls) }
    }
}

struct ConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("NXForge Converter", id: "main") {
            RootView(model: model)
                .frame(minWidth: 820, minHeight: 580)
                .task { await snapshotIfAsked() }
        }
        .defaultSize(width: 1200, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Game Folder…") {
                    if let d = model.chooseGame(start: model.settings.gameDir) { model.openDropped([d.url]) }
                }
                .keyboardShortcut("o")
                .disabled(model.run.running)
            }
            // View: the pages on ⌘1…⌘5, above the sidebar and toolbar items
            CommandGroup(before: .sidebar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                    Button(p.rawValue) { model.page = p }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("NXForge Converter Help") { NSWorkspace.shared.open(helpURL) }
            }
            CommandMenu("Build") {
                Button("Build Mac App") { model.build() }.keyboardShortcut("b").disabled(!model.ready)
                Button("Rebuild") { model.rebuildCurrent() }.keyboardShortcut("r").disabled(model.run.running || !model.allOK)
                Button("Rebuild All on Older Engines") { model.rebuildAll() }.disabled(model.run.running || !model.allOK || model.outdatedBuilds.isEmpty)
                Divider()
                Button("Stop Build…") { model.stopBuild() }.keyboardShortcut(".").disabled(!model.run.running)
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
        if env["NXC_PAGE"] == "settings" { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
        try? await Task.sleep(for: .seconds(5))
        if env["NXC_AUTOBUILD"] != nil {
            while !model.ready && model.run.result == nil { try? await Task.sleep(for: .milliseconds(300)) }
            model.build()
            // a successful build clears its result as it hands the app to Builds, so wait for the run to end instead
            try? await Task.sleep(for: .seconds(1))
            while model.run.running { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(1))
        }
        // the window can be ordered out for a moment when the app starts behind another one: bring it back rather than give up
        guard let w = (env["NXC_PAGE"] == "settings" ? NSApp.keyWindow : nil) ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first(where: { $0.contentView != nil }) else { exit(1) }
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
