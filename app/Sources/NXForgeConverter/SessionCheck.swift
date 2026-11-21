// A check after every session: when a game quits, scripts/perf_check.py reads its log (the share of frames shown on time, GPU
// time, heat, memory), adds the session to the game's history and says whether it ran worse than its usual. When it did, the
// recap card and the game's page say why in plain words and offer the one change most likely to help. The newest slower
// session per game is kept in session-checks.json until a later session runs as usual or the note is dismissed.
import Foundation
import SwiftUI

struct SessionCheck: Codable, Equatable {
    var titleID: String
    var ended: Int
    var verdict: String
    var onTime: Double?
    var usual: Double?
    var frames: Int
    var gpuP50: Double?
    var upscale: String
    var thermalMax: Int
    var lowPower: Bool
    var battery: Bool
    var footprintMB: Double
    var held: Int

    var slower: Bool { verdict == "slower" }

    /// "91 % of frames on time, usually 98 %"
    var numbers: String {
        let now = onTime.map { String(format: "%.0f %% of frames on time", $0) } ?? "Few frames on time"
        return usual.map { now + String(format: ", usually %.0f %%", $0) } ?? now
    }

    /// The likeliest reason, in plain words (the order perf_check.py's causes come in, with what the player can do about each)
    var why: String {
        if lowPower { return "Low Power Mode was on, which holds the Mac back. Turn it off or plug in for full speed." }
        if thermalMax >= 2 { return "The Mac ran hot and slowed itself down. A lower render scale keeps it cooler." }
        if footprintMB > 14000 { return String(format: "Memory was nearly full (%.1f GB for the game). Close other apps before playing.", footprintMB / 1024) }
        if let g = gpuP50, g > 14.5 { return String(format: "The graphics chip was at its limit (%.1f ms of each 16.7 ms frame).", g) }
        if battery { return "The Mac was on its battery, where it runs slower." }
        if held > 0 { return "The game missed frames and dropped to a lower frame rate for a while." }
        return "Nothing in the log stands out. Other apps working in the background can cost frames."
    }
}

/// One change to a Play option that should help a slower session
struct SessionFix: Equatable {
    var label: String
    var env: String
    var value: String
}

enum SessionChecks {
    static var file: URL { Settings.supportDir.appending(path: "session-checks.json") }

    /// perf_check.py --json: a list of sessions, each a flat object
    static func decode(_ json: Data) -> [SessionCheck] {
        guard let rows = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let t = r["title_id"] as? String, let v = r["verdict"] as? String else { return nil }
            func num(_ k: String) -> Double? { (r[k] as? NSNumber)?.doubleValue }
            return SessionCheck(titleID: t.uppercased(), ended: Int(num("ended") ?? 0), verdict: v, onTime: num("on_time"), usual: num("usual"), frames: Int(num("frames") ?? 0),
                                gpuP50: num("gpu_p50"), upscale: r["upscale"] as? String ?? "", thermalMax: Int(num("thermal_max") ?? 0), lowPower: r["low_power"] as? Bool ?? false,
                                battery: r["battery"] as? Bool ?? false, footprintMB: num("footprint_mb") ?? 0, held: Int((num("held2") ?? 0) + (num("held3") ?? 0)))
        }
    }

    /// The first change that applies, cheapest to the picture first: frame interpolation off, MetalFX off, then the render scale
    /// one step down (a quarter, never under the setting's lowest). Nothing when the cause is not the graphics load (Low Power
    /// Mode, memory), or when no such option is left to change.
    static func fix(_ c: SessionCheck, settings: [LaunchSetting], values: [String: String]) -> SessionFix? {
        guard c.slower, !c.lowPower, c.footprintMB <= 14000 || c.thermalMax >= 2 else { return nil }
        func now(_ s: LaunchSetting) -> String { values[s.env] ?? s.def }
        if let s = settings.first(where: { $0.env == "DM_PRESENT_INTERP" }), let off = ["off", "0"].first(where: { s.accepts($0) }), now(s) != off {
            return SessionFix(label: "Turn Off 120 fps Interpolation", env: s.env, value: off)
        }
        if let s = settings.first(where: { $0.env == "DM_PRESENT_UPSCALE" }), now(s) == "metalfx", let off = ["off", "0"].first(where: { s.accepts($0) }) {
            return SessionFix(label: "Turn Off MetalFX", env: s.env, value: off)
        }
        if let s = settings.first(where: { $0.env == "DM_RENDER_SCALE" }), let v = Double(now(s)), let lo = s.min {
            let step = s.step ?? 0.25
            let down = max(lo, ((v - 0.25) / step).rounded() * step)
            if down < v - 0.001 { return SessionFix(label: "Lower Render Scale to \(Int((down * 100).rounded())) %", env: s.env, value: String(format: step < 1 ? "%.2f" : "%.0f", down)) }
        }
        return nil
    }

    static func load() -> [String: SessionCheck] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: SessionCheck].self, from: $0) } ?? [:]
    }

    static func save(_ c: [String: SessionCheck]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(c) { try? d.write(to: file, options: .atomic) }
    }

    /// Run the check for one game's last log and record it in the history. Off the main thread.
    static func run(repo: String, python: String?, titleID: String) -> SessionCheck? {
        let script = repo + "/scripts/perf_check.py"
        guard FileManager.default.fileExists(atPath: script) else { return nil }
        let py = [python, "/usr/bin/python3"].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let py, let r = NXForgeConverter.run(py, [script, titleID, "--record", "--json"]), !r.out.isEmpty else { return nil }
        return decode(Data(r.out.utf8)).first
    }
}

