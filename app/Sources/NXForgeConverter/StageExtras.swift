// The front end's small extras (Converter 0.11.0): the marks a cover carries when a game needs a look (GameAttention), and the
// screenshots a game's sidebar took, on its page (GameCaptures, ScreenshotStrip).
import AppKit
import SwiftUI

/// Something about a game worth a look, as a mark on its cover, a line under it in the Library and a row on its page.
struct GameAttention: Hashable, Identifiable {
    enum Kind: Int, Comparable {
        case crashed, update, unsaved
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }
    let kind: Kind
    let text: String
    let detail: String
    var id: Int { kind.rawValue }

    var symbol: String {
        switch kind {
        case .crashed: "exclamationmark.triangle.fill"
        case .update: "arrow.clockwise"
        case .unsaved: "externaldrive.badge.exclamationmark"
        }
    }

    var color: Color {
        switch kind {
        case .crashed: Color(red: 1, green: 0.42, blue: 0.38)
        case .update: Color(red: 0.98, green: 0.75, blue: 0.14)
        case .unsaved: Color(red: 0.55, green: 0.75, blue: 1)
        }
    }

    /// What one built game needs, read from disk (call it off the main thread): its last run ended in a crash (the launcher's log says the
    /// host stopped on a signal), a newer NXForge can rebuild it, or it has a save with no copy anywhere else (Cloud saves off, no snapshot).
    static func check(app: String, titleID: String?, outdated: Bool, playing: Bool, home: String = NSHomeDirectory()) -> [GameAttention] {
        var out: [GameAttention] = []
        if let t = titleID, !playing, let tail = logTail("\(home)/Library/Logs/nxnative/\(t).log"), let sig = crashSignal(tail) {
            out.append(GameAttention(kind: .crashed, text: "Last run crashed", detail: "The game stopped on signal \(sig) last time. Its log is in ~/Library/Logs/nxnative/\(t).log."))
        }
        if outdated {
            out.append(GameAttention(kind: .update, text: "Update ready", detail: "A newer NXForge can rebuild this game. It still plays as it is."))
        }
        if let t = titleID {
            let loc = SaveSnapshots.location(app: app, titleID: t, home: home)
            let cloud = (LaunchSettings.defaults(app: app)?.string(forKey: "cloudSaves.folder") ?? "").isEmpty == false
            let snaps = ((try? FileManager.default.contentsOfDirectory(atPath: loc.snapshots)) ?? []).contains { !$0.hasPrefix(".") }
            if SaveSnapshots.hasSave(loc) && !cloud && !snaps {
                out.append(GameAttention(kind: .unsaved, text: "Save only on this Mac", detail: "No Cloud saves and no snapshot. Take a snapshot on the game's page in the converter, or turn on Cloud saves."))
            }
        }
        return out.sorted { $0.kind < $1.kind }
    }

    /// The last 4 KB of a log
    static func logTail(_ path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > 4096 ? end - 4096 : 0)
        return (try? h.readToEnd()).flatMap { String(decoding: $0, as: UTF8.self) }
    }

    /// The signal of "launcher: the host stopped on signal N" (dm/mac/launcher.c) when the log ends with it
    static func crashSignal(_ tail: String) -> Int? {
        guard let r = tail.range(of: "the host stopped on signal ", options: .backwards) else { return nil }
        if tail[r.upperBound...].contains("launcher: the host exited") { return nil }
        return Int(tail[r.upperBound...].prefix { $0.isNumber })
    }
}

extension AppModel {
    /// Reads what the built games need (GameAttention) off the main thread; the covers show it when it comes.
    func refreshAttention(_ games: [StageGame]) async {
        let items = games.compactMap { g in g.app.map { (id: g.id, app: $0, titleID: g.titleID, outdated: g.outdated, playing: isPlaying(app: $0)) } }
        let found = await Task.detached(priority: .utility) {
            Dictionary(items.map { ($0.id, GameAttention.check(app: $0.app, titleID: $0.titleID, outdated: $0.outdated, playing: $0.playing)) }, uniquingKeysWith: { a, _ in a })
        }.value
        if found != attention { attention = found }
    }
}

/// The screenshots the game's sidebar took (dm/host/capture_mac.m capture_folder): the folder chosen in the sidebar, else Screenshots in the
/// game folder (the folder the app is in), else ~/Pictures/NXForge, where they are named after the game.
enum GameCaptures {
    static let kinds: Set<String> = ["png", "jpg", "jpeg", "heic"]

