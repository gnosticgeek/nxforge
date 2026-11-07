// Quick settings sidebar (front_mac.m opens and closes it; quick_settings_mac.h is the C side): SwiftUI with the system's controls, on a Liquid Glass panel on macOS 26 and later
// (a material panel before). The settings are front_mac.m's: the same user defaults keys (per game), the same rule that a setting the environment names wins and is not saved.
// Layout, top to bottom: a quick bar (Screenshot, Record, the FPS counter, volume), a row of page tabs (Graphics, FPS, Capture, Mods, Cheats, Controls; L / R or Tab turn the page),
// the page, and a footer with what needs a restart (Restart game), Resume and Quit, and a legend of the buttons that work on the selection, in the controller's own glyphs or as keys.
// The filter (off or CRT; the engine's other filters stay for DM_PRESENT_FILTER), its strength and line size go to the graphics backend at once (front.h mtl_present_*); the frame-rate
// counter is drawn by front_mac.m, told through the fps callback; mods are the folders of this game's mods folder, overlaid at the next launch (front_mac.m mods_start); cheats are the
// host's (hle_cheats.c dm_cheat*): this build's Atmosphère cheat file, a switch each, which the host saves beside the file (<build ID>.enabled) and runs from the next frame. The Cheats
// menu and panel (front_mac.m) show the same rows. Settings that apply at the next launch (anisotropic filtering, frame times, mods) carry a "Next launch" tag, orange while they differ
// from what this launch runs, and the footer counts those
import AppKit
import SwiftUI

// The sidebar's own version, released as tags sidebar-vX.Y.Z with SIDEBAR_CHANGELOG.md (UPSTREAM.md, Versions); shown under the footer's legend.
// scripts/release_check.py reads this line: bump it with a new SIDEBAR_CHANGELOG.md entry when the sidebar changes.
let SIDEBAR_VERSION = "0.1.0"

private let env = ProcessInfo.processInfo.environment
private let pfxCRT = Int(DM_PFX_CRT)   // front.h DM_PFX_*: the sidebar offers off (0) and CRT
private let filterFixed = env["DM_PRESENT_FILTER"] != nil
private let cornerNames = ["Top left", "Top right", "Bottom left", "Bottom right"]
private let anisoSteps = [0, 2, 4, 8, 16]   // front.h mtl_aniso_set: 0 is the game's own
private let anisoDefault = 16               // front_mac.m graphics_start: 16x until a choice is saved
private let aaNames = ["Off", "FXAA"]   // front.h DM_PAA_*, in that order
// Upscaling is the settings window's setting too (launcher.DM_PRESENT_UPSCALE): fixed here only when the launch environment or an env file set it, not when the window or a saved choice did
private let upscaleFixed = env["DM_PRESENT_UPSCALE"] != nil && (env["DM_ENV_LAUNCH_KEYS"] == nil
    || Set(((env["DM_ENV_LAUNCH_KEYS"] ?? "") + " " + (env["DM_ENV_FILE_KEYS"] ?? "")).split(separator: " ").map(String.init)).contains("DM_PRESENT_UPSCALE"))

// The Controls page's rows: actions 0–15 are the Switch's buttons in NpadButton order, 16–19 the left stick, 20 shaking (front_mac.m's map); the controller map has the first 12
private let actionNames = ["A", "B", "X", "Y", "Left stick press", "Right stick press", "L", "R", "ZL", "ZR", "+ (Plus)", "− (Minus)", "D-pad left", "D-pad up", "D-pad right", "D-pad down",
                           "Left stick up", "Left stick left", "Left stick down", "Left stick right", "Shake"]
private let keyDefaults = ["J", "K", "U", "I", "F", "G", "Q", "E", "Z", "C", "Return", "Tab", "←", "↑", "→", "↓", "W", "A", "S", "D", "Space"]
private let padDefaults = ["Right button", "Bottom button", "Top button", "Left button", "Left stick press", "Right stick press", "Left shoulder", "Right shoulder",
                           "Left trigger", "Right trigger", "Menu", "Options"]
// The pages, in tab order: a short name for the tab, a longer one over the page
private let pages: [(tab: String, title: String, icon: String)] = [("Graphics", "Graphics", "display"), ("FPS", "Performance", "chart.bar.fill"), ("Capture", "Capture", "camera"),
                                                                  ("Mods", "Mods", "puzzlepiece.extension"), ("Cheats", "Cheats", "wand.and.stars"), ("Controls", "Controls", "gamecontroller")]
