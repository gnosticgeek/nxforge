// NXForge's settings window for the Mac app (dm/mac/Launcher.swift shows it in place of nxnative's LauncherView, with the same model, store and callbacks).
// A header with the game's icon, name and version over its artwork; General, Graphics and Advanced tabs, each two columns of grouped boxes; Show at launch, Quit and Play at the bottom.
// General: the basic settings (level=basic) and a few everyday controls, with Cloud saves. Graphics: every picture setting, basic or not. Advanced: the rest, and Reset to tested defaults.
// The rows are drawn here (a menu on the right, a switch, a slider with its value), each with a short Mac note; a row an env file or the launch sets is shown but disabled.
import AppKit
import SwiftUI

enum NXFLauncherTab: String, CaseIterable { case general = "General", graphics = "Graphics", advanced = "Advanced" }

enum NXFLauncherLayout {
    /// The Graphics tab's boxes and their rows in order, whatever settings.tsv's section or level says (its sections are the iPhone's single list)
    static let graphicsBoxes: [(title: String, envs: [String])] = [
        ("Resolution", ["DM_RENDER_SCALE", "DM_DYNAMIC_RESOLUTION", "DM_PRESENT_UPSCALE", "DM_UPSCALER", "DM_SCREEN_ASPECT", "DM_PRESENT_AA"]),
        ("Frame rate", ["DM_FPS_TARGET", "DM_PRESENT_INTERP"]),
        ("HDR", ["DM_PRESENT_EDR", "DM_PRESENT_EDR_STRENGTH"]),
    ]
    static let graphics: [String] = graphicsBoxes.flatMap(\.envs)
    /// The Advanced tab's boxes: Performance split in two so the columns match
    static let advancedBoxes: [(title: String, envs: [String])] = [
        ("Pipelines", ["DM_PSO_MTL4", "DM_PSO_PREBUILD", "DM_NVN_ENC_THREAD"]),
        ("Display", ["DM_PRESENT_SNAP", "DM_FPS_HOLD", "DM_METAL_HUD"]),
    ]
    static let boxes = graphicsBoxes + advancedBoxes
    /// On the General tab though not level=basic: everyday controls
    static let general: Set<String> = ["DM_RUMBLE_GAIN", "DM_RUMBLE_MIN", "DM_PAD_PRESS_TO_JOIN", "DM_SW2"]
    /// The Mac window's shorter notes (the two-column boxes are narrow); a setting not listed keeps settings.tsv's note
    static let notes: [String: String] = [
        "DM_DYNAMIC_RESOLUTION": "Lets the game lower its resolution under load.",
        "DM_PRESENT_UPSCALE": "Uses more GPU time and can increase heat.",
        "DM_SCREEN_ASPECT": "Renders about a quarter more pixels.",
        "DM_PRESENT_EDR": "On an XDR or HDR screen, highlights glow above white.",
        "DM_PRESENT_INTERP": "Shows 60 fps at 120 fps, about 8 ms later. Experimental.",
        "DM_PRESENT_AA": "Smooths jagged edges; small text softens a little.",
        "DM_SW2": "Pair Joy-Con 2 or Pro Controller 2 over Bluetooth.",
        "DM_PRESENT_SNAP": "Adds up to one frame of display latency.",
        "DM_PSO_MTL4": "Caches pipelines; uses more memory.",
        "DM_PSO_PREBUILD": "First launch may take a few minutes.",
    ]

    static func tab(_ s: Setting) -> NXFLauncherTab {
        graphics.contains(s.env) ? .graphics : s.basic || general.contains(s.env) ? .general : .advanced
    }
    static func group(_ s: Setting) -> String { boxes.first { $0.envs.contains(s.env) }?.title ?? s.sectionTitle }
    static func note(_ s: Setting) -> String { notes[s.env] ?? s.note }

    static let cloudSaves = "Cloud saves"   // General's box that is not a group of settings

