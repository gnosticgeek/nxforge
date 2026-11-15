// A game's details from its page on Nintendo's European store (nintendo.com/en-gb): the publisher's description, the facts the
// store lists (publisher, release date, genres, players, age rating, size, languages, play modes) and the official screenshots of
// the page's gallery. Found like the wide art (Covers.swift, HeroSource): the store's own search by title ID, else by exact name,
// then the game's store page once for the description and the gallery. Fetched when a game's page is opened, kept for 30 days in
// ~/Library/Application Support/NXForge Converter/covers/store as <key>.json and <key>-NN.jpg, and only on this Mac.
// A setting turns it off (Settings › Artwork).
import AppKit
import SwiftUI

struct StoreInfo: Codable, Equatable {
    var title: String
    var publisher: String?
    /// as the store writes it, day first: "11/07/2019"
    var released: String?
    var genres: [String] = []
    var playersFrom: Int?
    var playersTo: Int?
    var rating: String?
    var size: String?
    var languages: String?
    var excerpt: String?
    /// the description's paragraphs, from the store page
    var about: [String] = []
    /// "TV", "Tabletop", "Handheld"
    var modes: [String] = []
    var page: String?
    /// full-size screenshots of the page's gallery
    var shots: [String] = []
    /// the page's trailers, in its order (nil: kept before trailers were looked for, so the page is read again)
    var trailers: [StoreVideo]?
    var fetched = Date()

    var players: String? {
        guard let to = playersTo, to > 0 else { return nil }
        let from = playersFrom ?? 1
        return from == to ? "\(to) player\(to == 1 ? "" : "s")" : "\(from)–\(to) players"
    }

    /// "Japanese, English, Spanish …": the store's lower-case list, capitalised
    static func languageList(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).capitalized }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A trailer on a game's store page: Nintendo's own video file, played here by AVPlayer, or a video of Nintendo's on YouTube, played by
/// YouTube's embedded player with its ad servers blocked (MediaViewer.swift)
struct StoreVideo: Codable, Hashable {
    /// the YouTube video's ID
    var youtube: String?
    /// Nintendo's .mp4
    var file: String?
    var thumb: String?
    var title: String?

    var watchURL: URL? { youtube.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") } ?? file.flatMap(URL.init(string:)) }
}

/// The lookup and the page reading, apart from the network (tested)
enum StoreSource {
    static let fields = "application_id_s,title,type,url,publisher,pretty_date_s,pretty_game_categories_txt,players_from,players_to,pretty_agerating_s,"
        + "datasize_readable_txt,language_availability,excerpt,play_mode_tv_mode_b,play_mode_tabletop_mode_b,play_mode_handheld_mode_b"

    static func byID(_ id: String) -> URL? {
        let q = id.lowercased()
        guard q.count == 16, q.allSatisfy(\.isHexDigit) else { return nil }
        return HeroSource.url(["q": "*", "fq": "type:GAME AND application_id_s:\(q)", "rows": "6"], fields: fields)
    }

