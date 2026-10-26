// The app and its one window. NXC_SNAPSHOT=<file.png> saves a picture of the window a few seconds after it
// opens and quits (NXC_PAGE=builds, toolchain or settings for another page; NXC_AUTOBUILD=1 builds the chosen
// folder first), for checking the layout without a screen capture.
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        // run straight from the build folder (not a bundle), the process must ask to be a regular app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
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
                .frame(minWidth: 1080, minHeight: 720)
                .task { await snapshotIfAsked() }
        }
        .defaultSize(width: 1280, height: 980)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Game Folder…") {
                    if let d = model.choose(folder: true, start: model.settings.gameDir) { model.openDropped([d.url]) }
                }
                .keyboardShortcut("o")
                .disabled(model.run.running)
            }
            CommandMenu("Build") {
                Button("Build Mac App") { model.build() }.keyboardShortcut("b").disabled(!model.ready)
                Button("Rebuild") { model.rebuildCurrent() }.keyboardShortcut("r").disabled(model.run.running || !model.allOK)
                Button("Rebuild All on Older Engines") { model.rebuildAll() }.disabled(model.run.running || !model.allOK || model.outdatedBuilds.isEmpty)
                Divider()
                Button("Stop Build") { model.run.cancel() }.keyboardShortcut(".").disabled(!model.run.running)
            }
        }
    }

    @MainActor
    private func snapshotIfAsked() async {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["NXC_SNAPSHOT"] else { return }
        if let p = env["NXC_PAGE"], let page = Page.allCases.first(where: { $0.rawValue.lowercased() == p }) { model.page = page }
        try? await Task.sleep(for: .seconds(5))
        if env["NXC_AUTOBUILD"] != nil {
            while !model.ready && model.run.result == nil { try? await Task.sleep(for: .milliseconds(300)) }
            model.build()
            // a successful build clears its result as it hands the app to Builds, so wait for the run to end instead
            try? await Task.sleep(for: .seconds(1))
            while model.run.running { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(1))
        }
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let view = w.contentView?.superview ?? w.contentView else { exit(1) }
        // the window's number for `screencapture -l`, which shows the glass the way the screen does; the picture below is the fallback
        try? String(w.windowNumber).write(toFile: out + ".wid", atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(4))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        exit(0)
    }
}
