// A game's own name, publisher, version and icon, read from its Control NCA with prod.keys: the Library page shows them in
// place of names cleaned up from file names. Only the Control NCA is read (a few hundred KB: its header, then its RomFS with
// control.nacp and the icons), so it stays cheap on a network share. NSZ / XCZ files are read too when their Control NCA is
// stored uncompressed (.nca inside), as nsz leaves small ones.
import Foundation

struct GameControl: Codable, Hashable {
    var name: String
    var publisher: String
    /// the display version ("1.3.0") of the file it was read from
    var version: String
    /// the icon's JPEG bytes (not stored: the Library keeps it as a file)
    var icon: Data?

    enum CodingKeys: String, CodingKey { case name, publisher, version }
}

enum ControlReader {
    /// The newest version's control data among a game's files: the update's (its name and version are the current ones), else the base game's.
    static func read(files: [URL], keys: Keys) -> GameControl? {
        guard let headerKey = keys.key("header_key", size: 32) else { return nil }
        // updates first (newest version first), then base games
        let order = files.sorted { rank($0) > rank($1) }
        for f in order {
            if let c = try? read(file: f, keys: keys, headerKey: headerKey) { return c }
        }
        return nil
    }

    private static func rank(_ u: URL) -> UInt64 {
        let n = u.lastPathComponent
        let isUpdate = GameLibrary.titleTag(n).map { $0 & 0xFFF == 0x800 } ?? false
        return (isUpdate ? 1 << 62 : 0) + (GameLibrary.versionTag(n) ?? 0)
    }

    static func read(file: URL, keys: Keys, headerKey: [UInt8]) throws -> GameControl? {
        guard let h = FileHandle(forReadingAtPath: file.path) else { return nil }
        defer { try? h.close() }
        let ext = file.pathExtension.lowercased()
        let entries = (ext == "xci" || ext == "xcz") ? try GameFiles.xciSecure(h) : try GameFiles.pfs0(h, base: 0)
        let tickets: [[UInt8]] = entries.filter { $0.name.hasSuffix(".tik") }.compactMap { try? GameFiles.read(h, $0.offset, Int(min($0.size, 0x400))) }
        // a Control NCA is small: the large ones are program and data, so they are skipped without reading their headers
        for e in entries.filter({ $0.name.hasSuffix(".nca") && $0.size < 64 << 20 }).sorted(by: { $0.size < $1.size }) {
            let hd = AES.xtsDecrypt(try GameFiles.read(h, e.offset, 0xC00), key: headerKey, sectorSize: 0x200)
            guard String(bytes: hd[0x200..<0x203], encoding: .ascii) == "NCA", hd[0x205] == 2 else { continue }   // 2: Control
            guard let key = bodyKey(hd, keys: keys, tickets: tickets) else { return nil }
            return try control(h, e, hd, key: key)
        }
        return nil
    }

    /// The section key: the title key from the ticket, or the key area's.
    static func bodyKey(_ hd: [UInt8], keys: Keys, tickets: [[UInt8]]) -> [UInt8]? {
        let kg = max(hd[0x206], hd[0x220]) == 0 ? 0 : Int(max(hd[0x206], hd[0x220])) - 1
        let kgs = String(format: "%02x", kg)
        let rights = Array(hd[0x230..<0x240])
        if rights.contains(where: { $0 != 0 }) {
            guard let t = tickets.first(where: { GameFiles.ticketRights($0) == rights }), let base = GameFiles.ticketBase(t), t[base + 0x141] == 0,
                  let kek = keys.key("titlekek_\(kgs)") else { return nil }
            return AES.ecb(Array(t[(base + 0x40)..<(base + 0x50)]), key: kek, encrypt: false)
        }
        let areas = ["application", "ocean", "system"]
        guard Int(hd[0x207]) < areas.count, let kak = keys.key("key_area_key_\(areas[Int(hd[0x207])])_\(kgs)") else { return nil }
        return AES.ecb(Array(hd[0x320..<0x330]), key: kak, encrypt: false)
    }

