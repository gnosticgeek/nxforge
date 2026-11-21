// Around a play session (0.12.0): NXForge steps aside while a game runs (its window shows a plain card and lets go of its artwork,
// so the game has the memory), each session's memory and frame rate are kept with its playtime, a recap card shows when a game
// quits, a controller tester, and the list of what NXForge keeps on this Mac, for removing it.
import Combine
import AppKit
import CoreHaptics
import Darwin
import GameController
import SwiftUI

// MARK: - A session's memory

enum ProcessMemory {
    /// A process's memory as Activity Monitor counts it (its physical footprint), in bytes
    static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    static func children(_ pid: pid_t) -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 64)
        let n = buf.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        guard n > 0 else { return [] }
        return buf.filter { $0 > 0 }
    }

    /// A game app and the player it starts (dm/mac/launcher.c runs the game as its child)
    static func tree(_ pid: pid_t) -> UInt64 {
        ([pid] + children(pid)).compactMap(footprint).reduce(0, +)
    }
}

/// What a session's samples add up to
struct PlayStats {
    var peak: UInt64 = 0
    var sum: Double = 0
    var count = 0
    mutating func add(_ bytes: UInt64) { guard bytes > 0 else { return }; peak = max(peak, bytes); sum += Double(bytes); count += 1 }
    var peakMB: Double? { count > 0 ? Double(peak) / 1_048_576 : nil }
    var averageMB: Double? { count > 0 ? sum / Double(count) / 1_048_576 : nil }
}

/// The card shown when a game quits
struct SessionRecap: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var app: String
    var seconds: Double
    var total: Double
    var sessions: Int
    var peakMB: Double?
    var fps: Double?
    var hitches: Int?
    /// for the snapshot hook (NXC_SHEET=recap)
    static let sample = SessionRecap(name: "Super Mario Odyssey", app: "", seconds: 2940, total: 51300, sessions: 12, peakMB: 6350, fps: 59.6, hitches: 3)
}

func memoryText(_ mb: Double) -> String { mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb) }

extension AppModel {
    /// Sample the running games' memory every 15 seconds while one runs
    func samplePlay() {
        guard playSampler == nil, !playing.isEmpty else { return }
        playSampler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.playing.isEmpty else { break }
                let pids = Array(self.playing.keys)
                let sizes = await Task.detached { pids.map { ($0, ProcessMemory.tree($0)) } }.value
                for (pid, b) in sizes where self.playing[pid] != nil { self.playStats[pid, default: PlayStats()].add(b) }
                try? await Task.sleep(for: .seconds(15))
            }
            self?.playSampler = nil
        }
    }

    /// A session ended: what was measured, and the recap card (a setting; not for a start that failed)
    func sessionEnded(_ p: PlayingNow, pid: pid_t, end: Date) -> PlaySession? {
        let stats = playStats.removeValue(forKey: pid)
        let seconds = end.timeIntervalSince(p.start)
        guard seconds >= Playtime.minSeconds else { return nil }
        var s = PlaySession(start: p.start, seconds: seconds)
        s.peakMB = stats?.peakMB; s.avgMB = stats?.averageMB
        // a frame-time recording made in this session gives its frame rate
        if let r = FrameTimes.all(app: p.app, titleID: VerifiedGames.titleID(ofApp: p.app)).last, r.date >= p.start {
            s.fps = r.summary.fps; s.hitches = r.summary.hitches
        }
        return s
    }

    func showRecap(_ p: PlayingNow, session: PlaySession, record: PlayRecord) {
        guard settings.sessionRecap else { return }
        let r = SessionRecap(name: p.name, app: p.app, seconds: session.seconds, total: record.total, sessions: record.sessions.count,
                             peakMB: session.peakMB, fps: session.fps, hitches: session.hitches)
        recap = r
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            // a slower session's note (SessionCheck.swift) keeps the card up until it is answered
            if self?.recap?.id == r.id, self?.sessionCheck(app: r.app) == nil { self?.recap = nil }
        }
    }

    // MARK: stepping aside

    /// NXForge's window shows a plain card and holds no artwork: a game is running and NXForge is not the app in front
    var standby: Bool { settings.lightWhilePlaying && !playing.isEmpty && !appActive && !run.running }

    func watchActive() {
        let nc = NotificationCenter.default
        playObservers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = false; self?.stepAside() }
        })
        playObservers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = true }
        })
    }

    /// Let go of the pictures held in memory once the window no longer shows them (they are read again from disk when it does)
    func stepAside() {
        guard standby else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))   // after the launch screen has faded and the stage is off screen
            guard let self, self.standby else { return }
            CoverStore.shared.letGo()
            GameKeyArt.cache = [:]
            URLCache.shared.removeAllCachedResponses()
        }
    }
}

