// Cover art for the front end: a game's front cover, back cover and spine. In order: an image the player chose, box art
// downloaded from GameTDB (its public list of Switch titles is matched by name on this Mac, so only a GameTDB ID is ever
// asked for; a setting turns the downloads off), a download-only game's eShop box made from its square shop art (Nintendo Life,
// below), and else a cover drawn from the game's own icon. Kept in ~/Library/Application Support/NXForge Converter/covers as
// <title ID>-front.jpg, -back.jpg and -spine.jpg (an own image: -front-own.png, -back-own.png, chosen from a file or a link, a
// shop's render of a whole case cut down to its cover; the square art: -square.jpg).
// Wide key art ("hero" art) for the game page and Home: first the header art of the game's page on Nintendo Life
// (nintendolife.com/games/<platform>/<slug>, the slug made from the game's name), which also gives the square eShop art; else the
// 2:1 share image of the game's page on Nintendo's European store (nintendo.com/en-gb), found through the search service that
// store's own pages use (searching.nintendo-europe.com), by the game's title ID, else by its exact name; a game the search has no
// banner for (new Switch 2 games) gets the picture its store page shares (og:image). Only title IDs and names go out. Every wide
// picture is kept the same shape and size (HeroSource.standard: 2:1, 2560 x 1280, the shape Home fills; the game page shows a
// narrower band of it) beside the covers as <key>-hero.jpg; a setting turns it off. The pictures stay on this Mac.
import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum CoverSide: String, CaseIterable { case front, back, spine }

/// The lookup and the picture arithmetic, apart from the network and the files (tested).
enum CoverSource {
    static let list = URL(string: "https://www.gametdb.com/switchtdb.txt?LANG=EN")!
    static let art = "https://art.gametdb.com/switch"
    /// art folders tried in turn: the list has one ID for every region of most games
    static let regions = ["US", "EN", "JA"]
    /// a box is 105 mm wide and 170 mm tall; its spine about 10 mm
    static let aspect: CGFloat = 105.0 / 170.0
    static let spine: CGFloat = 10.0 / 105.0