    /// AES-CTR over whole blocks at an NCA offset (16-aligned): the counter is the section's nonce and the offset / 16.
    static func ctrBlocks(_ data: [UInt8], key: [UInt8], nonce: [UInt8], offset: UInt64) -> [UInt8] {
        let n = data.count / 16
        var counters = [UInt8](repeating: 0, count: n * 16)
        for b in 0..<n {
            var c = (offset >> 4) + UInt64(b)
            for j in 0..<8 { counters[b * 16 + j] = nonce[j] }
            for j in 0..<8 { counters[b * 16 + 15 - j] = UInt8(c & 0xFF); c >>= 8 }
        }
        let stream = AES.ecb(counters, key: key, encrypt: true)
        var out = data
        for i in 0..<(n * 16) { out[i] ^= stream[i] }
        return out
    }

    private static func control(_ h: FileHandle, _ e: Entry, _ hd: [UInt8], key: [UInt8]) throws -> GameControl? {
        for i in 0..<4 {
            let start = UInt64(GameFiles.u32(hd, 0x240 + i * 0x10)) * 0x200, end = UInt64(GameFiles.u32(hd, 0x244 + i * 0x10)) * 0x200
            guard end > start else { continue }
            let fs = Array(hd[(0x400 + i * 0x200)..<(0x600 + i * 0x200)])
            guard fs[3] == 3, fs[4] == 3, String(bytes: fs[8..<12], encoding: .ascii) == "IVFC" else { continue }   // RomFS, AES-CTR
            let rel = GameFiles.u64(fs, 0x18 + 5 * 0x18), size = GameFiles.u64(fs, 0x18 + 5 * 0x18 + 8)
            guard size > 0x50, size < 16 << 20 else { continue }
            var nonce = [UInt8](repeating: 0, count: 8)
            for j in 0..<8 { nonce[j] = fs[0x147 - j] }
            let off = start + rel, aligned = off & ~0xF
            let len = Int((off - aligned + size + 15) & ~0xF)
            let plain = ctrBlocks(try GameFiles.read(h, e.offset + aligned, len), key: key, nonce: nonce, offset: aligned)
            let romfs = Array(plain[Int(off - aligned)..<Int(off - aligned + size)])
            let files = romfsFiles(romfs)
            guard let nacp = files["control.nacp"], nacp.count >= 0x3070 else { return nil }
            func str(_ b: ArraySlice<UInt8>) -> String { String(decoding: b.prefix { $0 != 0 }, as: UTF8.self) }
            // 16 languages of (name 0x200, publisher 0x100); American English first, else the first one filled in
            let langs = (0..<16).map { l in (str(nacp[(l * 0x300)..<(l * 0x300 + 0x200)]), str(nacp[(l * 0x300 + 0x200)..<(l * 0x300 + 0x300)])) }
            guard let t = langs.first(where: { !$0.0.isEmpty }) else { return nil }
            let icon = files["icon_AmericanEnglish.dat"] ?? files.first(where: { $0.key.hasPrefix("icon_") })?.value
            return GameControl(name: langs[0].0.isEmpty ? t.0 : langs[0].0, publisher: langs[0].0.isEmpty ? t.1 : langs[0].1,
                               version: str(nacp[0x3060..<0x3070]), icon: icon.map { Data($0) })
        }
        return nil
    }

    /// A RomFS's files by name (control data has no folders): the file table's entries, each with its data.
    static func romfsFiles(_ r: [UInt8]) -> [String: [UInt8]] {
        guard r.count >= 0x50 else { return [:] }
        let metaOff = Int(GameFiles.u64(r, 0x38)), metaSize = Int(GameFiles.u64(r, 0x40)), dataOff = Int(GameFiles.u64(r, 0x48))
        guard metaOff + metaSize <= r.count else { return [:] }
        var out: [String: [UInt8]] = [:]
        var p = metaOff
        while p + 0x20 <= metaOff + metaSize {
            let fo = Int(GameFiles.u64(r, p + 8)), fsz = Int(GameFiles.u64(r, p + 0x10)), nl = Int(GameFiles.u32(r, p + 0x1C))
            guard p + 0x20 + nl <= r.count else { break }
            let name = String(decoding: r[(p + 0x20)..<(p + 0x20 + nl)], as: UTF8.self)
            if dataOff + fo + fsz <= r.count { out[name] = Array(r[(dataOff + fo)..<(dataOff + fo + fsz)]) }
            p += 0x20 + ((nl + 3) & ~3)
        }
        return out
    }
}