/// What the window shows while a game runs and NXForge is behind it
struct StandbyView: View {
    @Bindable var model: AppModel

    var body: some View {
        let p = model.playing.values.sorted { $0.start < $1.start }.first
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.5))
                Text(p.map { "Playing \($0.name)" } ?? "Playing").font(.system(size: 28, weight: .heavy))
                if let p { Text("Since \(p.start.formatted(date: .omitted, time: .shortened))").foregroundStyle(.white.opacity(0.6)) }
                Text("NXForge is resting so the game has the Mac's memory. Click here to bring it back.").font(.callout).foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white).multilineTextAlignment(.center).padding(40)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("NXForge")
    }
}

struct RecapCard: View {
    @Bindable var model: AppModel
    let recap: SessionRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppIcon(path: recap.app, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You played").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(recap.name).font(.title3.weight(.bold)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { model.recap = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26).background(.white.opacity(0.10), in: .circle) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            HStack(alignment: .top, spacing: 22) {
                stat("This time", Playtime.text(recap.seconds))
                stat("In total", Playtime.text(recap.total))
                stat("Sessions", "\(recap.sessions)")
                if let m = recap.peakMB { stat("Peak memory", memoryText(m)) }
                if let f = recap.fps { stat("Frame rate", String(format: "%.1f fps", f)) }
            }
            SessionCheckNote(model: model, app: recap.app)
        }
        .padding(18)
        .frame(width: 440)
        .foregroundStyle(.white)
        .background(StageLook.panel.opacity(0.92), in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .accessibilityElement(children: .contain)
    }

    func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// The last sessions of a game, with what was measured in each
struct SessionsList: View {
    let record: PlayRecord