    /// "The Legend of Zelda™: Skyward Sword HD" → "thelegendofzeldaskywardswordhd"
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "&", with: "and")
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }).lowercased()
    }

    /// A title without what follows in brackets: "Super Mario Odyssey [Starter Pack]" → "Super Mario Odyssey"
    static func plain(_ s: String) -> String {
        var out = "", depth = 0
        for c in s {
            if c == "[" || c == "(" { depth += 1 } else if c == "]" || c == ")" { depth = max(depth - 1, 0) } else if depth == 0 { out.append(c) }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The list's lines: "AAACA = Super Mario Odyssey" (the first line names the list)
    static func parse(_ text: String) -> [(id: String, title: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let r = line.range(of: " = ") else { return nil }
            let id = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard id != "TITLES", !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return (id, String(line[r.upperBound...]))
        }
    }

    /// The IDs a game's name matches, best first: the same name, then the same name once editions in brackets are dropped.
    /// "+" and "and" read alike ("Pikmin 1+2" and "Pikmin 1 + 2").
    static func match(_ name: String, in list: [(id: String, title: String)]) -> [String] {
        let want = normalize(plain(name))
        guard want.count >= 3 else { return [] }
        var exact: [String] = [], loose: [String] = []
        for e in list {
            if normalize(e.title) == want { exact.append(e.id) } else if normalize(plain(e.title)) == want { loose.append(e.id) }
        }
        return exact + loose
    }

    static func urls(id: String, kind: String) -> [URL] {
        regions.compactMap { URL(string: "\(art)/\(kind)/\($0)/\(id).jpg") }
    }

    /// A full wrap (back, spine, front, left to right) in unit widths
    static func wrap(_ side: CoverSide) -> CGRect {
        let s = spine / (2 + spine), face = (1 - s) / 2
        switch side {
        case .back: return CGRect(x: 0, y: 0, width: face, height: 1)
        case .spine: return CGRect(x: face, y: 0, width: s, height: 1)
        case .front: return CGRect(x: face + s, y: 0, width: face, height: 1)
        }
    }

    /// A picture as a JPEG no taller than `maxHeight`, or the part of it `unit` names
    /// Whether a downloaded front is a box's shape. Download-only games have a wide shop banner there, which is no cover.
    static func boxShaped(_ data: Data) -> Bool {
        guard case let (w, h)? = size(data) else { return false }
        return (0.5...0.75).contains(w / h)
    }

    /// A picture's width and height in pixels, read from its header
    static func size(_ data: Data) -> (Double, Double)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Double, let h = p[kCGImagePropertyPixelHeight] as? Double, w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// Whether a downloaded front is GameTDB's stand-in for a download-only game: the console's red all round a small shop banner
    /// and a shop sign (no printed box). The game's square shop art makes a better box (CoverArt.eshopBox).
    static func eshopStandIn(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        return eshopStandIn(cg)
    }

    static func eshopStandIn(_ image: CGImage) -> Bool {
        let w = 60, h = 97
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let raw = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // points down both sides and along the bottom (the top row first in memory)
        let points: [(Double, Double)] = [(0.04, 0.5), (0.96, 0.5), (0.5, 0.93), (0.04, 0.2), (0.96, 0.8), (0.1, 0.97), (0.9, 0.97)]
        let red = points.filter { p in
            let i = (min(Int(p.1 * Double(h)), h - 1) * w + min(Int(p.0 * Double(w)), w - 1)) * 4
            return px[i] > 190 && px[i + 1] < 60 && px[i + 2] < 70
        }
        return red.count >= 6
    }

    /// A shop's picture of a whole case (a product render: the cover inside the case's plastic, on a see-through background)
    /// cut down to the printed cover: the see-through margin and the plastic's rim go, so the cover is not shown inside a
    /// second case. Only a picture whose corners are see-through is taken for a render; any other comes back as it was.
    /// A rim is a band of light grey along an edge, as wide on most lines sampled and no wider than 6% of the picture.
    static func trimCase(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard w > 20, h > 20, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // a bitmap context's memory holds the top row first
        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * w + x) * 4
            return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), Int(px[i + 3]))
        }
        guard at(0, 0).a < 128, at(w - 1, 0).a < 128, at(0, h - 1).a < 128, at(w - 1, h - 1).a < 128 else { return image }
        // the opaque part
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where at(x, y).a >= 200 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX > minX + 10, maxY > minY + 10 else { return image }
        func rim(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
            p.a < 250 || (min(p.r, p.g, p.b) > 160 && max(p.r, p.g, p.b) - min(p.r, p.g, p.b) < 16)
        }
        // how far in the rim runs from one edge, measured on seven lines across the middle of that edge; 0 when they disagree
        func band(_ length: Int, _ limit: Int, _ pixel: (Int, Int) -> (r: Int, g: Int, b: Int, a: Int)) -> Int {
            let widths = (1...7).map { k -> Int in
                let along = length * (k + 1) / 9
                var d = 0
                while d < limit, rim(pixel(along, d)) { d += 1 }
                return d
            }
            // the middle width, when five of the seven lines agree with it (a white logo at the edge can run one line further)
            let mid = widths.sorted()[3], near = max(3, mid / 8)
            guard mid < limit, widths.filter({ abs($0 - mid) <= near }).count >= 5 else { return 0 }
            return widths.filter { abs($0 - mid) <= near }.max() ?? mid
        }
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        let left = band(ch, cw * 6 / 100) { a, d in at(minX + d, minY + a) }
        let right = band(ch, cw * 6 / 100) { a, d in at(maxX - d, minY + a) }
        let top = band(cw, ch * 6 / 100) { a, d in at(minX + a, minY + d) }
        let bottom = band(cw, ch * 6 / 100) { a, d in at(minX + a, maxY - d) }
        let crop = CGRect(x: minX + left, y: minY + top, width: cw - left - right, height: ch - top - bottom)
        return image.cropping(to: crop) ?? image
    }

    static func jpeg(_ data: Data, unit: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), maxHeight: Int = 1400) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let crop = CGRect(x: (unit.minX * w).rounded(), y: (unit.minY * h).rounded(), width: (unit.width * w).rounded(), height: (unit.height * h).rounded())
        guard let part = full.cropping(to: crop), part.width > 0, part.height > 0 else { return nil }
        let scale = min(1, CGFloat(maxHeight) / CGFloat(part.height))
        let ow = max(Int(CGFloat(part.width) * scale), 1), oh = max(Int(CGFloat(part.height) * scale), 1)
        guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: ow, height: oh))
        guard let out = ctx.makeImage() else { return nil }
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buf, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? buf as Data : nil
    }
}

/// The lookup of a game's wide art on Nintendo's European store, apart from the network (tested)
enum HeroSource {
    static let search = "https://searching.nintendo-europe.com/en/select"
    /// title IDs asked for in one search
    static let batch = 40

    /// One search for many games by title ID ("0100C2700C252000" is kept as "0100c2700c252000" there)
    static func byIDs(_ ids: [String]) -> URL? {
        let q = ids.map { $0.lowercased() }.filter { $0.count == 16 && $0.allSatisfy(\.isHexDigit) }
        guard !q.isEmpty else { return nil }
        return url(["q": "*", "fq": "application_id_s:(\(q.joined(separator: " OR ")))", "rows": "\(q.count * 6)"])
    }

