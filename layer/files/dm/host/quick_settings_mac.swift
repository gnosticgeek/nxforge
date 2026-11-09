// Quick settings sidebar (front_mac.m opens and closes it; quick_settings_mac.h is the C side): SwiftUI with the system's controls, on a Liquid Glass panel on macOS 26 and later
// (a material panel before). The settings are front_mac.m's: the same user defaults keys (per game), the same rule that a setting the environment names wins and is not saved.
// Layout, top to bottom: a quick bar (Screenshot, Record, the FPS counter, volume and mute), a row of page tabs (General, Graphics, FPS, Capture, Mods, Cheats, Controls; L / R or Tab turn the page),
// the page, and a footer with what needs a restart (Restart game), Resume and Quit, and a legend of the buttons that work on the selection, in the controller's own glyphs or as keys.
// The filter (off or CRT; the engine's other filters stay for DM_PRESENT_FILTER), its strength and line size go to the graphics backend at once (front.h mtl_present_*); the frame-rate
// counter is drawn by front_mac.m, told through the fps callback; mods are the folders of this game's mods folder, overlaid at the next launch (front_mac.m mods_start); cheats are the
// host's (hle_cheats.c dm_cheat*): this build's Atmosphère cheat file, a switch each, which the host saves beside the file (<build ID>.enabled) and runs from the next frame. The Cheats
// menu and panel (front_mac.m) show the same rows. Settings that apply at the next launch (anisotropic filtering, frame times, mods) carry a "Next launch" tag, orange while they differ
// from what this launch runs, and the footer counts and names those. General: pause while open, quieter while open, a save backup (the Converter's save snapshots, same format),
// the settings file (front_mac_settings_file.inc: the settings as text beside the game) and my defaults for every game
import AppKit
import AVFoundation
import GameController
import SwiftUI

// The sidebar's own version, released as tags sidebar-vX.Y.Z with SIDEBAR_CHANGELOG.md (UPSTREAM.md, Versions); shown under the footer's legend.
// scripts/release_check.py reads this line: bump it with a new SIDEBAR_CHANGELOG.md entry when the sidebar changes.
let SIDEBAR_VERSION = "0.3.0"

private let env = ProcessInfo.processInfo.environment
private let pfxCRT = Int(DM_PFX_CRT)   // front.h DM_PFX_*: the sidebar offers off (0) and CRT
private let filterFixed = env["DM_PRESENT_FILTER"] != nil
private let cornerNames = ["Top left", "Top right", "Bottom left", "Bottom right"]
private let anisoSteps = [0, 2, 4, 8, 16]   // front.h mtl_aniso_set: 0 is the game's own
private let anisoDefault = 16               // front_mac.m graphics_start: 16x until a choice is saved
private let sizeNames = ["Fit", "Stretch", "Pixel-perfect"]   // front.h DM_PSCALE_*, in that order
private let scaleFixed = env["DM_PRESENT_SCALE"] != nil
private let aaNames = ["Off", "FXAA"]   // front.h DM_PAA_*, in that order
private let interpNames = ["Off", "On", "Auto"]   // front.h mtl_present_interp, in that order
// Upscaling is the settings window's setting too (launcher.DM_PRESENT_UPSCALE): fixed here only when the launch environment or an env file set it, not when the window or a saved choice did
private let upscaleFixed = env["DM_PRESENT_UPSCALE"] != nil && (env["DM_ENV_LAUNCH_KEYS"] == nil
    || Set(((env["DM_ENV_LAUNCH_KEYS"] ?? "") + " " + (env["DM_ENV_FILE_KEYS"] ?? "")).split(separator: " ").map(String.init)).contains("DM_PRESENT_UPSCALE"))

// The Controls page's rows: actions 0–15 are the Switch's buttons in NpadButton order, 16–19 the left stick, 20 shaking (front_mac.m's map); the controller map has the first 12
private let actionNames = ["A", "B", "X", "Y", "Left stick press", "Right stick press", "L", "R", "ZL", "ZR", "+ (Plus)", "− (Minus)", "D-pad left", "D-pad up", "D-pad right", "D-pad down",
                           "Left stick up", "Left stick left", "Left stick down", "Left stick right", "Shake"]
private let keyDefaults = ["J", "K", "U", "I", "F", "G", "Q", "E", "Z", "C", "Return", "Tab", "←", "↑", "→", "↓", "W", "A", "S", "D", "Space"]
private let keyDefaultCodes: [Int] = [38, 40, 32, 34, 3, 5, 12, 14, 6, 8, 36, 48, 123, 126, 124, 125, 13, 0, 1, 2, 49]   // front_mac.m g_key_default
private let padDefaultInputs = [GCInputButtonB, GCInputButtonA, GCInputButtonY, GCInputButtonX, GCInputLeftThumbstickButton, GCInputRightThumbstickButton,   // front_mac.m pad_default
                                GCInputLeftShoulder, GCInputRightShoulder, GCInputLeftTrigger, GCInputRightTrigger, GCInputButtonMenu, GCInputButtonOptions]
private let padDefaults = ["Right button", "Bottom button", "Top button", "Left button", "Left stick press", "Right stick press", "Left shoulder", "Right shoulder",
                           "Left trigger", "Right trigger", "Menu", "Options"]
// The pages, in tab order: a short name for the tab, a longer one over the page
private let pages: [(tab: String, title: String, icon: String)] = [("General", "General", "gearshape"), ("Graphics", "Graphics", "display"), ("FPS", "Performance", "chart.bar.fill"),
                                                                  ("Capture", "Capture", "camera"), ("Mods", "Mods", "puzzlepiece.extension"), ("Cheats", "Cheats", "wand.and.stars"),
                                                                  ("Controls", "Controls", "gamecontroller")]
private let pGeneral = 0, pGraphics = 1, pPerformance = 2, pCapture = 3, pMods = 4, pCheats = 5, pControls = 6
// What the controller and keyboard selection can be on (dm_qs_nav)
enum Nav: Hashable {
    case shot, record, fpsQuick, volume, mute, tab(Int)
    case pauseOpen, duckOpen, backup, backupShow, settingsShow, settingsOpen, defaultsSave, defaultsUse
    case fullscreen, scale, crt, strength, scanlines, upscale, aa, aniso, edr, edrStrength, resetGraphics
    case fps, corner, fpsMs, interp, frameTimes, frameTimesFolder, resetPerformance
    case capture(String), captureCopy, captureOpen, captureReveal, showFolder, changeFolder, defaultFolder
    case mod(String), modUp(String), modDown(String), modsOpen, modsRefresh
    case section(String), cheat(Int), cheatsAllOff, cheatsRestore, cheatsOpen, cheatsRefresh
    case key(Int), pad(Int), resetControls
    case restart, resume, quit
    /// A setting with a value: left and right change it
    var isValue: Bool {
        switch self {
        case .volume, .pauseOpen, .duckOpen, .fullscreen, .scale, .crt, .strength, .scanlines, .upscale, .aa, .aniso, .edr, .edrStrength, .fps, .fpsQuick, .interp, .corner, .fpsMs, .frameTimes, .mod, .cheat: return true
        default: return false
        }
    }
}
struct Cheat: Identifiable {
    let id: Int, name: String, why: String, note: String, kind: Int32, on: Bool, flags: Int32, section: String
    var master: Bool { kind == 1 }
    var disabled: Bool { kind == 2 }
    var label: Bool { kind == 3 }
    var once: Bool { flags & Int32(QS_CHEAT_ONCE) != 0 }
}
// One entry of the button legend: the keys or buttons, and what they do
struct Cap: Hashable { let symbol: String?, text: String }
struct Hint: Hashable { let caps: [Cap], text: String }
// The engine's strings come from the player's files: UTF-8 when they are, else Latin-1 (which decodes any byte)
private func cheatText(_ p: UnsafePointer<CChar>?) -> String {
    guard let p else { return "" }
    return String(validatingCString: p) ?? String(cString: p, encoding: .isoLatin1) ?? ""
}

// A screenshot or recording on the Capture page
struct CaptureFile: Hashable { let path: String, date: Date, video: Bool }
// The save backup (General page): the Converter's save snapshots, made here while the game runs (app/Sources/NXForgeConverter/SaveSnapshots.swift, the same files and manifest)
struct BackupFile: Codable, Equatable { var size: Int64; var sha256: String }
struct BackupInventory: Codable, Equatable { var files: [String: BackupFile] = [:]; var directories: [String] = [] }
struct BackupManifest: Codable { var schema = 1; var id: String; var titleID: String; var created: Date; var reason: String; var inventory: BackupInventory }
enum SaveBackup {
    struct Failure: Error { let text: String }
    /// The committed save (hle_fs.c DM_SAVE; the game writes to <save>.work and commits by swapping it in) and the device save beside it
    static var save: String? { env["DM_SAVE"].map { var p = $0; while p.count > 1 && p.hasSuffix("/") { p.removeLast() }; return p } }
    static var folder: String? { save.map { ($0 as NSString).deletingLastPathComponent + "/save-snapshots" } }
    static func sha256(_ path: String) throws -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { throw Failure(text: "cannot read \(path)") }
        defer { try? h.close() }
        var ctx = CC_SHA256_CTX(); CC_SHA256_Init(&ctx)
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { chunk.withUnsafeBytes { _ = CC_SHA256_Update(&ctx, $0.baseAddress, CC_LONG($0.count)) } }
        var d = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH)); CC_SHA256_Final(&d, &ctx)
        return d.map { String(format: "%02x", $0) }.joined()
    }
    static func inventory(_ parts: [(String, String)]) throws -> BackupInventory {
        let fm = FileManager.default; var inv = BackupInventory()
        for (name, root) in parts {
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &dir) else { continue }
            guard dir.boolValue else { throw Failure(text: "\(root) is not a folder") }
            inv.directories.append(name)
            guard let walk = fm.enumerator(atPath: root) else { continue }
            for case let rel as String in walk {
                let p = "\(root)/\(rel)", a = try fm.attributesOfItem(atPath: p)
                switch a[.type] as? FileAttributeType {
                case .typeDirectory?: inv.directories.append("\(name)/\(rel)")
                case .typeRegular?: inv.files["\(name)/\(rel)"] = BackupFile(size: (a[.size] as? NSNumber)?.int64Value ?? 0, sha256: try sha256(p))
                default: throw Failure(text: "the save holds a link or a special file")
                }
            }
        }
        inv.directories.sort(); return inv
    }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    /// A checked copy of the save in save-snapshots/<id> (the Converter lists and restores it); the time it was made
    static func make() throws -> Date {
        guard let save = save, let folder = folder else { throw Failure(text: "this launch has no save folder (DM_SAVE)") }
        let fm = FileManager.default, parts = [("save", save), ("save_device", save + "_device")]
        let has = parts.contains { ((try? fm.contentsOfDirectory(atPath: $0.1)) ?? []).contains { $0 != ".DS_Store" } }
        guard has else { throw Failure(text: "The game has not saved anything yet") }
        let inv = try inventory(parts)
        try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let now = Date(), id = f.string(from: now) + " " + String(UUID().uuidString.prefix(4)).lowercased()
        let stage = "\(folder)/.making-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: stage) }
        for d in inv.directories { try fm.createDirectory(atPath: "\(stage)/data/\(d)", withIntermediateDirectories: true) }
        let roots = Dictionary(uniqueKeysWithValues: parts)
        for k in inv.files.keys.sorted() {
            let top = String(k.split(separator: "/", maxSplits: 1)[0])
            try fm.copyItem(atPath: (roots[top] ?? "") + k.dropFirst(top.count), toPath: "\(stage)/data/\(k)")
        }
        let copied = try inventory(inv.directories.filter { !$0.contains("/") }.map { ($0, "\(stage)/data/\($0)") })
        guard copied == inv else { throw Failure(text: "The copy did not match the save; try again") }
        guard try inventory(parts) == inv else { throw Failure(text: "The game saved while it was being copied; try again") }
        let m = BackupManifest(id: id, titleID: String(cString: front_qs_title_id()).uppercased(), created: now, reason: "manual", inventory: inv)
        try encoder.encode(m).write(to: URL(fileURLWithPath: stage + "/manifest.json"), options: .atomic)
        try fm.moveItem(atPath: stage, toPath: "\(folder)/\(id)")
        return now
    }
    /// The newest backup's time, nil when there is none
    static func latest() -> Date? {
        guard let folder = folder else { return nil }
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for id in ids.reversed() {
            if let d = FileManager.default.contents(atPath: "\(folder)/\(id)/manifest.json"), let m = try? decoder.decode(BackupManifest.self, from: d) { return m.created }
        }
        return nil
    }
}