    /// One tab's boxes, each a group's visible rows in the list's order, split into two columns. General: Game on the left and Controls on the right, then Cloud saves and
    /// any other group each where the column is shorter so far (a slider counts as taller, a note adds a line). Graphics: Resolution on the left, the others on the right. Advanced: Pipelines and Display
    static func columns(_ m: LauncherModel, _ t: NXFLauncherTab) -> (left: [String], right: [String]) {
        let shown = m.settings.filter { tab($0) == t && m.visible($0) }
        func height(_ g: String) -> Double {
            g == cloudSaves ? 3 : shown.filter { group($0) == g }.reduce(0) { $0 + ($1.kind == "range" ? 1.6 : 1) + (note($1).isEmpty ? 0 : 0.4) }
        }
        let groups = shown.reduce(into: [String]()) { if !$0.contains(group($1)) { $0.append(group($1)) } }
        switch t {
        case .general:
            var left = height("Game") > 0 ? ["Game"] : [], right = height("Controls") > 0 ? ["Controls"] : []
            var l = height("Game"), r = height("Controls")
            for g in [cloudSaves] + groups.filter({ $0 != "Game" && $0 != "Controls" }) where height(g) > 0 {
                if l <= r { left.append(g); l += height(g) + 1 } else { right.append(g); r += height(g) + 1 }
            }
            return (left, right)
        case .graphics:
            let boxes = graphicsBoxes.map(\.title).filter { height($0) > 0 }
            return (Array(boxes.prefix(1)), Array(boxes.dropFirst()))
        case .advanced:   // Pipelines and Display side by side, any other group under the shorter column
            let named = advancedBoxes.map(\.title).filter { height($0) > 0 }
            var left = Array(named.prefix(1)), right = Array(named.dropFirst())
            var l = left.map(height).reduce(0, +), r = right.map(height).reduce(0, +)
            for g in groups where !named.contains(g) {
                if l <= r { left.append(g); l += height(g) + 1 } else { right.append(g); r += height(g) + 1 }
            }
            return (left, right)
        }
    }

    static func rows(_ m: LauncherModel, group g: String, tab t: NXFLauncherTab) -> [Setting] {
        let rows = m.settings.filter { tab($0) == t && m.visible($0) && group($0) == g }
        guard let order = boxes.first(where: { $0.title == g })?.envs else { return rows }
        return rows.sorted { (order.firstIndex(of: $0.env) ?? 0) < (order.firstIndex(of: $1.env) ?? 0) }
    }
}

struct NXFLauncherView: View {
    @ObservedObject var m: LauncherModel
    let done: (Bool) -> Void
    let fit: (CGFloat) -> Void
    @AppStorage("window.show") private var show = true
    @AppStorage("window.tab") private var tab = NXFLauncherTab.general

