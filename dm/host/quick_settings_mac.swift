// Quick settings sidebar (front_mac.m opens and closes it; quick_settings_mac.h is the C side): SwiftUI with the system's controls, on a Liquid Glass panel on macOS 26 and later
// (a material panel before). The settings are front_mac.m's: the same user defaults keys (per game), the same rule that a setting the environment names wins and is not saved.
// Filter, strength and scanlines go to the graphics backend at once (front.h mtl_present_*); the frame-rate counter is drawn by front_mac.m, told through the fps callback;
// mods are the folders of this game's mods folder, overlaid at the next launch (front_mac.m mods_start); cheats are the host's (hle_cheats.c dm_cheat*): this build's
// Atmosphère cheat file, a switch each, which the host saves beside the file (<build ID>.enabled) and runs from the next frame. The Cheats menu and panel (front_mac.m) show the same rows
import AppKit
import SwiftUI

private let env = ProcessInfo.processInfo.environment
private let filterNames = ["Off", "Sharpen", "Pixel-perfect", "CRT", "CRT-Lottes", "LCD Grid"]   // front.h DM_PFX_*, in that order
private let filterShort = ["Off", "Sharpen", "Pixel", "CRT", "Lottes", "LCD"]
private let filterAbout = ["The picture scaled smoothly, as the game drew it.", "Crisper edges and texture detail, without halos.",
                           "Crisp pixel art at any window size, without shimmer.", "Scanlines and an RGB mask, like a TV.",
                           "Timothy Lottes' CRT: soft beams, bloom and a shadow mask.", "A handheld's screen: a fine grid and RGB subpixels."]
private let usesStrength: Set<Int> = [1, 3, 4, 5], usesLines: Set<Int> = [3, 4, 5]   // pixel-perfect has no strength; the CRT filters and LCD Grid work on lines (cells)
private let cornerNames = ["Top left", "Top right", "Bottom left", "Bottom right"]
private let anisoSteps = [0, 2, 4, 8, 16]   // front.h mtl_aniso_set: 0 is the game's own
private let aaNames = ["Off", "FXAA"]   // front.h DM_PAA_*, in that order
// Upscaling is the settings window's setting too (launcher.DM_PRESENT_UPSCALE): fixed here only when the launch environment or an env file set it, not when the window or a saved choice did
private let upscaleFixed = env["DM_PRESENT_UPSCALE"] != nil && (env["DM_ENV_LAUNCH_KEYS"] == nil
    || Set(((env["DM_ENV_LAUNCH_KEYS"] ?? "") + " " + (env["DM_ENV_FILE_KEYS"] ?? "")).split(separator: " ").map(String.init)).contains("DM_PRESENT_UPSCALE"))

// The Controls section's rows: actions 0–15 are the Switch's buttons in NpadButton order, 16–19 the left stick, 20 shaking (front_mac.m's map); the controller map has the first 12
private let actionNames = ["A", "B", "X", "Y", "Left stick press", "Right stick press", "L", "R", "ZL", "ZR", "+ (Plus)", "− (Minus)", "D-pad left", "D-pad up", "D-pad right", "D-pad down",
                           "Left stick up", "Left stick left", "Left stick down", "Left stick right", "Shake"]
private let keyDefaults = ["J", "K", "U", "I", "F", "G", "Q", "E", "Z", "C", "Return", "Tab", "←", "↑", "→", "↓", "W", "A", "S", "D", "Space"]
private let padDefaults = ["Right button", "Bottom button", "Top button", "Left button", "Left stick press", "Right stick press", "Left shoulder", "Right shoulder",
                           "Left trigger", "Right trigger", "Menu", "Options"]
// What the controller and keyboard selection can be on (dm_qs_nav), in the order the sidebar shows it
enum Nav: Hashable { case header(Int), filter, strength, scanlines, upscale, aa, aniso, fps, corner, volume, shot, record, mod(String), modsOpen, modsRefresh, showFolder, changeFolder, cheat(Int), cheatsOpen, cheatsRefresh, key(Int), pad(Int), resetControls, resume, quit }
private let sectionOrder = [0, 1, 5, 6, 2, 3, 7]
struct Cheat: Identifiable {
    let id: Int, name: String, why: String, note: String, kind: Int32, on: Bool, flags: Int32
    var master: Bool { kind == 1 }
    var disabled: Bool { kind == 2 }
    var label: Bool { kind == 3 }
    var once: Bool { flags & Int32(QS_CHEAT_ONCE) != 0 }
}
// The engine's strings come from the player's files: UTF-8 when they are, else Latin-1 (which decodes any byte)
private func cheatText(_ p: UnsafePointer<CChar>?) -> String {
    guard let p else { return "" }
    return String(validatingCString: p) ?? String(cString: p, encoding: .isoLatin1) ?? ""
}