    /// A search for one game by name
    static func byName(_ name: String) -> URL? {
        // words only, so nothing in a name reads as search syntax
        let n = String(CoverSource.plain(name).map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").joined(separator: " ")
        guard CoverSource.normalize(n).count >= 3 else { return nil }
        return url(["q": n, "fq": "type:GAME", "rows": "8"])
    }

    static func url(_ params: [String: String], fields: String = "application_id_s,title,type,image_url_h2x1_s,url") -> URL? {
        var c = URLComponents(string: search)
        c?.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "fl", value: fields), URLQueryItem(name: "wt", value: "json")]
        return c?.url
    }

    /// An entry of the search: its banner, else its store page (whose shared picture is read instead)
    struct Doc: Equatable { var id: String?; var title: String; var game: Bool; var image: String?; var page: URL? }

    static let site = "https://www.nintendo.com"

    /// The search's answer: the entries that have wide art or a store page
    static func parse(_ data: Data) -> [Doc] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = o["response"] as? [String: Any],
              let docs = r["docs"] as? [[String: Any]] else { return [] }
        return docs.compactMap { d in
            guard let t = d["title"] as? String else { return nil }
            let img = (d["image_url_h2x1_s"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil }
            let page = (d["url"] as? String).flatMap { $0.hasPrefix("/") && !$0.hasPrefix("//") ? URL(string: site + $0) : nil }
            guard img != nil || page != nil else { return nil }
            return Doc(id: (d["application_id_s"] as? String)?.uppercased(), title: t, game: (d["type"] as? String) == "GAME", image: img, page: page)
        }
    }

    /// The art for a title ID: an entry with a banner first, a game's before an add-on's (they share the ID), the shortest title
    /// first ("Mina the Hollower" before "Mina the Hollower - Nintendo Switch 2 Edition"); an add-on's page is never read
    static func pick(_ docs: [Doc], id: String) -> Doc? {
        docs.filter { $0.id == id.uppercased() && ($0.image != nil || $0.game) }
            .min { ($0.image == nil ? 1 : 0, $0.game ? 0 : 1, $0.title.count) < ($1.image == nil ? 1 : 0, $1.game ? 0 : 1, $1.title.count) }
    }

    /// The picture a store page shares: <meta property="og:image" content="...">, on nintendo.com only
    static func shared(_ html: String) -> String? {
        guard let r = html.range(of: #"<meta[^>]*property="og:image"[^>]*>"#, options: .regularExpression) else { return nil }
        let tag = html[r]
        guard let c = tag.range(of: #"content="[^"]*""#, options: .regularExpression) else { return nil }
        let v = tag[c].dropFirst(9).dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return v.hasPrefix(site + "/") ? v : nil
    }

    /// The art for a name: only a Switch game whose title is the same name
    static func pick(_ docs: [Doc], name: String) -> Doc? {
        let want = CoverSource.normalize(CoverSource.plain(name))
        return docs.first { $0.game && $0.id != nil && (CoverSource.normalize($0.title) == want || CoverSource.normalize(CoverSource.plain($0.title)) == want) }
    }

    /// The search names a 500 px wide copy and a page a 1280 px one; the same picture is there 1600 px wide
    static func sizes(_ image: String) -> [URL] {
        let big = image.replacingOccurrences(of: "_image500w.", with: "_image1600w.").replacingOccurrences(of: "_image1280w.", with: "_image1600w.")
        return (big == image ? [image] : [big, image]).compactMap(URL.init(string:))
    }

    /// Whether a picture is wide art (about 2:1), not a square or a box
    static func wide(_ data: Data) -> Bool {
        guard case let (w, h)? = CoverSource.size(data) else { return false }
        return (1.6...2.4).contains(w / h)
    }

    /// The one shape and size every wide picture is kept at: 2:1 (Home fills the top of the window with it, about that shape on a
    /// Mac's screen; the game page's banner is a narrower band of the same picture), 2560 × 1280 so a full-screen window on a
    /// Retina display barely enlarges it. A wider picture loses its sides (cut about the middle, as Home would show it), a taller
    /// one its top and bottom.
    static let standardSize = CGSize(width: 2560, height: 1280)

    static func standard(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
              full.width > 0, full.height > 0 else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height), want = standardSize.width / standardSize.height
        let crop = w / h > want ? CGRect(x: ((w - h * want) / 2).rounded(), y: 0, width: (h * want).rounded(), height: h)
                                : CGRect(x: 0, y: ((h - w / want) / 2).rounded(), width: w, height: (w / want).rounded())
        guard let part = full.cropping(to: crop) else { return nil }
        let ow = Int(standardSize.width), oh = Int(standardSize.height)
        // Lanczos rather than CoreGraphics' own scaling: most art is enlarged here, and that keeps its edges cleaner
        let ci = CIImage(cgImage: part)
        let scaled = ci.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: CGFloat(oh) / CGFloat(part.height),
                                                                               kCIInputAspectRatioKey: (CGFloat(ow) / CGFloat(part.width)) / (CGFloat(oh) / CGFloat(part.height))])
        let out = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: CGRect(x: 0, y: 0, width: ow, height: oh))
            ?? part
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buf, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? buf as Data : nil
    }
}

/// A game's page on Nintendo Life, apart from the network (tested): its header art (the wide art) and its cover (the square eShop
/// art of a download-only game, the box of a boxed one). The page's address is made from the game's name, as the site makes it
/// ("Kirby's Return to Dream Land Deluxe" → kirbys_return_to_dream_land_deluxe), under the site's console sections in turn.
enum NLifeSource {
    static let site = "https://www.nintendolife.com"
    /// a wide picture this low (in pixels) is soft once enlarged: the store's is taken instead when it has one
    static let lowHeight = 500.0
    /// pages asked for at most for one game (a second each); one not found is looked for again after a week
    static let maxTries = 16