final class QuickSettings: ObservableObject {
    let game: String, modsDir: String, modsRun: Set<String>?, modsRunOrder: [String]?, close: () -> Void, fpsChanged: () -> Void
    let canRestart = front_qs_can_restart() != 0
    @Published var filter = 0
    @Published var strength = 0.5
    @Published var scanline = 0
    @Published var fps = false
    @Published var corner = 0
    @Published var fpsMs = false          // the counter shows milliseconds a frame too
    @Published var frameTimes = false   // record from the next launch
    @Published var mods: [String] = []    // in load order
    @Published var wanted: [String] = []
    @Published var modClash: [String: String] = [:]   // an enabled mod sharing files with another: a line saying which wins
    @Published var cheats: [Cheat] = []
    @Published var cheatsBuild = ""
    @Published var cheatsVersion = ""
    @Published var cheatsSafe = false
    @Published var cheatSearch = ""
    @Published var folded: Set<String> = []   // the Cheats page's closed sections
    @Published var page: Int
    @Published var volume = 1.0
    @Published var muted = false
    @Published var recording = false
    @Published var shotDir = ""
    @Published var upscale = false   // MetalFX where the picture is shown larger than the game renders it
    @Published var aa = 0            // the present's anti-aliasing (DM_PAA_*)
    @Published var edr = false       // EDR highlights (front.h mtl_present_edr)
    @Published var edrStrength = 0.5
    @Published var edrHeadroom: Float = 1   // the screen's potential EDR headroom, 1 = SDR
    @Published var interp = 0        // frame interpolation to 120 fps (front.h mtl_present_interp: 0 off, 1 on, 2 auto)
    @Published var interpActive = false   // whether it applies now (auto: on a 120 Hz screen)
    @Published var aniso = 0      // the chosen anisotropic filtering floor (0: the game's own)
    @Published var anisoRun = 0   // the one this launch took
    @Published var scale = 0      // picture size (DM_PSCALE_*)
    @Published var fullscreen = false
    @Published var pauseOpen = true   // pause the game while the sidebar is up
    @Published var duckOpen = false   // quieter sound while it is up
    @Published var paused = false
    @Published var lastBackup: Date?
    @Published var backupBusy = false
    @Published var backupNote = ""
    @Published var settingsPath = ""
    @Published var defaultsExist = false
    @Published var captures: [CaptureFile] = []
    @Published var picked: String?    // the capture the Capture page's buttons act on
    @Published var thumbs: [String: NSImage] = [:]
    @Published var recDir = ""
    @Published var customDir = false
    @Published var sel: Nav? { didSet { if sel != .quit { quitArmed = false }; if sel != .restart { restartArmed = false } } }
    @Published var quitArmed = false      // Quit game asks twice, so a stray A press on the couch does not end the game
    @Published var restartArmed = false   // and so does Restart game
    @Published var pad = false            // a controller drives the sidebar (the legend shows its buttons), else the keyboard
    @Published var glyphs: [String?] = [nil, nil, nil, nil]   // that controller's SF Symbols for choose, close, previous and next page
    @Published var assigning = -1
    @Published var keyNames: [String] = keyDefaults
    @Published var padNames: [String] = padDefaults
    @Published var keyClash: [Int: String] = [:]   // an action whose key another action has too: that action's name
    @Published var padClash: [Int: String] = [:]
    private var observers: [NSObjectProtocol] = []
    init(game: String, modsDir: String, modsRunOrder: [String]?, close: @escaping () -> Void, fpsChanged: @escaping () -> Void) {
        self.game = game; self.modsDir = modsDir; self.modsRunOrder = modsRunOrder; self.modsRun = modsRunOrder.map(Set.init); self.close = close; self.fpsChanged = fpsChanged
        page = min(max(UserDefaults.standard.integer(forKey: "DMQuickSettings.page.\(game)"), 0), pages.count - 1)
        for n in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.fullscreen = front_qs_fullscreen() != 0 })
        }
        refresh()
    }
    private func pfxKey(_ what: String) -> String { "DMPresentFilter.\(what).\(game)" }
    private func optKey(_ what: String) -> String { "DMQuickSettings.\(what).\(game)" }
    func refresh() {
        var k: Float = 0.5
        filter = Int(mtl_present_filter(&k)); strength = Double(k); scanline = Int(mtl_present_scanline())
        let d = UserDefaults.standard
        if let e = env["DM_SHOW_FPS"] { fps = (Int(e) ?? 0) != 0 } else { fps = d.bool(forKey: optKey("fps")) }
        corner = min(max(d.integer(forKey: optKey("fpsPos")), 0), 3); fpsMs = d.bool(forKey: optKey("fpsMs"))
        if let e = env["DM_FRAME_TIMES"] { frameTimes = (Int(e) ?? 0) != 0 } else { frameTimes = d.bool(forKey: optKey("frameTimes")) }
        wanted = d.stringArray(forKey: optKey("mods")) ?? []
        volume = d.object(forKey: optKey("volume")) == nil ? 1 : d.double(forKey: optKey("volume")); muted = d.bool(forKey: optKey("muted"))
        recording = front_qs_recording() != 0
        pauseOpen = d.object(forKey: optKey("pauseOpen")) == nil ? true : d.bool(forKey: optKey("pauseOpen")); duckOpen = d.bool(forKey: optKey("duckOpen"))
        paused = front_qs_paused() != 0; fullscreen = front_qs_fullscreen() != 0
        assigning = Int(front_qs_assigning())
        anisoRun = Int(mtl_aniso()); aniso = env["DM_ANISO"] != nil || d.object(forKey: optKey("aniso")) == nil ? anisoRun : d.integer(forKey: optKey("aniso"))   // unsaved: front_mac.m's 16x
        upscale = mtl_present_upscale() != 0; aa = Int(mtl_present_aa()); scale = Int(mtl_present_scale())
        edr = mtl_present_edr() != 0; edrStrength = Double(mtl_present_edr_strength()) / 100; edrHeadroom = mtl_present_edr_headroom(); interp = Int(mtl_present_interp()); interpActive = mtl_present_interp_active() != 0
        shotDir = String(cString: front_qs_capture_folder(0)); recDir = String(cString: front_qs_capture_folder(1)); customDir = front_qs_capture_custom() != 0
        settingsPath = String(cString: front_qs_settings_path()); defaultsExist = front_qs_defaults_exist() != 0
        let kn = d.dictionary(forKey: optKey("keyNames")) as? [String: String] ?? [:], pn = d.dictionary(forKey: optKey("padNames")) as? [String: String] ?? [:]
        keyNames = keyDefaults.indices.map { kn[String($0)] ?? keyDefaults[$0] }; padNames = padDefaults.indices.map { pn[String($0)] ?? padDefaults[$0] }
        refreshClashes()
        let fm = FileManager.default
        let found = ((try? fm.contentsOfDirectory(atPath: modsDir)) ?? []).filter { n in
            var dir: ObjCBool = false
            return !n.hasPrefix(".") && fm.fileExists(atPath: (modsDir as NSString).appendingPathComponent(n), isDirectory: &dir) && dir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var order: [String] = []   // front_mac.m mods_list: the saved order first, then the rest by name
        for n in d.stringArray(forKey: optKey("modOrder")) ?? [] where found.contains(n) && !order.contains(n) { order.append(n) }
        mods = order + found.filter { !order.contains($0) }
        refreshModClash()
        lastBackup = SaveBackup.latest()
        refreshCheats()
        refreshCaptures()
    }
    // Keys or buttons two actions share (a map saved before swapping, or a hand edit of the settings file): each names the other
    private func refreshClashes() {
        let d = UserDefaults.standard
        let k = d.dictionary(forKey: optKey("keys")) ?? [:], p = d.dictionary(forKey: optKey("pad")) ?? [:]
        let codes = keyDefaultCodes.indices.map { (k[String($0)] as? NSNumber)?.intValue ?? keyDefaultCodes[$0] }
        let inputs = padDefaultInputs.indices.map { p[String($0)] as? String ?? padDefaultInputs[$0] }
        var kc: [Int: String] = [:], pc: [Int: String] = [:]
        for i in codes.indices where codes[i] != 0xffff { if let j = codes.indices.first(where: { $0 != i && codes[$0] == codes[i] }) { kc[i] = actionNames[j] } }
        for i in inputs.indices where !inputs[i].isEmpty { if let j = inputs.indices.first(where: { $0 != i && inputs[$0] == inputs[i] }) { pc[i] = actionNames[j] } }
        keyClash = kc; padClash = pc
    }
    /// A mod's game files (front_mac.m mod_root): its romfs folder, an Atmosphere layout's, or the folder itself
    private func modRoot(_ n: String) -> String {
        let p = (modsDir as NSString).appendingPathComponent(n), tid = String(cString: front_qs_title_id())
        for sub in ["romfs", "atmosphere/contents/\(tid)/romfs", "contents/\(tid)/romfs", "\(tid)/romfs"] {
            var dir: ObjCBool = false; let rf = (p as NSString).appendingPathComponent(sub)
            if FileManager.default.fileExists(atPath: rf, isDirectory: &dir), dir.boolValue { return rf }
        }
        return p
    }
    // Enabled mods that replace the same files: the first in the load order wins
    func refreshModClash() {
        let on = mods.filter { wanted.contains($0) }
        guard on.count > 1 else { modClash = [:]; return }
        var owner: [String: String] = [:], shared: [String: [String: Int]] = [:]
        for n in on {
            var seen = 0
            guard let walk = FileManager.default.enumerator(atPath: modRoot(n)) else { continue }
            for case let rel as String in walk {
                seen += 1; if seen > 50_000 { break }
                if rel.hasPrefix(".") || rel.contains("/.") { continue }
                if let first = owner[rel] { shared[n, default: [:]][first, default: 0] += 1; shared[first, default: [:]][n, default: 0] += 1 } else { owner[rel] = n }
            }
        }
        var out: [String: String] = [:]
        for (n, others) in shared {
            out[n] = others.sorted { $0.key < $1.key }.map { o, c in
                let wins = (on.firstIndex(of: n) ?? 0) < (on.firstIndex(of: o) ?? 0)
                return "\(c) file\(c == 1 ? "" : "s") also in \(o): \(wins ? "this one wins" : "\(o) wins")"
            }.joined(separator: "\n")
        }
        modClash = out
    }
    // One row per cheat the Cheats page shows: not the off half of an on / off pair (its on half is the switch) and not a section marker
    func refreshCheats() {
        let hidden = Int32(QS_CHEAT_PAIR_OFF | QS_CHEAT_SECTION_START | QS_CHEAT_SECTION_END)
        cheats = (0..<Int(dm_cheats_ncheats())).compactMap { i in
            let f = dm_cheat_flags_at(Int32(i))
            if f & hidden != 0 { return nil }
            var name = cheatText(dm_cheat_name_at(Int32(i)))
            if f & Int32(QS_CHEAT_PAIR_ON) != 0, let r = name.range(of: #"(\s*[-:_]\s*|\s+|\s*[(\[]\s*)on\s*[)\]]?\s*$"#, options: [.regularExpression, .caseInsensitive]), r.lowerBound > name.startIndex { name.removeSubrange(r) }
            return Cheat(id: i, name: name, why: cheatText(dm_cheat_why_at(Int32(i))).trimmingCharacters(in: .whitespaces), note: cheatText(dm_cheat_note_at(Int32(i))),
                         kind: dm_cheat_kind_at(Int32(i)), on: dm_cheat_on_at(Int32(i)) != 0, flags: f, section: cheatText(dm_cheat_section_at(Int32(i))))
        }
        cheatsBuild = cheatText(dm_cheats_build()).uppercased()
        cheatsVersion = cheatText(dm_cheats_version()); cheatsSafe = dm_cheats_safe() != 0
    }
    func setCheat(_ c: Cheat, _ on: Bool) { if c.on != on { dm_cheat_toggle(Int32(c.id)) }; refreshCheats() }
    func rescanCheats() { dm_cheats_reload(); refreshCheats() }
    func restoreCheats() { dm_cheats_safe_restore(); refreshCheats() }
    func cheatsAllOff() { for c in cheats where c.kind == 0 && c.on { dm_cheat_toggle(Int32(c.id)) }; refreshCheats() }
    func openCheatsFolder() {
        let dir = cheatText(dm_cheats_dir_path()); if dir.isEmpty { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
    var cheatsOn: Int { cheats.filter { $0.on && $0.kind == 0 }.count }
    /// The Cheats page as shown: the search's matches (no sections), or the sections in file order, each with its rows unless closed
    var cheatGroups: [(section: String, rows: [Cheat])] {
        let q = cheatSearch.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return [("", cheats.filter { !$0.label && ($0.name.localizedCaseInsensitiveContains(q) || $0.note.localizedCaseInsensitiveContains(q)) })] }
        var g: [(section: String, rows: [Cheat])] = []
        for c in cheats { if let i = g.indices.last, g[i].section == c.section { g[i].rows.append(c) } else { g.append((c.section, [c])) } }
        return g
    }
    func toggleSection(_ s: String) { if folded.contains(s) { folded.remove(s) } else { folded.insert(s) } }
    var crtOn: Bool { filter == pfxCRT }
    func setFilter(_ m: Int, _ k: Double) {
        mtl_present_filter_set(Int32(m), Float(k)); filter = m; strength = k
        if !filterFixed { UserDefaults.standard.set(m, forKey: pfxKey("mode")); UserDefaults.standard.set(Float(k), forKey: pfxKey("strength")) }
    }
    func setCRT(_ on: Bool) { if !filterFixed { setFilter(on ? pfxCRT : 0, strength) } }
    func setAniso(_ n: Int) {   // saved for the next launch (Metal's samplers are made once): the engine only logs it when the game has made its first one
        aniso = n; if env["DM_ANISO"] == nil { UserDefaults.standard.set(n, forKey: optKey("aniso")); mtl_aniso_set(Int32(n)) }
    }
    func setUpscale(_ on: Bool) {   // at once, from the next frame, and saved where the settings window keeps it, by its rule: the Mac default
        guard !upscaleFixed else { return }   // (MetalFX) is not stored, so a later build's default still reaches this game (docs/settings.md, Tested defaults)
        upscale = on; mtl_present_upscale_set(on ? 1 : 0)
        if on { UserDefaults.standard.removeObject(forKey: "launcher.DM_PRESENT_UPSCALE") } else { UserDefaults.standard.set("off", forKey: "launcher.DM_PRESENT_UPSCALE") }
    }
    func setAA(_ n: Int) {
        aa = n; mtl_present_aa_set(Int32(n)); if env["DM_PRESENT_AA"] == nil { UserDefaults.standard.set(n, forKey: optKey("aa")) }
    }
    func setEDR(_ on: Bool) {   // at once, from the next frame
        guard env["DM_PRESENT_EDR"] == nil else { return }
        edr = on; mtl_present_edr_set(on ? 1 : 0); UserDefaults.standard.set(on, forKey: optKey("edr"))
    }
    func setEDRStrength(_ k: Double) {
        guard env["DM_PRESENT_EDR_STRENGTH"] == nil else { return }
        edrStrength = k; mtl_present_edr_strength_set(Int32((k * 100).rounded())); UserDefaults.standard.set(k, forKey: optKey("edrStrength"))
    }
    func setScanline(_ r: Int) {
        mtl_present_scanline_set(Int32(r)); scanline = r
        if env["DM_PRESENT_SCANLINE"] == nil { UserDefaults.standard.set(r, forKey: pfxKey("scanline")) }
    }
    func setScale(_ n: Int) { guard !scaleFixed else { return }; scale = n; mtl_present_scale_set(Int32(n)); UserDefaults.standard.set(n, forKey: optKey("scale")) }
    func toggleFullscreen() { front_qs_fullscreen_toggle() }
    var graphicsChanged: Bool { filter != 0 || abs(strength - 0.5) > 0.001 || scanline != 0 || !upscale || aa != 0 || aniso != anisoDefault || scale != 0 || edr || abs(edrStrength - 0.5) > 0.001 }
    func resetGraphics() {   // each setting the environment does not fix, back to the Mac's default
        if !filterFixed { setFilter(0, 0.5) }
        if env["DM_PRESENT_SCANLINE"] == nil { setScanline(0) }
        setUpscale(true); setScale(0)
        if env["DM_PRESENT_AA"] == nil { setAA(0) }
        setEDR(false); setEDRStrength(0.5)
        if env["DM_ANISO"] == nil { setAniso(anisoDefault) }
    }
    func setFps(_ on: Bool) { fps = on; if env["DM_SHOW_FPS"] == nil { UserDefaults.standard.set(on, forKey: optKey("fps")) }; fpsChanged() }
    func setCorner(_ c: Int) { corner = c; UserDefaults.standard.set(c, forKey: optKey("fpsPos")); fpsChanged() }
    func setFpsMs(_ on: Bool) { fpsMs = on; UserDefaults.standard.set(on, forKey: optKey("fpsMs")); fpsChanged() }
    /// The file this launch records to (front_mac.m frame_times_begin), nil when it records nothing
    var frameTimesNow: String? { env["DM_NVN_TSV"].flatMap { $0.isEmpty ? nil : $0 } }
    /// Where Record frame times writes: the game folder's Frame times, else <DM_ROOT>/frame-times (as frame_times_begin)
    var frameTimesDir: String? {
        if let g = env["DM_GAME_FOLDER"], !g.isEmpty { return (g as NSString).appendingPathComponent("Frame times") }
        if let r = env["DM_ROOT"], !r.isEmpty { return (r as NSString).appendingPathComponent("frame-times") }
        return nil
    }
    func setFrameTimes(_ on: Bool) { frameTimes = on; if env["DM_FRAME_TIMES"] == nil { UserDefaults.standard.set(on, forKey: optKey("frameTimes")) } }
    func showFrameTimes() {
        guard let dir = frameTimesNow.map({ ($0 as NSString).deletingLastPathComponent }) ?? frameTimesDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
    func setInterp(_ n: Int) {   // at once: the display link moves to 120 Hz (or back) on the next frame
        guard env["DM_PRESENT_INTERP"] == nil else { return }
        interp = n; mtl_present_interp_set(Int32(n)); interpActive = mtl_present_interp_active() != 0; UserDefaults.standard.set(n, forKey: optKey("interp"))
    }
    var performanceChanged: Bool { fps || corner != 0 || frameTimes || fpsMs || interp != 0 }
    func resetPerformance() {
        if env["DM_SHOW_FPS"] == nil && fps { setFps(false) }
        if corner != 0 { setCorner(0) }
        if fpsMs { setFpsMs(false) }
        if env["DM_FRAME_TIMES"] == nil && frameTimes { setFrameTimes(false) }
        if interp != 0 { setInterp(0) }
    }
    func setMod(_ n: String, _ on: Bool) {
        wanted.removeAll { $0 == n }; if on { wanted.append(n) }
        UserDefaults.standard.set(wanted, forKey: optKey("mods")); refreshModClash()
    }
    /// Move a mod up (d -1: it loads earlier and wins over the ones after it) or down the load order
    func moveMod(_ n: String, _ d: Int) {
        guard let i = mods.firstIndex(of: n) else { return }
        let j = min(max(i + d, 0), mods.count - 1); if i == j { return }
        mods.swapAt(i, j); UserDefaults.standard.set(mods, forKey: optKey("modOrder")); refreshModClash()
    }
    // Sound: the volume and mute are saved, and front_mac.m sets the game's gain from them (quieter while the sidebar is up when that is on)
    func setVolume(_ v: Double) { volume = v; muted = false; UserDefaults.standard.set(v, forKey: optKey("volume")); UserDefaults.standard.set(false, forKey: optKey("muted")); front_qs_volume_apply() }
    func setMuted(_ on: Bool) { muted = on; UserDefaults.standard.set(on, forKey: optKey("muted")); front_qs_volume_apply() }
    func setDuck(_ on: Bool) { duckOpen = on; UserDefaults.standard.set(on, forKey: optKey("duckOpen")); front_qs_volume_apply() }
    func setPauseOpen(_ on: Bool) { pauseOpen = on; front_qs_pause_set(on ? 1 : 0); paused = front_qs_paused() != 0 }
    // Save backup: off the main thread (it reads and checks every file twice), a toast when it is done
    func backup() {
        guard !backupBusy else { return }
        backupBusy = true; backupNote = "Backing up…"
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result<Date, Error>(catching: { try SaveBackup.make() })
            DispatchQueue.main.async {
                self.backupBusy = false
                switch r {
                case .success(let d): self.lastBackup = d; self.backupNote = ""; front_qs_toast_text("Save backed up")
                case .failure(let e): self.backupNote = (e as? SaveBackup.Failure)?.text ?? e.localizedDescription
                }
            }
        }
    }
    func showBackups() {
        guard let f = SaveBackup.folder else { return }
        try? FileManager.default.createDirectory(atPath: f, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: f))
    }
    func showSettingsFile() { if !settingsPath.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settingsPath)]) } }
    func openSettingsFile() { if !settingsPath.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: settingsPath)) } }
    func saveDefaults() { front_qs_defaults_save(); defaultsExist = front_qs_defaults_exist() != 0 }
    func useDefaults() { front_qs_defaults_use(); refresh(); fpsChanged() }
    func showCaptureFolder() {
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: shotDir == recDir ? shotDir : (shotDir as NSString).deletingLastPathComponent))
    }
    func chooseCaptureFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "Choose"
        p.message = "Screenshots and recordings of \(game) go to this folder."; p.directoryURL = URL(fileURLWithPath: shotDir)
        if p.runModal() == .OK, let u = p.url { front_qs_capture_folder_set(u.path); refresh() }
    }
    func defaultCaptureFolder() { front_qs_capture_folder_set(nil); refresh() }
    // Recent captures: the newest six screenshots and recordings in the capture folders, with thumbnails made off the main thread
    func refreshCaptures() {
        let fm = FileManager.default
        var all: [CaptureFile] = []
        for dir in Set([shotDir, recDir]) {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                let ext = (n as NSString).pathExtension.lowercased(); guard ["png", "jpg", "heic", "mov", "mp4"].contains(ext) else { continue }
                let p = (dir as NSString).appendingPathComponent(n)
                if let d = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date { all.append(CaptureFile(path: p, date: d, video: ext == "mov" || ext == "mp4")) }
            }
        }
        captures = Array(all.sorted { $0.date > $1.date }.prefix(6))
        if picked == nil || !captures.contains(where: { $0.path == picked }) { picked = captures.first?.path }
        for c in captures where thumbs[c.path] == nil {
            DispatchQueue.global(qos: .utility).async {
                var img: NSImage?
                if c.video {
                    let g = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: c.path))); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 320, height: 180)
                    g.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600)) { cg, _, _ in
                        if let cg { let i = NSImage(cgImage: cg, size: .zero); DispatchQueue.main.async { self.thumbs[c.path] = i } }
                    }
                } else if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: c.path) as CFURL, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) {
                    img = NSImage(cgImage: cg, size: .zero)
                }
                if let img { DispatchQueue.main.async { self.thumbs[c.path] = img } }
            }
        }
    }
    func copyCapture() {
        guard let p = picked else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        let url = URL(fileURLWithPath: p) as NSURL
        if p.lowercased().hasSuffix(".mov") || p.lowercased().hasSuffix(".mp4") { pb.writeObjects([url]) } else if let img = NSImage(contentsOfFile: p) { pb.writeObjects([img, url]) }
        front_qs_toast_text("Copied: paste it into a message or document")
    }
    func openCapture() { if let p = picked { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
    func revealCapture() { if let p = picked { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } }
    func record() { front_qs_record(); recording = front_qs_recording() != 0 }
    func assign(_ i: Int, pad: Bool) { front_qs_assign(Int32(i), pad ? 1 : 0); assigning = Int(front_qs_assigning()) }
    func resetControls() {
        for k in ["keys", "keyNames", "pad", "padNames"] { UserDefaults.standard.removeObject(forKey: optKey(k)) }
        front_qs_controls_reload(); refresh()
    }
    func openModsFolder() {
        try? FileManager.default.createDirectory(atPath: modsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: modsDir))
    }
    var modsOn: Int { mods.filter { wanted.contains($0) }.count }

    // What applies at the next launch: one count for the footer and the names under it, the same test as each row's tag
    var anisoPending: Bool { env["DM_ANISO"] == nil && aniso != anisoRun }
    var frameTimesPending: Bool { env["DM_FRAME_TIMES"] == nil && frameTimes != (frameTimesNow != nil) }
    func modPending(_ n: String) -> Bool { modsRun.map { $0.contains(n) != wanted.contains(n) } ?? false }
    /// The enabled mods would load in another order than this launch's
    var modOrderPending: Bool {
        guard let run = modsRunOrder else { return false }
        let now = mods.filter { wanted.contains($0) }
        return Set(now) == Set(run) && now != run
    }
    var pendingNames: [String] {
        (anisoPending ? ["Anisotropic filtering"] : []) + (frameTimesPending ? ["Record frame times"] : [])
            + mods.filter(modPending).map { "Mod \($0) \(wanted.contains($0) ? "on" : "off")" } + (modOrderPending ? ["Mod load order"] : [])
    }
    var restartCount: Int { pendingNames.count }
    /// Restart game (front_mac.m front_qs_restart): the first press arms it, the second quits and the launcher starts the game again
    func restart() { if restartArmed { front_qs_restart() } else { restartArmed = true } }
    /// Quit game (after the NxNative Launcher's hold-Home exit): the first press arms it, the second ends the game as ⌘Q does
    func quit() { if quitArmed { NSApp.terminate(nil) } else { quitArmed = true } }

    // Controller and keyboard navigation (after RetroReplay's pause menu): a selection over rows of items. Up and down move between rows; left and right change a
    // setting's value, or move along a row of buttons (the quick bar, the tabs, the footer); L / R (Tab / Shift-Tab) turn the page
    func pageRows(_ p: Int) -> [[Nav]] {
        switch p {
        case pGeneral:
            return [[.pauseOpen], [.duckOpen], [.backup, .backupShow]] + (settingsPath.isEmpty ? [] : [[.settingsShow, .settingsOpen]]) + [defaultsExist ? [.defaultsSave, .defaultsUse] : [.defaultsSave]]
        case pGraphics: return [[.fullscreen], [.scale], [.crt]] + (crtOn ? [[.strength], [.scanlines]] : []) + [[.upscale], [.aa], [.aniso], [.edr]] + (edr ? [[.edrStrength]] : []) + [[.resetGraphics]]
        case pPerformance: return [[.fps]] + (fps ? [[.corner], [.fpsMs]] : []) + [[.interp], [.frameTimes], [.frameTimesFolder], [.resetPerformance]]
        case pCapture:
            let shots = captures.map { Nav.capture($0.path) }
            return (shots.isEmpty ? [] : [Array(shots.prefix(3))] + (shots.count > 3 ? [Array(shots.dropFirst(3))] : []) + [[.captureCopy, .captureOpen, .captureReveal]])
                + [[.showFolder, .changeFolder]] + (customDir ? [[.defaultFolder]] : [])
        case pMods: return mods.map { [.mod($0), .modUp($0), .modDown($0)] } + [[.modsOpen, .modsRefresh]]
        case pCheats:
            var r: [[Nav]] = cheatsSafe ? [[.cheatsRestore]] : []
            for g in cheatGroups {
                if !g.section.isEmpty && cheatSearch.isEmpty { r.append([.section(g.section)]); if folded.contains(g.section) { continue } }
                r += g.rows.filter { !$0.label }.map { [.cheat($0.id)] }
            }
            return r + (cheatsOn > 0 ? [[.cheatsAllOff]] : []) + [[.cheatsOpen, .cheatsRefresh]]
        case pControls: return actionNames.indices.map { [.key($0)] } + padDefaults.indices.map { [.pad($0)] } + [[.resetControls]]
        default: return []
        }
    }
    var rows: [[Nav]] {
        var r: [[Nav]] = [[.shot, .record, .fpsQuick], [.mute, .volume], pages.indices.map { .tab($0) }] + pageRows(page)
        if restartCount > 0 && canRestart { r.append([.restart]) }
        return r + [[.resume, .quit]]
    }
    var firstOnPage: Nav { pageRows(page).first?.first ?? .tab(page) }
    func setPage(_ p: Int) { page = p; UserDefaults.standard.set(p, forKey: optKey("page")); if p == pCapture { refreshCaptures() } }
    func turnPage(_ d: Int) { setPage((page + d + pages.count) % pages.count); sel = firstOnPage }
    func nav(_ cmd: Int32) {
        if cmd == 6 { close(); return }
        if cmd == 7 || cmd == 8 { turnPage(cmd == 8 ? 1 : -1); return }
        let rs = rows
        guard let cur = sel, let ri = rs.firstIndex(where: { $0.contains(cur) }), let ci = rs[ri].firstIndex(of: cur) else { sel = firstOnPage; return }
        switch cmd {
        case 1, 2:
            let to = rs[min(max(ri + (cmd == 2 ? 1 : -1), 0), rs.count - 1)]
            if to.contains(.tab(page)) { sel = .tab(page) } else { sel = to[min(ci, to.count - 1)] }
        case 3, 4:
            let d = cmd == 4 ? 1 : -1
            if rs[ri].count > 1 && !(cur == .volume) {
                let n = rs[ri][min(max(ci + d, 0), rs[ri].count - 1)]; sel = n
                if case .tab(let i) = n { setPage(i) }
                if case .capture(let p) = n { picked = p }
            } else { adjust(cur, d) }
        case 5: activate(cur)
        default: break
        }
    }
    private func adjust(_ n: Nav, _ d: Int) {
        switch n {
        case .pauseOpen: setPauseOpen(d > 0)
        case .duckOpen: setDuck(d > 0)
        case .fullscreen: if (d > 0) != fullscreen { toggleFullscreen() }
        case .scale: setScale(min(max(scale + d, 0), sizeNames.count - 1))
        case .crt: setCRT(d > 0)
        case .strength: if crtOn { setFilter(filter, min(max(strength + 0.05 * Double(d), 0), 1)) }
        case .scanlines: if crtOn { setScanline(min(max(scanline + d, 0), 8)) }
        case .upscale: setUpscale(d > 0)
        case .edr: setEDR(d > 0)
        case .edrStrength: if edr { setEDRStrength(min(max(edrStrength + 0.05 * Double(d), 0), 1)) }
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA(min(max(aa + d, 0), aaNames.count - 1)) }
        case .interp: setInterp(min(max(interp + d, 0), interpNames.count - 1))
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[min(max(i + d, 0), anisoSteps.count - 1)]) }
        case .fps, .fpsQuick: setFps(d > 0)
        case .corner: if fps { setCorner((corner + d + 4) % 4) }
        case .fpsMs: setFpsMs(d > 0)
        case .frameTimes: setFrameTimes(d > 0)
        case .volume: setVolume(min(max(volume + 0.05 * Double(d), 0), 1))
        case .mod(let name): setMod(name, d > 0)
        case .cheat(let id): if let c = cheats.first(where: { $0.id == id }), c.kind == 0 { setCheat(c, d > 0) }
        default: break
        }
    }
    private func activate(_ n: Nav) {
        switch n {
        case .shot: front_qs_screenshot()
        case .record: record()
        case .fps, .fpsQuick: setFps(!fps)
        case .mute, .volume: setMuted(!muted)
        case .tab(let i): setPage(i); sel = firstOnPage
        case .pauseOpen: setPauseOpen(!pauseOpen)
        case .duckOpen: setDuck(!duckOpen)
        case .backup: backup()
        case .backupShow: showBackups()
        case .settingsShow: showSettingsFile()
        case .settingsOpen: openSettingsFile()
        case .defaultsSave: saveDefaults()
        case .defaultsUse: useDefaults()
        case .fullscreen: toggleFullscreen()
        case .scale: setScale((scale + 1) % sizeNames.count)
        case .crt: setCRT(!crtOn)
        case .scanlines: if crtOn { setScanline((scanline + 1) % 9) }
        case .upscale: setUpscale(!upscale)
        case .edr: setEDR(!edr)
        case .edrStrength: if edr { setEDRStrength(edrStrength >= 0.999 ? 0 : min(edrStrength + 0.25, 1)) }
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA((aa + 1) % aaNames.count) }
        case .interp: setInterp((interp + 1) % interpNames.count)
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[(i + 1) % anisoSteps.count]) }
        case .resetGraphics: resetGraphics()
        case .corner: if fps { setCorner((corner + 1) % 4) }
        case .fpsMs: setFpsMs(!fpsMs)
        case .frameTimes: setFrameTimes(!frameTimes)
        case .frameTimesFolder: showFrameTimes()
        case .resetPerformance: resetPerformance()
        case .capture(let p): picked = p; copyCapture()
        case .captureCopy: copyCapture()
        case .captureOpen: openCapture()
        case .captureReveal: revealCapture()
        case .showFolder: showCaptureFolder()
        case .changeFolder: chooseCaptureFolder()
        case .defaultFolder: defaultCaptureFolder()
        case .mod(let name): setMod(name, !wanted.contains(name))
        case .modUp(let name): moveMod(name, -1)
        case .modDown(let name): moveMod(name, 1)
        case .modsOpen: openModsFolder()
        case .modsRefresh: refresh()
        case .section(let s): toggleSection(s)
        case .cheat(let id): if let c = cheats.first(where: { $0.id == id }), c.kind == 0 { setCheat(c, !c.on) }
        case .cheatsAllOff: cheatsAllOff()
        case .cheatsRestore: restoreCheats()
        case .cheatsOpen: openCheatsFolder()
        case .cheatsRefresh: rescanCheats()
        case .key(let i): assign(i, pad: false)
        case .pad(let i): assign(i, pad: true)
        case .resetControls: resetControls()
        case .restart: restart()
        case .resume: close()
        case .quit: quit()
        case .strength: break
        }
    }
    // The legend: what the buttons do on the selection now, as this controller's glyphs or as keys
    var legend: [Hint] {
        let ok = pad ? Cap(symbol: glyphs[0], text: "A") : Cap(symbol: nil, text: "Return")
        let back = pad ? Cap(symbol: glyphs[1], text: "B") : Cap(symbol: nil, text: "Esc")
        let turn = pad ? [Cap(symbol: glyphs[2], text: "L"), Cap(symbol: glyphs[3], text: "R")] : [Cap(symbol: nil, text: "Tab")]
        let side = Cap(symbol: nil, text: pad ? "◀▶" : "←→")
        var r: [Hint] = []
        if let s = sel {
            if s == .volume { r.append(Hint(caps: [ok], text: muted ? "Unmute" : "Mute")); r.append(Hint(caps: [side], text: "Adjust")) }
            else if case .capture = s { r.append(Hint(caps: [ok], text: "Copy")); r.append(Hint(caps: [side], text: "Move")) }
            else if case .section(let n) = s { r.append(Hint(caps: [ok], text: folded.contains(n) ? "Open" : "Close")) }
            else if s.isValue && (rows.first(where: { $0.contains(s) })?.count ?? 1) == 1 {
                if s != .strength { r.append(Hint(caps: [ok], text: "Change")) }
                r.append(Hint(caps: [side], text: "Adjust"))
            } else {
                if case .tab = s { r.append(Hint(caps: [ok], text: "Open")) } else if case .mod = s { r.append(Hint(caps: [ok], text: "Change")) } else { r.append(Hint(caps: [ok], text: "Select")) }
                if (rows.first(where: { $0.contains(s) })?.count ?? 1) > 1 { r.append(Hint(caps: [side], text: "Move")) }
            }
        } else { r.append(Hint(caps: [Cap(symbol: nil, text: pad ? "▲▼" : "↑↓")], text: "Move")) }
        return r + [Hint(caps: [back], text: "Close"), Hint(caps: turn, text: "Page")]
    }
}