final class QuickSettings: ObservableObject {
    let game: String, modsDir: String, modsRun: Set<String>?, close: () -> Void, fpsChanged: () -> Void
    @Published var filter = 0
    @Published var strength = 0.5
    @Published var scanline = 0
    @Published var fps = false
    @Published var corner = 0
    @Published var mods: [String] = []
    @Published var wanted: [String] = []
    @Published var cheats: [Cheat] = []
    @Published var cheatsBuild = ""
    @Published var cheatsVersion = ""
    @Published var cheatsSafe = false
    @Published var open: Int
    @Published var volume = 1.0
    @Published var recording = false
    @Published var shotDir = ""
    @Published var upscale = false   // MetalFX where the picture is shown larger than the game renders it
    @Published var aa = 0            // the present's anti-aliasing (DM_PAA_*)
    @Published var aniso = 0      // the chosen anisotropic filtering floor (0: the game's own)
    @Published var anisoRun = 0   // the one this launch took
    @Published var recDir = ""
    @Published var customDir = false
    @Published var sel: Nav? { didSet { if sel != .quit { quitArmed = false } } }
    @Published var quitArmed = false   // Quit game asks twice, so a stray A press on the couch does not end the game
    @Published var assigning = -1
    @Published var keyNames: [String] = keyDefaults
    @Published var padNames: [String] = padDefaults
    init(game: String, modsDir: String, modsRun: Set<String>?, close: @escaping () -> Void, fpsChanged: @escaping () -> Void) {
        self.game = game; self.modsDir = modsDir; self.modsRun = modsRun; self.close = close; self.fpsChanged = fpsChanged
        let d = UserDefaults.standard, k = "DMQuickSettings.section.\(game)"
        open = d.object(forKey: k) != nil ? d.integer(forKey: k) : 0
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
    // One row per cheat the Cheats menu shows: not the off half of an on / off pair (its on half is the switch) and not a section marker
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
    func setFilter(_ m: Int, _ k: Double) {
        mtl_present_filter_set(Int32(m), Float(k)); filter = m; strength = k
        if env["DM_PRESENT_FILTER"] == nil { UserDefaults.standard.set(m, forKey: pfxKey("mode")); UserDefaults.standard.set(Float(k), forKey: pfxKey("strength")) }
    }
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
    func setFps(_ on: Bool) { fps = on; if env["DM_SHOW_FPS"] == nil { UserDefaults.standard.set(on, forKey: optKey("fps")) }; fpsChanged() }
    func setCorner(_ c: Int) { corner = c; UserDefaults.standard.set(c, forKey: optKey("fpsPos")); fpsChanged() }
    func setMod(_ n: String, _ on: Bool) {
        wanted.removeAll { $0 == n }; if on { wanted.append(n) }
        UserDefaults.standard.set(wanted, forKey: optKey("mods"))
        if let v = NSApp.keyWindow?.contentView { dm_qs_toast(Unmanaged.passUnretained(v).toOpaque(), "Mods apply when the game next starts") }
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
    func assign(_ i: Int, pad: Bool) { front_qs_assign(Int32(i), pad ? 1 : 0); assigning = Int(front_qs_assigning()) }
    func resetControls() {
        for k in ["keys", "keyNames", "pad", "padNames"] { UserDefaults.standard.removeObject(forKey: optKey(k)) }
        front_qs_controls_reload(); refresh()
    }
    // Controller and keyboard navigation (after RetroReplay's pause menu): a selection over the visible items
    var items: [Nav] {
        var r: [Nav] = []
        for i in sectionOrder {
            r.append(.header(i)); guard open == i else { continue }
            switch i {
            case 0: r += [.filter, .strength, .scanlines, .upscale, .aa, .aniso]
            case 1: r += [.fps, .corner]
            case 5: r += [.volume]
            case 6: r += [.shot, .record, .showFolder, .changeFolder]
            case 2: r += mods.map { .mod($0) } + [.modsOpen, .modsRefresh]
            case 3: r += cheats.filter { !$0.label }.map { .cheat($0.id) } + [.cheatsOpen, .cheatsRefresh]
            case 7: r += actionNames.indices.map { .key($0) } + padDefaults.indices.map { .pad($0) } + [.resetControls]
            default: break
            }
        }
        return r + [.resume, .quit]
    }
    func nav(_ cmd: Int32) {
        let list = items
        guard let cur = sel, let at = list.firstIndex(of: cur) else { if cmd == 6 { close() } else if cmd == 5 && sel == nil { sel = list.first } else { sel = list.first }; return }
        switch cmd {
        case 1: sel = list[max(at - 1, 0)]
        case 2: sel = list[min(at + 1, list.count - 1)]
        case 3, 4: adjust(cur, cmd == 4 ? 1 : -1)
        case 5: activate(cur)
        case 6: close()
        case 7, 8:   // the previous / next section's header
            let heads = list.enumerated().filter { if case .header = $0.element { return true }; return false }.map(\.offset)
            if let to = cmd == 7 ? heads.last(where: { $0 < at }) : heads.first(where: { $0 > at }) { sel = list[to] }
        default: break
        }
    }
    /// Quit game (after the NxNative Launcher's hold-Home exit): the first press arms it, the second ends the game as ⌘Q does
    func quit() {
        if quitArmed { NSApp.terminate(nil) } else { quitArmed = true }
    }
    private func adjust(_ n: Nav, _ d: Int) {
        switch n {
        case .header(let i): if (d > 0) != (open == i) { toggle(i) }
        case .filter: setFilter(min(max(filter + d, 0), filterNames.count - 1), strength)
        case .strength: if usesStrength.contains(filter) { setFilter(filter, min(max(strength + 0.05 * Double(d), 0), 1)) }
        case .scanlines: if usesLines.contains(filter) { setScanline(min(max(scanline + d, 0), 8)) }
        case .upscale: setUpscale(d > 0)
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA(min(max(aa + d, 0), aaNames.count - 1)) }
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[min(max(i + d, 0), anisoSteps.count - 1)]) }
        case .fps: setFps(d > 0)
        case .corner: if fps { setCorner((corner + d + 4) % 4) }
        case .volume: setVolume(min(max(volume + 0.05 * Double(d), 0), 1))
        case .mod(let name): setMod(name, d > 0)
        case .cheat(let id): if let c = cheats.first(where: { $0.id == id }), c.kind == 0 { setCheat(c, d > 0) }
        default: break
        }
    }
    private func activate(_ n: Nav) {
        switch n {
        case .header(let i): toggle(i)
        case .filter: setFilter((filter + 1) % filterNames.count, strength)
        case .scanlines: if usesLines.contains(filter) { setScanline((scanline + 1) % 9) }
        case .upscale: setUpscale(!upscale)
        case .aa: if env["DM_PRESENT_AA"] == nil { setAA((aa + 1) % aaNames.count) }
        case .aniso: if env["DM_ANISO"] == nil, let i = anisoSteps.firstIndex(of: aniso) { setAniso(anisoSteps[(i + 1) % anisoSteps.count]) }
        case .fps: setFps(!fps)
        case .corner: if fps { setCorner((corner + 1) % 4) }
        case .shot: front_qs_screenshot()
        case .showFolder: showCaptureFolder()
        case .changeFolder: chooseCaptureFolder()
        case .record: front_qs_record(); recording = front_qs_recording() != 0
        case .mod(let name): setMod(name, !wanted.contains(name))
        case .modsOpen: openModsFolder()
        case .modsRefresh: refresh()
        case .cheat(let id): if let c = cheats.first(where: { $0.id == id }), c.kind == 0 { setCheat(c, !c.on) }
        case .cheatsOpen: openCheatsFolder()
        case .cheatsRefresh: rescanCheats()
        case .key(let i): assign(i, pad: false)
        case .pad(let i): assign(i, pad: true)
        case .resetControls: resetControls()
        case .resume: close()
        case .quit: quit()
        case .strength, .volume: break
        }
    }
    func toggle(_ i: Int) { open = open == i ? -1 : i; UserDefaults.standard.set(open, forKey: optKey("section")) }
    func openModsFolder() {
        try? FileManager.default.createDirectory(atPath: modsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: modsDir))
    }
    var modsOn: Int { mods.filter { wanted.contains($0) }.count }
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