    static func folders(app: String, home: String = NSHomeDirectory()) -> [(path: String, prefix: String?)] {
        var out: [(String, String?)] = []
        if let d = LaunchSettings.defaults(app: app) {
            for (k, v) in d.dictionaryRepresentation() where k.hasPrefix("DMQuickSettings.captureDir.") {
                if let p = v as? String, !p.isEmpty { out.append((p, nil)) }
            }
        }
        out.append((app.url.deletingLastPathComponent().appendingPathComponent("Screenshots").path, nil))
        let name = (NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleName"] as? String) ?? app.url.deletingPathExtension().lastPathComponent
        out.append(("\(home)/Pictures/NXForge", name))
        return out
    }

    /// The newest screenshots first, at most `limit`
    static func screenshots(app: String, limit: Int = 12) -> [URL] {
        var seen = Set<String>(), found: [(URL, Date)] = []
        for (dir, prefix) in folders(app: app) where !seen.contains(dir) {
            seen.insert(dir)
            let u = URL(fileURLWithPath: dir)
            let items = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for f in items where kinds.contains(f.pathExtension.lowercased()) && (prefix.map { f.lastPathComponent.hasPrefix($0) } ?? true) {
                found.append((f, (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

/// Thumbnails, made once off the main thread and kept
@MainActor @Observable
final class ThumbStore {
    static let shared = ThumbStore()
    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var asked = Set<URL>()

    func image(_ u: URL) -> NSImage? {
        if let i = images[u] { return i }
        guard !asked.contains(u) else { return nil }
        asked.insert(u)
        Task.detached(priority: .utility) {
            let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 480, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            await MainActor.run { ThumbStore.shared.images[u] = img }
        }
        return nil
    }
}

/// The game's screenshots on its page: a row of thumbnails; a click opens one, the menu shows it in Finder or shares it.
struct ScreenshotStrip: View {
    let app: String
    let tint: Color
    @State private var shots: [URL] = []

    var body: some View {
        Group {
            if !shots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 11, weight: .bold)).foregroundStyle(tint).brightness(0.25)
                        Text("SCREENSHOTS").font(.system(size: 10.5, weight: .bold)).fontWidth(.expanded).kerning(1.4).foregroundStyle(StageLook.soft)
                        Spacer()
                        Button("Show All") { NSWorkspace.shared.activateFileViewerSelecting(Array(shots.prefix(1))) }
                            .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(StageLook.soft)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shots, id: \.self) { u in thumb(u) }
                        }
                    }
                }
                .padding(18)
                .background(StageLook.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(StageLook.edge, lineWidth: 1))
            }
        }
        .task(id: app) {
            let a = app
            shots = await Task.detached(priority: .utility) { GameCaptures.screenshots(app: a) }.value
        }
    }

    func thumb(_ u: URL) -> some View {
        let img = ThumbStore.shared.image(u)
        return Button { NSWorkspace.shared.open(u) } label: {
            Color(white: 0.12)
                .overlay { if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) } }
                .frame(width: 160, height: 90).clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(u.lastPathComponent)
        .accessibilityLabel("Screenshot \(u.deletingPathExtension().lastPathComponent)")
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(u) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            Button("Copy") { if let i = NSImage(contentsOf: u) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([i]) } }
            ShareLink(item: u) { Text("Share…") }
        }
    }
}

/// A game's marks on its page: each thing that needs a look, with what to do about it
struct AttentionRows: View {
    let items: [GameAttention]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { a in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: a.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(a.color).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.text).font(.system(size: 14.5, weight: .semibold))
                            Text(a.detail).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StageLook.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(StageLook.edge, lineWidth: 1))
        }
    }
}

/// The marks on a cover's top corners: a star for a favourite, and the most pressing thing that needs a look
struct CoverMarks: View {
    let favorite: Bool
    let attention: GameAttention?

    var body: some View {
        HStack(alignment: .top) {
            if favorite {
                Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.82, blue: 0.30))
                    .frame(width: 22, height: 22).background(.black.opacity(0.62), in: .circle).accessibilityLabel("Favourite")
            }
            Spacer(minLength: 0)
            if let a = attention {
                Image(systemName: a.symbol).font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
                    .frame(width: 22, height: 22).background(a.color, in: .circle)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .help(a.text).accessibilityLabel(a.text)
            }
        }
        .padding(6)
    }
}