// What the controller and keyboard selection can be on (dm_qs_nav)
enum Nav: Hashable {
    case shot, record, fpsQuick, volume, tab(Int)
    case crt, strength, scanlines, upscale, aa, aniso, resetGraphics
    case fps, corner, frameTimes, frameTimesFolder, resetPerformance
    case showFolder, changeFolder, defaultFolder
    case mod(String), modsOpen, modsRefresh
    case cheat(Int), cheatsRestore, cheatsOpen, cheatsRefresh
    case key(Int), pad(Int), resetControls
    case restart, resume, quit
    /// A setting with a value: left and right change it
    var isValue: Bool {
        switch self {
        case .volume, .crt, .strength, .scanlines, .upscale, .aa, .aniso, .fps, .fpsQuick, .corner, .frameTimes, .mod, .cheat: return true
        default: return false
        }
    }
}
struct Cheat: Identifiable {
    let id: Int, name: String, why: String, note: String, kind: Int32, on: Bool, flags: Int32
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

final class QuickSettings: ObservableObject {
    let game: String, modsDir: String, modsRun: Set<String>?, close: () -> Void, fpsChanged: () -> Void
    let canRestart = front_qs_can_restart() != 0
    @Published var filter = 0
    @Published var strength = 0.5
    @Published var scanline = 0
    @Published var fps = false
    @Published var corner = 0
    @Published var frameTimes = false   // record from the next launch
    @Published var mods: [String] = []
    @Published var wanted: [String] = []
    @Published var cheats: [Cheat] = []
    @Published var cheatsBuild = ""
    @Published var cheatsVersion = ""
    @Published var cheatsSafe = false
    @Published var page: Int
    @Published var volume = 1.0
    @Published var recording = false
    @Published var shotDir = ""
    @Published var upscale = false   // MetalFX where the picture is shown larger than the game renders it
    @Published var aa = 0            // the present's anti-aliasing (DM_PAA_*)
    @Published var aniso = 0      // the chosen anisotropic filtering floor (0: the game's own)
    @Published var anisoRun = 0   // the one this launch took
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
    init(game: String, modsDir: String, modsRun: Set<String>?, close: @escaping () -> Void, fpsChanged: @escaping () -> Void) {
        self.game = game; self.modsDir = modsDir; self.modsRun = modsRun; self.close = close; self.fpsChanged = fpsChanged
        page = min(max(UserDefaults.standard.integer(forKey: "DMQuickSettings.page.\(game)"), 0), pages.count - 1)
        refresh()
    }
    private func pfxKey(_ what: String) -> String { "DMPresentFilter.\(what).\(game)" }
    private func optKey(_ what: String) -> String { "DMQuickSettings.\(what).\(game)" }
    func refresh() {
        var k: Float = 0.5
        filter = Int(mtl_present_filter(&k)); strength = Double(k); scanline = Int(mtl_present_scanline())
        let d = UserDefaults.standard
        if let e = env["DM_SHOW_FPS"] { fps = (Int(e) ?? 0) != 0 } else { fps = d.bool(forKey: optKey("fps")) }
        corner = min(max(d.integer(forKey: optKey("fpsPos")), 0), 3)
        if let e = env["DM_FRAME_TIMES"] { frameTimes = (Int(e) ?? 0) != 0 } else { frameTimes = d.bool(forKey: optKey("frameTimes")) }
        wanted = d.stringArray(forKey: optKey("mods")) ?? []
        volume = Double(dm_audio_volume()); recording = front_qs_recording() != 0
        assigning = Int(front_qs_assigning())
        anisoRun = Int(mtl_aniso()); aniso = env["DM_ANISO"] != nil || d.object(forKey: optKey("aniso")) == nil ? anisoRun : d.integer(forKey: optKey("aniso"))   // unsaved: front_mac.m's 16x
        upscale = mtl_present_upscale() != 0; aa = Int(mtl_present_aa())
        shotDir = String(cString: front_qs_capture_folder(0)); recDir = String(cString: front_qs_capture_folder(1)); customDir = front_qs_capture_custom() != 0
        let kn = d.dictionary(forKey: optKey("keyNames")) as? [String: String] ?? [:], pn = d.dictionary(forKey: optKey("padNames")) as? [String: String] ?? [:]
        keyNames = keyDefaults.indices.map { kn[String($0)] ?? keyDefaults[$0] }; padNames = padDefaults.indices.map { pn[String($0)] ?? padDefaults[$0] }
        let fm = FileManager.default
        mods = ((try? fm.contentsOfDirectory(atPath: modsDir)) ?? []).filter { n in
            var dir: ObjCBool = false
            return !n.hasPrefix(".") && fm.fileExists(atPath: (modsDir as NSString).appendingPathComponent(n), isDirectory: &dir) && dir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        refreshCheats()
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
                         kind: dm_cheat_kind_at(Int32(i)), on: dm_cheat_on_at(Int32(i)) != 0, flags: f)
        }
        cheatsBuild = cheatText(dm_cheats_build()).uppercased()
        cheatsVersion = cheatText(dm_cheats_version()); cheatsSafe = dm_cheats_safe() != 0
    }
    func setCheat(_ c: Cheat, _ on: Bool) { if c.on != on { dm_cheat_toggle(Int32(c.id)) }; refreshCheats() }
    func rescanCheats() { dm_cheats_reload(); refreshCheats() }
    func restoreCheats() { dm_cheats_safe_restore(); refreshCheats() }
    func openCheatsFolder() {
        let dir = cheatText(dm_cheats_dir_path()); if dir.isEmpty { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
    var cheatsOn: Int { cheats.filter { $0.on && $0.kind == 0 }.count }
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
    func setScanline(_ r: Int) {
        mtl_present_scanline_set(Int32(r)); scanline = r
        if env["DM_PRESENT_SCANLINE"] == nil { UserDefaults.standard.set(r, forKey: pfxKey("scanline")) }
    }
    var graphicsChanged: Bool { filter != 0 || abs(strength - 0.5) > 0.001 || scanline != 0 || !upscale || aa != 0 || aniso != anisoDefault }
    func resetGraphics() {   // each setting the environment does not fix, back to the Mac's default
        if !filterFixed { setFilter(0, 0.5) }
        if env["DM_PRESENT_SCANLINE"] == nil { setScanline(0) }
        setUpscale(true)
        if env["DM_PRESENT_AA"] == nil { setAA(0) }
        if env["DM_ANISO"] == nil { setAniso(anisoDefault) }
    }
    func setFps(_ on: Bool) { fps = on; if env["DM_SHOW_FPS"] == nil { UserDefaults.standard.set(on, forKey: optKey("fps")) }; fpsChanged() }
    func setCorner(_ c: Int) { corner = c; UserDefaults.standard.set(c, forKey: optKey("fpsPos")); fpsChanged() }
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
    var performanceChanged: Bool { fps || corner != 0 || frameTimes }
    func resetPerformance() {
        if env["DM_SHOW_FPS"] == nil && fps { setFps(false) }
        if corner != 0 { setCorner(0) }
        if env["DM_FRAME_TIMES"] == nil && frameTimes { setFrameTimes(false) }
    }
    func setMod(_ n: String, _ on: Bool) {
        wanted.removeAll { $0 == n }; if on { wanted.append(n) }
        UserDefaults.standard.set(wanted, forKey: optKey("mods"))
    }
    func setVolume(_ v: Double) { volume = v; dm_audio_volume_set(Float(v)); UserDefaults.standard.set(v, forKey: optKey("volume")) }
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

    // What applies at the next launch: one count for the footer, the same test as each row's tag
    var anisoPending: Bool { env["DM_ANISO"] == nil && aniso != anisoRun }
    var frameTimesPending: Bool { env["DM_FRAME_TIMES"] == nil && frameTimes != (frameTimesNow != nil) }
    func modPending(_ n: String) -> Bool { modsRun.map { $0.contains(n) != wanted.contains(n) } ?? false }
    var restartCount: Int { (anisoPending ? 1 : 0) + (frameTimesPending ? 1 : 0) + mods.filter(modPending).count }
    /// Restart game (front_mac.m front_qs_restart): the first press arms it, the second quits and the launcher starts the game again
    func restart() { if restartArmed { front_qs_restart() } else { restartArmed = true } }
    /// Quit game (after the NxNative Launcher's hold-Home exit): the first press arms it, the second ends the game as ⌘Q does
    func quit() { if quitArmed { NSApp.terminate(nil) } else { quitArmed = true } }

    // Controller and keyboard navigation (after RetroReplay's pause menu): a selection over rows of items. Up and down move between rows; left and right change a
    // setting's value, or move along a row of buttons (the quick bar, the tabs, the footer); L / R (Tab / Shift-Tab) turn the page
    func pageRows(_ p: Int) -> [[Nav]] {
        switch p {
        case 0: return [[.crt]] + (crtOn ? [[.strength], [.scanlines]] : []) + [[.upscale], [.aa], [.aniso], [.resetGraphics]]
        case 1: return [[.fps]] + (fps ? [[.corner]] : []) + [[.frameTimes], [.frameTimesFolder], [.resetPerformance]]
        case 2: return [[.showFolder, .changeFolder]] + (customDir ? [[.defaultFolder]] : [])
        case 3: return mods.map { [.mod($0)] } + [[.modsOpen, .modsRefresh]]
        case 4: return (cheatsSafe ? [[.cheatsRestore]] : []) + cheats.filter { !$0.label }.map { [.cheat($0.id)] } + [[.cheatsOpen, .cheatsRefresh]]
        case 5: return actionNames.indices.map { [.key($0)] } + padDefaults.indices.map { [.pad($0)] } + [[.resetControls]]
        default: return []
        }
    }
    var rows: [[Nav]] {
        var r: [[Nav]] = [[.shot, .record, .fpsQuick], [.volume], pages.indices.map { .tab($0) }] + pageRows(page)
        if restartCount > 0 && canRestart { r.append([.restart]) }
        return r + [[.resume, .quit]]
    }
    var firstOnPage: Nav { pageRows(page).first?.first ?? .tab(page) }
    func setPage(_ p: Int) { page = p; UserDefaults.standard.set(p, forKey: optKey("page")) }
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
            if rs[ri].count > 1 {
                let n = rs[ri][min(max(ci + d, 0), rs[ri].count - 1)]; sel = n
                if case .tab(let i) = n { setPage(i) }
            } else { adjust(cur, d) }
        case 5: activate(cur)
        default: break
        }
    }
    private func adjust(_ n: Nav, _ d: Int) {
        switch n {
        case .crt: setCRT(d > 0)
        case .strength: if crtOn { setFilter(filter, min(max(strength + 0.05 * Double(d), 0), 1)) }
        case .scanlines: if crtOn { setScanline(min(max(scanline + d, 0), 8)) }
        case .upscale: setUpscale(d > 0)
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA(min(max(aa + d, 0), aaNames.count - 1)) }
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[min(max(i + d, 0), anisoSteps.count - 1)]) }
        case .fps, .fpsQuick: setFps(d > 0)
        case .corner: if fps { setCorner((corner + d + 4) % 4) }
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
        case .tab(let i): setPage(i); sel = firstOnPage
        case .crt: setCRT(!crtOn)
        case .scanlines: if crtOn { setScanline((scanline + 1) % 9) }
        case .upscale: setUpscale(!upscale)
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA((aa + 1) % aaNames.count) }
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[(i + 1) % anisoSteps.count]) }
        case .resetGraphics: resetGraphics()
        case .corner: if fps { setCorner((corner + 1) % 4) }
        case .frameTimes: setFrameTimes(!frameTimes)
        case .frameTimesFolder: showFrameTimes()
        case .resetPerformance: resetPerformance()
        case .showFolder: showCaptureFolder()
        case .changeFolder: chooseCaptureFolder()
        case .defaultFolder: defaultCaptureFolder()
        case .mod(let name): setMod(name, !wanted.contains(name))
        case .modsOpen: openModsFolder()
        case .modsRefresh: refresh()
        case .cheat(let id): if let c = cheats.first(where: { $0.id == id }), c.kind == 0 { setCheat(c, !c.on) }
        case .cheatsRestore: restoreCheats()
        case .cheatsOpen: openCheatsFolder()
        case .cheatsRefresh: rescanCheats()
        case .key(let i): assign(i, pad: false)
        case .pad(let i): assign(i, pad: true)
        case .resetControls: resetControls()
        case .restart: restart()
        case .resume: close()
        case .quit: quit()
        case .strength, .volume: break
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
            if s.isValue {
                if s != .strength && s != .volume { r.append(Hint(caps: [ok], text: "Change")) }
                r.append(Hint(caps: [side], text: "Adjust"))
            } else {
                if case .tab = s { r.append(Hint(caps: [ok], text: "Open")) } else { r.append(Hint(caps: [ok], text: "Select")) }
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
                Image(systemName: m.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(.secondary).frame(width: 22)
                Slider(value: Binding(get: { m.volume }, set: { m.setVolume($0) }), in: 0...1)
                Text("\(Int((m.volume * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
            }.help("Volume").nav(m, .volume)
        }
    }
    private func tabBadge(_ i: Int) -> Color? {
        switch i {
        case 2: return m.recording ? .red : nil
        case 3: return m.modsOn > 0 ? .accentColor : nil
        case 4: return m.cheatsOn > 0 ? .accentColor : nil
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
        case 0: graphics
        case 1: performance
        case 2: capture
        case 3: mods
        case 4: cheats
        default: controls
        }
    }
    private func subhead(_ t: String) -> some View { Text(t.uppercased()).font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary).padding(.top, 2) }
    private func note(_ t: String) -> some View { Text(t).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing) }
    private func resetButton(_ title: String, _ n: Nav, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion) { action() } } label: { Label(title, systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
            .modifier(GlassButton(prominent: false)).controlSize(.large).disabled(!enabled).padding(.top, 4).nav(m, n)
    }
    private var graphics: some View {
        VStack(alignment: .leading, spacing: 12) {
            subhead("Look")
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
            }
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
            subhead("Saved to")
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
    private var mods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each folder in this game's mods folder replaces game files. Enabled mods load in name order; the first one with a file wins.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if m.mods.isEmpty {
                Text("No mods yet. Put each mod in a folder of its own in the mods folder (its files, a romfs folder holding them, or a mod as downloaded for Atmosphere), then Refresh.")
                    .font(.callout).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(m.mods, id: \.self) { n in
                let on = m.wanted.contains(n)
                Toggle(isOn: Binding(get: { on }, set: { m.setMod(n, $0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n).font(.body.weight(.medium))
                        if let run = m.modsRun {
                            if m.modPending(n) { NextLaunchTag(pending: true) }
                            else { Text(run.contains(n) ? "Loaded" : "Off").font(.caption).foregroundStyle(.secondary) }
                        } else { Text("Not used: DM_ROMFS_OVERLAY is set").font(.caption).foregroundStyle(.secondary) }
                    }
                }.toggleStyle(.switch).nav(m, .mod(n))
            }
            HStack(spacing: 10) {
                Button { m.openModsFolder() } label: { Label("Open mods folder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .modsOpen)
                Button { withAnimation(motion) { m.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .modsRefresh)
            }.controlSize(.large)
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a key or button, then press the new one; Esc cancels. Saved for this game.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        let waiting = m.assigning == i * 2 + (pad ? 1 : 0)
        return Button { m.assign(i, pad: pad) } label: {
            Text(waiting ? (pad ? "Press a button…" : "Press a key…") : (pad ? m.padNames[i] : m.keyNames[i])).lineLimit(1).frame(minWidth: 130)
        }.modifier(GlassButton(prominent: waiting))
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
            ForEach(m.cheats) { c in
                if c.label {
                    Text(c.name).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle(isOn: Binding(get: { c.on || c.master }, set: { m.setCheat(c, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.body.weight(.medium))
                            if !c.note.isEmpty { Text(c.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            if c.master { Text("Master code: always on").font(.caption).foregroundStyle(.secondary) }
                            else if c.disabled { Label(c.why.isEmpty ? "Off: this host cannot run it" : c.why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                            else if c.once { Text("Applied once, then it turns itself off").font(.caption).foregroundStyle(.secondary) }
                            else { Text(c.on ? "Active" : "Off").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.toggleStyle(.switch).disabled(c.kind != 0).nav(m, .cheat(c.id))
                }
            }
            HStack(spacing: 10) {
                Button { m.openCheatsFolder() } label: { Label("Open cheats folder", systemImage: "folder").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .cheatsOpen)
                Button { withAnimation(motion) { m.rescanCheats() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.modifier(GlassButton(prominent: false)).nav(m, .cheatsRefresh)
            }.controlSize(.large)
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
                if !m.canRestart { Text("Quit and open the game again to apply.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
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
    let run = modsRun.map { Set(String(cString: $0).split(separator: "\n").map(String.init)) }
    let m = QuickSettings(game: String(cString: game), modsDir: String(cString: modsDir), modsRun: run, close: { close() }, fpsChanged: { fps() })
    shared = m
    let v = NSHostingView(rootView: QuickSettingsView(m: m))
    v.sizingOptions = []   // front_mac.m sizes it: the right of the game window, full height
    return Unmanaged.passRetained(v).toOpaque()
}
@_cdecl("dm_qs_nav")
public func dm_qs_nav(_ cmd: Int32) { shared?.nav(cmd) }
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
