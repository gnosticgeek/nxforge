// Quick settings sidebar (front_mac.m opens and closes it; quick_settings_mac.h is the C side): SwiftUI with the system's controls, on a Liquid Glass panel on macOS 26 and later
// (a material panel before). The settings are front_mac.m's: the same user defaults keys (per game), the same rule that a setting the environment names wins and is not saved.
// Filter, strength and scanlines go to the graphics backend at once (front.h mtl_present_*); the frame-rate counter is drawn by front_mac.m, told through the fps callback;
// mods are the folders of this game's mods folder, overlaid at the next launch (front_mac.m mods_start)
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

final class QuickSettings: ObservableObject {
    let game: String, modsDir: String, modsRun: Set<String>?, close: () -> Void, fpsChanged: () -> Void
    @Published var filter = 0
    @Published var strength = 0.5
    @Published var scanline = 0
    @Published var fps = false
    @Published var corner = 0
    @Published var mods: [String] = []
    @Published var wanted: [String] = []
    @Published var open: Int
    @Published var volume = 1.0
    @Published var recording = false
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
        let fm = FileManager.default
        mods = ((try? fm.contentsOfDirectory(atPath: modsDir)) ?? []).filter { n in
            var dir: ObjCBool = false
            return !n.hasPrefix(".") && fm.fileExists(atPath: (modsDir as NSString).appendingPathComponent(n), isDirectory: &dir) && dir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func setFilter(_ m: Int, _ k: Double) {
        mtl_present_filter_set(Int32(m), Float(k)); filter = m; strength = k
        if env["DM_PRESENT_FILTER"] == nil { UserDefaults.standard.set(m, forKey: pfxKey("mode")); UserDefaults.standard.set(Float(k), forKey: pfxKey("strength")) }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section(0, "Graphics & shaders", "display", summary: m.filter == 0 ? "Off" : filterNames[m.filter]) { graphics }
                    section(1, "Performance", "chart.bar.fill", summary: m.fps ? "FPS on" : "FPS off") { performance }
                    section(5, "Sound", "speaker.wave.2.fill", summary: "\(Int((m.volume * 100).rounded()))%") { sound }
                    section(6, "Capture", "camera", summary: m.recording ? "Recording" : "", badge: m.recording) { capture }
                    section(2, "Mods", "puzzlepiece.extension", summary: m.modsOn == 0 ? "None enabled" : "\(m.modsOn) enabled", badge: m.modsOn > 0) { mods }
                    cheats
                }.padding(.horizontal, 16).padding(.vertical, 14)
            }.scrollIndicators(.automatic)
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
            }.buttonStyle(.plain)
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
            }.pickerStyle(.segmented).labelsHidden().controlSize(.large)
            Text(filterAbout[min(m.filter, filterAbout.count - 1)]).font(.caption).foregroundStyle(.secondary)
            Row(title: "Strength") {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { m.strength }, set: { m.setFilter(m.filter, $0) }), in: 0...1)
                    Text("\(Int((m.strength * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                }.disabled(!hasStrength)
            }
            Row(title: "Scanlines") {
                Picker("Scanlines", selection: Binding(get: { m.scanline }, set: { m.setScanline($0) })) {
                    Text("Auto").tag(0)
                    ForEach(1..<9) { Text("\($0) frame row\($0 == 1 ? "" : "s")").tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(!usesLines.contains(m.filter))
            }
            if !usesLines.contains(m.filter) { Text("Scanlines are available with CRT, Lottes and LCD").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing) }
        }
    }
    private var performance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Row(title: "Show FPS") { Toggle("Show FPS", isOn: Binding(get: { m.fps }, set: { m.setFps($0) })).toggleStyle(.switch).labelsHidden() }
            Row(title: "Counter position") {
                Picker("Counter position", selection: Binding(get: { m.corner }, set: { m.setCorner($0) })) {
                    ForEach(0..<4) { Text(cornerNames[$0]).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(!m.fps)
            }
        }
    }
    private var mods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each folder in this game's mods folder replaces game files. Enabled mods load in name order; the first one with a file wins.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if m.mods.isEmpty {
                Text("No mods yet. Put each mod in a folder of its own in the mods folder (its files, or a romfs folder holding them), then Refresh.")
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
                }.toggleStyle(.switch)
            }
            HStack(spacing: 10) {
                Button { m.openModsFolder() } label: { Label("Open mods folder", systemImage: "folder").frame(maxWidth: .infinity) }
                Button { withAnimation(motion) { m.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
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
        }
    }
    private var capture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { front_qs_screenshot() } label: { Label("Screenshot", systemImage: "camera.viewfinder").frame(maxWidth: .infinity) }
                Button { front_qs_record(); m.recording = front_qs_recording() != 0 } label: {
                    Label(m.recording ? "Stop" : "Record", systemImage: m.recording ? "stop.circle.fill" : "record.circle").frame(maxWidth: .infinity)
                }.tint(m.recording ? .red : nil)
            }.modifier(GlassButton(prominent: false)).controlSize(.large)
            Text("Shift-Command-S takes a screenshot, Shift-Command-R starts and stops a recording. The picture is saved as you see it, filter included; screenshots go to Pictures › NxNative, recordings (with sound) to Movies › NxNative.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var cheats: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.title3).frame(width: 26)
            Text("Cheats").font(.headline)
            Spacer()
            Text("Coming later").font(.callout)
        }
        .foregroundStyle(.tertiary).padding(14)
        .background(.white.opacity(0.02), in: .rect(cornerRadius: 16))
        .help("Cheats are not in the engine yet")
    }
    private var footer: some View {
        VStack(spacing: 12) {
            Label("Settings saved for this game", systemImage: "gearshape").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: m.close) { Text("Resume game").font(.headline).frame(maxWidth: .infinity) }
                .modifier(GlassButton(prominent: true)).controlSize(.extraLarge).keyboardShortcut(.defaultAction)
            HStack(spacing: 8) {
                Text("Esc").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.18)))
                Text("Close menu").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
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
@_cdecl("dm_qs_refresh")
public func dm_qs_refresh() { shared?.refresh() }