    /// The page names the site may use for a game, likeliest first: words joined by "_" ("Mario & Luigi - Brothership" →
    /// mario_and_luigi_brothership), then with its hyphens kept (pac-man_championship_edition_2_plus, shadow_of_the_ninja_-_reborn),
    /// "+" said as "plus" apart or joined to its word (pac-man_museumplus), without a leading "The" (legend_of_zelda_…) or a
    /// closing "… Edition" (alpaca_ball_allstars)
    static func slugs(_ name: String) -> [String] {
        let n = CoverSource.plain(name).folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
            .lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: ".", with: "")
        var names = [n]
        let words = n.split(separator: " ")
        if words.first == "the", words.count > 2 { names.append(words.dropFirst().joined(separator: " ")) }
        if words.last == "edition", words.count > 3 { names += names.map { $0.split(separator: " ").dropLast(2).joined(separator: " ") } }
        var out: [String] = []
        for t in names {
            for hyphens in [false, true] {
                for glue in n.contains("+") ? [false, true] : [false] {
                    var u = glue ? t.replacingOccurrences(of: #"([a-z0-9])\+"#, with: "$1plus", options: .regularExpression) : t
                    u = u.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "+", with: " plus ")
                    let kept = u.unicodeScalars.map { c -> Character in
                        if c.isASCII, CharacterSet.alphanumerics.contains(c) { return Character(c) }
                        return hyphens && c == "-" ? "-" : " "
                    }
                    let s = String(kept).split(separator: " ").joined(separator: "_")
                    if s.count >= 2, !out.contains(s) { out.append(s) }
                }
            }
        }
        return out
    }

    /// The pages to try, likeliest first: Switch 2 games (title IDs from 04) under its section first; every game under the
    /// boxed games' section, then the download games'
    static func pages(name: String, titleID: String?) -> [URL] {
        var sections = ["nintendo-switch", "switch-eshop"]
        if titleID?.hasPrefix("04") == true { sections.insert("nintendo-switch-2", at: 0) }
        return Array(slugs(name).flatMap { s in sections.compactMap { URL(string: "\(site)/games/\($0)/\(s)") } }.prefix(maxTries))
    }

    struct Page: Equatable { var hero: URL?; var cover: URL? }

    /// The header art (`<div class="… background-desktop" data-bg-image="…artwork.1920x350.jpg">`) and the cover
    /// (`<p id="cover" …><img src="…cover.cover_300x.jpg">`), both asked for at their original size
    static func parse(_ html: String) -> Page {
        func attr(_ pattern: String, _ name: String) -> String? {
            guard let r = html.range(of: pattern, options: .regularExpression), let a = html[r].range(of: name + #"="[^"]*""#, options: .regularExpression) else { return nil }
            let v = html[r][a].dropFirst(name.count + 2).dropLast()
            return v.hasPrefix("https://images.nintendolife.com/") ? String(v) : nil
        }
        let hero = attr(#"<div[^>]*background-desktop[^>]*>"#, "data-bg-image")
        let cover = attr(#"<p id="cover"[^>]*>\s*<img[^>]*>"#, "src")
        return Page(hero: hero.flatMap { URL(string: original($0)) }, cover: cover.flatMap { URL(string: original($0)) })
    }

    /// "…/cuphead-artwork.1920x350.jpg" → "…/cuphead-artwork.original.jpg"; the same for "….cover_300x.jpg"
    static func original(_ u: String) -> String {
        u.replacingOccurrences(of: #"\.[a-z_]*[0-9]+x[0-9]*\.(jpg|jpeg|png)$"#, with: ".original.$1", options: .regularExpression)
    }

    /// Whether a cover is square art (a download game's) rather than a box
    static func square(_ data: Data) -> Bool {
        guard case let (w, h)? = CoverSource.size(data) else { return false }
        return (0.9...1.1).contains(w / h)
    }
}

@MainActor @Observable
final class CoverStore {
    static let shared = CoverStore()
    /// bumped when a cover arrives or changes, so views draw again
    var revision = 0
    @ObservationIgnored private var memory: [String: NSImage] = [:]
    @ObservationIgnored private var absent = Set<String>()
    @ObservationIgnored private var tints: [String: NSColor] = [:]
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var asked = Set<String>()
    @ObservationIgnored private var heroFetch: Task<Void, Never>?
    @ObservationIgnored private var nlFetch: Task<Void, Never>?
    @ObservationIgnored private var nlAsked = Set<String>()
    /// the Nintendo Life pass under way (tests wait on it)
    var nintendoLifeTask: Task<Void, Never>? { nlFetch }
    @ObservationIgnored private var heroAsked = Set<String>()
    /// the wide art is shown (Settings › Artwork)
    var showHeroes = true
    @ObservationIgnored private var reading = Set<String>()
    @ObservationIgnored private var bump = false
    @ObservationIgnored private var tintsRead = false
    @ObservationIgnored private var coverTints = Set<String>()   // the colours read from a cover: only those are kept between starts (an icon's changes with a rebuild)
    @ObservationIgnored private var tintsWrite: Task<Void, Never>?

    /// Drop the pictures held in memory (they are read from disk again when next drawn); what is known about them stays
    func letGo() { memory = [:] }

    nonisolated static var dir: URL { Settings.supportDir.appending(path: "covers") }

    nonisolated static func key(titleID: String?, name: String) -> String {
        titleID ?? CoverSource.normalize(name)
    }

    /// The cover on disk for a side: the player's own first, then the downloaded one
    func image(_ key: String, _ side: CoverSide) -> NSImage? {
        let _ = revision
        let k = key + "-" + side.rawValue
        if let i = memory[k] { return i }
        if absent.contains(k) { return nil }
        for name in [k + "-own.png", k + ".jpg"] {
            if let i = NSImage(contentsOf: Self.dir.appending(path: name)), i.isValid, i.size.width > 0 {
                memory[k] = i
                return i
            }
        }
        absent.insert(k)
        return nil
    }

    /// The game's wide art, when it was downloaded and the setting is on
    func hero(_ key: String) -> NSImage? {
        guard showHeroes else { return nil }
        let _ = revision
        let k = key + "-hero"
        if let i = memory[k] { return i }
        if absent.contains(k) { return nil }
        if let i = NSImage(contentsOf: Self.dir.appending(path: k + ".jpg")), i.isValid, i.size.width > 0 {
            memory[k] = i
            return i
        }
        absent.insert(k)
        return nil
    }

    /// The longest side, in pixels, of a tile's cover: the grid's largest cover (Settings.coverSizes, 280 points wide) on a Retina screen
    nonisolated static let tileSide = 920

    /// A side's cover for a tile on the shelf or in the grid: a smaller copy, read and decoded off the main thread so a scroll past
    /// covers not seen yet never waits for a JPEG. `.none`: no cover on disk (a drawn stand-in takes its place);
    /// `.some(nil)`: there is one and it is being read, and `revision` moves when it arrives
    func thumb(_ key: String, _ side: CoverSide) -> NSImage?? {
        let _ = revision
        let k = key + "-" + side.rawValue, tk = k + "-thumb"
        if let i = memory[tk] { return .some(i) }
        if absent.contains(k) { return .none }
        if reading.contains(tk) { return .some(nil) }
        guard let file = Self.file(k) else { absent.insert(k); return .none }
        reading.insert(tk)
        Task.detached(priority: .userInitiated) {
            let cg = Self.small(file, side: Self.tileSide)
            await MainActor.run { CoverStore.shared.arrived(tk, k, cg) }
        }
        return .some(nil)
    }

    /// The cover on disk under a side's name: the player's own first, then the downloaded one
    nonisolated static func file(_ k: String) -> URL? {
        [k + "-own.png", k + ".jpg"].map { dir.appending(path: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A picture file no longer than `side` pixels, decoded here and now (ImageIO reads a JPEG at a reduced size without decoding all of it)
    nonisolated static func small(_ file: URL, side: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: side, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private func arrived(_ tk: String, _ k: String, _ cg: CGImage?) {
        guard reading.remove(tk) != nil else { return }   // forgotten meanwhile (a new cover came): the next draw reads it again
        if let cg, cg.width > 0 { memory[tk] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) } else { absent.insert(k) }
        // several covers arriving in one burst (a first scroll) redraw the tiles once
        if !bump { bump = true; Task { @MainActor in try? await Task.sleep(for: .milliseconds(15)); self.bump = false; self.revision += 1 } }
    }

    /// A drawn stand-in (a front made from the icon, a back with the game's details), kept so it is drawn once
    func drawn(_ key: String, _ make: () -> NSImage?) -> NSImage? {
        let k = "drawn-" + key
        if let i = memory[k] { return i }
        guard let i = make() else { return nil }
        memory[k] = i
        return i
    }

    func forget(_ key: String) {
        for k in memory.keys where k.hasPrefix(key + "-") || k.hasPrefix("drawn-" + key) { memory[k] = nil }
        absent = absent.filter { !$0.hasPrefix(key + "-") }
        reading = reading.filter { !$0.hasPrefix(key + "-") }
        readTints(); tints[key] = nil; coverTints.remove(key); writeTints()
        revision += 1
    }

    /// The colour a game lights the stage with: its cover's, else its icon's, made vivid enough to show on black
    func tint(_ key: String, icon: String?) -> Color {
        readTints()
        if let c = tints[key] { return Color(nsColor: c) }
        var base: NSColor?
        // from a copy a few dozen pixels high (about 3 ms), once: the colour is kept between starts
        if !absent.contains(key + "-front"), let f = Self.file(key + "-front"), let cg = Self.small(f, side: 64) { base = Self.average(cg); if base != nil { coverTints.insert(key) } }
        if base == nil, let icon, let img = NSImage(contentsOfFile: icon) ?? (icon.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: icon) : nil) { base = Self.average(img) }
        let c = Self.vivid(base ?? NSColor(srgbRed: 0.25, green: 0.35, blue: 0.75, alpha: 1))
        tints[key] = c
        if coverTints.contains(key) { writeTints() }
        return Color(nsColor: c)
    }

    /// The colours are kept between starts (tints.json beside the covers): reading one from a cover costs about 3 ms, the whole
    /// file a fraction of that. `forget` drops a game's when its cover changes.
    nonisolated static var tintsFile: URL { dir.appending(path: "tints.json") }

    private func readTints() {
        guard !tintsRead else { return }
        tintsRead = true
        guard let d = try? Data(contentsOf: Self.tintsFile), let kept = try? JSONDecoder().decode([String: [Double]].self, from: d) else { return }
        for (k, v) in kept where v.count == 3 && tints[k] == nil { tints[k] = NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: 1); coverTints.insert(k) }
    }

    private func writeTints() {
        tintsWrite?.cancel()
        tintsWrite = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            var out: [String: [Double]] = [:]
            for (k, c) in self.tints where self.coverTints.contains(k) { if let s = c.usingColorSpace(.sRGB) { out[k] = [Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent)] } }
            guard let d = try? JSONEncoder().encode(out) else { return }
            try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            try? d.write(to: Self.tintsFile, options: .atomic)
        }
    }

    static func average(_ img: NSImage) -> NSColor? {
        img.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { average($0) }
    }

    nonisolated static func average(_ cg: CGImage) -> NSColor? {
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    /// An average colour is often a muddy grey: keep its hue, lift its saturation and hold its brightness in a middle band
    static func vivid(_ c: NSColor) -> NSColor {
        guard let rgb = c.usingColorSpace(.sRGB) else { return c }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(max(s * 1.6, 0.45), 0.9), brightness: min(max(b, 0.55), 0.85), alpha: 1)
    }

    // MARK: the player's own image

    /// Keep a chosen picture as a game's front or back cover (a PNG copy, so the original can move). A shop's render of
    /// a whole case is cut down to its printed cover (CoverSource.trimCase).
    func setOwn(_ key: String, _ side: CoverSide, from file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        return setOwn(key, side, data: data)
    }

    func setOwn(_ key: String, _ side: CoverSide, data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary) else { return false }
        let rep = NSBitmapImageRep(cgImage: CoverSource.trimCase(full))
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        do { try png.write(to: Self.dir.appending(path: "\(key)-\(side.rawValue)-own.png")) } catch { return false }
        forget(key)
        return true
    }

    func hasOwn(_ key: String) -> Bool {
        [CoverSide.front, .back].contains { FileManager.default.fileExists(atPath: Self.dir.appending(path: "\(key)-\($0.rawValue)-own.png").path) }
    }

    func removeOwn(_ key: String) {
        for s in [CoverSide.front, .back] { try? FileManager.default.removeItem(at: Self.dir.appending(path: "\(key)-\(s.rawValue)-own.png")) }
        forget(key)
    }

    // MARK: downloads

    /// Fetch the box art of the games that have none yet, one after another. A game the list does not have is tried again
    /// after a week (its <key>.none file says when it was last looked for).
    func fetchMissing(_ games: [(key: String, name: String)]) {
        let todo = games.filter { !asked.contains($0.key) }
        guard !todo.isEmpty else { return }
        for g in todo { asked.insert(g.key) }
        let previous = fetch, nl = nlFetch
        fetch = Task.detached(priority: .utility) {
            await previous?.value
            await nl?.value   // a game's eShop box (from Nintendo Life) is made before GameTDB's stand-in is taken
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            var list: [(id: String, title: String)]?
            for g in todo {
                if Task.isCancelled { return }
                let front = Self.dir.appending(path: "\(g.key)-front.jpg"), none = Self.dir.appending(path: "\(g.key).none")
                if fm.fileExists(atPath: front.path) { continue }
                if let d = (try? fm.attributesOfItem(atPath: none.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) < 7 * 86400 { continue }
                if list == nil { list = await Self.titles() }
                guard let list else { return }   // offline: try again at the next start
                var got = false
                for id in CoverSource.match(g.name, in: list).prefix(4) {
                    guard let data = await Self.first(CoverSource.urls(id: id, kind: "coverHQ") + CoverSource.urls(id: id, kind: "cover")),
                          CoverSource.boxShaped(data), let jpg = CoverSource.jpeg(data) else { continue }
                    try? jpg.write(to: front)
                    if let wrap = await Self.first(CoverSource.urls(id: id, kind: "coverfullHQ") + CoverSource.urls(id: id, kind: "coverfull")) {
                        if let b = CoverSource.jpeg(wrap, unit: CoverSource.wrap(.back)) { try? b.write(to: Self.dir.appending(path: "\(g.key)-back.jpg")) }
                        if let s = CoverSource.jpeg(wrap, unit: CoverSource.wrap(.spine)) { try? s.write(to: Self.dir.appending(path: "\(g.key)-spine.jpg")) }
                    }
                    got = true
                    break
                }
                if got {
                    try? fm.removeItem(at: none)
                    let key = g.key
                    await MainActor.run { CoverStore.shared.forget(key) }
                } else {
                    try? Data().write(to: none)
                }
            }
        }
    }

    /// Look again for every game's art (Settings › Covers)
    func lookAgain() {
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil) {
            for f in files where ["none", "heronone", "nlife", "nlifenone"].contains(f.pathExtension) { try? FileManager.default.removeItem(at: f) }
        }
        asked = []
        heroAsked = []
        nlAsked = []
        revision += 1
    }

    /// What a game's Nintendo Life pass took, kept in <key>.nlife so it is done once (Settings › Artwork › Look again does it over):
    /// "hero" and "box" for the parts asked for. A game whose page is not found is looked for again after a week (<key>.nlifenone).
    nonisolated static let nlifeVersion = "1"

    /// Nintendo Life first, for every game not done yet: its page (found by name, NLifeSource.pages, a second between requests),
    /// then its header art as the game's wide art (replacing the store's; a header too small to enlarge well keeps a store picture
    /// already there) and its cover: square shop art becomes the game's eShop box when it has no printed box (none yet, or
    /// GameTDB's red stand-in, kept as -front-eshop.jpg), a box is the front when it has none. Offline, nothing is marked.
    func fetchNintendoLife(_ games: [(key: String, titleID: String?, name: String, console: String)], heroes: Bool, boxes: Bool) {
        guard heroes || boxes else { return }
        let parts = (heroes ? ["hero"] : []) + (boxes ? ["box"] : [])
        let todo = games.filter { !nlAsked.contains($0.key) }
        guard !todo.isEmpty else { return }
        for g in todo { nlAsked.insert(g.key) }
        let previous = nlFetch
        nlFetch = Task.detached(priority: .utility) {
            await previous?.value
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            for g in todo {
                if Task.isCancelled { return }
                let mark = Self.dir.appending(path: "\(g.key).nlife"), none = Self.dir.appending(path: "\(g.key).nlifenone")
                let done = (try? String(contentsOf: mark, encoding: .utf8))?.split(whereSeparator: \.isNewline).map(String.init) ?? []
                if done.first == Self.nlifeVersion, parts.allSatisfy(done.contains) { continue }
                if let d = (try? fm.attributesOfItem(atPath: none.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) < 7 * 86400 { continue }
                var page: NLifeSource.Page?
                for u in NLifeSource.pages(name: g.name, titleID: g.titleID) {
                    try? await Task.sleep(for: .seconds(1))
                    guard case let (data, code)? = await Self.fetch(u) else { return }   // offline: try again at the next start
                    if code == 200 { page = NLifeSource.parse(String(decoding: data, as: UTF8.self)); break }
                }
                guard let page else { try? Data().write(to: none); continue }
                try? fm.removeItem(at: none)
                var changed = false
                if heroes {
                    let file = Self.dir.appending(path: "\(g.key)-hero.jpg")
                    if let u = page.hero {
                        try? await Task.sleep(for: .seconds(1))
                        if let d = await Self.get(u), let h = CoverSource.size(d)?.1, h >= NLifeSource.lowHeight || !fm.fileExists(atPath: file.path),
                           let jpg = HeroSource.standard(d), (try? jpg.write(to: file)) != nil {
                            changed = true
                            try? fm.removeItem(at: Self.dir.appending(path: "\(g.key).heronone"))
                        }
                    }
                    // a store picture kept (Nintendo Life's too small, or none) goes to the standard size too
                    if !changed, let old = try? Data(contentsOf: file), CoverSource.size(old).map({ $0.0 != HeroSource.standardSize.width }) ?? false,
                       let std = HeroSource.standard(old), (try? std.write(to: file)) != nil { changed = true }
                }
                if boxes, let u = page.cover {
                    try? await Task.sleep(for: .seconds(1))
                    if let d = await Self.get(u) {
                        let front = Self.dir.appending(path: "\(g.key)-front.jpg"), made = Self.dir.appending(path: "\(g.key).eshopbox")
                        if NLifeSource.square(d), let sq = CoverSource.jpeg(d, maxHeight: 1000) {
                            try? sq.write(to: Self.dir.appending(path: "\(g.key)-square.jpg"))
                            let old = try? Data(contentsOf: front)
                            let standIn = old.map(CoverSource.eshopStandIn) ?? false
                            if old == nil || standIn || fm.fileExists(atPath: made.path),
                               let box = await MainActor.run(body: { CoverArt.eshopBox(name: g.name, console: g.console, square: sq) }) {
                                if standIn, let old { try? old.write(to: Self.dir.appending(path: "\(g.key)-front-eshop.jpg")) }
                                if (try? box.write(to: front)) != nil { try? Data().write(to: made); changed = true }
                            }
                        } else if CoverSource.boxShaped(d), !fm.fileExists(atPath: front.path), let jpg = CoverSource.jpeg(d) {
                            changed = (try? jpg.write(to: front)) != nil || changed
                        }
                    }
                }
                let had = done.first == Self.nlifeVersion ? Array(done.dropFirst()) : []
                try? ([Self.nlifeVersion] + Set(had + parts).sorted()).joined(separator: "\n").write(to: mark, atomically: true, encoding: .utf8)
                if changed {
                    let key = g.key
                    await MainActor.run { CoverStore.shared.forget(key) }
                }
            }
        }
    }

    /// Fetch the wide art of the games that have none yet: one search for all their title IDs, then one by name for each game
    /// the IDs did not find, then the pictures one after another. A game with no art is looked for again after a week
    /// (<key>.heronone). Offline, nothing is marked, so the next start tries again.
    func fetchHeroes(_ games: [(key: String, titleID: String?, name: String)]) {
        let todo = games.filter { !heroAsked.contains($0.key) }
        guard !todo.isEmpty else { return }
        for g in todo { heroAsked.insert(g.key) }
        let previous = heroFetch, nl = nlFetch
        heroFetch = Task.detached(priority: .utility) {
            await previous?.value
            await nl?.value   // Nintendo Life's art first; the store's only for a game still without any
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let want = todo.filter { g in
                if fm.fileExists(atPath: Self.dir.appending(path: "\(g.key)-hero.jpg").path) { return false }
                let none = Self.dir.appending(path: "\(g.key).heronone")
                if let d = (try? fm.attributesOfItem(atPath: none.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) < 7 * 86400 { return false }
                return true
            }
            guard !want.isEmpty else { return }
            var found: [String: HeroSource.Doc] = [:]
            let ids = want.compactMap(\.titleID)
            for start in stride(from: 0, to: ids.count, by: HeroSource.batch) {
                let part = Array(ids[start..<min(start + HeroSource.batch, ids.count)])
                guard let u = HeroSource.byIDs(part) else { continue }
                guard let data = await Self.get(u) else { return }   // offline or refused: try again at the next start
                let docs = HeroSource.parse(data)
                for id in part { if let d = HeroSource.pick(docs, id: id) { found[id.uppercased()] = d } }
            }
            for g in want {
                if Task.isCancelled { return }
                var doc = g.titleID.flatMap { found[$0.uppercased()] }
                if doc == nil, let u = HeroSource.byName(g.name) {
                    guard let data = await Self.get(u) else { return }
                    doc = HeroSource.pick(HeroSource.parse(data), name: g.name)
                }
                let file = Self.dir.appending(path: "\(g.key)-hero.jpg"), none = Self.dir.appending(path: "\(g.key).heronone")
                var got = false
                var image = doc?.image
                if image == nil, let page = doc?.page, let d = await Self.get(page) {
                    image = HeroSource.shared(String(decoding: d, as: UTF8.self))
                }
                if let image {
                    for u in HeroSource.sizes(image) {
                        guard let d = await Self.get(u), HeroSource.wide(d), let jpg = HeroSource.standard(d) else { continue }
                        got = (try? jpg.write(to: file)) != nil
                        if got { break }
                    }
                }
                if got {
                    try? fm.removeItem(at: none)
                    let key = g.key
                    await MainActor.run { CoverStore.shared.forget(key) }
                } else {
                    try? Data().write(to: none)
                }
            }
        }
    }

    /// GameTDB's list of Switch titles, kept for a week
    nonisolated private static func titles() async -> [(id: String, title: String)]? {
        let file = dir.appending(path: "switchtdb.txt")
        let age = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) }
        if let age, age < 7 * 86400, let t = try? String(contentsOf: file, encoding: .utf8) { return CoverSource.parse(t) }
        if let d = await get(CoverSource.list), let t = String(data: d, encoding: .utf8), t.contains(" = ") {
            try? d.write(to: file)
            return CoverSource.parse(t)
        }
        return (try? String(contentsOf: file, encoding: .utf8)).map(CoverSource.parse)
    }

    nonisolated private static func first(_ urls: [URL]) async -> Data? {
        for u in urls { if let d = await get(u), d.count > 2000 { return d } }
        return nil
    }

    /// Whether a file answers (a HEAD request, 8 seconds at most)
    nonisolated static func reachable(_ url: URL) async -> Bool {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "HEAD"
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<400).contains(code)
    }

    /// A page and its status (a missing page answers 404, which is no reason to stop); nil when nothing answered
    nonisolated static func fetch(_ url: URL) async -> (Data, Int)? {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = false
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        return (data, code)
    }

    nonisolated static func get(_ url: URL, browser: Bool = false) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 30)
        // a page that answers a bare client with less (YouTube's search) is asked as Safari asks
        req.setValue(browser ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" : "Mozilla/5.0",
                     forHTTPHeaderField: "User-Agent")
        if browser { req.setValue("en-GB,en;q=0.8", forHTTPHeaderField: "Accept-Language") }
        req.httpShouldHandleCookies = false
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
