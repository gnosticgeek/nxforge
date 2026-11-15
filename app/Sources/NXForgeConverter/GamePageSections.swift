// The game page's two columns under its headline: Media (the store's trailer and screenshots, and the player's own captures, three
// large tiles with View all opening the in-app gallery) and About (the store's pitch, Read more, and a table of its facts).
import AppKit
import SwiftUI

/// The game page's Media: a switch between the store's pictures (trailer first) and the player's own screenshots, three tiles
/// across, and View all for the gallery (MediaViewer.swift). Without the store's pictures it is the player's screenshots alone.
struct GameMedia: View {
    let model: AppModel
    let game: StageGame
    /// the column's width: three tiles across it
    var width: CGFloat = 900
    enum Tab { case store, captures }
    @State private var tab: Tab? = nil
    @State private var captures: [URL]? = nil

    var body: some View {
        let store = StoreInfoStore.shared
        let storeOn = model.settings.downloadStoreInfo
        let videos = storeOn ? store.videos(game.coverKey) : []
        let shots = storeOn ? store.shots(game.coverKey) : []
        let storeItems: [GalleryItem] = videos.map { .video($0.video, thumb: $0.thumb) } + shots.map { .image($0) }
        let mine: [GalleryItem] = (captures ?? []).map { .image($0) }
        let current = tab ?? (storeItems.isEmpty ? .captures : .store)
        let items = current == .store ? storeItems : mine
        let accent = CoverArt.tint(game)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Media").font(.system(size: 26, weight: .heavy)).tracking(-0.4)
                Spacer()
                if !items.isEmpty {
                    Button { open(items, at: 0, current) } label: {
                        HStack(spacing: 6) { Text("View all \(items.count)"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                    }
                    .buttonStyle(.plain).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(accent).brightness(0.35)
                    .help("Shows them all full screen")
                }
            }
            if !storeItems.isEmpty {
                HStack(spacing: 0) {
                    segment("From the store (\(storeItems.count))", on: current == .store, accent: accent) { tab = .store }
                    segment("Your captures (\(mine.count))", on: current == .captures, accent: accent) { tab = .captures }
                }
                .padding(3)
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .padding(.top, 16)
            }
            Text(caption(current, videos: videos.count, shots: shots.count, mine: mine.count))
                .font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.soft)
                .padding(.top, storeItems.isEmpty ? 10 : 18)
            if !items.isEmpty {
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { i in
                        if i < items.count { tile(items[i]) { open(items, at: i, current) } }
                        else { Color.clear.frame(width: tileWidth, height: 1) }
                    }
                }
                .padding(.top, 14)
            } else if captures != nil {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 20, weight: .semibold)).foregroundStyle(StageLook.soft)
                    Text(game.app == nil ? "Screenshots you take in game show here once the game is built." : "No screenshots yet. Take one in game from the sidebar and it shows here.")
                        .font(.system(size: 14)).foregroundStyle(StageLook.faint)
                }
                .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: tileWidth * 9 / 16, alignment: .leading)
                .background(StageLook.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StageLook.edge, lineWidth: 1))
                .padding(.top, 14)
            }
        }
        .task(id: game.app ?? game.id) {
            guard let a = game.app else { captures = []; return }
            captures = await Task.detached(priority: .utility) { GameCaptures.screenshots(app: a, limit: 200) }.value
        }
    }

    var tileWidth: CGFloat { max((width - 32) / 3, 120) }

    func caption(_ t: Tab, videos: Int, shots: Int, mine: Int) -> String {
        func count(_ n: Int, _ what: String) -> String { "\(n) \(what)\(n == 1 ? "" : "s")" }
        if t == .store { return [videos > 0 ? count(videos, "trailer") : nil, shots > 0 ? count(shots, "screenshot") : nil].compactMap { $0 }.joined(separator: " · ") }
        return mine == 0 ? "Your screenshots" : count(mine, "screenshot") + " you took"
    }

    func open(_ items: [GalleryItem], at i: Int, _ t: Tab) {
        model.openGallery(items, at: i, title: "\(game.name) · " + (t == .store ? "From the store" : "Screenshots"))
    }

    func segment(_ title: String, on: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeOut(duration: 0.18)) { action() } }) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(on ? .white : StageLook.soft)
                .padding(.horizontal, 26).frame(height: 38)
                .background {
                    if on {
                        Capsule().fill(accent.opacity(0.42)).brightness(-0.05)
                            .overlay(Capsule().strokeBorder(accent.opacity(0.9), lineWidth: 1).brightness(0.2))
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A picture, or a trailer: its picture with a play mark and a Trailer label
    func tile(_ item: GalleryItem, open: @escaping () -> Void) -> some View {
        let img = item.thumb.flatMap { ThumbStore.shared.image($0) }
        let w = tileWidth
        var video: StoreVideo? { if case .video(let v, _) = item { v } else { nil } }
        return Button(action: open) {
            Color(white: 0.12)
                .frame(width: w, height: w * 9 / 16)
                .overlay { if let img { Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill) } }
                .overlay {
                    if video != nil {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                            PlayGlyph(size: min(56, w * 0.18)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text("Trailer").font(.system(size: 13.5, weight: .semibold))
                                .padding(.horizontal, 9).frame(height: 24)
                                .background(.black.opacity(0.6), in: .rect(cornerRadius: 6)).padding(10)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(video?.title ?? item.thumb?.lastPathComponent ?? "")
        .accessibilityLabel(video.map { "Play \($0.title ?? "the trailer")" } ?? "Screenshot")
        .contextMenu {
            if case .image(let u) = item {
                Button("View", action: open)
                Button("Open in Preview") { NSWorkspace.shared.open(u) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                Button("Copy") { if let i = NSImage(contentsOf: u) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([i]) } }
                ShareLink(item: u) { Text("Share…") }
            } else if let u = video?.watchURL {
                Button("Play", action: open)
                Button("Open in Browser") { NSWorkspace.shared.open(u) }
            }
        }
    }
}

/// The game page's About, from the game's page on Nintendo's UK store: the short pitch with Read more for the publisher's whole
/// description, a table of the store's facts (More details adds play modes and languages), and a link to the store page
struct GameAbout: View {
    let game: StageGame
    let info: StoreInfo
    @State private var readMore = false
    @State private var details = false

    var body: some View {
        let accent = CoverArt.tint(game)
        let paras = info.about.filter { $0 != info.excerpt }
        let pitch = info.excerpt ?? paras.first
        let rest = info.excerpt == nil ? Array(paras.dropFirst()) : paras
        VStack(alignment: .leading, spacing: 0) {
            Text("About").font(.system(size: 26, weight: .heavy)).tracking(-0.4)
            if let pitch {
                // the pitch with Read more at its end, as one run of text: the link opens the rest in place
                Text(pitchText(pitch, more: !rest.isEmpty, accent: accent))
                    .font(.system(size: 16)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "nxforge-more" else { return .systemAction }
                        withAnimation(.easeOut(duration: 0.2)) { readMore.toggle() }
                        return .handled
                    })
                    .padding(.top, 12)
                if readMore {
                    Text(rest.joined(separator: "\n\n")).font(.system(size: 14.5)).foregroundStyle(StageLook.soft).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                        .transition(.opacity)
                }
            }
            table(rows(extra: details)).padding(.top, 16)
            HStack {
                if !rows(extra: true).dropFirst(rows(extra: false).count).isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.2)) { details.toggle() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).rotationEffect(.degrees(details ? 90 : 0))
                            Text(details ? "Fewer details" : "More details")
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let p = info.page.flatMap(URL.init(string:)) {
                    Button { NSWorkspace.shared.open(p) } label: {
                        HStack(spacing: 5) { Text("Nintendo UK store"); Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)) }
                    }
                    .buttonStyle(.plain).help(p.absoluteString)
                }
            }
            .font(.system(size: 15.5, weight: .semibold)).foregroundStyle(accent).brightness(0.35)
            .padding(.top, 20)
        }
    }

    func pitchText(_ pitch: String, more: Bool, accent: Color) -> AttributedString {
        var s = AttributedString(pitch)
        guard more else { return s }
        var link = AttributedString(readMore ? "  Show less" : "  Read more ›")
        link.link = URL(string: "nxforge-more:toggle")
        link.foregroundColor = NSColor(accent).blended(withFraction: 0.35, of: .white).map { Color(nsColor: $0) } ?? accent
        link.font = .system(size: 16, weight: .semibold)
        s += link
        return s
    }

    /// The facts the store gives, in the mock-up's order; with extra, the ones More details adds
    func rows(extra: Bool) -> [(String, String)] {
        var r: [(String, String?)] = [("Publisher", info.publisher), ("Released", Self.date(info.released)), ("Players", players),
                                      ("Rating", info.rating), ("Size", info.size), ("Genres", info.genres.isEmpty ? nil : info.genres.joined(separator: " · "))]
        if extra { r += [("Play modes", info.modes.isEmpty ? nil : info.modes.joined(separator: " · ")), ("Languages", StoreInfo.languageList(info.languages))] }
        return r.compactMap { k, v in v.map { (k, $0) } }
    }

    var players: String? {
        guard let to = info.playersTo, to > 0 else { return nil }
        let from = info.playersFrom ?? 1
        return from == to ? "\(to)" : "\(from)–\(to)"
    }

    /// "11/07/2019" (the store's, day first) as "11 Jul 2019"; anything else as it is
    static func date(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.dateFormat = "dd/MM/yyyy"
        guard let d = f.date(from: s) else { return s }
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    func table(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.0).font(.system(size: 14.5, weight: .medium)).foregroundStyle(StageLook.soft).frame(width: 130, alignment: .leading)
                    Text(r.1).font(.system(size: 15, weight: .semibold)).lineLimit(r.0 == "Languages" ? 4 : 1).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6).padding(.horizontal, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
            }
        }
    }
}
