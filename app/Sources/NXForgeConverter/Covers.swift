// Cover art for the front end: a game's front cover, back cover and spine. In order: an image the player chose, box art
// downloaded from GameTDB (its public list of Switch titles is matched by name on this Mac, so only a GameTDB ID is ever
// asked for; a setting turns the downloads off), and else a cover drawn from the game's own icon. Kept in
// ~/Library/Application Support/NXForge Converter/covers as <title ID>-front.jpg, -back.jpg and -spine.jpg
// (an own image: -front-own.png, -back-own.png).
import AppKit
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
        tints[key] = nil
        revision += 1
    }

    /// The colour a game lights the stage with: its cover's, else its icon's, made vivid enough to show on black
    func tint(_ key: String, icon: String?) -> Color {
        if let c = tints[key] { return Color(nsColor: c) }
        var base: NSColor?
        if let img = image(key, .front) { base = Self.average(img) }
        if base == nil, let icon, let img = NSImage(contentsOfFile: icon) ?? (icon.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: icon) : nil) { base = Self.average(img) }
        let c = Self.vivid(base ?? NSColor(srgbRed: 0.25, green: 0.35, blue: 0.75, alpha: 1))
        tints[key] = c
        return Color(nsColor: c)
    }

    static func average(_ img: NSImage) -> NSColor? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
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

    /// Keep a chosen picture as a game's front or back cover (a PNG copy, so the original can move)
    func setOwn(_ key: String, _ side: CoverSide, from file: URL) -> Bool {
        guard let img = NSImage(contentsOf: file), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
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
        let previous = fetch
        fetch = Task.detached(priority: .utility) {
            await previous?.value
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
                          let jpg = CoverSource.jpeg(data) else { continue }
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
            for f in files where f.pathExtension == "none" { try? FileManager.default.removeItem(at: f) }
        }
        asked = []
        revision += 1
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

    nonisolated private static func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