    var body: some View {
        let last = Array(record.sessions.suffix(5).reversed())
        if last.contains(where: { $0.peakMB != nil || $0.fps != nil }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent sessions").font(.headline)
                ForEach(last, id: \.self) { s in
                    HStack(spacing: 10) {
                        Text(relativeDay(s.start)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(Playtime.text(s.seconds)).frame(width: 80, alignment: .leading)
                        if let m = s.peakMB { Text("peak \(memoryText(m))").foregroundStyle(.secondary) }
                        if let f = s.fps { Text(String(format: "%.1f fps", f)).foregroundStyle(.secondary) }
                        if let h = s.hitches, h > 0 { Text("\(h) hitch\(h == 1 ? "" : "es")").foregroundStyle(.orange) }
                        Spacer(minLength: 0)
                    }
                    .font(.callout).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Controller tester

/// What a controller's inputs read now. Polled (the app's own navigation keeps the button handlers), so nothing else changes.
struct PadReading: Identifiable {
    var id: Int
    var name: String
    var battery: Float?
    var charging = false
    var buttons: [(name: String, role: String, value: Float)] = []
    var left = CGPoint.zero, right = CGPoint.zero
    var gyro: (x: Double, y: Double, z: Double)?
    var hasHaptics = false
    var both = false

    @MainActor static func read(_ c: GCController, index: Int) -> PadReading {
        var r = PadReading(id: index, name: c.vendorName ?? c.productCategory)
        if let b = c.battery, b.batteryState != .unknown { r.battery = b.batteryLevel; r.charging = b.batteryState == .charging }
        r.hasHaptics = c.haptics != nil
        if let m = c.motion {
            if m.sensorsRequireManualActivation, !m.sensorsActive { m.sensorsActive = true }
            if m.hasRotationRate { r.gyro = (m.rotationRate.x, m.rotationRate.y, m.rotationRate.z) }
        }
        guard let p = c.extendedGamepad else { return r }
        // a Switch game reads buttons by where they sit: the right one is A, the bottom one B, the top one X, the left one Y
        let nintendo = c.productCategory.localizedCaseInsensitiveContains("switch") || c.productCategory.localizedCaseInsensitiveContains("joy-con") || (c.vendorName ?? "").localizedCaseInsensitiveContains("nintendo")
        func add(_ b: GCControllerButtonInput?, _ role: String) { if let b { r.buttons.append((b.localizedName ?? b.sfSymbolsName ?? role, role, b.value)) } }
        add(nintendo ? p.buttonA : p.buttonB, "A"); add(nintendo ? p.buttonB : p.buttonA, "B"); add(nintendo ? p.buttonX : p.buttonY, "X"); add(nintendo ? p.buttonY : p.buttonX, "Y")
        add(p.leftShoulder, "L"); add(p.rightShoulder, "R"); add(p.leftTrigger, "ZL"); add(p.rightTrigger, "ZR")
        add(p.buttonMenu, "+"); add(p.buttonOptions, "−"); add(p.buttonHome, "Home")
        add(p.leftThumbstickButton, "Left stick press"); add(p.rightThumbstickButton, "Right stick press")
        add(p.dpad.up, "D-pad up"); add(p.dpad.down, "D-pad down"); add(p.dpad.left, "D-pad left"); add(p.dpad.right, "D-pad right")
        r.left = CGPoint(x: CGFloat(p.leftThumbstick.xAxis.value), y: CGFloat(p.leftThumbstick.yAxis.value))
        r.right = CGPoint(x: CGFloat(p.rightThumbstick.xAxis.value), y: CGFloat(p.rightThumbstick.yAxis.value))
        r.both = p.buttonMenu.isPressed && (p.buttonOptions?.isPressed ?? false)
        return r
    }
}

struct ControllerTestSheet: View {
    @Bindable var model: AppModel
    @State private var pads: [PadReading] = []
    @State private var held = 0
    @State private var engines: [Int: CHHapticEngine] = [:]
    @State private var rumbleNote: String?
    private let tick = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Controller test").font(.title2.weight(.bold))
                    Text("Press anything. Each button is shown with the Switch button a game reads it as. Hold + and − together to close.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { close() }.buttonStyle(.stagePrimary).keyboardShortcut(.cancelAction)
            }
            if pads.isEmpty {
                ContentUnavailableView("No controller connected", systemImage: "gamecontroller", description: Text("Connect one by Bluetooth or cable. It appears here by itself."))
            } else {
                ScrollView { VStack(spacing: 14) { ForEach(pads) { pad($0) } } }
            }
        }
        .padding(22)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 480, idealHeight: 560)
        .onReceive(tick) { _ in poll() }
        .onAppear { model.controllerTest = true; poll() }
        .onDisappear { model.controllerTest = false; for e in engines.values { e.stop() } }
    }

    func pad(_ r: PadReading) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary)
                Text("Player \(r.id + 1): \(r.name)").font(.headline)
                if let b = r.battery { Label("\(Int((b * 100).rounded()))%", systemImage: r.charging ? "battery.100.bolt" : "battery.75").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if r.hasHaptics { Button { rumble(r.id) } label: { Label("Test Rumble", systemImage: "waveform") }.buttonStyle(.stage) }
            }
            HStack(alignment: .top, spacing: 24) {
                stick("Left stick", r.left)
                stick("Right stick", r.right)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(r.buttons.enumerated()), id: \.offset) { _, b in
                        HStack(spacing: 6) {
                            Text(b.role).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 2)
                            if b.value > 0.02, b.value < 0.98 { Text("\(Int(b.value * 100))%").font(.caption.monospacedDigit()) }
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Color.accentColor.opacity(Double(b.value) * 0.85 + 0.0), in: .rect(cornerRadius: 8))
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
                        .help(b.name)
                    }
                }
            }
            if let g = r.gyro {
                Text(String(format: "Gyro  x %+.2f   y %+.2f   z %+.2f rad/s", g.x, g.y, g.z)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let rumbleNote { Text(rumbleNote).font(.caption).foregroundStyle(.orange) }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    func stick(_ title: String, _ p: CGPoint) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                Circle().fill(.white.opacity(0.06))
                Circle().fill(Color.accentColor).frame(width: 14, height: 14).offset(x: p.x * 38, y: -p.y * 38)
            }
            .frame(width: 92, height: 92)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%+.2f  %+.2f", p.x, p.y)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    func poll() {
        pads = GCController.controllers().enumerated().map { PadReading.read($0.element, index: $0.offset) }
        held = pads.contains(where: \.both) ? held + 1 : 0
        if held > 30 { close() }
    }

    func close() { model.controllerTest = false; model.showControllerTest = false }

    func rumble(_ index: Int) {
        let all = GCController.controllers()
        guard all.indices.contains(index), let h = all[index].haptics else { return }
        guard let e = engines[index] ?? h.createEngine(withLocality: .default) else { rumbleNote = "This controller's rumble is not available to apps."; return }
        engines[index] = e
        do {
            try e.start()
            let ev = CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1), CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)], relativeTime: 0, duration: 0.4)
            try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: [])).start(atTime: CHHapticTimeImmediate)
            rumbleNote = nil
        } catch { rumbleNote = "This controller's rumble could not be started: \(error.localizedDescription)" }
    }
}

// MARK: - What NXForge keeps on this Mac

struct Leftover: Identifiable, Hashable {
    var id: String { path }
    let title, note, path: String
    var bytes: Int64 = 0
    /// ticked when the sheet opens
    var suggested = true
}