    var body: some View {
        VStack(spacing: 0) {
            NXFLauncherHeader()
            tabs
            ScrollView {
                VStack(spacing: 14) { page(tab) }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height
            } action: { _, extraHeight in
                fit(extraHeight)
            }
            Divider().padding(.horizontal, 16)
            HStack(spacing: 12) {
                Toggle("Show at launch", isOn: $show).toggleStyle(.checkbox)
                    .help("Off: the game starts straight away. Hold Option while opening the app to see this window again.")
                Spacer()
                Button { done(false) } label: { Text("Quit").frame(minWidth: 70) }
                Button { done(true) } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 70) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(minWidth: 720, idealWidth: 760)
    }

    private var tabs: some View {
        HStack(spacing: 14) {
            VStack { Divider() }
            Picker("", selection: $tab) {
                ForEach(NXFLauncherTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large).fixedSize()
            VStack { Divider() }
        }
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private func empty(_ t: NXFLauncherTab) -> Bool { let c = NXFLauncherLayout.columns(m, t); return c.left.isEmpty && c.right.isEmpty }

    @ViewBuilder private func page(_ t: NXFLauncherTab) -> some View {
        let c = NXFLauncherLayout.columns(m, t)
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) { ForEach(c.left, id: \.self) { box($0, tab: t) } }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(spacing: 14) { ForEach(c.right, id: \.self) { box($0, tab: t) } }
                .frame(maxWidth: .infinity, alignment: .top)
        }
        switch t {
        case .general:
            let more = [NXFLauncherTab.graphics, .advanced].filter { !empty($0) }.map(\.rawValue)
            if !more.isEmpty {
                Text("More options in \(more.joined(separator: " and ")).").italic().font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            }
        case .graphics:
            if empty(t) { Text("This game has no graphics settings.").foregroundStyle(.secondary).padding(.vertical, 20) }
        case .advanced:
            if empty(t) { Text("This game has no advanced settings.").foregroundStyle(.secondary).padding(.vertical, 20) }
            VStack(spacing: 6) {
                Button { m.reset() } label: { Text("Reset to tested defaults").frame(minWidth: 220) }
                    .controlSize(.large).disabled(!m.changed)
                Text("Restore the settings this game was tested with.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    // General: the title above the box; Graphics and Advanced: inside it, over a line (as the mock-ups draw them). Sliders sit under their label except on Advanced
    @ViewBuilder private func box(_ group: String, tab t: NXFLauncherTab) -> some View {
        let rows = NXFLauncherLayout.rows(m, group: group, tab: t)
        if group == NXFLauncherLayout.cloudSaves {
            NXFCloudSavesBox()
        } else if t == .general {
            VStack(alignment: .leading, spacing: 8) {
                Text(group).font(.title3.weight(.semibold)).padding(.leading, 12)
                NXFBox { rowList(rows, inline: false) }
            }
        } else {
            NXFBox {
                VStack(alignment: .leading, spacing: 0) {
                    Text(group).font(.title3.weight(.semibold)).padding(.vertical, 8)
                    Divider()
                    rowList(rows, inline: t == .advanced)
                }
            }
        }
    }

    private func rowList(_ rows: [Setting], inline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider() }
                NXFSettingRow(s: s, m: m, inline: inline).padding(.vertical, inline ? 7 : 9)
            }
        }
    }
}

/// A rounded, lightly filled box with a hairline edge, as a grouped Form draws its sections
struct NXFBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// One setting: its label and note on the left; a menu, a switch, or a slider with its value on the right. A slider sits under its label (inline: false) or beside it
struct NXFSettingRow: View {
    let s: Setting
    @ObservedObject var m: LauncherModel
    let inline: Bool

    private var locked: Bool { m.fixed.contains(s.env) }
    private var note: String {
        let n = NXFLauncherLayout.note(s)
        guard locked else { return n }
        return (n.isEmpty ? "" : n + " · ") + (m.fromLaunch.contains(s.env) ? "Set at launch" : "Set by an env file")
    }
    private var rangeValue: Binding<Double> {
        Binding(get: { Double(m.values[s.env] ?? s.def) ?? s.max ?? 1 }, set: { m.values[s.env] = String(format: "%.2f", $0) })
    }
    private var rangeText: String { m.rangeLabel(s, rangeValue.wrappedValue) }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.label)
            if !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private var slider: some View {
        Slider(value: rangeValue, in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05)
            .labelsHidden().accessibilityLabel(s.label).accessibilityValue(rangeText)
    }

    var body: some View {
        Group {
            switch s.kind {
            case "choice":   // the note under the whole row, so the menu keeps its width
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        Text(s.label).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        NXFMenu(s: s, selection: m.binding(s))
                    }
                    if !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            case "range":
                if inline {
                    HStack(spacing: 12) {
                        label.frame(minWidth: 110, alignment: .leading)
                        slider
                        Text(rangeText).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 48, alignment: .trailing)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            label
                            Spacer()
                            Text(rangeText).monospacedDigit().foregroundStyle(.secondary)
                        }
                        slider.padding(.leading, 120)
                    }
                }
            default:
                Toggle(isOn: Binding(get: { (m.values[s.env] ?? s.def) == s.onValue }, set: { m.values[s.env] = $0 ? s.onValue : s.offValue })) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
            }
        }
        .disabled(locked)
    }
}

