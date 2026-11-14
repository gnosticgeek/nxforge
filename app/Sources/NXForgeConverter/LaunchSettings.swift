// A built game's launch settings, set from the converter (idea 5): the list is the app's own Resources/dm/launcher.json (what the
// game's settings window shows, dm/games/settings.py), and the values are where that window keeps them: "launcher.<VARIABLE>" in
// the game app's preferences (its bundle ID's domain), a string, removed when it is the default (dm/ios/Sources/LauncherSettings.swift,
// dm/mac/launcher.c). "window.show" off opens the game straight in, with these choices, as "Show this window at launch" does.
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
        return f.settings
    }

    static func bundleID(app: String) -> String? {
        NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String
    }

    static func defaults(app: String) -> UserDefaults? { bundleID(app: app).flatMap { UserDefaults(suiteName: $0) } }

    static func value(_ s: LaunchSetting, app: String) -> String {
        let saved = defaults(app: app)?.object(forKey: "launcher." + s.env) as? String
        return saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def
    }

    static func set(_ s: LaunchSetting, _ v: String, app: String) {
        guard let d = defaults(app: app) else { return }
        if s.isDefault(v) { d.removeObject(forKey: "launcher." + s.env) } else { d.set(v, forKey: "launcher." + s.env) }
        d.synchronize()
    }

    /// Show the game's settings window at launch (its own "Show this window at launch")
    static func showsWindow(app: String) -> Bool { (defaults(app: app)?.object(forKey: "window.show") as? Bool) ?? true }
    static func setShowsWindow(_ on: Bool, app: String) {
        guard let d = defaults(app: app) else { return }
        d.set(on, forKey: "window.show")
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
