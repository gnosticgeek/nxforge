// Play options: a game's launch settings as the front end offers them (the Play options panel), with presets, and Play itself:
// the game opens straight in (--no-launcher) with the choices saved for it, so its own settings window stays closed. A run
// can also take choices for that run only: they go in the launch environment, which the game treats as fixed for the run and
// does not save (DM_ENV_LAUNCH_KEYS, dm/mac/launcher.c).
import AppKit
import Foundation
import IOKit.ps

enum PlayPreset: String, CaseIterable, Identifiable {
    case battery = "Battery", balanced = "Balanced", quality = "Quality", custom = "Custom"
    var id: String { rawValue }
    var note: String {
        switch self {
        case .battery: "Lower frame rate and resolution. Cooler and quieter."
        case .balanced: "The tested defaults for this game."
        case .quality: "Full resolution, MetalFX and HDR where the game has them."
        case .custom: "Your own mix of the rows below."
        }
    }
}

enum PlayTab: String, CaseIterable, Identifiable {
    case general = "General", graphics = "Graphics", advanced = "Advanced"
    var id: String { rawValue }
}

enum PlayOptions {
    /// The Graphics tab's rows in order, as the game's own settings window groups them (NXFLauncherLayout.graphicsBoxes)
    static let graphics = ["DM_FPS_TARGET", "DM_PRESENT_INTERP", "DM_RENDER_SCALE", "DM_DYNAMIC_RESOLUTION", "DM_PRESENT_UPSCALE", "DM_UPSCALER",
                           "DM_SCREEN_ASPECT", "DM_SCREEN_WIDE", "DM_PRESENT_AA", "DM_PIXEL_ART", "DM_PRESENT_EDR", "DM_PRESENT_EDR_STRENGTH"]
    /// On General though not level=basic: everyday controls (NXFLauncherLayout.general)
    static let general: Set<String> = ["DM_RUMBLE_GAIN", "DM_RUMBLE_MIN", "DM_PAD_PRESS_TO_JOIN", "DM_SW2"]
    /// What a preset sets; every other setting is left as it is
    static let presetKeys = ["DM_FPS_TARGET", "DM_RENDER_SCALE", "DM_PRESENT_UPSCALE", "DM_PRESENT_EDR", "DM_PRESENT_INTERP"]

    static func tab(_ s: LaunchSetting) -> PlayTab {
        graphics.contains(s.env) ? .graphics : s.basic || general.contains(s.env) ? .general : .advanced
    }

    /// A tab's rows: Graphics in its own order, the others in the list's
    static func rows(_ t: PlayTab, settings: [LaunchSetting], values: [String: String]) -> [LaunchSetting] {
        let mine = settings.filter { tab($0) == t && LaunchSettings.visible($0, values: values) }
        guard t == .graphics else { return mine }
        return mine.sorted { (graphics.firstIndex(of: $0.env) ?? 0) < (graphics.firstIndex(of: $1.env) ?? 0) }
    }

    static func format(_ s: LaunchSetting, _ v: Double) -> String { String(format: (s.step ?? 1) < 1 ? "%.2f" : "%.0f", v) }

    private static func snap(_ s: LaunchSetting, _ v: Double) -> String {
        let lo = s.min ?? 0, hi = s.max ?? 1, step = s.step ?? 0.05
        let n = step > 0 ? (lo + ((v - lo) / step).rounded() * step) : v
        return format(s, Swift.min(Swift.max(n, lo), hi))
    }

