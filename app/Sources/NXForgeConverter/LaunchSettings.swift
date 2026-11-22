// A built game's launch settings, set from the converter (idea 5): the list is the app's own Resources/dm/launcher.json
// (dm/games/settings.py), and the values are the game's saved choices: "launcher.<VARIABLE>" in the game app's preferences (its
// bundle ID's domain), a string, removed when it is the default (dm/ios/Sources/LauncherSettings.swift, dm/mac/launcher.c). The game
// has no settings window of its own (NXForge 0.55.1 on): it starts straight in with these choices, from here, Finder or the Dock.
import Foundation

struct LaunchSetting: Decodable, Identifiable, Hashable {
    let env, kind, label, note, def: String
    let section: String?
    let needs: String?
    let level: String?
    let options: [[String]]?
    let min, max, step: Double?
    let on, off: String?
    var id: String { env }

    // the list names a setting's default "default" (dm/games/settings.py); "def" is read too
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", legacyDef = "def", section, needs, level, options, min, max, step, on, off }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        env = try c.decode(String.self, forKey: .env)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        def = try c.decodeIfPresent(String.self, forKey: .def) ?? c.decode(String.self, forKey: .legacyDef)
        section = try c.decodeIfPresent(String.self, forKey: .section)
        needs = try c.decodeIfPresent(String.self, forKey: .needs)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        options = try c.decodeIfPresent([[String]].self, forKey: .options)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        step = try c.decodeIfPresent(Double.self, forKey: .step)
        on = try c.decodeIfPresent(String.self, forKey: .on)
        off = try c.decodeIfPresent(String.self, forKey: .off)
    }
    var basic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }

    func isDefault(_ v: String) -> Bool {
        kind == "range" ? abs((Double(v) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : v == def
    }

    func accepts(_ v: String) -> Bool {
        switch kind {
        case "choice": return options?.contains { $0.first == v } ?? false
        case "range":
            guard !v.contains(where: { $0 == "x" || $0 == "X" }), let n = Double(v), n.isFinite, let lo = min, let hi = max else { return false }
            return n >= lo && n <= hi
        case "toggle": return v == onValue || v == offValue
        default: return true
        }
    }
}

private struct LaunchSettingsFile: Decodable { let settings: [LaunchSetting] }

enum LaunchSettings {
    static func load(app: String) -> [LaunchSetting] {
        guard let d = FileManager.default.contents(atPath: app + "/Contents/Resources/dm/launcher.json"),
              let f = try? JSONDecoder().decode(LaunchSettingsFile.self, from: d) else { return [] }
        guard let mic = f.settings.firstIndex(where: { $0.env == "DM_MIC" }), !f.settings.contains(where: { $0.env == MicrophoneInputs.env }) else { return f.settings }
        // the input picker the game's old settings window had, after Microphone (MicrophoneInputs)
        var list = f.settings
        list.insert(MicrophoneInputs.setting(saved: defaults(app: app)?.string(forKey: "launcher." + MicrophoneInputs.env)), at: mic + 1)
        return list
    }

    static func bundleID(app: String) -> String? {
        NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String
    }

    static func defaults(app: String) -> UserDefaults? { bundleID(app: app).flatMap { UserDefaults(suiteName: $0) } }

    static func value(_ s: LaunchSetting, app: String) -> String {
        let saved = defaults(app: app)?.object(forKey: "launcher." + s.env) as? String
        return saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def
    }

    /// The settings with a choice saved for this game (a value that is not the default; the default is not stored)
    static func chosen(_ settings: [LaunchSetting], app: String) -> Set<String> {
        guard let d = defaults(app: app) else { return [] }
        return Set(settings.filter { s in (d.object(forKey: "launcher." + s.env) as? String).map { s.accepts($0) } ?? false }.map(\.env))
    }

    static func set(_ s: LaunchSetting, _ v: String, app: String) {
        guard let d = defaults(app: app) else { return }
        if s.isDefault(v) { d.removeObject(forKey: "launcher." + s.env) } else { d.set(v, forKey: "launcher." + s.env) }
        d.synchronize()
    }

    /// Whether a sub-setting shows: its "VAR=value" holds for the values now.
    static func visible(_ s: LaunchSetting, values: [String: String]) -> Bool {
        guard let n = s.needs, let eq = n.firstIndex(of: "=") else { return true }
        return values[String(n[..<eq])] == String(n[n.index(after: eq)...])
    }

    static func reset(app: String, settings: [LaunchSetting]) {
        guard let d = defaults(app: app) else { return }
        for s in settings { d.removeObject(forKey: "launcher." + s.env) }
        d.synchronize()
    }
}
