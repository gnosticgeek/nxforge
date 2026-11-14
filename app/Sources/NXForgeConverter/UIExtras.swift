// Converter 0.7.0's ten UI changes, the parts that live on their own: a build's progress on the sidebar's Convert row (1),
// Storage deletes held back so they can be undone (3), banners for work that ended in the background instead of alerts (7),
// the recent games under Convert's drop area (8), the Dock icon's menu (9) and the window remembering where it was (10).
import AppKit
import SwiftUI

// MARK: 1 · the build on the sidebar

/// "1 h 12 m", "35 m", "<1 m": the time left, short enough for a sidebar row.
func shortTimeLeft(_ s: Double) -> String {
    if s < 60 { return "<1 m" }
    let m = Int((s / 60).rounded())
    return m < 60 ? "\(m) m" : "\(m / 60) h \(m % 60) m"
}

/// A ring filling with the build and the time left, beside "Convert" while a build runs, so the build stays in sight from
/// every page. Redrawn every few seconds, only while it is shown.
struct SidebarBuildProgress: View {
    let run: BuildRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3)) { ctx in
            let o = run.overall(now: ctx.date)
            let pct = Int((o.fraction * 100).rounded())
            HStack(spacing: 6) {
                Text(o.remaining.map(shortTimeLeft) ?? "\(pct)%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(o.fraction, 0.02))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
            }
            .help(o.remaining.map { "Building · \(pct)% · \(timeLeft($0).lowercasedFirst)" } ?? "Building · \(pct)%")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Building, \(pct) percent\(o.remaining.map { ", \(timeLeft($0).lowercasedFirst)" } ?? "")")
        }
    }
}

// MARK: 3 · Storage deletes that can be undone

/// Something Storage deleted, held under a hidden name beside where it was until the undo time is over. A rename on the same
/// drive is instant and needs no room; the Trash would keep the space taken until it is emptied, which is what Storage is for.
struct PendingDelete: Codable, Hashable, Identifiable {
    var id: String { hidden }
    let original: String
    let hidden: String
    let bytes: Int64
    let label: String
}

enum PendingDeletes {
    /// How long Undo is offered before the files go for good.
    static let undoSeconds: Double = 20

    static var file: URL { Settings.supportDir.appending(path: "pending-deletes.json") }

    static func load() -> [PendingDelete] {
        guard let d = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([PendingDelete].self, from: d)) ?? []
    }

    static func save(_ list: [PendingDelete]) {
        if list.isEmpty { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: file, options: .atomic) }
    }

    /// "/x/Game_build" → "/x/.Game_build.nxforge-deleting-1a2b3c": hidden from Finder and from Storage's scan (no "_build" end).
    static func hiddenPath(for path: String) -> String {
        let u = path.url
        let tag = UUID().uuidString.prefix(6).lowercased()
        return u.deletingLastPathComponent().appending(path: ".\(u.lastPathComponent).nxforge-deleting-\(tag)").path
    }

    static func hide(_ path: String, bytes: Int64, label: String) throws -> PendingDelete {
        let p = PendingDelete(original: path, hidden: hiddenPath(for: path), bytes: bytes, label: label)
        try FileManager.default.moveItem(atPath: p.original, toPath: p.hidden)
        return p
    }

    /// Puts it back where it was; refused when something new took its place meanwhile (a build made the cache again).
    static func restore(_ p: PendingDelete) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: p.original) {
            throw NSError(domain: "NXForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(p.original.tildePath) exists again"])
        }
        try fm.moveItem(atPath: p.hidden, toPath: p.original)
    }

    /// Deletes for good (slow for a big cache: off the main thread).
    static func purge(_ p: PendingDelete) { try? FileManager.default.removeItem(atPath: p.hidden) }
}

