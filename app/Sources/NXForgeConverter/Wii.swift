// Wii and GameCube games (wii/README.md). A game is one disc image in the Wii games folder (.iso, .rvz, .wbfs, .gcz, .ciso, .wia, .gcm;
// a WiiWare .wad; a homebrew .dol or .elf); scripts/wii_build.py makes it a Mac app whose player (wii/host) runs it with Dolphin and has
// the same in-game sidebar as a Switch game's. The app plays the disc where it lies. Here: finding the games for the Library, what the
// Convert page shows about one, where its app goes, and the Port details card.
//
// A Wii game's title ID is 0E00 and its six-character game ID in hex, a GameCube game's 0C00 and the same (wii_build.py title_id), read
// from the disc header alone: listing a folder of games reads the first few hundred bytes of each file.
import Foundation
import SwiftUI
import zlib

enum Wii {
    static let helper = "scripts/wii_build.py"
    static let discExtensions: Set<String> = ["iso", "gcm", "rvz", "wia", "wbfs", "gcz", "ciso"]
    static let extensions: Set<String> = discExtensions.union(["wad", "dol", "elf"])

    static func isGame(_ p: String) -> Bool { extensions.contains(p.url.pathExtension.lowercased()) && !Source.isDir(p) }
    /// Whether a built app is a Wii or GameCube one (its port.json sits in Contents/Resources/wii)
    static func isApp(_ app: String) -> Bool { FileManager.default.fileExists(atPath: app + "/Contents/Resources/wii/port.json") }
    static func isTitleID(_ t: String?) -> Bool { isWiiID(t) || isGameCubeID(t) }
    static func isWiiID(_ t: String?) -> Bool { t?.uppercased().hasPrefix("0E00") == true }
    static func isGameCubeID(_ t: String?) -> Bool { t?.uppercased().hasPrefix("0C00") == true }