extension AppModel {
    /// After a session (Playtime quit): check it, keep it when it was slower, and let go of an older note when it was not
    func checkSession(app: String) {
        guard let repo = env?.repo, let t = VerifiedGames.titleID(ofApp: app), ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        let python = env?.python
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))   // the launcher's last lines reach the log after the host has gone
            let c = await Task.detached(priority: .utility) { SessionChecks.run(repo: repo, python: python, titleID: t) }.value
            guard let self, let c, c.verdict != "too short" else { return }
            if c.slower { self.sessionChecks[t] = c } else { self.sessionChecks[t] = nil }
            SessionChecks.save(self.sessionChecks)
            self.revision += 1
        }
    }

    func sessionCheck(app: String) -> SessionCheck? { VerifiedGames.titleID(ofApp: app).flatMap { sessionChecks[$0] } }

    func sessionFix(app: String) -> SessionFix? {
        guard let c = sessionCheck(app: app) else { return nil }
        let settings = LaunchSettings.load(app: app)
        return SessionChecks.fix(c, settings: settings, values: Dictionary(settings.map { ($0.env, LaunchSettings.value($0, app: app)) }, uniquingKeysWith: { a, _ in a }))
    }

    /// The one-click fix: the Play option saved for the game, and the note gone (the next session says whether it helped)
    func applySessionFix(app: String) {
        guard let f = sessionFix(app: app), let s = LaunchSettings.load(app: app).first(where: { $0.env == f.env }) else { return }
        LaunchSettings.set(s, f.value, app: app)
        dismissSessionCheck(app: app)
        showBanner("\(s.label) changed for this game", detail: "It applies from the next start. Play options has it if you want it back.", tone: .success)
    }

    func dismissSessionCheck(app: String) {
        guard let t = VerifiedGames.titleID(ofApp: app), sessionChecks[t] != nil else { return }
        sessionChecks[t] = nil
        SessionChecks.save(sessionChecks)
        revision += 1
    }
}

/// "Slower than usual" on the recap card and the game's page: the numbers, why, and the change that should help
struct SessionCheckNote: View {
    let model: AppModel
    let app: String
    var onStage = false

    var body: some View {
        if let c = model.sessionCheck(app: app) {
            let fix = model.sessionFix(app: app)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tortoise.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.orange).frame(width: 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Slower than usual last time").font(.system(size: 14.5, weight: .semibold))
                    Text("\(c.numbers). \(c.why)").font(.system(size: 12.5)).foregroundStyle(onStage ? StageLook.faint : .secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if let fix { Button(fix.label) { model.applySessionFix(app: app) }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.small) }
                        Button("Dismiss") { model.dismissSessionCheck(app: app) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }
}