    /// What a preset gives one setting; nil leaves it alone. Only values the game offers are given.
    static func value(_ p: PlayPreset, for s: LaunchSetting) -> String? {
        guard p != .custom, presetKeys.contains(s.env) else { return nil }
        func offered(_ v: String) -> String { s.accepts(v) ? v : s.def }
        switch (s.env, p) {
        case ("DM_FPS_TARGET", .battery):
            let lowest = (s.options ?? []).compactMap { $0.first }.compactMap { v in Double(v).map { (v, $0) } }.min { $0.1 < $1.1 }?.0
            return lowest ?? s.def
        case ("DM_RENDER_SCALE", .battery):
            let def = Double(s.def) ?? 1
            return snap(s, Swift.min(def, 0.75))
        case ("DM_RENDER_SCALE", .quality):
            return snap(s, Swift.max(Double(s.def) ?? 1, s.max ?? 1))
        case ("DM_PRESENT_UPSCALE", .battery): return offered("off")
        case ("DM_PRESENT_UPSCALE", .quality): return offered("metalfx")
        case ("DM_PRESENT_EDR", .battery): return s.offValue
        case ("DM_PRESENT_EDR", .quality): return s.onValue
        case ("DM_PRESENT_INTERP", .battery): return offered("off")
        default: return s.def
        }
    }

    static func apply(_ p: PlayPreset, settings: [LaunchSetting], to values: inout [String: String]) {
        for s in settings { if let v = value(p, for: s) { values[s.env] = v } }
    }

    private static func same(_ s: LaunchSetting, _ a: String, _ b: String) -> Bool {
        s.kind == "range" ? abs((Double(a) ?? .nan) - (Double(b) ?? .nan)) < 1e-6 : a == b
    }

    static func matches(_ p: PlayPreset, settings: [LaunchSetting], values: [String: String]) -> Bool {
        settings.allSatisfy { s in value(p, for: s).map { same(s, $0, values[s.env] ?? s.def) } ?? true }
    }

    /// The preset the values are, Balanced first (a game with none of a preset's settings is on Balanced)
    static func current(settings: [LaunchSetting], values: [String: String]) -> PlayPreset {
        [PlayPreset.balanced, .quality, .battery].first { matches($0, settings: settings, values: values) } ?? .custom
    }

    /// The values that differ between two sets (for a run that takes them without saving them)
    static func difference(_ settings: [LaunchSetting], from saved: [String: String], to values: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for s in settings {
            let a = saved[s.env] ?? s.def, b = values[s.env] ?? s.def
            if !same(s, a, b) { out[s.env] = b }
        }
        return out
    }

    static func optionLabel(_ s: LaunchSetting, _ v: String) -> String {
        (s.options ?? []).first { $0.first == v }.map { $0.count > 1 ? $0[1] : $0[0] } ?? v
    }

    static func percent(_ v: String) -> String { "\(Int(((Double(v) ?? 0) * 100).rounded())) %" }

    /// What a row shows as its value
    static func valueText(_ s: LaunchSetting, _ v: String) -> String {
        switch s.kind {
        case "choice": optionLabel(s, v)
        case "toggle": v == s.onValue ? "On" : "Off"
        case "range": (s.max ?? 1) <= 4 ? percent(v) : v
        default: v
        }
    }

    /// The few choices worth showing beside Play: frame rate, resolution, aspect ratio, HDR
    static func summary(settings: [LaunchSetting], values: [String: String]) -> [(value: String, label: String)] {
        func find(_ env: String) -> (LaunchSetting, String)? { settings.first { $0.env == env }.map { ($0, values[$0.env] ?? $0.def) } }
        var out: [(String, String)] = []
        if let (s, v) = find("DM_FPS_TARGET") {
            let interp = find("DM_PRESENT_INTERP").map { $0.1 != "off" && $0.1 != $0.0.offValue } ?? false
            out.append((optionLabel(s, v), interp ? "Shown at 120 fps" : "Frame rate"))
        }
        if let (_, v) = find("DM_RENDER_SCALE") {
            let up = find("DM_PRESENT_UPSCALE").map { $0.1 == "metalfx" } ?? false
            out.append((percent(v), up ? "Render scale · MetalFX" : "Render scale"))
        }
        if let (s, v) = find("DM_SCREEN_ASPECT") ?? find("DM_SCREEN_WIDE") { out.append((optionLabel(s, v), "Aspect ratio")) }
        if let (s, v) = find("DM_PRESENT_EDR") { out.append((v == s.onValue ? "HDR" : "SDR", v == s.onValue ? "Highlights on" : "Highlights off")) }
        if let (s, v) = find("DM_OPMODE"), out.count < 4 { out.append((optionLabel(s, v), "Console mode")) }
        return Array(out.prefix(4))
    }