// One row: a label of a fixed width on the left, the control filling the rest, so every control in the sidebar lines up
private struct Row<C: View>: View {
    let title: String; @ViewBuilder let control: () -> C
    var body: some View { HStack(spacing: 12) { Text(title).frame(width: 118, alignment: .leading); control().frame(maxWidth: .infinity, alignment: .trailing) } }
}

struct QuickSettingsView: View {
    @ObservedObject var m: QuickSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compact = false   // a short window: a smaller title and tighter spacing
    private var motion: Animation? { reduceMotion ? nil : .snappy }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, compact ? 14 : 22).padding(.bottom, compact ? 8 : 14)
            Divider().padding(.horizontal, 22)
            ScrollViewReader { proxy in ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section(0, "Graphics & shaders", "display", summary: m.filter == 0 ? "Off" : filterNames[m.filter]) { graphics }
                    section(1, "Performance", "chart.bar.fill", summary: m.fps ? "FPS on" : "FPS off") { performance }
                    section(5, "Sound", "speaker.wave.2.fill", summary: "\(Int((m.volume * 100).rounded()))%") { sound }
                    section(6, "Capture", "camera", summary: m.recording ? "Recording" : "", badge: m.recording) { capture }
                    section(2, "Mods", "puzzlepiece.extension", summary: m.modsOn == 0 ? "None enabled" : "\(m.modsOn) enabled", badge: m.modsOn > 0) { mods }
                    section(3, "Cheats", "wand.and.stars", summary: m.cheats.isEmpty ? "None for this build" : m.cheatsOn == 0 ? "None on" : "\(m.cheatsOn) on", badge: m.cheatsOn > 0) { cheats }
                    section(7, "Controls", "gamecontroller", summary: "") { controls }
                }.padding(.horizontal, 16).padding(.vertical, 14)
            }.scrollIndicators(.automatic)
            .onChange(of: m.sel) { _, s in if let s { withAnimation(motion) { proxy.scrollTo(s, anchor: .center) } } } }
            Divider().padding(.horizontal, 22)
            footer.padding(.horizontal, 22).padding(.top, compact ? 10 : 14).padding(.bottom, compact ? 12 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) { $0.size.height < 640 } action: { compact = $0 }
        .modifier(Panel())
        .padding(12)
        .environment(\.colorScheme, .dark)
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("IN-GAME OPTIONS").font(.caption.weight(.semibold)).kerning(1.2).foregroundStyle(.secondary)
                Text("Quick settings").font(compact ? .title.bold() : .largeTitle.bold())
                Text(m.game).font(.title3).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: m.close) { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 22, height: 22) }
                .modifier(GlassButton(prominent: false)).buttonBorderShape(.circle).controlSize(.large).help("Close (Esc)")
        }
    }
    // A section: its header row opens and closes it, one open at a time; the body sits under it in the same card
    private func section<B: View>(_ i: Int, _ title: String, _ icon: String, summary: String, badge: Bool = false, @ViewBuilder body: () -> B) -> some View {
        let open = m.open == i
        return VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(motion) { m.toggle(i) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 26)
                    Text(title).font(.headline)
                    Spacer()
                    if badge { Text(summary).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3).background(.tint.opacity(0.2), in: .capsule).foregroundStyle(.tint) }
                    else if !open { Text(summary).font(.callout).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).rotationEffect(.degrees(open ? 90 : 0))
                }.contentShape(.rect)
            }.buttonStyle(.plain).nav(m, .header(i))
            if open { body().transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))) }
        }
        .padding(14)
        .background(.white.opacity(open ? 0.07 : 0.04), in: .rect(cornerRadius: 16))
    }
    private var graphics: some View {
        let hasStrength = usesStrength.contains(m.filter)
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Filter", selection: Binding(get: { m.filter }, set: { m.setFilter($0, m.strength) })) {
                ForEach(0..<filterNames.count, id: \.self) { Text(filterShort[$0]).tag($0).help(filterNames[$0]) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.large).nav(m, .filter)
            Text(filterAbout[min(m.filter, filterAbout.count - 1)]).font(.caption).foregroundStyle(.secondary)
            Row(title: "Strength") {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { m.strength }, set: { m.setFilter(m.filter, $0) }), in: 0...1)
                    Text("\(Int((m.strength * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                }.disabled(!hasStrength)
            }.nav(m, .strength)
            Row(title: "Scanlines") {
                Picker("Scanlines", selection: Binding(get: { m.scanline }, set: { m.setScanline($0) })) {
                    Text("Auto").tag(0)
                    ForEach(1..<9) { Text("\($0) frame row\($0 == 1 ? "" : "s")").tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(!usesLines.contains(m.filter))
            }.nav(m, .scanlines)
            if !usesLines.contains(m.filter) { Text("Scanlines are available with CRT, Lottes and LCD").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing) }
            // Upscaling: MetalFX's spatial scaler in place of the bilinear stretch wherever the window or screen is larger than the game's picture; Sharpen then sharpens the scaled picture
            Row(title: "MetalFX upscaling") {
                Toggle("MetalFX upscaling", isOn: Binding(get: { m.upscale }, set: { m.setUpscale($0) })).toggleStyle(.switch).labelsHidden().disabled(upscaleFixed)
            }.nav(m, .upscale)
            Group {
                if upscaleFixed { Text("Set by DM_PRESENT_UPSCALE for this run").foregroundStyle(.tertiary) }
                else if m.upscale && usesLines.union([2]).contains(m.filter) { Text("Off while \(filterShort[m.filter]) is on: it needs the game's own pixels").foregroundStyle(.tertiary) }
                else { Text("Sharper than plain stretching when the window is larger than the game").foregroundStyle(.tertiary) }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
            // Anti-aliasing: FXAA over the game's picture, smoothing jagged edges in games without their own; it softens small HUD text a little
            Row(title: "Anti-aliasing") {
                Picker("Anti-aliasing", selection: Binding(get: { m.aa }, set: { m.setAA($0) })) {
                    ForEach(aaNames.indices, id: \.self) { Text(aaNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_PRESENT_AA"] != nil)
            }.nav(m, .aa)
            // Anisotropic filtering: sharper textures on surfaces seen at an angle; the game's samplers take it when they are made, so it applies at the next start
            Row(title: "Anisotropic filtering") {
                Picker("Anisotropic filtering", selection: Binding(get: { m.aniso }, set: { m.setAniso($0) })) {
                    ForEach(anisoSteps, id: \.self) { Text($0 == 0 ? "Game default" : "\($0)x").tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(env["DM_ANISO"] != nil)
            }.nav(m, .aniso)
            Group {
                if env["DM_ANISO"] != nil { Text("Set by DM_ANISO for this run").foregroundStyle(.tertiary) }
                else if m.aniso != m.anisoRun { Label("Applies when the game next starts", systemImage: "circle.fill").foregroundStyle(.orange).labelStyle(DotLabel()) }
                else { Text("Applies when the game next starts").foregroundStyle(.tertiary) }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    private var performance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Row(title: "Show FPS") { Toggle("Show FPS", isOn: Binding(get: { m.fps }, set: { m.setFps($0) })).toggleStyle(.switch).labelsHidden() }.nav(m, .fps)
            Row(title: "Counter position") {
                Picker("Counter position", selection: Binding(get: { m.corner }, set: { m.setCorner($0) })) {
                    ForEach(0..<4) { Text(cornerNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(!m.fps)
            }.nav(m, .corner)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n).font(.body.weight(.medium))
                        if let run = m.modsRun {
                            if run.contains(n) != on { Label("Restart required", systemImage: "circle.fill").font(.caption).foregroundStyle(.orange).labelStyle(DotLabel()) }
                            else { Text(on ? "Loaded" : "Off").font(.caption).foregroundStyle(.secondary) }
                        } else { Text("Not used: DM_ROMFS_OVERLAY is set").font(.caption).foregroundStyle(.secondary) }
                    }
                }.toggleStyle(.switch).nav(m, .mod(n))
            }
            HStack(spacing: 10) {
                Button { m.openModsFolder() } label: { Label("Open mods folder", systemImage: "folder").frame(maxWidth: .infinity) }.nav(m, .modsOpen)
                Button { withAnimation(motion) { m.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.nav(m, .modsRefresh)
            }.modifier(GlassButton(prominent: false)).controlSize(.large)
            Text("Restart the game to apply mod changes.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var sound: some View {
        Row(title: "Volume") {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { m.volume }, set: { m.setVolume($0) }), in: 0...1)
                Text("\(Int((m.volume * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
            }
        }.nav(m, .volume)
    }
    private var capture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { front_qs_screenshot() } label: { Label("Screenshot", systemImage: "camera.viewfinder").frame(maxWidth: .infinity) }.nav(m, .shot)
                Button { front_qs_record(); m.recording = front_qs_recording() != 0 } label: {
                    Label(m.recording ? "Stop" : "Record", systemImage: m.recording ? "stop.circle.fill" : "record.circle").frame(maxWidth: .infinity)
                }.tint(m.recording ? .red : nil).nav(m, .record)
            }.modifier(GlassButton(prominent: false)).controlSize(.large)
            VStack(alignment: .leading, spacing: 3) {   // where they go: by default beside the game, in the game folder
                if m.shotDir == m.recDir { Text(tilde(m.shotDir)).font(.callout).lineLimit(2).truncationMode(.middle) }
                else { Text("Screenshots: \(tilde(m.shotDir))").font(.callout).lineLimit(1).truncationMode(.middle); Text("Recordings: \(tilde(m.recDir))").font(.callout).lineLimit(1).truncationMode(.middle) }
            }.foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 10) {
                Button { m.showCaptureFolder() } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }.nav(m, .showFolder)
                Button { m.chooseCaptureFolder() } label: { Label("Change…", systemImage: "folder.badge.gearshape").frame(maxWidth: .infinity) }.nav(m, .changeFolder)
            }.modifier(GlassButton(prominent: false)).controlSize(.large)
            if m.customDir { Button("Use the game folder again") { m.defaultCaptureFolder() }.buttonStyle(.link).font(.caption) }
            Text("Shift-Command-S takes a screenshot, Shift-Command-R starts and stops a recording (with sound). The picture is saved as you see it, filter included.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a key or button, then press the new one; Esc cancels. Saved for this game.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Keyboard").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ForEach(actionNames.indices, id: \.self) { i in Row(title: actionNames[i]) { assignButton(i, pad: false) }.nav(m, .key(i)) }
            Text("Controller").font(.subheadline.weight(.semibold)).padding(.top, 6)
            ForEach(padDefaults.indices, id: \.self) { i in Row(title: actionNames[i]) { assignButton(i, pad: true) }.nav(m, .pad(i)) }
            Text("A controller's D-pad and sticks stay as they are. Its Home button, or − and + together, opens this sidebar; the D-pad moves, A chooses, B closes, L and R jump between sections.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { m.resetControls() } label: { Label("Reset to defaults", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                .modifier(GlassButton(prominent: false)).controlSize(.large).nav(m, .resetControls)
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
                    .modifier(GlassButton(prominent: false))
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
                Button { m.openCheatsFolder() } label: { Label("Open cheats folder", systemImage: "folder").frame(maxWidth: .infinity) }.nav(m, .cheatsOpen)
                Button { withAnimation(motion) { m.rescanCheats() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.nav(m, .cheatsRefresh)
            }.modifier(GlassButton(prominent: false)).controlSize(.large)
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            Label("Settings saved for this game", systemImage: "gearshape").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: m.close) { Text("Resume game").font(.headline).frame(maxWidth: .infinity) }
                .modifier(GlassButton(prominent: true)).controlSize(.extraLarge).keyboardShortcut(.defaultAction).nav(m, .resume)
            Button(action: m.quit) {
                Label(m.quitArmed ? "Press again to quit" : "Quit game", systemImage: "power").frame(maxWidth: .infinity)
            }
            .modifier(GlassButton(prominent: false)).controlSize(.large).tint(m.quitArmed ? Color.red : nil).nav(m, .quit)
            .help("Ends the game, as ⌘Q does. Asks twice.")
            HStack(spacing: 8) {
                Text("Esc").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.18)))
                Text("Close menu").font(.callout).foregroundStyle(.secondary)
            }
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
public func dm_qs_opened() { shared?.quitArmed = false }