enum Leftovers {
    static func size(_ path: String) -> Int64 {
        let fm = FileManager.default
        var dir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &dir) else { return 0 }
        if !dir.boolValue { return ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0 }
        var total: Int64 = 0
        if let e = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) {
            for case let u as URL in e {
                if let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    /// Everything NXForge and its games write outside the games' own folders, that exists now. Built apps and build caches are Storage's.
    static func list(home: String = NSHomeDirectory(), app: String = Bundle.main.bundlePath) -> [Leftover] {
        let fm = FileManager.default
        var out: [Leftover] = [
            Leftover(title: "Game data", note: "Each game's saves, cheats, mods and shader archives. Your saves are in here.", path: "\(home)/Library/Application Support/nxnative", suggested: false),
            Leftover(title: "NXForge's own data", note: "Settings, playtime, covers and store art, build records, and the engine if NXForge downloaded it.", path: Settings.supportDir.path),
            Leftover(title: "Sidebar defaults", note: "My defaults for the in-game sidebar.", path: "\(home)/Library/Application Support/NXForge"),
            Leftover(title: "Game logs", note: "Each game's last two logs.", path: "\(home)/Library/Logs/nxnative"),
            Leftover(title: "Caches", note: "Downloaded pages and pictures NXForge can fetch again.", path: "\(home)/Library/Caches/org.nxforge.converter"),
            Leftover(title: "nxforge command", note: "The command line tool.", path: "\(home)/.local/bin/nxforge"),
            Leftover(title: "nxforge-mcp command", note: "The command line tool's server for assistants.", path: "\(home)/.local/bin/nxforge-mcp"),
        ]
        let prefs = "\(home)/Library/Preferences"
        for f in ((try? fm.contentsOfDirectory(atPath: prefs)) ?? []).sorted() where f.hasPrefix("org.nxforge.") && f.hasSuffix(".plist") {
            let game = f != "org.nxforge.converter.plist"
            out.append(Leftover(title: game ? "A game's settings" : "NXForge's preferences", note: f, path: prefs + "/" + f))
        }
        out.append(Leftover(title: "NXForge itself", note: "The app. Tick it last: the list closes with it.", path: app, suggested: false))
        return out.filter { fm.fileExists(atPath: $0.path) }
    }
}

struct LeftoversSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Leftover] = []
    @State private var ticked: Set<String> = []
    @State private var measuring = true
    @State private var confirm = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What NXForge keeps on this Mac").font(.title2.weight(.bold))
            Text("Tick what to remove. It goes to the Trash, so it can be put back until the Trash is emptied. The games you built and their build files are on the Storage page.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { i in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { ticked.contains(i.path) }, set: { if $0 { ticked.insert(i.path) } else { ticked.remove(i.path) } })).labelsHidden().toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.title).font(.headline)
                                Text(i.note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                Text(i.path.tildePath).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(measuring && i.bytes == 0 ? "…" : ByteCountFormatter.string(fromByteCount: i.bytes, countStyle: .file)).monospacedDigit().foregroundStyle(.secondary)
                            Button("Show in Finder", systemImage: "folder") { reveal(i.path) }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Show in Finder")
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            HStack {
                if let result { Text(result).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.stage).keyboardShortcut(.cancelAction)
                let total = items.filter { ticked.contains($0.path) }.reduce(Int64(0)) { $0 + $1.bytes }
                Button("Move \(ticked.count) to Trash\(total > 0 ? " · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" : "")") { confirm = true }
                    .buttonStyle(.stagePrimary).disabled(ticked.isEmpty || !model.playing.isEmpty || model.run.running)
                    .help(model.playing.isEmpty && !model.run.running ? "" : "Quit the game and wait for the build first")
            }
        }
        .padding(22)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 460, idealHeight: 560)
        .task { await load() }
        .confirmationDialog("Move \(ticked.count) item\(ticked.count == 1 ? "" : "s") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ticked.contains { $0.hasSuffix("/nxnative") } ? "This includes your games' saves." : "NXForge makes what it needs again the next time it opens.")
        }
    }

    func load() async {
        items = Leftovers.list()
        ticked = Set(items.filter(\.suggested).map(\.path))
        let list = items
        let sized = await Task.detached { list.map { i -> Leftover in var j = i; j.bytes = Leftovers.size(i.path); return j } }.value
        items = sized; measuring = false
    }

    func remove() {
        var failed: [String] = [], n = 0
        // the app itself goes last
        for i in items.filter({ ticked.contains($0.path) }).sorted(by: { !$0.path.hasSuffix(".app") && $1.path.hasSuffix(".app") }) {
            do { try FileManager.default.trashItem(at: i.path.url, resultingItemURL: nil); n += 1 } catch { failed.append(i.title) }
        }
        result = failed.isEmpty ? "Moved \(n) item\(n == 1 ? "" : "s") to the Trash." : "Could not move: \(failed.joined(separator: ", "))."
        ticked = []
        Task { await load() }
    }
}