/// A choice's menu, the same width on every row (macOS 26 sizes a menu button to its title unless told otherwise)
struct NXFMenu: View {
    let s: Setting
    @Binding var selection: String
    var body: some View {
        let p = Picker(s.label, selection: $selection) {
            ForEach(s.options ?? [], id: \.[0]) { Text($0[1]).tag($0[0]) }
        }
        .pickerStyle(.menu).labelsHidden()
        if #available(macOS 26, *) { p.buttonSizing(.flexible).frame(width: 190) } else { p.frame(width: 190) }
    }
}

/// The game's icon, name and version, over its artwork fading in from the right: Resources/dm/banner.(jpg|png) when the app has one, else the icon itself, enlarged and softened, zoomed past the icon's transparent margin
struct NXFLauncherHeader: View {
    private static func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }
    private static let banner: NSImage? = ["jpg", "png"].lazy.compactMap { Bundle.main.url(forResource: "banner", withExtension: $0, subdirectory: "dm") }.compactMap(NSImage.init(contentsOf:)).first

    var body: some View {
        HStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.info("CFBundleName") ?? "Game").font(.system(size: 26, weight: .bold)).lineLimit(2)
                Text("Version \(Self.info("CFBundleShortVersionString") ?? "1.0")").font(.title3).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(alignment: .trailing) {
            art.frame(width: 440).frame(minHeight: 0, maxHeight: .infinity).clipped()   // minHeight 0: the header's height, not the filled image's
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.55), location: 0.3), .init(color: .black, location: 0.6)],
                                     startPoint: .leading, endPoint: .trailing))   // fades in from the left
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))   // and out towards the tabs
                .accessibilityHidden(true)
        }
        .clipped()
    }

    @ViewBuilder private var art: some View {
        if let b = Self.banner {
            Image(nsImage: b).resizable().scaledToFill()
        } else {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFill().scaleEffect(1.3).blur(radius: 3, opaque: true).saturation(1.1).opacity(0.85)
        }
    }
}

/// Cloud saves as a box: what the save syncs through (CloudSavesSection's store and env.txt rule, dm/mac/Launcher.swift), and the folder buttons
struct NXFCloudSavesBox: View {
    @AppStorage("cloudSaves.folder") private var folder = ""
    private let fixed: String? = {
        let env = ProcessInfo.processInfo.environment
        let keys = ((env["DM_ENV_FILE_KEYS"] ?? "") + " " + (env["DM_ENV_LAUNCH_KEYS"] ?? "")).split(separator: " ")
        return keys.contains("DM_SAVE_SYNC") || env["DM_SAVE_SYNC"] != nil ? env["DM_SAVE_SYNC"] : nil
    }()

    var body: some View {
        NXFBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Cloud saves").font(.title3.weight(.semibold))
                    Spacer(minLength: 12)
                    Text(fixed.map { "\(CloudSavesSection.shown($0)) (env.txt)" } ?? (folder.isEmpty ? "Off" : CloudSavesSection.shown(folder)))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        .help(fixed ?? folder)
                }
                Text("Sync saves with your iPhone using an iCloud Drive folder.").font(.callout).foregroundStyle(.secondary)
                if fixed == nil {
                    HStack {
                        Button(folder.isEmpty ? "Choose a folder…" : "Choose a different folder…", action: choose)
                        if !folder.isEmpty { Button("Turn off") { folder = "" } }
                    }
                    .controlSize(.large)
                }
                Text("Replaced saves are backed up automatically.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Use for Cloud Saves"
        panel.message = "The folder the iPhone app chose in its launcher's Cloud saves"
        panel.directoryURL = URL(fileURLWithPath: folder.isEmpty ? CloudSavesSection.drive : folder)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}
