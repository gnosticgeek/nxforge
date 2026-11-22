// The build along the foot of the window: while a game builds, a strip under every page (the front end's and the converter's)
// says which game, the step, how many files, the time left and how far it is, with View Build and Stop, so a build stays in
// sight wherever you are. The Convert page shows the build itself, so the strip steps aside there.
import AppKit
import SwiftUI

extension AppModel {
    /// The strip shows: a build (not a Preview) is running, and the Convert page with the build on it is not on screen.
    var showsBuildStrip: Bool {
        guard run.running, !run.planning, !standby else { return false }
        return frontEnd || page != .convert || gameDetail != nil
    }

    /// The game folder being built.
    var buildingDir: String { snapshotBuildDir ?? settings.gameDir ?? "" }

    /// The game being built, by its Library name, else its folder's.
    var buildingName: String {
        let dir = buildingDir
        if let g = library?.games.first(where: { $0.path == dir || $0.folder == dir }) { return g.displayName }
        return dir.isEmpty ? "your game" : dir.lastComponent
    }

    /// The Convert page with the build on it.
    func viewBuild() {
        if frontEnd { showConverter() }
        gameDetail = nil
        page = .convert
    }
}

struct BuildStrip: View {
    @Bindable var model: AppModel
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.14)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            let run = model.run
            let o = run.overall(now: ctx.date)
            let pct = Int((o.fraction * 100).rounded())
            let step = friendly(run.stage.name)
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 3)
                    Circle().trim(from: 0, to: max(o.fraction, 0.02))
                        .stroke(Self.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "hammer.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Self.amber)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Building \(model.buildingName)").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        if !model.batchQueue.isEmpty {
                            Text("· \(model.batchQueue.count) more queued").font(.system(size: 12.5)).foregroundStyle(StageLook.faint).lineLimit(1)
                        }
                    }
                    Text(line(run, step: step)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(StageLook.soft).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 10) {
                        if let r = o.remaining ?? run.stage.eta { Text(o.remaining == nil ? "\(timeLeft(r)) in this step" : timeLeft(r)).font(.system(size: 12.5)).foregroundStyle(StageLook.soft).lineLimit(1) }
                        Text("\(pct)%").font(.system(size: 14, weight: .bold).monospacedDigit())
                    }
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.12))
                            .overlay(alignment: .leading) { Capsule().fill(Self.amber).frame(width: max(geo.size.width * o.fraction, 4)) }
                    }
                    .frame(width: 220, height: 4)
                }
                Button("View Build") { model.viewBuild() }.buttonStyle(StageButton(height: 32))
                    .help("The Convert page, with every step and the log")
                Button(model.run.held ? "Resume" : "Pause") { model.pauseBuild() }.buttonStyle(StageButton(height: 32))
                    .disabled(model.run.paused && !model.run.held)
                    .help(model.run.held ? "Carry on from where the build was paused" : "Hold the build where it is. Nothing is lost, and Resume carries on from the same point.")
                Button("Stop") { model.stopBuild() }.buttonStyle(StageButton(height: 32))
                    .help("Stop the build. The finished steps are kept, so building again carries on.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Building \(model.buildingName), \(pct) percent")
        }
        .padding(.horizontal, 28).frame(height: 60)
        .background(StageLook.panel.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
        .foregroundStyle(.white)
    }

    /// "Step 4 of 9 · Mac shaders · 1,240/3,412 files"
    func line(_ run: BuildRun, step: String) -> String {
        var parts = run.paused ? ["Paused"] : []
        parts += ["Step \(max(run.stage.k, 1)) of \(max(run.stage.n, 1))"]
        if !step.isEmpty { parts.append(step) }
        if !run.stage.detail.isEmpty { parts.append(run.stage.detail) }
        else if !run.stage.step.isEmpty { parts.append(run.stage.step) }
        return parts.joined(separator: " · ")
    }
}