    /// Whether the Mac runs on its battery now
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == "Battery Power"
    }
}

/// The Play options panel's choices while it is open: nothing is saved until Play or closing it.
@MainActor @Observable
final class PlayOptionsState: Identifiable {
    let ref: GameRef
    let app: String
    let name: String
    let settings: [LaunchSetting]
    let saved: [String: String]
    var values: [String: String]
    var tab: PlayTab
    /// the row the keyboard or a controller is on
    var focus = 0

    init(ref: GameRef, app: String, name: String) {
        self.ref = ref
        self.app = app
        self.name = name
        settings = LaunchSettings.load(app: app)
        saved = Dictionary(settings.map { ($0.env, LaunchSettings.value($0, app: app)) }, uniquingKeysWith: { a, _ in a })
        values = saved
        tab = .graphics
        if rows.isEmpty { tab = tabs.first ?? .general }
    }

    var tabs: [PlayTab] { PlayTab.allCases.filter { !PlayOptions.rows($0, settings: settings, values: values).isEmpty } }
    var rows: [LaunchSetting] { PlayOptions.rows(tab, settings: settings, values: values) }
    var preset: PlayPreset { PlayOptions.current(settings: settings, values: values) }
    var changed: [String: String] { PlayOptions.difference(settings, from: saved, to: values) }
    var allDefault: Bool { settings.allSatisfy { $0.isDefault(values[$0.env] ?? $0.def) } }

    func value(_ s: LaunchSetting) -> String { values[s.env] ?? s.def }

    func set(_ s: LaunchSetting, _ v: String) {
        guard s.accepts(v) else { return }
        values[s.env] = v
        focus = min(focus, max(rows.count - 1, 0))
    }

    func choose(_ p: PlayPreset) {
        guard p != .custom else { return }
        PlayOptions.apply(p, settings: settings, to: &values)
    }

    func nextPreset() {
        let order: [PlayPreset] = [.battery, .balanced, .quality]
        let i = order.firstIndex(of: preset) ?? -1
        choose(order[(i + 1) % order.count])
    }

    /// Left and right on a row: the next choice, the other side of a switch, one step of a slider
    func step(_ s: LaunchSetting, by d: Int) {
        let v = value(s)
        switch s.kind {
        case "choice":
            let opts = (s.options ?? []).compactMap { $0.first }
            guard let i = opts.firstIndex(of: v) else { if let f = opts.first { set(s, f) }; return }
            set(s, opts[min(max(i + d, 0), opts.count - 1)])
        case "toggle": set(s, d > 0 ? s.onValue : s.offValue)
        case "range":
            let n = (Double(v) ?? 0) + Double(d) * (s.step ?? 0.05)
            set(s, PlayOptions.format(s, min(max(n, s.min ?? 0), s.max ?? 1)))
        default: break
        }
    }

    func moveTab(_ d: Int) {
        let t = tabs
        guard let i = t.firstIndex(of: tab) else { return }
        tab = t[min(max(i + d, 0), t.count - 1)]
        focus = 0
    }

    func reset() { for s in settings { values[s.env] = s.def } }

    func save() {
        for s in settings where values[s.env] != saved[s.env] { LaunchSettings.set(s, value(s), app: app) }
    }
}

/// The launch screen over the front end while a game starts
struct Launching: Identifiable, Equatable {
    let id = UUID()
    var ref: GameRef
    var app: String
    var name: String
    var note: String?
    var summary: String
}