extension AppModel {
    /// Holds what Storage just moved aside: Undo on a banner and on Edit › Undo (⌘Z) for a while, then it is deleted.
    func holdDeletes(_ held: [PendingDelete], failed: [String]) {
        if !failed.isEmpty {
            showBanner("Could not delete \(failed.count == 1 ? failed[0] : "\(failed.count) items")", tone: .failure)
        }
        guard !held.isEmpty else { revision += 1; return }
        pendingDeletes += held
        PendingDeletes.save(pendingDeletes)
        revision += 1
        let total = held.reduce(0) { $0 + $1.bytes }
        let what = held.count == 1 ? held[0].label : "\(held.count) items"
        if let um = NSApp.keyWindow?.undoManager {
            um.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { model.undoDeletes(held) } }
            um.setActionName("Delete \(Disk.gb(total))")
        }
        showBanner("Deleted \(what) · \(Disk.gb(total))", detail: "The space comes back in \(Int(PendingDeletes.undoSeconds)) seconds, once Undo is no longer offered.",
                   tone: .success, symbol: "trash", action: ("Undo", { [weak self] in self?.undoDeletes(held) }), seconds: PendingDeletes.undoSeconds)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PendingDeletes.undoSeconds))
            self?.purgeDeletes(held)
        }
    }

    func undoDeletes(_ list: [PendingDelete]) {
        let still = list.filter { p in pendingDeletes.contains(p) }
        guard !still.isEmpty else { return }
        var problems: [String] = []
        for p in still {
            do { try PendingDeletes.restore(p) } catch { problems.append(error.localizedDescription) }
        }
        pendingDeletes.removeAll { still.contains($0) }
        PendingDeletes.save(pendingDeletes)
        revision += 1
        measure()
        if problems.isEmpty {
            showBanner("Put back \(still.count == 1 ? still[0].label : "\(still.count) items")", tone: .success, symbol: "arrow.uturn.backward")
        } else {
            // what could not go back stays held under its hidden name, so delete it with the rest
            Task.detached { for p in still { if FileManager.default.fileExists(atPath: p.hidden) { PendingDeletes.purge(p) } } }
            showBanner("Some items could not be put back", detail: problems.joined(separator: "; "), tone: .failure)
        }
    }

    func purgeDeletes(_ list: [PendingDelete]) {
        let gone = list.filter { p in pendingDeletes.contains(p) }
        guard !gone.isEmpty else { return }
        pendingDeletes.removeAll { gone.contains($0) }
        let total = gone.reduce(0) { $0 + $1.bytes }
        Task { [weak self] in
            await Task.detached { for p in gone { PendingDeletes.purge(p) } }.value
            guard let self else { return }
            PendingDeletes.save(self.pendingDeletes)
            self.revision += 1
            self.measure()
            // only when nothing newer is on show: Undo is no longer there, so the banner it was on has to go anyway
            if self.banner == nil || self.banner?.action != nil { self.showBanner("Freed \(Disk.gb(total))", tone: .success, symbol: "leaf.fill") }
        }
    }

    /// Items a quit left held: deleted at the next launch, in the background.
    func purgeLeftoverDeletes() {
        let left = PendingDeletes.load()
        guard !left.isEmpty else { return }
        PendingDeletes.save([])
        Task.detached { for p in left { PendingDeletes.purge(p) } }
    }
}

// MARK: 7 · banners

/// A note at the foot of the window for work that ended in the background: it goes away by itself, and never needs a click.
struct Banner: Identifiable {
    enum Tone { case info, success, warning, failure }
    let id = UUID()
    var text: String
    var detail: String?
    var tone: Tone
    var symbol: String
    var action: (title: String, run: @MainActor () -> Void)?

    var color: Color {
        switch tone { case .info: .accentColor; case .success: .green; case .warning: .orange; case .failure: .red }
    }
}

extension AppModel {
    /// Shows a banner for `seconds` (longer with a button or a detail line), replacing the one on show.
    func showBanner(_ text: String, detail: String? = nil, tone: Banner.Tone = .info, symbol: String? = nil,
                    action: (String, @MainActor () -> Void)? = nil, seconds: Double? = nil) {
        let sym = symbol ?? { switch tone { case .info: "info.circle.fill"; case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .failure: "xmark.octagon.fill" } }()
        let b = Banner(text: text, detail: detail, tone: tone, symbol: sym, action: action.map { (title: $0.0, run: $0.1) })
        banner = b
        let wait = seconds ?? (tone == .failure ? 12 : action != nil || detail != nil ? 8 : 5)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            if self?.banner?.id == b.id { self?.banner = nil }
        }
    }
}

struct BannerView: View {
    @Bindable var model: AppModel
    let banner: Banner
    @State private var hover = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: banner.symbol).font(.title3).foregroundStyle(banner.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.text).font(.headline).lineLimit(2)
                if let d = banner.detail { Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            }
            Spacer(minLength: 8)
            if let a = banner.action {
                Button(a.title) { model.banner = nil; a.run() }.buttonStyle(.stagePrimary)
            }
            if banner.tone == .failure {
                Button { copyToClipboard([banner.text, banner.detail].compactMap { $0 }.joined(separator: "\n")) } label: {
                    Label("Copy", systemImage: "doc.on.doc").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless).help("Copy the message")
            }
            Button { model.banner = nil } label: { Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).help("Dismiss")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 620)
        .glassEffect(.regular.tint(banner.color.opacity(0.12)), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.bottom, 18).padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}

// MARK: 8 · recent games on Convert

enum RecentSources {
    static let limit = 5

    /// The list with `path` put first, without repeats, at most `limit` long.
    static func adding(_ path: String, to list: [String]) -> [String] {
        Array(([path] + list.filter { $0 != path }).prefix(limit))
    }
}

