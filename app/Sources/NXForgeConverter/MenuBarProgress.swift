// The build in the menu bar (idea 9): while a build runs, a hammer and the percentage sit in the menu bar; its window has the
// game, the bar with the time left, the step, Show Window, Show Log and Stop Build. The window can stay closed meanwhile.
import AppKit
import SwiftUI

/// The status item itself, in AppKit: SwiftUI's MenuBarExtra kept redrawing its button from launch (a hang at start in 0.2.0's
/// first builds), so the item is made only while a build runs, and its title set only when the percent changes.
@MainActor
enum StatusProgress {
    private static var item: NSStatusItem?
    private static var popover: NSPopover?
    private static var shown = -1

    /// Called on every change of the run, beside DockProgress.show.
    static func show(_ model: AppModel) {
        let run = model.run
        guard run.running, !run.planning else {
            if let i = item { NSStatusBar.system.removeStatusItem(i); item = nil; popover?.close(); popover = nil; shown = -1 }
            return
        }
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Build progress")
            i.button?.imagePosition = .imageLeading
            i.button?.target = Handler.shared
            i.button?.action = #selector(Handler.toggle(_:))
            item = i
            let p = NSPopover()
            p.behavior = .transient
            p.contentViewController = NSHostingController(rootView: MenuBarProgress(model: model))
            popover = p
        }
        let pct = Int((run.overall().fraction * 100).rounded())
        if pct != shown { shown = pct; item?.button?.title = " \(pct)%" }
    }

    final class Handler: NSObject {
        static let shared = Handler()
        @objc func toggle(_ sender: NSStatusBarButton) {
            MainActor.assumeIsolated {
                guard let p = StatusProgress.popover else { return }
                if p.isShown { p.performClose(nil) } else { p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY) }
            }
        }
    }
}

struct MenuBarProgress: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            let run = model.run
            let o = run.overall(now: ctx.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let icon = model.game?.icon { GameIcon(url: icon, size: 40) } else { IconTile(symbol: "hammer", size: 40) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.batchCurrent?.displayName ?? model.game?.name ?? "Building").font(.headline).lineLimit(1)
                        Text(model.batchQueue.isEmpty ? "Building a Mac app" : "Build selected · \(model.batchQueue.count) to go").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: o.fraction)
                HStack {
                    Text(o.remaining.map(timeLeft) ?? "Working out the time left…")
                    Spacer()
                    Text("\(Int((o.fraction * 100).rounded()))%").monospacedDigit()
                }
                .font(.callout)
                if run.stage.k > 0 {
                    Text("Step \(run.stage.k) of \(run.stage.n): \(friendly(run.stage.name))\(run.stage.step.isEmpty ? "" : " · \(run.stage.step)")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let w = model.diskWarning { Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Divider()
                HStack {
                    Button("Show Window") { show(.convert) }
                    Button("Show Log") { show(.convert) }
                    Spacer()
                    Button("Stop Build…") { NSApp.activate(); model.stopBuild() }
                }
                .buttonStyle(.stage)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    func show(_ p: Page) {
        model.page = p
        model.gameDetail = nil
        NSApp.activate()
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        }
    }
}
