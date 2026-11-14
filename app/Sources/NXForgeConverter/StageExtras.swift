// The front end's small extras (Converter 0.11.0, 0.11.1): the marks a cover carries when a game needs a look (GameAttention), and the
// screenshots a game's sidebar took, on its page (GameCaptures, ScreenshotRow), and the game page's key art (GameKeyArt).
import AppKit
import CoreImage
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
    /// The mark a cover carries: a crash or a save with no copy elsewhere. Update ready stays in the line under the cover, not on
    /// it: after an NXForge update every built game has it, and a mark on every cover marks nothing.
    func coverMark(_ g: StageGame) -> GameAttention? { attention[g.id]?.first { $0.kind != .update } }

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
        // snapshots of the game page: NXC_SHOTS=<folder> stands in for every game's screenshots
        if let d = ProcessInfo.processInfo.environment["NXC_SHOTS"] { return [(d, nil)] }
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
            let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            await MainActor.run { ThumbStore.shared.images[u] = img }
        }
        return nil
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

/// The game page's Screenshots: the three newest, large, with View all showing the rest in Finder. A game with none says where they come from.
struct ScreenshotRow: View {
    let app: String
    @State private var shots: [URL]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Screenshots").font(.system(size: 24, weight: .heavy)).tracking(-0.4)
                Spacer()
                if let s = shots, !s.isEmpty {
                    Button { NSWorkspace.shared.activateFileViewerSelecting(Array(s.prefix(1))) } label: {
                        HStack(spacing: 6) { Text("View all"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                    }
                    .buttonStyle(.plain).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(StageLook.soft)
                    .help("Shows the screenshots in Finder")
                }
            }
            if let s = shots, !s.isEmpty {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { i in
                        if i < s.count { tile(s[i]) } else { Color.clear.aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity) }
                    }
                }
            } else if shots != nil {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 20, weight: .semibold)).foregroundStyle(StageLook.soft)
                    Text("No screenshots yet. Take one in game from the sidebar and it shows here.").font(.system(size: 14)).foregroundStyle(StageLook.faint)
                }
                .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .background(StageLook.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StageLook.edge, lineWidth: 1))
            }
        }
        .task(id: app) {
            let a = app
            shots = await Task.detached(priority: .utility) { GameCaptures.screenshots(app: a) }.value
        }
    }

    func tile(_ u: URL) -> some View {
        let img = ThumbStore.shared.image(u)
        return Button { NSWorkspace.shared.open(u) } label: {
            Color(white: 0.12)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { if let img { Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill) } }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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

/// The game page's key art, filling the top of the window behind the box and the title and fading into the stage below and to the
/// left. GameTDB has covers only, no wide art, so it is the game's newest screenshot, sharp; a game with none gets its front cover,
/// enlarged and blurred.
struct GameKeyArt: View {
    let game: StageGame
    @State private var shot: NSImage?
    @Environment(\.accessibilityReduceTransparency) private var solid
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        let _ = CoverStore.shared.revision
        let art = shot ?? CoverArt.wide(game)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if let art, !solid {
                ZStack(alignment: .top) {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h * 0.78).clipped()
                        .saturation(shot == nil ? 1.2 : 1.05)
                        .opacity(shot == nil ? 0.55 : 0.75)
                    // the left darker, where the box and the title stand
                    LinearGradient(stops: [.init(color: StageLook.background.opacity(0.80), location: 0), .init(color: StageLook.background.opacity(0.35), location: 0.5),
                                           .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
                        .frame(height: h * 0.78)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.40), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom).frame(height: h * 0.78).frame(maxHeight: .infinity, alignment: .top))
                .frame(width: w, height: h, alignment: .top)
                .id(shot == nil ? "cover" : "shot").transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.4), value: shot == nil)
        .task(id: game.app) {
            guard let app = game.app else { shot = nil; return }
            if let c = Self.cache[app] { shot = c; return }
            let img = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let u = GameCaptures.screenshots(app: app, limit: 1).first,
                      let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400,
                                                                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            if let img { Self.cache[app] = img }
            shot = img
        }
    }
}

extension CoverArt {
    /// The front cover (or the icon) made into wide art: small and blurred, so it can fill the top of the window
    static func wide(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        let art = store.image(g.coverKey, .front)
        return store.drawn(g.coverKey + "-wide2-" + (art == nil ? "icon" : "art")) {
            guard let src = (art ?? icon(g)).flatMap({ small($0, art == nil ? 320 : 640) }), let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let ci = CIImage(cgImage: cg)
            guard let f = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: ci.clampedToExtent(), kCIInputRadiusKey: art == nil ? 7 : 3.5]),
                  let out = f.outputImage?.cropped(to: ci.extent),
                  let done = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(out, from: ci.extent) else { return src }
            return NSImage(cgImage: done, size: src.size)
        }
    }
}