extension AppModel {
    func openPlayOptions(_ r: GameRef) {
        guard let app = r.app ?? resolve(r).build?.app else { return }
        let (g, _) = resolve(r)
        let state = PlayOptionsState(ref: GameRef(libraryID: r.libraryID, app: app), app: app, name: g?.displayName ?? app.url.deletingPathExtension().lastPathComponent)
        guard !state.settings.isEmpty else {
            showBanner("\(state.name) has no options", detail: "It was built before games listed their settings. Rebuild it to get them.")
            return
        }
        playOptions = state
    }

    /// Closing the panel keeps its choices for the game, unless they were for one run
    func closePlayOptions(save: Bool = true) {
        if save { playOptions?.save() }
        playOptions = nil
        revision += 1
    }

    /// Play from the front end: a game not built goes to Convert; the first Play of a game shows its options once (a setting);
    /// on battery the Battery preset can stand in for the run (a setting).
    func playFromStage(_ r: GameRef) {
        let (g, b) = resolve(r)
        guard let app = r.app ?? b?.app, FileManager.default.fileExists(atPath: app) else {
            if let g { frontEnd = false; convertFromLibrary(g) }
            return
        }
        let ref = GameRef(libraryID: r.libraryID, app: app)
        let list = LaunchSettings.load(app: app)
        let shownKey = "stage.optionsShown." + Self.playKey(app: app)
        if settings.firstPlayOptions, !list.isEmpty, !UserDefaults.standard.bool(forKey: shownKey),
           playRecord(app: app, titleID: g?.titleID) == nil, !isPlaying(app: app) {
            UserDefaults.standard.set(true, forKey: shownKey)
            openPlayOptions(ref)
            return
        }
        let saved = Dictionary(list.map { ($0.env, LaunchSettings.value($0, app: app)) }, uniquingKeysWith: { a, _ in a })
        var once: [String: String] = [:]
        var note: String?
        if settings.batteryPreset, PlayOptions.onBattery, !list.isEmpty {
            var v = saved
            PlayOptions.apply(.battery, settings: list, to: &v)
            once = PlayOptions.difference(list, from: saved, to: v)
            if !once.isEmpty { note = "On battery: the Battery preset for this run" }
        }
        launch(ref, app: app, name: g?.displayName ?? app.url.deletingPathExtension().lastPathComponent, settings: list, saved: saved, once: once, note: note)
    }

    /// Play through the game's own settings window, as before the front end. (Its cloud save check also runs on a straight-in Play
    /// from NXForge 0.34.0's player on: launcher.c's --no-launcher calls it without the window.)
    func playWithOwnWindow(_ r: GameRef) {
        let (g, b) = resolve(r)
        guard let app = r.app ?? b?.app, FileManager.default.fileExists(atPath: app) else { return }
        launch(GameRef(libraryID: r.libraryID, app: app), app: app, name: g?.displayName ?? app.url.deletingPathExtension().lastPathComponent,
               settings: [], saved: [:], once: [:], note: "Opening the game's own settings window", ownWindow: true)
    }