    /// Whether Dolphin is built on this Mac (scripts/wii_engine.py's default home): the first conversion builds it, 15 to 30 minutes
    static var engineBuilt: Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: base.appending(path: "NXForge Converter/dolphin/out/nxdolphin.dylib").path)
    }

    /// "0E0052545A453038" → "RTZE08", for GameTDB's art
    static func gameID(titleID t: String?) -> String? {
        guard let t, isTitleID(t), t.count == 16 else { return nil }
        let hex = Array(t.dropFirst(4)), bytes = stride(from: 0, to: 12, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
        guard bytes.count == 6 else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// GameTDB's art for a disc, the game's own region first (the ID's fourth letter: E America, P Europe, J Japan)
    static func coverURLs(id: String, kind: String) -> [URL] {
        let region = ["E": "US", "N": "US", "P": "EN", "D": "DE", "F": "FR", "J": "JA", "K": "KO"][String(id.dropFirst(3).prefix(1))] ?? "EN"
        var regions = [region]
        for r in ["US", "EN"] where !regions.contains(r) { regions.append(r) }
        return regions.compactMap { URL(string: "https://art.gametdb.com/wii/\(kind)/\($0)/\(id).png") }
    }

    /// The game's own folder for its app and build folder: GBA.home's rule (a local drive, NXForge Builds)
    static func home(for file: String) -> String { GBA.home(for: file) }
    static func cleanName(_ file: String) -> String { GBA.cleanName(file) }

    struct Header: Hashable { var title: String, gameID: String, gamecube: Bool, titleID: String }

    /// The disc's own first 0x80 bytes, from whichever image format holds it (wii_build.py disc_header)
    static func discHeader(_ path: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 0x8100), d.count >= 0x80 else { return nil }
        let b = [UInt8](d)
        let magic = String(bytes: b[0..<4], encoding: .ascii) ?? ""
        func slice(_ at: Int) -> Data? { b.count >= at + 0x80 ? Data(b[at..<(at + 0x80)]) : nil }
        if magic == "RVZ\u{1}" || magic == "WIA\u{1}" { return slice(0x58) }
        if magic == "WBFS" { return slice(0x200) }
        if magic == "CISO" { return slice(0x8000) }
        let le32 = { (o: Int) in UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 }
        let le64 = { (o: Int) in UInt64(le32(o)) | UInt64(le32(o + 4)) << 32 }
        if le32(0) == 0xB10B_C001 {   // GCZ: the header is in the first block, stored or zlib-compressed
            let blockSize = Int(le32(24)), blocks = Int(le32(28))
            guard blocks > 0, blockSize > 0, b.count >= 40 else { return nil }
            let ptr = le64(32), stored = ptr & (1 << 63) != 0
            try? h.seek(toOffset: UInt64(32 + blocks * 12) + (ptr & ~(1 << 63)))
            guard let raw = try? h.read(upToCount: blockSize) else { return nil }
            if stored { return raw.count >= 0x80 ? raw.prefix(0x80) : nil }
            var out = [UInt8](repeating: 0, count: 0x80)
            var s = z_stream()
            guard inflateInit_(&s, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
            defer { inflateEnd(&s) }
            let got: Int = raw.withUnsafeBytes { src in
                out.withUnsafeMutableBytes { dst in
                    s.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress!)
                    s.avail_in = uInt(src.count)
                    s.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
                    s.avail_out = uInt(dst.count)
                    _ = inflate(&s, Z_SYNC_FLUSH)
                    return dst.count - Int(s.avail_out)
                }
            }
            return got >= 0x80 ? Data(out) : nil
        }
        return slice(0)
    }

    /// The game's title, game ID, console and the title ID NXForge keeps it under; nil when the file is not a Wii or GameCube disc.
    /// A WAD, DOL or ELF has no disc header: wii_build.py --info reads those.
    static func header(_ path: String) -> Header? {
        guard discExtensions.contains(path.url.pathExtension.lowercased()), let d = discHeader(path), d.count >= 0x60 else { return nil }
        let b = [UInt8](d)
        let be32 = { (o: Int) in UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]) }
        let wii = be32(0x18) == 0x5D1C_9EA3, gc = be32(0x1C) == 0xC233_9F3D
        guard wii || gc else { return nil }
        let id = b[0..<6].map { $0 > 32 && $0 < 127 ? $0 : 0x30 }
        let gameID = String(bytes: id, encoding: .ascii) ?? "000000"
        let titleBytes = b[0x20..<0x60].prefix { $0 != 0 }
        let title = (String(bytes: titleBytes, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
        return Header(title: title, gameID: gameID, gamecube: !wii, titleID: (wii ? "0E00" : "0C00") + id.map { String(format: "%02X", $0) }.joined())
    }

    /// The Wii games folder: the one in Settings, else folders named wii or gamecube beside the Switch games folder or the
    /// Game Boy Advance one (…/roms/gba → …/roms/wii, …/roms/gamecube).
    static func roots(_ s: Settings) -> [String] {
        if let r = s.wiiRoot, !r.isEmpty { return [r] }
        var out: [String] = []
        for base in [s.gamesRoot, s.gbaRoot].compactMap({ $0 }) where !base.isEmpty {
            let parent = base.url.deletingLastPathComponent()
            for n in ["wii", "gamecube", "gc", "ngc"] {
                let p = parent.appending(path: n).path
                if !out.contains(p) && Source.isDir(p) { out.append(p) }
            }
        }
        return out
    }
    static func root(_ s: Settings) -> String? { roots(s).first }

    /// Every game in the folders (and two levels of folders under them: sets often keep a folder per game), as Library games.
    static func scan(roots: [String]) -> [LibraryGame] {
        let fm = FileManager.default
        var out: [LibraryGame] = []
        func take(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names.sorted() where !n.hasPrefix(".") {
                let p = "\(dir)/\(n)"
                if Source.isDir(p) {
                    if depth < 2 && n != GBA.folderName && !n.hasSuffix(".app") && !n.hasSuffix("_build") { take(p, depth: depth + 1) }
                    continue
                }
                guard isGame(p) else { continue }
                let ext = p.url.pathExtension.lowercased()
                let h = header(p)
                if h == nil && discExtensions.contains(ext) { continue }   // an .iso of something else
                if ext == "wbfs", n.range(of: #"\.wbf\d$"#, options: .regularExpression) != nil { continue }
                let bytes = ((try? fm.attributesOfItem(atPath: (p as NSString).resolvingSymlinksInPath))?[.size] as? NSNumber)?.int64Value ?? 0
                var g = LibraryGame(kind: .wii, path: p, name: cleanName(n), titleID: h?.titleID, files: [], fileCount: 1, bytes: bytes, base: true, updates: 0, dlc: 0)
                // its app in its own folder, made here or by wii_build.py by hand (the build records list the converter's)
                let home = home(for: p)
                g.app = ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter { $0.hasSuffix(".app") }.sorted().first.map { "\(home)/\($0)" }
                out.append(g)
            }
        }
        for r in roots { take(r, depth: 0) }
        // the same game twice (an .iso and an .rvz of one disc): the first is the game
        var seen = Set<String>()
        return out.filter { g in g.titleID.map { seen.insert($0).inserted } ?? true }
    }

    /// What wii_build.py --info says about a disc
    struct Info: Decodable { var platform: String, id: String, title: String, form: String, titleID: String, name: String, bytes: Int64, disc: String }

    static func read(_ p: String, env: ToolEnv) -> Result<SourceInfo, ConverterError> {
        guard let repo = env.repo, let py = env.python else { return .failure(ConverterError("no engine checkout or Python yet: see Toolchain")) }
        guard FileManager.default.fileExists(atPath: repo + "/" + helper) else {
            return .failure(ConverterError("this engine has no \(helper): update the engine to play Wii and GameCube games"))
        }
        guard let r = run(py, ["-u", repo + "/" + helper, p, "--info"], env: ["PATH": env.path], cwd: repo) else { return .failure(ConverterError("cannot start \(py)")) }
        let line = r.out.split(separator: "\n").last.map(String.init) ?? ""
        guard r.ok, let i = try? JSONDecoder().decode(Info.self, from: Data(line.utf8)) else {
            return .failure(ConverterError(line.isEmpty ? "\(helper) said nothing about the file" : line.replacingOccurrences(of: "wii_build: ", with: "")))
        }
        var notes: [String] = []
        if Disk.isNetwork(p) { notes.append("the disc is on a network share: the app reads it from there, so the share must be connected to play") }
        return .success(SourceInfo(kind: .wii, source: p, folder: home(for: p), titleID: i.titleID, name: cleanName(p), base: true, updates: [], dlc: 0,
                                   romfsBytes: i.bytes, fileBytes: i.bytes, zbic: false, zbicInstalled: false, profile: nil,
                                   notes: notes + ["\(i.platform == "wii" ? "Wii" : "GameCube") \(i.form): \(i.title) (\(i.id))"]))
    }

    static func validation(_ i: SourceInfo) -> Validation {
        let console = isGameCubeID(i.titleID) ? "GameCube" : "Wii"
        var s = [CheckLine(ok: true, text: "\(console) game \(i.titleID): played with Dolphin, no keys and no BIOS needed")]
        s.append(CheckLine(ok: true, text: "the app plays the disc image where it is: keep it there"))
        if let first = i.notes.last { s.append(CheckLine(ok: true, text: first)) }
        s += i.notes.dropLast().map { CheckLine(ok: false, text: $0, warn: true) }
        return Validation(ok: true, keysSummary: "no keys needed", summary: s,
                          files: [FileReport(name: "Disc", role: "Game", ok: true, lines: [CheckLine(ok: true, text: i.source.lastComponent)])])
    }

    // MARK: Port details

    struct Port: Decodable {
        struct Trial: Decodable { var playing: Bool, frames: Int, fps: Double?, seconds: Int?, error: String? }
        struct EngineRef: Decodable { var name: String, commit: String }
        var platform: String, id: String, title: String, form: String, name: String, bytes: Int64, disc: String
        var engine: EngineRef, built: Double, trial: Trial?
    }

    static func port(app: String) -> Port? {
        guard let d = FileManager.default.contents(atPath: app + "/Contents/Resources/wii/port.json") else { return nil }
        return try? JSONDecoder().decode(Port.self, from: d)
    }
}

/// Port details for a Wii or GameCube app: the disc it plays, where that is, and how its trial run went.
struct WiiPortCard: View {
    let app: String

    var body: some View {
        if let p = Wii.port(app: app) {
            let console = p.platform == "wii" ? "Wii" : "GameCube"
            let there = FileManager.default.fileExists(atPath: p.disc)
            Card(title: "Disc", subtitle: "The \(console) disc this app plays with Dolphin, from where it is.") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    row("Game", "\(p.title) · \(p.id) · \(ByteCountFormatter.string(fromByteCount: p.bytes, countStyle: .file))")
                    row("Disc image", p.disc.tildePath + (there ? "" : " (not there now: connect its drive, or convert the game again from where it is)"))
                    if let t = p.trial {
                        row("Trial run", t.playing ? "Started and drew \(t.frames.formatted()) frames in \(t.seconds ?? 0) s with no window" : "Did not reach its first frame: \(t.error ?? "see the build log")")
                    }
                    row("Engine", "\(p.engine.name) \(p.engine.commit.prefix(8))")
                }
                .font(.callout)
                if !there { Label("The app cannot start until the disc image is back at that path.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
    }
}