/// The last games chosen on Convert, under its drop area: one click chooses one again.
struct RecentSourcesRow: View {
    @Bindable var model: AppModel

    var body: some View {
        let fm = FileManager.default
        let list = model.settings.recentSources.filter { $0 != model.settings.gameDir }
        if !list.isEmpty && !model.run.running {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(list, id: \.self) { p in
                    let here = fm.fileExists(atPath: p)
                    Button { model.setGameDir(p) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: p.isNupFileish ? "shippingbox" : "folder").foregroundStyle(Color.accentColor).frame(width: 18)
                            Text(recentName(p)).lineLimit(1)
                            Text(p.url.deletingLastPathComponent().path.tildePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if !here { Text("Offline").font(.caption).foregroundStyle(.orange) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!here)
                    .help(here ? "Choose \(p.tildePath)" : "\(p.tildePath) is not here: its drive may be away")
                    .contextMenu {
                        Button("Show in Finder") { reveal(p) }.disabled(!here)
                        Button("Remove from Recent") { model.settings.recentSources.removeAll { $0 == p } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The game's own name when the Library knows it, else the folder's or the file's name.
    func recentName(_ p: String) -> String {
        model.library?.games.first(where: { $0.path == p })?.displayName ?? p.lastComponent
    }
}

// MARK: 9 · the Dock icon's menu

/// A menu item that runs a closure (the Dock menu is AppKit's, built each time it opens).
final class ClosureMenuItem: NSMenuItem {
    private var handler: (@MainActor () -> Void)?

    init(_ title: String, symbol: String? = nil, enabled: Bool = true, _ handler: @escaping @MainActor () -> Void) {
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
        self.handler = handler
        target = self
        isEnabled = enabled
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { MainActor.assumeIsolated { handler?() } }
}

extension AppModel {
    /// Recently played games with Play, Rebuild and Show in Finder; the build running now, with Stop.
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if run.running {
            let o = run.overall()
            let title = "Building \(batchCurrent?.displayName ?? game?.name ?? "a game") · \(Int((o.fraction * 100).rounded()))%"
            menu.addItem(ClosureMenuItem(title, symbol: "hammer", enabled: false) {})
            menu.addItem(ClosureMenuItem("Stop Build…", symbol: "stop.circle") { [weak self] in NSApp.activate(); self?.stopBuild() })
            menu.addItem(.separator())
        }
        let recent = recentlyPlayed(limit: 6)
        if !recent.isEmpty {
            menu.addItem(ClosureMenuItem("Recently Played", enabled: false) {})
            let builds = Engine.builds()
            for r in recent {
                let item = NSMenuItem(title: r.record.name, action: nil, keyEquivalent: "")
                let icon = NSWorkspace.shared.icon(forFile: r.record.app)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                let sub = NSMenu()
                sub.autoenablesItems = false
                let app = r.record.app
                sub.addItem(ClosureMenuItem(isPlaying(app: app) ? "Show Game" : "Play", symbol: "play.fill") { [weak self] in self?.openApp(app) })
                if let b = builds.first(where: { $0.app == app }) {
                    sub.addItem(ClosureMenuItem("Rebuild", symbol: "hammer", enabled: !run.running && allOK) { [weak self] in
                        NSApp.activate(); self?.rebuildAsked(b)
                    })
                }
                sub.addItem(ClosureMenuItem("Game Page", symbol: "info.circle") { [weak self] in
                    NSApp.activate(); self?.openGame(GameRef(libraryID: nil, app: app))
                })
                sub.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { reveal(app) })
                item.submenu = sub
                menu.addItem(item)
            }
        }
        if !run.running, ready {
            if !recent.isEmpty { menu.addItem(.separator()) }
            menu.addItem(ClosureMenuItem("Build \(game?.name ?? "Mac App")", symbol: "macwindow.badge.plus") { [weak self] in NSApp.activate(); self?.build() })
        }
        return menu
    }
}

// MARK: 10 · where the window was

extension AppModel {
    /// The page, the build picked on Builds and the game the Library was on, as they were at the last quit.
    func restoreWindowState() {
        if let p = settings.lastPage.flatMap(Page.init(rawValue:)) { page = p }
        if let b = settings.lastBuild, FileManager.default.fileExists(atPath: b) { selectedBuild = b }
        if let f = settings.lastLibraryFocus, library?.games.contains(where: { $0.id == f }) == true { libraryFocus = f }
    }

    /// Called as they change: kept in the settings file.
    func rememberWindowState() {
        guard ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }   // a test picture leaves the real one alone
        var s = settings
        s.lastPage = page.rawValue
        s.lastBuild = selectedBuild
        s.lastLibraryFocus = libraryFocus
        if s != settings { settings = s }
    }
}