    static func byName(_ name: String) -> URL? {
        let n = String(CoverSource.plain(name).map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").joined(separator: " ")
        guard CoverSource.normalize(n).count >= 3 else { return nil }
        return HeroSource.url(["q": n, "fq": "type:GAME", "rows": "8"], fields: fields)
    }

    /// The search's answer as details: for a title ID the shortest title (a game's Switch 2 Edition shares its ID), for a name the
    /// game whose title is that name
    static func parse(_ data: Data, id: String? = nil, name: String? = nil) -> StoreInfo? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = o["response"] as? [String: Any],
              let docs = r["docs"] as? [[String: Any]] else { return nil }
        let want = name.map { CoverSource.normalize(CoverSource.plain($0)) }
        let fit = docs.filter { d in
            guard (d["type"] as? String) == "GAME", let t = d["title"] as? String else { return false }
            if let id { return (d["application_id_s"] as? String)?.uppercased() == id.uppercased() }
            if let want { return d["application_id_s"] != nil && (CoverSource.normalize(t) == want || CoverSource.normalize(CoverSource.plain(t)) == want) }
            return false
        }
        guard let d = fit.min(by: { (($0["title"] as? String) ?? "").count < (($1["title"] as? String) ?? "").count }), let title = d["title"] as? String else { return nil }
        func s(_ k: String) -> String? { (d[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func first(_ k: String) -> String? { (d[k] as? [String])?.first ?? s(k) }
        var info = StoreInfo(title: title)
        info.publisher = s("publisher")
        info.released = s("pretty_date_s")
        info.genres = d["pretty_game_categories_txt"] as? [String] ?? []
        info.playersFrom = d["players_from"] as? Int
        info.playersTo = d["players_to"] as? Int
        info.rating = s("pretty_agerating_s")
        info.size = first("datasize_readable_txt")
        info.languages = StoreInfo.languageList(first("language_availability"))
        info.excerpt = s("excerpt")
        info.modes = [("play_mode_tv_mode_b", "TV"), ("play_mode_tabletop_mode_b", "Tabletop"), ("play_mode_handheld_mode_b", "Handheld")]
            .filter { d[$0.0] as? Bool == true }.map(\.1)
        if let u = s("url"), u.hasPrefix("/"), !u.hasPrefix("//") { info.page = HeroSource.site + u }
        return info
    }

    /// The page's gallery: the pictures of its "mediagallery" list, full size (the list shows "_TM_Standard" copies)
    static func gallery(_ html: String) -> [String] {
        guard let start = html.range(of: "mediagallery\"") else { return [] }
        let rest = html[start.upperBound...]
        let block = rest[..<(rest.range(of: "</ul>")?.lowerBound ?? rest.endIndex)]
        var out: [String] = []
        var at = block.startIndex
        while let r = block.range(of: #"data-xs="[^"]+""#, options: .regularExpression, range: at..<block.endIndex) {
            let v = String(block[r].dropFirst(9).dropLast()).replacingOccurrences(of: "_TM_Standard.", with: ".")
            if v.hasPrefix(HeroSource.site + "/"), !out.contains(v), v.lowercased().hasSuffix(".jpg") || v.lowercased().hasSuffix(".png") { out.append(v) }
            at = r.upperBound
        }
        return out
    }

    /// The page's trailers, at most four, in the page's order: Nintendo's own files (the gallery's video entries) first, then the
    /// YouTube videos its sections embed (window.videos, else their iframes); playlists are left out
    static func videos(_ html: String) -> [StoreVideo] {
        func amp(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&") }
        func groups(_ pattern: String) -> [[String]] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = html as NSString
            return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { m in
                (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            }
        }
        var out: [StoreVideo] = []
        for g in groups(#"'video_thumbnail_url':\s*'([^']*)',\s*'video_content_url':\s*'(https://[^']+\.mp4[^']*)'"#) {
            let file = amp(g[1])
            guard !out.contains(where: { $0.file == file }) else { continue }
            out.append(StoreVideo(file: file, thumb: g[0].hasPrefix("https://") ? amp(g[0]) : nil))
        }
        var ids = groups(#"window\.videos\.push\(\{[^}]*?\bid:\s*"([A-Za-z0-9_-]{11})"[^}]*?isPlaylist:\s*false"#).map { $0[0] }
        if ids.isEmpty { ids = groups(#"youtube(?:-nocookie)?\.com/embed/([A-Za-z0-9_-]{11})"#).map { $0[0] } }
        for id in ids where !out.contains(where: { $0.youtube == id }) {
            out.append(StoreVideo(youtube: id, thumb: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"))
        }
        return Array(out.prefix(4))
    }

    /// YouTube's search for a game's trailer (asked only when its store page has none that plays)
    static func youtubeSearch(_ name: String) -> URL? {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: "\(CoverSource.plain(name)) Nintendo Switch trailer")]
        return c.url
    }

    /// The trailer in YouTube's search results: a video whose title names the game and whose channel is Nintendo's or the
    /// publisher's, a trailer for Switch rather than for an older console first. Nil when no result is an official one.
    static func pickTrailer(_ html: String, name: String, publisher: String?) -> StoreVideo? {
        let want = CoverSource.normalize(CoverSource.plain(name))
        let pub = publisher.map { CoverSource.normalize($0) } ?? ""
        guard want.count >= 3 else { return nil }
        func first(_ pattern: String, in s: Substring) -> String? {
            guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
            let m = String(s[r])
            guard let q = m.dropLast().lastIndex(of: "\"") else { return nil }
            return String(m[m.index(after: q)..<m.index(before: m.endIndex)])
        }
        var best: (score: Int, video: StoreVideo)?
        let parts = html.components(separatedBy: "\"videoRenderer\":{").dropFirst().prefix(12)
        for part in parts {
            let s = Substring(part)
            guard let id = first(#""videoId":"[A-Za-z0-9_-]{11}""#, in: s),
                  let title = first(#""title":\{"runs":\[\{"text":"[^"]*""#, in: s),
                  let owner = first(#""ownerText":\{"runs":\[\{"text":"[^"]*""#, in: s) else { continue }
            let t = title.replacingOccurrences(of: "\\u0026", with: "&")
            let nt = CoverSource.normalize(t), no = CoverSource.normalize(owner)
            guard nt.contains(want) else { continue }
            guard no.contains("nintendo") || (!pub.isEmpty && (no.contains(pub) || pub.contains(no))) else { continue }
            var score = 0
            if nt.contains("trailer") { score += 2 }
            if nt.contains("switch") { score += 1 }
            if nt.contains("wiiu") || nt.contains("3ds") { score -= 3 }
            if best == nil || score > best!.score { best = (score, StoreVideo(youtube: id, thumb: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg", title: t)) }
        }
        return best?.video
    }

    /// A YouTube video's title, from its oEmbed answer
    static func oembedTitle(_ data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["title"] as? String
    }

    /// The description: the paragraphs of the page's first content blocks (a game with its own designed page splits its text over
    /// several), without headings, short captions or the publisher note; about 900 characters at most
    static func about(_ html: String) -> [String] {
        var out: [String] = [], total = 0
        var from = html.startIndex
        for _ in 0..<4 {
            guard total < 600, let start = html.range(of: "class=\"col-xs-12 content\"", range: from..<html.endIndex) else { break }
            let rest = html[start.upperBound...]
            let end = rest.range(of: "class=\"col-xs-12", range: rest.index(rest.startIndex, offsetBy: min(20, rest.count))..<rest.endIndex)?.lowerBound
                ?? rest.index(rest.startIndex, offsetBy: min(8000, rest.count))
            let block = rest[..<end]
            from = end
            var at = block.startIndex
            while let o = block.range(of: "<p[ >]", options: .regularExpression, range: at..<block.endIndex),
                  let c = block.range(of: "</p>", range: o.upperBound..<block.endIndex) {
                let inner = block[block.index(before: o.upperBound)..<c.lowerBound]
                let body = inner.firstIndex(of: ">").map { inner[inner.index(after: $0)...] } ?? inner
                let text = plainText(String(body))
                at = c.upperBound
                guard text.count >= 30 || text.hasPrefix("•"), !text.hasPrefix("This description was provided"), !out.contains(text) else { continue }
                guard total + text.count <= 1400 || out.isEmpty else { break }
                out.append(text)
                total += text.count
            }
        }
        return out
    }

    /// Text without tags, entities read, white space folded
    static func plainText(_ s: String) -> String {
        // list items on lines of their own
        var t = s.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: .regularExpression)
            .replacingOccurrences(of: "<br[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, c) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
                       ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&hellip;", "…"), ("&ndash;", "–"), ("&mdash;", "—")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        return t.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

@MainActor @Observable
final class StoreInfoStore {
    static let shared = StoreInfoStore()
    var revision = 0
    @ObservationIgnored private var memory: [String: StoreInfo] = [:]
    @ObservationIgnored private var loading = Set<String>()
    @ObservationIgnored private var shotsAsked = Set<String>()

    nonisolated static var dir: URL { CoverStore.dir.appending(path: "store") }
    nonisolated static func file(_ key: String) -> URL { dir.appending(path: "\(key).json") }
    nonisolated static func shot(_ key: String, _ i: Int) -> URL { dir.appending(path: String(format: "%@-%02d.jpg", key, i + 1)) }
    nonisolated static func videoThumb(_ key: String, _ i: Int) -> URL { dir.appending(path: String(format: "%@-t%02d.jpg", key, i + 1)) }
    /// how many of a game's store screenshots are kept
    static let maxShots = 12

    /// The details on disk (or nil: not looked for yet, not found, or the setting is off)
    func info(_ key: String) -> StoreInfo? {
        let _ = revision
        if let i = memory[key] { return i }
        guard let d = try? Data(contentsOf: Self.file(key)), let i = try? JSONDecoder().decode(StoreInfo.self, from: d) else { return nil }
        memory[key] = i
        return i
    }

    /// The screenshots kept on disk so far, in the gallery's order
    func shots(_ key: String) -> [URL] {
        let _ = revision
        guard let i = info(key) else { return [] }
        return (0..<min(i.shots.count, Self.maxShots)).map { Self.shot(key, $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The trailers, each with its picture once it is on disk
    func videos(_ key: String) -> [(video: StoreVideo, thumb: URL?)] {
        let _ = revision
        guard let v = info(key)?.trailers else { return [] }
        return v.enumerated().map { i, x in
            let t = Self.videoThumb(key, i)
            return (x, FileManager.default.fileExists(atPath: t.path) ? t : nil)
        }
    }

    /// Look a game up once (again after 30 days, or a week when it was not found), then fetch its screenshots
    func load(key: String, titleID: String?, name: String) {
        guard !loading.contains(key) else { return }
        loading.insert(key)
        Task.detached(priority: .utility) {
            defer { Task { @MainActor in StoreInfoStore.shared.loading.remove(key) } }
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let file = Self.file(key), none = Self.dir.appending(path: "\(key).none")
            if let d = (try? fm.attributesOfItem(atPath: none.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) < 7 * 86400 { return }
            var info = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(StoreInfo.self, from: $0) }
            if info == nil || info!.trailers == nil || Date().timeIntervalSince(info!.fetched) > 30 * 86400 {
                var found: StoreInfo?
                if let id = titleID, let u = StoreSource.byID(id) {
                    guard let d = await CoverStore.get(u) else { return }   // offline: try again next time
                    found = StoreSource.parse(d, id: id)
                }
                if found == nil, let u = StoreSource.byName(name) {
                    guard let d = await CoverStore.get(u) else { return }
                    found = StoreSource.parse(d, name: name)
                }
                guard var f = found else { try? Data().write(to: none); return }
                if let p = f.page.flatMap(URL.init(string:)), let d = await CoverStore.get(p) {
                    let html = String(decoding: d, as: UTF8.self)
                    f.about = StoreSource.about(html)
                    f.shots = StoreSource.gallery(html)
                    var vids: [StoreVideo] = []
                    for v in StoreSource.videos(html) {
                        // Nintendo's older trailer files were on Limelight's network, which is gone: keep a file only if it answers
                        if let f = v.file.flatMap(URL.init(string:)) { if await CoverStore.reachable(f) { vids.append(v) } } else { vids.append(v) }
                    }
                    if vids.isEmpty, let u = StoreSource.youtubeSearch(f.title), let d = await CoverStore.get(u, browser: true),
                       let v = StoreSource.pickTrailer(String(decoding: d, as: UTF8.self), name: f.title, publisher: f.publisher) {
                        vids.append(v)
                    }
                    for i in vids.indices where vids[i].title == nil {
                        guard let id = vids[i].youtube, let u = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)"),
                              let d = await CoverStore.get(u) else { continue }
                        vids[i].title = StoreSource.oembedTitle(d)
                    }
                    f.trailers = vids
                } else if f.page != nil {
                    return   // offline: the page is read next time
                } else {
                    f.trailers = []
                }
                if let d = try? JSONEncoder().encode(f) { try? d.write(to: file) }
                try? fm.removeItem(at: none)
                info = f
                let done = f
                await MainActor.run { StoreInfoStore.shared.memory[key] = done; StoreInfoStore.shared.revision += 1 }
            }
            guard let info else { return }
            // the trailers' pictures (YouTube's large one, else its smaller one)
            for (i, v) in (info.trailers ?? []).enumerated() {
                let out = Self.videoThumb(key, i)
                if fm.fileExists(atPath: out.path) { continue }
                guard let t = v.thumb, let u = URL(string: t) else { continue }
                var data = await CoverStore.get(u)
                if data == nil, t.contains("/maxresdefault."), let hq = URL(string: t.replacingOccurrences(of: "/maxresdefault.", with: "/hqdefault.")) { data = await CoverStore.get(hq) }
                guard let data, let jpg = CoverSource.jpeg(data, maxHeight: 720) else { continue }
                try? jpg.write(to: out)
                await MainActor.run { StoreInfoStore.shared.revision += 1 }
            }
            // the screenshots, one after another
            for (i, s) in info.shots.prefix(Self.maxShots).enumerated() {
                let out = Self.shot(key, i)
                if fm.fileExists(atPath: out.path) { continue }
                guard let u = URL(string: s) else { continue }
                var data = await CoverStore.get(u)
                if data == nil, let small = URL(string: s.replacingOccurrences(of: ".jpg", with: "_TM_Standard.jpg")) { data = await CoverStore.get(small) }
                guard let data, let jpg = CoverSource.jpeg(data, maxHeight: 1080) else { continue }
                try? jpg.write(to: out)
                await MainActor.run { StoreInfoStore.shared.revision += 1 }
            }
        }
    }

    /// Look again for every game (Settings › Artwork › Look Again)
    func lookAgain() {
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "none" { try? FileManager.default.removeItem(at: f) }
        }
        revision += 1
    }
}

/// The game page's "From the store" section: the official screenshots in a row, the description and the store's facts
struct StoreAbout: View {
    let model: AppModel
    let game: StageGame
    var width: CGFloat = 900
    @State private var more = false

    var body: some View {
        let store = StoreInfoStore.shared
        if let info = store.info(game.coverKey) {
            let shots = store.shots(game.coverKey)
            let videos = store.videos(game.coverKey)
            let items: [GalleryItem] = videos.map { .video($0.video, thumb: $0.thumb) } + shots.map { .image($0) }
            VStack(alignment: .leading, spacing: 14) {
                if !items.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("From the store").font(.system(size: 24, weight: .heavy)).tracking(-0.4)
                        Text(count(videos.count, "trailer") + (videos.isEmpty || info.shots.isEmpty ? "" : " · ") + count(info.shots.count, "screenshot"))
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(StageLook.faint)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in tile(item) { model.openGallery(items, at: i, title: "\(game.name) · From the store") } }
                        }
                        .padding(.vertical, 14)
                    }
                    .padding(.vertical, -14)
                }
                Text("About").font(.system(size: 24, weight: .heavy)).tracking(-0.4).padding(.top, shots.isEmpty ? 0 : 14)
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let e = info.excerpt { Text(e).font(.system(size: 16.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true) }
                        let paras = info.about.filter { $0 != info.excerpt }
                        if !paras.isEmpty {
                            Text(paras.joined(separator: "\n\n")).font(.system(size: 14.5)).foregroundStyle(StageLook.soft).lineSpacing(3)
                                .lineLimit(more ? nil : 5).fixedSize(horizontal: false, vertical: true)
                            Button(more ? "Less" : "More") { withAnimation(.easeOut(duration: 0.2)) { more.toggle() } }
                                .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(CoverArt.tint(game)).brightness(0.3)
                        }
                        HStack(spacing: 6) {
                            Text("From the game's page on Nintendo's UK store").font(.system(size: 12.5)).foregroundStyle(StageLook.faint)
                            if let p = info.page.flatMap(URL.init(string:)) {
                                Button("Open") { NSWorkspace.shared.open(p) }.buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(StageLook.soft).help(p.absoluteString)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    facts(info).frame(width: min(max(width * 0.36, 300), 420), alignment: .leading)
                }
            }
            .padding(.top, 30)
        }
    }

    func facts(_ i: StoreInfo) -> some View {
        let rows: [(String, String?)] = [("Publisher", i.publisher), ("Released", i.released), ("Genre", i.genres.isEmpty ? nil : i.genres.joined(separator: ", ")),
                                         ("Players", i.players), ("Age rating", i.rating), ("Size", i.size),
                                         ("Play modes", i.modes.isEmpty ? nil : i.modes.joined(separator: ", ")), ("Languages", i.languages)]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.filter { $0.1 != nil }.enumerated()), id: \.offset) { n, r in
                if n > 0 { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.0).font(.system(size: 13.5, weight: .medium)).foregroundStyle(StageLook.faint).frame(width: 92, alignment: .leading)
                    Text(r.1 ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(r.0 == "Languages" ? 3 : 1).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(StageLook.panel.opacity(0.82), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StageLook.edge, lineWidth: 1))
    }

    func count(_ n: Int, _ what: String) -> String { n == 0 ? "" : "\(n) \(what)\(n == 1 ? "" : "s")" }

    /// A picture, or a trailer: its picture with a play mark and its title
    func tile(_ item: GalleryItem, open: @escaping () -> Void) -> some View {
        let img = item.thumb.flatMap { ThumbStore.shared.image($0) }
        let w = max((width - 28) / 3, 120)
        var video: StoreVideo? { if case .video(let v, _) = item { v } else { nil } }
        return Button(action: open) {
            Color(white: 0.12)
                .frame(width: w, height: w * 9 / 16)
                .overlay { if let img { Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill) } }
                .overlay {
                    if let v = video {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                            PlayGlyph(size: 58).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text(v.title ?? "Trailer").font(.system(size: 13.5, weight: .semibold)).lineLimit(1).padding(12)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(video.map { "Play \($0.title ?? "the trailer")" } ?? "Store screenshot")
    }
}