// The panel: Liquid Glass with a dark tint on macOS 26 and later, so the game behind does not compete with the text; a dark material before
// With Reduce Transparency or Increase Contrast on, a solid panel instead (after RetroReplay's PauseGlassSurface)
private struct Panel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(red: 0.14, green: 0.15, blue: 0.18), in: .rect(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(contrast == .increased ? 0.5 : 0.12)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.55)), in: .rect(cornerRadius: 26))
        } else {
            content.background(.ultraThickMaterial, in: .rect(cornerRadius: 26))
        }
    }
}
private struct GlassButton: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

// The controller / keyboard selection's mark: an accent outline around the selected item, which the scroll view keeps in sight
private struct NavMark: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content.padding(4).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 2).opacity(on ? 1 : 0)).padding(-4)
    }
}
extension View { fileprivate func nav(_ m: QuickSettings, _ n: Nav) -> some View { id(n).modifier(NavMark(on: m.sel == n)) } }

// "Next launch": on each setting that the game takes when it starts; orange while the choice differs from what this launch runs
private struct NextLaunchTag: View {
    let pending: Bool
    var body: some View {
        Text("Next launch").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
            .background((pending ? Color.orange : Color.white).opacity(pending ? 0.22 : 0.1), in: .capsule).foregroundStyle(pending ? Color.orange : Color.secondary)
            .help(pending ? "Changed: restart the game to apply it" : "Applies when the game next starts")
    }
}
// One row: a label of a fixed width on the left, the control filling the rest, so every control lines up. A dot before the label marks a setting changed from its default;
// nextLaunch (nil: applies at once) puts the tag under the label
private struct Row<C: View>: View {
    let title: String
    var changed = false
    var nextLaunch: Bool? = nil
    @ViewBuilder let control: () -> C
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).opacity(changed ? 1 : 0).help("Changed from the default")
                VStack(alignment: .leading, spacing: 3) { Text(title); if let n = nextLaunch { NextLaunchTag(pending: n) } }
            }.frame(width: 150, alignment: .leading)
            control().frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct QuickSettingsView: View {
    @ObservedObject var m: QuickSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compact = false   // a short window: tighter spacing
    private var motion: Animation? { reduceMotion ? nil : .snappy }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, compact ? 12 : 18).padding(.bottom, compact ? 8 : 12)
            quickBar.padding(.horizontal, 18).padding(.bottom, compact ? 8 : 12)
            tabBar.padding(.horizontal, 14).padding(.bottom, 8)
            Divider().padding(.horizontal, 22)
            ScrollViewReader { proxy in ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(pages[m.page].title).font(.title3.bold()).id("top")
                    pageBody
                }.padding(.horizontal, 22).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.automatic)
            .onChange(of: m.sel) { _, s in if let s { withAnimation(motion) { proxy.scrollTo(s, anchor: .center) } } }
            .onChange(of: m.page) { _, _ in proxy.scrollTo("top", anchor: .top) } }
            Divider().padding(.horizontal, 22)
            footer.padding(.horizontal, 22).padding(.top, compact ? 8 : 12).padding(.bottom, compact ? 10 : 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) { $0.size.height < 640 } action: { compact = $0 }
        .modifier(Panel())
        .padding(12)
        .environment(\.colorScheme, .dark)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick settings").font(compact ? .title2.bold() : .title.bold())
                Text(m.game).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: m.close) { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 22, height: 22) }
                .modifier(GlassButton(prominent: false)).buttonBorderShape(.circle).controlSize(.large).help("Close (Esc)")
        }
    }
    // What a player reaches for mid-game, on every page
    private var quickBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { front_qs_screenshot() } label: { Label("Screenshot", systemImage: "camera.viewfinder").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).help("Shift-Command-S").nav(m, .shot)
                Button { m.record() } label: { Label(m.recording ? "Stop" : "Record", systemImage: m.recording ? "stop.circle.fill" : "record.circle").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).tint(m.recording ? .red : nil).help("Shift-Command-R; records with sound").nav(m, .record)
                Button { m.setFps(!m.fps) } label: { Label("FPS", systemImage: "speedometer").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: m.fps)).help(m.fps ? "Hide the frame-rate counter" : "Show the frame-rate counter").nav(m, .fpsQuick)
            }.controlSize(.large)
            HStack(spacing: 10) {
                Button { m.setMuted(!m.muted) } label: {
                    Image(systemName: m.muted || m.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(m.muted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)).frame(width: 22, height: 22).contentShape(.rect)
                }.buttonStyle(.plain).keyboardShortcut("m", modifiers: []).help(m.muted ? "Unmute (M)" : "Mute (M)").nav(m, .mute)
                Slider(value: Binding(get: { m.muted ? 0 : m.volume }, set: { m.setVolume($0) }), in: 0...1)
                Text(m.muted ? "Muted" : "\(Int((m.volume * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }.help("Volume").nav(m, .volume)
        }
    }
    private func tabBadge(_ i: Int) -> Color? {
        switch i {
        case pCapture: return m.recording ? .red : nil
        case pMods: return m.modsOn > 0 ? .accentColor : nil
        case pCheats: return m.cheatsOn > 0 ? .accentColor : nil
        case pControls: return m.keyClash.isEmpty && m.padClash.isEmpty ? nil : .orange
        default: return nil
        }
    }
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(pages.indices, id: \.self) { i in
                let on = m.page == i
                Button { withAnimation(motion) { m.setPage(i) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: pages[i].icon).font(.title3).frame(height: 22)
                            .overlay(alignment: .topTrailing) { if let c = tabBadge(i) { Circle().fill(c).frame(width: 7, height: 7).offset(x: 6, y: -1) } }
                        Text(pages[i].tab).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background(.white.opacity(on ? 0.1 : 0), in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }.buttonStyle(.plain).help(pages[i].title).nav(m, .tab(i))
            }
        }
    }
    @ViewBuilder private var pageBody: some View {
        switch m.page {
        case pGeneral: general
        case pGraphics: graphics
        case pPerformance: performance
        case pCapture: capture
        case pMods: mods
        case pCheats: cheats
        default: controls
        }
    }
    private func subhead(_ t: String) -> some View { Text(t.uppercased()).font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary).padding(.top, 2) }
    private func note(_ t: String) -> some View { Text(t).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing) }
    private func resetButton(_ title: String, _ n: Nav, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion) { action() } } label: { Label(title, systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
            .modifier(GlassButton(prominent: false)).controlSize(.large).disabled(!enabled).padding(.top, 4).nav(m, n)
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 12) {
            subhead("While this menu is open")
            Row(title: "Pause the game", changed: !m.pauseOpen) {
                Toggle("Pause the game", isOn: Binding(get: { m.pauseOpen }, set: { m.setPauseOpen($0) })).toggleStyle(.switch).labelsHidden()
            }.nav(m, .pauseOpen)
            note(m.paused ? "Paused now: the game, its sound and its clock stop until you resume" : m.pauseOpen ? "The game stops a moment after this menu opens"
                 : "The game keeps running behind this menu, so graphics changes show at once")
            Row(title: "Quieter sound", changed: m.duckOpen) {
                Toggle("Quieter sound", isOn: Binding(get: { m.duckOpen }, set: { m.setDuck($0) })).toggleStyle(.switch).labelsHidden()
            }.nav(m, .duckOpen)
            note(m.pauseOpen ? "Used when the game is not paused: a quarter of the volume" : "A quarter of the volume while this menu is open")
            subhead("Save").padding(.top, 6)
            HStack(spacing: 10) {
                Button { m.backup() } label: { Label(m.backupBusy ? "Backing up…" : "Back up save now", systemImage: "externaldrive.badge.timemachine").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).disabled(m.backupBusy || SaveBackup.save == nil).nav(m, .backup)
                Button { m.showBackups() } label: { Label("Show", systemImage: "folder").frame(maxWidth: 90) }.modifier(GlassButton(prominent: false)).disabled(SaveBackup.folder == nil).nav(m, .backupShow)
            }.controlSize(.large)
            Group {
                if !m.backupNote.isEmpty { Label(m.backupNote, systemImage: m.backupBusy ? "clock" : "exclamationmark.triangle").foregroundStyle(m.backupBusy ? Color.secondary : Color.orange) }
                else if let d = m.lastBackup { Text("Last backup \(d.formatted(.relative(presentation: .named))). The NXForge Converter's Builds page restores it (Save snapshots).").foregroundStyle(.secondary) }
                else { Text("A checked copy of this game's save, kept beside it; the NXForge Converter's Builds page restores it.").foregroundStyle(.secondary) }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            if !m.settingsPath.isEmpty {
                subhead("Settings file").padding(.top, 6)
                Text(tilde(m.settingsPath)).font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                HStack(spacing: 10) {
                    Button { m.showSettingsFile() } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .settingsShow)
                    Button { m.openSettingsFile() } label: { Label("Open", systemImage: "doc.text").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .settingsOpen)
                }.controlSize(.large)
                Text("This game's settings as plain text, one per line, kept up to date as you change them. Edit it with the game closed, or reopen this menu after saving it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            subhead("My defaults").padding(.top, 6)
            HStack(spacing: 10) {
                Button { m.saveDefaults() } label: { Label("Make these my defaults", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .defaultsSave)
                if m.defaultsExist {
                    Button { withAnimation(motion) { m.useDefaults() } } label: { Label("Use my defaults", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .defaultsUse)
                }
            }.controlSize(.large)
            Text("Graphics, sound, the FPS counter, pausing and controls. A game opened for the first time starts with your defaults; mods, frame times and the capture folder stay per game.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var graphics: some View {
        VStack(alignment: .leading, spacing: 12) {
            if m.paused { Label("The game is paused: changes here show when it resumes. Turn off General › Pause the game to see them at once.", systemImage: "pause.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            subhead("Display")
            Row(title: "Full screen", changed: false) {
                Toggle("Full screen", isOn: Binding(get: { m.fullscreen }, set: { _ in m.toggleFullscreen() })).toggleStyle(.switch).labelsHidden()
            }.nav(m, .fullscreen)
            Row(title: "Picture size", changed: m.scale != 0) {
                Picker("Picture size", selection: Binding(get: { m.scale }, set: { m.setScale($0) })) {
                    ForEach(sizeNames.indices, id: \.self) { Text(sizeNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(scaleFixed)
            }.nav(m, .scale)
            note(scaleFixed ? "Set by DM_PRESENT_SCALE for this run" : m.scale == 1 ? "Fills the window; the picture may look wider or taller than the game draws it"
                 : m.scale == 2 ? "Each game pixel the same whole number of screen pixels: crisp pixel art, with a border" : "The game's shape, with black bars where the window is wider or taller")
            subhead("Look").padding(.top, 6)
            Row(title: "CRT filter", changed: m.crtOn) {
                Toggle("CRT filter", isOn: Binding(get: { m.crtOn }, set: { on in withAnimation(motion) { m.setCRT(on) } })).toggleStyle(.switch).labelsHidden().disabled(filterFixed)
            }.nav(m, .crt)
            note(filterFixed ? "Set by DM_PRESENT_FILTER for this run" : m.crtOn ? "Scanlines and an RGB mask, like an old TV" : "Off: the picture as the game draws it")
            if m.crtOn {
                Row(title: "Strength", changed: abs(m.strength - 0.5) > 0.001) {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { m.strength }, set: { m.setFilter(m.filter, $0) }), in: 0...1)
                        Text("\(Int((m.strength * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                    }
                }.nav(m, .strength)
                Row(title: "Line size", changed: m.scanline != 0) {
                    Picker("Line size", selection: Binding(get: { m.scanline }, set: { m.setScanline($0) })) {
                        Text("Auto").tag(0)
                        ForEach(1..<9) { Text("\($0) game row\($0 == 1 ? "" : "s")").tag($0) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_PRESENT_SCANLINE"] != nil)
                }.nav(m, .scanlines)
                note("Auto gives about 240 lines; for pixel art, pick the rows one art pixel covers")
            }
            subhead("Image quality").padding(.top, 6)
            // Upscaling: MetalFX's spatial scaler in place of the bilinear stretch wherever the window or screen is larger than the game's picture
            Row(title: "MetalFX upscaling", changed: !m.upscale) {
                Toggle("MetalFX upscaling", isOn: Binding(get: { m.upscale }, set: { m.setUpscale($0) })).toggleStyle(.switch).labelsHidden().disabled(upscaleFixed)
            }.nav(m, .upscale)
            note(upscaleFixed ? "Set by DM_PRESENT_UPSCALE for this run"
                 : m.upscale && m.crtOn ? "Not used while the CRT filter is on: it needs the game's own pixels"
                 : "Sharper than plain stretching when the window is larger than the game")
            // Anti-aliasing: FXAA over the game's picture, smoothing jagged edges in games without their own; it softens small HUD text a little
            Row(title: "Anti-aliasing", changed: m.aa != 0) {
                Picker("Anti-aliasing", selection: Binding(get: { m.aa }, set: { m.setAA($0) })) {
                    ForEach(aaNames.indices, id: \.self) { Text(aaNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_PRESENT_AA"] != nil)
            }.nav(m, .aa)
            // Anisotropic filtering: sharper textures on surfaces seen at an angle; the game's samplers take it when they are made, so it applies at the next start
            Row(title: "Anisotropic filtering", changed: m.aniso != anisoDefault, nextLaunch: env["DM_ANISO"] == nil ? m.anisoPending : nil) {
                Picker("Anisotropic filtering", selection: Binding(get: { m.aniso }, set: { m.setAniso($0) })) {
                    ForEach(anisoSteps, id: \.self) { Text($0 == 0 ? "Game default" : "\($0)x").tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_ANISO"] != nil)
            }.nav(m, .aniso)
            if env["DM_ANISO"] != nil { note("Set by DM_ANISO for this run") }
            // HDR highlights (EDR): the picture's brightest parts glow above SDR white on an XDR or HDR screen, an estimate from the game's SDR picture
            Row(title: "HDR highlights", changed: m.edr) {
                Toggle("HDR highlights", isOn: Binding(get: { m.edr }, set: { on in withAnimation(motion) { m.setEDR(on) } })).toggleStyle(.switch).labelsHidden().disabled(env["DM_PRESENT_EDR"] != nil)
            }.nav(m, .edr)
            if m.edr {
                Row(title: "Brightness boost", changed: abs(m.edrStrength - 0.5) > 0.001) {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { m.edrStrength }, set: { m.setEDRStrength($0) }), in: 0...1).disabled(env["DM_PRESENT_EDR_STRENGTH"] != nil)
                        Text("\(Int((m.edrStrength * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                    }
                }.nav(m, .edrStrength)
            }
            note(env["DM_PRESENT_EDR"] != nil ? "Set by DM_PRESENT_EDR for this run"
                 : m.edrHeadroom <= 1.01 ? "Needs an XDR or HDR screen; this one shows SDR, so the picture stays the same"
                 : "Sun, lava and shiny things glow brighter than white. White HUD text brightens too")
            resetButton("Reset graphics", .resetGraphics, enabled: m.graphicsChanged) { m.resetGraphics() }
        }
    }
    private var performance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Row(title: "Show FPS", changed: m.fps) { Toggle("Show FPS", isOn: Binding(get: { m.fps }, set: { on in withAnimation(motion) { m.setFps(on) } })).toggleStyle(.switch).labelsHidden() }.nav(m, .fps)
            if m.fps {
                Row(title: "Counter position", changed: m.corner != 0) {
                    Picker("Counter position", selection: Binding(get: { m.corner }, set: { m.setCorner($0) })) {
                        ForEach(0..<4) { Text(cornerNames[$0]).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                }.nav(m, .corner)
                Row(title: "Show milliseconds", changed: m.fpsMs) {
                    Toggle("Show milliseconds", isOn: Binding(get: { m.fpsMs }, set: { m.setFpsMs($0) })).toggleStyle(.switch).labelsHidden()
                }.nav(m, .fpsMs)
            }
            // Frame interpolation: an in-between picture on every other refresh of a 120 Hz screen, made from the game's last two frames (frame_interp.inc)
            Row(title: "Frame interpolation", changed: m.interp != 0) {
                Picker("Frame interpolation", selection: Binding(get: { m.interp }, set: { m.setInterp($0) })) {
                    ForEach(interpNames.indices, id: \.self) { Text(interpNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_PRESENT_INTERP"] != nil)
            }.nav(m, .interp)
            note(env["DM_PRESENT_INTERP"] != nil ? "Set by DM_PRESENT_INTERP for this run"
                 : m.interp == 2 && !m.interpActive ? "Auto: off on this screen, which runs below 120 Hz"
                 : "60 FPS games shown at 120 on a 120 Hz screen, about 8 ms later. Experimental: fast edges and the HUD can wobble")
            subhead("Frame times").padding(.top, 6)
            FrameGraph(paused: m.paused)
            subhead("Advanced").padding(.top, 6)
            Row(title: "Record frame times", changed: m.frameTimes, nextLaunch: env["DM_FRAME_TIMES"] == nil ? m.frameTimesPending : nil) {
                Toggle("Record frame times", isOn: Binding(get: { m.frameTimes }, set: { m.setFrameTimes($0) })).toggleStyle(.switch).labelsHidden()
            }.nav(m, .frameTimes)
            Group {
                if let now = m.frameTimesNow { Label("Recording this launch: \((now as NSString).lastPathComponent)", systemImage: "record.circle").foregroundStyle(.red) }
                else { Text("Each launch writes a file of frame times; the NXForge Converter's Builds page sums the newest one up.").foregroundStyle(.tertiary) }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            Button { m.showFrameTimes() } label: { Label("Show frame times", systemImage: "folder").frame(maxWidth: .infinity) }
                .modifier(GlassButton(prominent: false)).controlSize(.large).nav(m, .frameTimesFolder)
            resetButton("Reset performance", .resetPerformance, enabled: m.performanceChanged) { m.resetPerformance() }
        }
    }
    private var capture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot and Record are at the top of this menu. The picture is saved as you see it, filter included.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            subhead("Recent")
            if m.captures.isEmpty { Text("Nothing yet: your screenshots and recordings show here.").font(.callout).foregroundStyle(.tertiary) }
            else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(m.captures, id: \.self) { c in captureTile(c) }
                }
                HStack(spacing: 8) {
                    Button { m.copyCapture() } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .captureCopy)
                    Button { m.openCapture() } label: { Label("Open", systemImage: "eye").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .captureOpen)
                    Button { m.revealCapture() } label: { Label("Finder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .captureReveal)
                }.controlSize(.large).disabled(m.picked == nil)
            }
            subhead("Saved to").padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {   // where they go: by default beside the game, in the game folder
                if m.shotDir == m.recDir { Text(tilde(m.shotDir)).font(.callout).lineLimit(2).truncationMode(.middle) }
                else { Text("Screenshots: \(tilde(m.shotDir))").font(.callout).lineLimit(1).truncationMode(.middle); Text("Recordings: \(tilde(m.recDir))").font(.callout).lineLimit(1).truncationMode(.middle) }
            }.foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 10) {
                Button { m.showCaptureFolder() } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .showFolder)
                Button { m.chooseCaptureFolder() } label: { Label("Change…", systemImage: "folder.badge.gearshape").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .changeFolder)
            }.controlSize(.large)
            if m.customDir {
                Button { m.defaultCaptureFolder() } label: { Label("Use the game folder again", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).controlSize(.large).nav(m, .defaultFolder)
            }
            Text("Shift-Command-S takes a screenshot, Shift-Command-R starts and stops a recording.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func captureTile(_ c: CaptureFile) -> some View {
        let on = m.picked == c.path
        return Button { m.picked = c.path } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let img = m.thumbs[c.path] { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
                    else { Rectangle().fill(.white.opacity(0.06)) }
                }.frame(height: 72).frame(maxWidth: .infinity).clipped()
                if c.video { Image(systemName: "video.fill").font(.caption2).padding(4).background(.black.opacity(0.5), in: .rect(cornerRadius: 4)).padding(4) }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.accentColor : .white.opacity(0.12), lineWidth: on ? 2 : 1))
            .contentShape(.rect)
        }.buttonStyle(.plain).help("\((c.path as NSString).lastPathComponent), \(c.date.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu {
            Button("Copy") { m.picked = c.path; m.copyCapture() }
            Button("Open") { m.picked = c.path; m.openCapture() }
            Button("Show in Finder") { m.picked = c.path; m.revealCapture() }
        }
        .onTapGesture(count: 2) { m.picked = c.path; m.openCapture() }
        .nav(m, .capture(c.path))
    }
    private var mods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each folder in this game's mods folder replaces game files. Enabled mods load from the top down; when two have the same file, the higher one wins. The arrows change the order.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if m.mods.isEmpty {
                Text("No mods yet. Put each mod in a folder of its own in the mods folder (its files, a romfs folder holding them, or a mod as downloaded for Atmosphere), then Refresh.")
                    .font(.callout).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(m.mods.enumerated()), id: \.element) { i, n in
                let on = m.wanted.contains(n)
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: 2) {
                        Button { withAnimation(motion) { m.moveMod(n, -1) } } label: { Image(systemName: "chevron.up").frame(width: 18, height: 14) }.buttonStyle(.plain).disabled(i == 0).help("Load earlier: wins over the ones below").nav(m, .modUp(n))
                        Button { withAnimation(motion) { m.moveMod(n, 1) } } label: { Image(systemName: "chevron.down").frame(width: 18, height: 14) }.buttonStyle(.plain).disabled(i == m.mods.count - 1).help("Load later").nav(m, .modDown(n))
                    }.foregroundStyle(.secondary).padding(.top, 2)
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(n).font(.body.weight(.medium))
                            if let run = m.modsRun {
                                if m.modPending(n) { NextLaunchTag(pending: true) }
                                else { Text(run.contains(n) ? "Loaded" : "Off").font(.caption).foregroundStyle(.secondary) }
                            } else { Text("Not used: DM_ROMFS_OVERLAY is set").font(.caption).foregroundStyle(.secondary) }
                            if on, let c = m.modClash[n] { Label(c, systemImage: "square.on.square").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(n, isOn: Binding(get: { on }, set: { m.setMod(n, $0) })).toggleStyle(.switch).labelsHidden()
                    }.nav(m, .mod(n))
                }
            }
            if m.modOrderPending { HStack(spacing: 6) { Text("Load order").font(.caption); NextLaunchTag(pending: true) } }
            HStack(spacing: 10) {
                Button { m.openModsFolder() } label: { Label("Open mods folder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .modsOpen)
                Button { withAnimation(motion) { m.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .modsRefresh)
            }.controlSize(.large)
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a key or button, then press the new one; Esc cancels. A key another button already has swaps with it. Saved for this game.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !m.keyClash.isEmpty || !m.padClash.isEmpty {
                Label("\(m.keyClash.count + m.padClash.count) buttons share a key or button with another (marked below). Choose a new one, or Reset controls.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            subhead("Keyboard").padding(.top, 4)
            ForEach(actionNames.indices, id: \.self) { i in Row(title: actionNames[i]) { assignButton(i, pad: false) }.nav(m, .key(i)) }
            subhead("Controller").padding(.top, 6)
            ForEach(padDefaults.indices, id: \.self) { i in Row(title: actionNames[i]) { assignButton(i, pad: true) }.nav(m, .pad(i)) }
            Text("A controller's D-pad and sticks stay as they are. Its Home button, or − and + together, opens this menu.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            resetButton("Reset controls", .resetControls, enabled: true) { m.resetControls() }
        }
    }
    private func assignButton(_ i: Int, pad: Bool) -> some View {
        let waiting = m.assigning == i * 2 + (pad ? 1 : 0), name = pad ? m.padNames[i] : m.keyNames[i]
        let clash = pad ? m.padClash[i] : m.keyClash[i], unset = name == "Not set"
        return VStack(alignment: .trailing, spacing: 2) {
            Button { m.assign(i, pad: pad) } label: {
                Text(waiting ? (pad ? "Press a button…" : "Press a key…") : name).lineLimit(1).frame(minWidth: 130)
            }.modifier(GlassButton(prominent: waiting)).tint(clash != nil || unset ? .orange : nil)
            if let c = clash { Text("Also on \(c)").font(.caption2).foregroundStyle(.orange) }
        }
    }
    private var cheats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atmosphère cheat codes from this game build's .txt file in the cheats folder. The Cheats menu (⇧⌘C) has the full panel: sections, values and imports.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Row(title: "Game build") {
                HStack(spacing: 6) {
                    Text(m.cheatsVersion.isEmpty ? m.cheatsBuild : "\(m.cheatsVersion) · \(m.cheatsBuild)").font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.cheatsBuild, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy the build ID: the cheat file is named after it")
                }
            }
            if m.cheatsSafe {
                Label("The last run ended without a clean exit, so every cheat starts off.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(motion) { m.restoreCheats() } } label: { Label("Restore saved cheats", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).nav(m, .cheatsRestore)
            }
            if m.cheats.isEmpty {
                Text("No cheats for this build. Put Atmosphère's \(m.cheatsBuild).txt in the cheats folder, then Refresh.")
                    .font(.callout).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if m.cheats.filter({ !$0.label }).count > 8 {
                TextField("Search cheats", text: $m.cheatSearch).textFieldStyle(.roundedBorder)
            }
            ForEach(Array(m.cheatGroups.enumerated()), id: \.offset) { _, g in
                if !g.section.isEmpty && m.cheatSearch.isEmpty {
                    let open = !m.folded.contains(g.section), live = g.rows.filter { $0.kind == 0 }, nOn = live.filter(\.on).count
                    Button { withAnimation(motion) { m.toggleSection(g.section) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(open ? 90 : 0))
                            Text(g.section).font(.callout.weight(.semibold))
                            Spacer(minLength: 4)
                            Text(nOn > 0 ? "\(nOn) of \(live.count) on" : "\(live.count)").font(.caption).foregroundStyle(nOn > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }.contentShape(.rect)
                    }.buttonStyle(.plain).padding(.top, 4).nav(m, .section(g.section))
                    if open { ForEach(g.rows) { c in cheatRow(c) } }
                } else { ForEach(g.rows) { c in cheatRow(c) } }
            }
            if !m.cheatSearch.isEmpty && m.cheatGroups.first?.rows.isEmpty != false { Text("No cheat matches “\(m.cheatSearch)”.").font(.callout).foregroundStyle(.tertiary) }
            if m.cheatsOn > 0 {
                Button { withAnimation(motion) { m.cheatsAllOff() } } label: { Label("Turn all off (\(m.cheatsOn) on)", systemImage: "power").frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: false)).controlSize(.large).nav(m, .cheatsAllOff)
            }
            HStack(spacing: 10) {
                Button { m.openCheatsFolder() } label: { Label("Open cheats folder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .cheatsOpen)
                Button { withAnimation(motion) { m.rescanCheats() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .cheatsRefresh)
            }.controlSize(.large)
        }
    }
    @ViewBuilder private func cheatRow(_ c: Cheat) -> some View {
        if c.label {
            Text(c.name).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.body.weight(.medium))
                    if !c.note.isEmpty { Text(c.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if c.master { Text("Master code: always on").font(.caption).foregroundStyle(.secondary) }
                    else if c.disabled { Label(c.why.isEmpty ? "Off: this host cannot run it" : c.why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    else if c.once { Text("Applied once, then it turns itself off").font(.caption).foregroundStyle(.secondary) }
                    else { Text(c.on ? "Active" : "Off").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle(c.name, isOn: Binding(get: { c.on || c.master }, set: { m.setCheat(c, $0) })).toggleStyle(.switch).labelsHidden().disabled(c.kind != 0)
            }.nav(m, .cheat(c.id))
        }
    }
    private var footer: some View {
        VStack(spacing: 10) {
            if m.restartCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    Text(m.restartCount == 1 ? "1 change applies after a restart" : "\(m.restartCount) changes apply after a restart").font(.callout)
                    Spacer(minLength: 4)
                    if m.canRestart {
                        Button { m.restart() } label: { Text(m.restartArmed ? "Press again" : "Restart game") }
                            .modifier(GlassButton(prominent: m.restartArmed)).tint(.orange).help("Quits and starts the game again. Asks twice.").nav(m, .restart)
                    }
                }
                Text(m.pendingNames.joined(separator: ", ") + (m.canRestart ? "" : ". Quit and open the game again to apply."))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: m.close) { Text("Resume game").font(.headline).frame(maxWidth: .infinity) }
                    .modifier(GlassButton(prominent: true)).controlSize(.extraLarge).keyboardShortcut(.defaultAction).nav(m, .resume)
                Button(action: m.quit) { Label(m.quitArmed ? "Press again" : "Quit", systemImage: "power").frame(minWidth: 96) }
                    .modifier(GlassButton(prominent: false)).controlSize(.extraLarge).tint(m.quitArmed ? Color.red : nil).help("Ends the game, as ⌘Q does. Asks twice.").nav(m, .quit)
            }
            legend
            Text("NXForge Sidebar \(SIDEBAR_VERSION)").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                .help("The sidebar's own version (SIDEBAR_CHANGELOG.md), separate from NXForge's release")
        }
    }
    // The button legend: what works on the selection now (Nav, QuickSettings.legend), in the controller's own glyphs while a controller drives the sidebar
    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(m.legend, id: \.self) { h in
                HStack(spacing: 5) {
                    HStack(spacing: 3) { ForEach(h.caps, id: \.self) { capView($0) } }
                    Text(h.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
    }
    @ViewBuilder private func capView(_ c: Cap) -> some View {
        if let s = c.symbol { Image(systemName: s).font(.body).foregroundStyle(.primary) }
        else {
            Text(c.text).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.18)))
        }
    }
}
// The Performance page's frame-time graph: the time between the last presents (front.h mtl_present_times, about four seconds at 60 FPS), redrawn four times a second while the
// page shows, with lines at 60 and 30 FPS; under it the average, the 1% low (the slowest 1% of frames as a rate) and the longest frame
struct FrameGraph: View {
    let paused: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let (v, age) = FrameGraph.sample()
            VStack(alignment: .leading, spacing: 6) {
                Canvas { ctx, size in
                    let top = 50.0   // ms at the top of the graph
                    func y(_ ms: Double) -> CGFloat { size.height * (1 - CGFloat(min(ms, top) / top)) }
                    for (ms, label) in [(1000.0 / 60, "60"), (1000.0 / 30, "30")] {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y(ms))); p.addLine(to: CGPoint(x: size.width, y: y(ms)))
                        ctx.stroke(p, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ctx.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: size.width - 2, y: y(ms) - 6), anchor: .trailing)
                    }
                    guard v.count > 1 else { return }
                    let w = size.width / CGFloat(max(v.count, 120))
                    for (i, ms) in v.enumerated() {
                        let r = CGRect(x: CGFloat(i) * w, y: y(ms), width: max(w - 0.5, 1), height: size.height - y(ms))
                        ctx.fill(Path(r), with: .color(ms > 1000.0 / 30 + 2 ? .orange : ms > 1000.0 / 60 + 2 ? .yellow.opacity(0.85) : .green.opacity(0.85)))
                    }
                }.frame(height: 70).background(.white.opacity(0.05), in: .rect(cornerRadius: 8))
                Text(FrameGraph.summary(v, age: age, paused: paused)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
    static func sample() -> ([Double], Double) {
        var buf = [Double](repeating: 0, count: 240), age = -1.0
        let n = Int(mtl_present_times(&buf, 240, &age))
        return (Array(buf.prefix(n)).filter { $0 > 0 && $0 < 1000 }, age)
    }
    static func summary(_ v: [Double], age: Double, paused: Bool) -> String {
        if paused { return "Paused: the graph starts again when the game resumes" }
        if v.count < 10 || age > 1000 { return "No frames in the last second" }
        let avg = v.reduce(0, +) / Double(v.count), sorted = v.sorted()
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        return String(format: "%.0f FPS average · 1%% low %.0f FPS · longest %.1f ms", 1000 / avg, 1000 / p99, sorted.last ?? 0)
    }
}
private func tilde(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }
private struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 5) { configuration.icon.font(.system(size: 6)); configuration.title } }
}

// Toasts: a glass capsule over the top of the game picture for 2 seconds; a new one replaces the one showing
final class ToastModel: ObservableObject { @Published var text: String? }
private struct ToastView: View {
    @ObservedObject var t: ToastModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack {
            if let text = t.text {
                Text(text).font(.callout.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 10).modifier(ToastSurface())
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }.padding(.top, 18).frame(maxWidth: .infinity).environment(\.colorScheme, .dark).animation(reduceMotion ? nil : .snappy, value: t.text)
    }
}
private struct ToastSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency { content.glassEffect(.regular.tint(.black.opacity(0.4)), in: .capsule) }
        else { content.background(Color(red: 0.14, green: 0.15, blue: 0.18), in: .capsule) }
    }
}
private final class PassThroughHost: NSHostingView<ToastView> { override func hitTest(_ point: NSPoint) -> NSView? { nil } }   // clicks go to the game under it
private let toastModel = ToastModel()
private var toastHost: PassThroughHost?
private var toastSerial = 0
@_cdecl("dm_qs_toast")
public func dm_qs_toast(_ parent: UnsafeMutableRawPointer, _ msg: UnsafePointer<CChar>) {
    let p = Unmanaged<NSView>.fromOpaque(parent).takeUnretainedValue()
    if toastHost?.superview !== p {
        toastHost?.removeFromSuperview()
        let h = PassThroughHost(rootView: ToastView(t: toastModel)); h.frame = NSRect(x: 0, y: p.bounds.height - 90, width: p.bounds.width, height: 90)
        h.autoresizingMask = [.width, .minYMargin]; p.addSubview(h, positioned: .above, relativeTo: nil); toastHost = h
    } else if let h = toastHost { p.addSubview(h, positioned: .above, relativeTo: nil) }   // over a sidebar opened since
    toastModel.text = String(cString: msg); toastSerial += 1; let serial = toastSerial
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if toastSerial == serial { toastModel.text = nil } }
}

private var shared: QuickSettings?
@_cdecl("dm_qs_make")
public func dm_qs_make(_ game: UnsafePointer<CChar>, _ modsDir: UnsafePointer<CChar>, _ modsRun: UnsafePointer<CChar>?,
                       _ close: @escaping @convention(c) () -> Void, _ fps: @escaping @convention(c) () -> Void) -> UnsafeMutableRawPointer {
    let run = modsRun.map { String(cString: $0).split(separator: "\n").map(String.init) }   // in load order
    let m = QuickSettings(game: String(cString: game), modsDir: String(cString: modsDir), modsRunOrder: run, close: { close() }, fpsChanged: { fps() })
    shared = m
    let v = NSHostingView(rootView: QuickSettingsView(m: m))
    v.sizingOptions = []   // front_mac.m sizes it: the right of the game window, full height
    return Unmanaged.passRetained(v).toOpaque()
}
@_cdecl("dm_qs_nav")
public func dm_qs_nav(_ cmd: Int32) { shared?.nav(cmd) }
@_cdecl("dm_qs_captures_changed")
public func dm_qs_captures_changed() { shared?.refreshCaptures() }
@_cdecl("dm_qs_refresh")
public func dm_qs_refresh() { shared?.refresh() }
@_cdecl("dm_qs_opened")
public func dm_qs_opened(_ pad: Int32) {
    guard let m = shared else { return }
    m.quitArmed = false; m.restartArmed = false
    if pad != 0 { m.pad = true; m.sel = m.firstOnPage } else { m.sel = nil }
}
@_cdecl("dm_qs_input")
public func dm_qs_input(_ pad: Int32, _ ok: UnsafePointer<CChar>?, _ back: UnsafePointer<CChar>?, _ prev: UnsafePointer<CChar>?, _ next: UnsafePointer<CChar>?) {
    guard let m = shared else { return }
    if m.pad != (pad != 0) { m.pad = pad != 0 }
    if pad != 0, let ok { m.glyphs = [ok, back, prev, next].map { $0.map { String(cString: $0) } } }
}
