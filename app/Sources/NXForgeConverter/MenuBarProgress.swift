// The build in the menu bar (idea 9): while a build runs, a hammer and the percentage sit in the menu bar; its window has the
// game, the bar with the time left, the step, Show Window, Show Log and Stop Build. The window can stay closed meanwhile.
import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        // no timer here: a TimelineView in a menu bar label keeps SwiftUI redrawing it from launch; the run's own changes
        // (each log line) redraw it often enough
        let pct = model.run.running ? Int((model.run.overall().fraction * 100).rounded()) : 0
        Label("\(pct)%", systemImage: "hammer.fill").labelStyle(.titleAndIcon)
    }
}

struct MenuBarProgress: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

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
                .buttonStyle(.glass)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    func show(_ p: Page) {
        model.page = p
        model.gameDetail = nil
        openWindow(id: "main")
        NSApp.activate()
    }
}