    /// Start the game: straight in, with `once` in its environment for this run only.
    func launch(_ ref: GameRef, app: String, name: String, settings list: [LaunchSetting], saved: [String: String], once: [String: String], note: String?, ownWindow: Bool = false) {
        var shown = saved
        for (k, v) in once { shown[k] = v }
        let summary = ([PlayOptions.current(settings: list, values: shown).rawValue] + PlayOptions.summary(settings: list, values: shown).map(\.value)).joined(separator: " · ")
        if frontEnd { launching = Launching(ref: ref, app: app, name: name, note: note, summary: list.isEmpty ? "" : summary) }
        let cfg = NSWorkspace.OpenConfiguration()
        if settings.straightPlay && !ownWindow { cfg.arguments = ["--no-launcher"] }
        // added to the environment the game starts with; its launcher takes what is set there as fixed for the run
        cfg.environment = once.merging(Self.frontEndEnvironment) { a, _ in a }
        cfg.activates = true
        let id = launching?.id
        NSWorkspace.shared.openApplication(at: app.url, configuration: cfg) { [weak self] _, error in
            let text = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    if self.launching?.id == id { self.launching = nil }
                    self.showBanner("\(name) did not open", detail: text, tone: .warning)
                }
            }
        }
        Engine.setLaunched(app)
        revision += 1
        // the launch screen goes when the game's window shows (watchLaunch), or after a while if that is never seen
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            if self?.launching?.id == id { self?.launching = nil }
        }
    }

    /// What a game NXForge starts finds in its environment: NXForge's own path (NXFORGE_FRONT_END). With it the game's sidebar has Quit to Library,
    /// and its window stays see-through until its first frame (dm/host/nxforge/front_mac_front_end.inc), so the launch screen leads straight into the picture.
    static var frontEndEnvironment: [String: String] { ["NXFORGE_FRONT_END": Bundle.main.bundlePath] }

    /// The launch screen leaves when the game's window shows: the game says so (org.nxforge.gameShown, a build from NXForge 0.34.0 on, at its first frame),
    /// or, for an older build, its window is seen on screen and opaque once the game is the active app.
    func watchLaunch() {
        let nc = NSWorkspace.shared.notificationCenter
        playObservers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let path = a?.bundleURL?.standardizedFileURL.path, pid = a?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let l = self.launching, let path, let pid, l.app.url.standardizedFileURL.path == path else { return }
                self.waitForWindow(pid: pid, launch: l.id)
            }
        })
        let dc = DistributedNotificationCenter.default()
        playObservers.append(dc.addObserver(forName: Notification.Name("org.nxforge.gameShown"), object: nil, queue: .main) { [weak self] n in
            let path = (n.object as? String).map { $0.url.standardizedFileURL.path }
            MainActor.assumeIsolated {
                guard let self, let l = self.launching, path == nil || l.app.url.standardizedFileURL.path == path else { return }
                self.launching = nil
            }
        })
        // Quit to Library in the game's sidebar: NXForge comes to the front on that game's page
        playObservers.append(dc.addObserver(forName: Notification.Name("org.nxforge.showGame"), object: nil, queue: .main) { [weak self] n in
            let path = n.object as? String
            MainActor.assumeIsolated { if let self, let path { self.showGameFromPlayer(app: path) } }
        })
    }

    /// Polls the window server for the game's window (any of the process's on-screen windows at full opacity), then lets the launch screen go
    private func waitForWindow(pid: pid_t, launch id: UUID) {
        Task { @MainActor [weak self] in
            for _ in 0..<300 {
                guard let self, self.launching?.id == id else { return }
                if Self.hasVisibleWindow(pid: pid) {
                    try? await Task.sleep(for: .milliseconds(250))
                    if self.launching?.id == id { self.launching = nil }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    nonisolated static func hasVisibleWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { w in
            (w[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } == pid && (w[kCGWindowLayer as String] as? Int) == 0
                && ((w[kCGWindowAlpha as String] as? Double) ?? 0) > 0.9
                && ((w[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 100
        }
    }

    /// The game's sidebar said Quit to Library: its page on the front end, with NXForge in front
    func showGameFromPlayer(app: String) {
        let path = app.url.standardizedFileURL.path
        launching = nil
        playOptions = nil
        stageSettings = false
        frontEnd = true
        if let g = stageGames().first(where: { $0.app.map { $0.url.standardizedFileURL.path } == path }) {
            libraryFocus = g.id
            caseFlipped = false
            gameDetail = g.ref
        }
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
    }

    /// A game quit: the front end comes back to the front (a setting), ready for the next one.
    func gameQuit(app: String) {
        if launching?.app == app { launching = nil }
        guard frontEnd, settings.returnToLibrary, playing.isEmpty else { return }
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
    }
}
