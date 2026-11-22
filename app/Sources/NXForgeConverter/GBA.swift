// Game Boy Advance games (gba/README.md). A GBA game is one cartridge file in the GBA games folder (a .gba, or a .zip
// holding one, as No-Intro sets come); scripts/gba_build.py converts it into a Mac app whose player (gba/host) has the
// same in-game sidebar as a Switch game's. Here: finding the games for the Library, what the Convert page shows about
// one, where its app and build folder go, and the Port details the game page shows from the app's port.json.
//
// NXForge keeps every game under a 16-digit title ID. A GBA game's is 0BA0, its four-character game code as hex, the
// header's version byte and 00 (gba_build.py title_id): read from the cartridge header alone, so listing a folder of
// games needs the first few hundred bytes of each file and no hashing.
import Compression
import Foundation
import SwiftUI

enum GBA {
    static let helper = "scripts/gba_build.py"
    static let extensions: Set<String> = ["gba", "agb", "zip"]
    static let folderName = "NXForge Builds"

    static func isGame(_ p: String) -> Bool { extensions.contains(p.url.pathExtension.lowercased()) && !Source.isDir(p) }
    static func isTitleID(_ t: String?) -> Bool { t?.uppercased().hasPrefix("0BA0") == true }

    /// "Legend of Zelda, The - The Minish Cap (Europe) (En,Fr,De,Es,It).zip" → "The Legend of Zelda - The Minish Cap" (gba_build.py clean_name)
    static func cleanName(_ file: String) -> String {
        var n = (file.lastComponent as NSString).deletingPathExtension
        n = n.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let m = n.firstMatch(of: #/^(.*?), (The|A|An)( - .*)?$/#) { n = "\(m.2) \(m.1)\(m.3 ?? "")" }
        return n.isEmpty ? "Game" : n
    }

    /// The game's own folder, on a local drive: its app, its build folder and its media go here. The cartridge files stay
    /// where they are, side by side in the games folder (often a network share).
    static func home(for file: String) -> String {
        let parent = file.url.deletingLastPathComponent().path
        let base = Disk.outDir.flatMap { Disk.isNetwork($0) ? nil : $0 } ?? (Disk.isNetwork(parent) || !FileManager.default.isWritableFile(atPath: parent) ? NSHomeDirectory() + "/Documents" : parent)
        return "\(base)/\(folderName)/\(cleanName(file).replacingOccurrences(of: ":", with: " - ").replacingOccurrences(of: "/", with: " - "))"
    }

    /// The first `count` bytes of the cartridge: of the file itself, or of the first file inside a .zip (stored or deflated).
    static func head(_ path: String, count: Int = 192) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard path.url.pathExtension.lowercased() == "zip" else { return try? h.read(upToCount: count) }
        guard let d = try? h.read(upToCount: 16384), d.count > 30, d[0] == 0x50, d[1] == 0x4B, d[2] == 3, d[3] == 4 else { return nil }
        let u16 = { (o: Int) in Int(d[o]) | Int(d[o + 1]) << 8 }
        let method = u16(8), start = 30 + u16(26) + u16(28)
        guard start < d.count else { return nil }
        let body = d.subdata(in: start..<d.count)
        if method == 0 { return body.prefix(count) }
        guard method == 8 else { return nil }
        // raw deflate, as far as the bytes read go: the header is at the very start of the stream
        var out = Data(count: max(count, 1024))
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }
        let cap = out.count
        let got: Int = body.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                stream.pointee.src_ptr = src.bindMemory(to: UInt8.self).baseAddress!
                stream.pointee.src_size = src.count
                stream.pointee.dst_ptr = dst.bindMemory(to: UInt8.self).baseAddress!
                stream.pointee.dst_size = cap
                let s = compression_stream_process(stream, 0)
                return s == COMPRESSION_STATUS_ERROR ? 0 : cap - stream.pointee.dst_size
            }
        }
        return got >= count ? out.prefix(count) : nil
    }

    struct Header: Hashable { var title: String, code: String, version: UInt8, titleID: String }

    /// The cartridge header's title, game code and version, and the title ID NXForge keeps the game under; nil when the file is not a GBA ROM.
    static func header(_ path: String) -> Header? {
        guard let d = head(path), d.count >= 0xC0, d[d.startIndex + 0xB2] == 0x96 else { return nil }
        let b = [UInt8](d)
        let text = { (r: Range<Int>) in String(bytes: b[r].filter { $0 >= 32 && $0 < 127 }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "" }
        let code = text(0xAC..<0xB0)
        let padded = Array((code.isEmpty ? "????" : code).utf8.prefix(4)) + [UInt8](repeating: 0x3F, count: max(0, 4 - code.utf8.count))
        let id = "0BA0" + padded.map { String(format: "%02X", $0) }.joined() + String(format: "%02X00", b[0xBC])
        return Header(title: text(0xA0..<0xAC), code: code, version: b[0xBC], titleID: id)
    }

    /// The GBA games folder: the one in Settings, else a folder named gba beside the Switch games folder (…/roms/switch → …/roms/gba).
    static func root(_ s: Settings) -> String? {
        if let r = s.gbaRoot, !r.isEmpty { return r }
        guard let sw = s.gamesRoot else { return nil }
        let beside = sw.url.deletingLastPathComponent().appending(path: "gba").path
        return Source.isDir(beside) ? beside : nil
    }

    /// Every cartridge file in the folder (and one level of folders under it), as Library games. One listing per folder and
    /// a few hundred bytes of each file; a file whose header cannot be read is listed by its name, without a title ID.
    static func scan(root: String) -> [LibraryGame] {
        let fm = FileManager.default
        var out: [LibraryGame] = []
        func take(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names.sorted() where !n.hasPrefix(".") {
                let p = "\(dir)/\(n)"
                if Source.isDir(p) { if depth < 1 && n != folderName && !n.hasSuffix(".app") && !n.hasSuffix("_build") { take(p, depth: depth + 1) }; continue }
                guard isGame(p) else { continue }
                let h = header(p)
                if h == nil && p.url.pathExtension.lowercased() == "zip" { continue }   // a zip of something else
                let bytes = ((try? fm.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
                out.append(LibraryGame(kind: .gba, path: p, name: cleanName(n), titleID: h?.titleID, files: [], fileCount: 1, bytes: bytes, base: true, updates: 0, dlc: 0))
            }
        }
        take(root, depth: 0)
        // two files of one game (two regions keep different codes; the same code twice is a duplicate dump): the first is the game
        var seen = Set<String>()
        return out.filter { g in g.titleID.map { seen.insert($0).inserted } ?? true }
    }

    /// What gba_build.py --info says about a cartridge file.
    struct Info: Decodable { var title: String, code: String, titleID: String, sha1: String, bytes: Int64, name: String, checksumOK: Bool }

    static func read(_ p: String, env: ToolEnv) -> Result<SourceInfo, ConverterError> {
        guard let repo = env.repo, let py = env.python else { return .failure(ConverterError("no engine checkout or Python yet: see Toolchain")) }
        guard FileManager.default.fileExists(atPath: repo + "/" + helper) else {
            return .failure(ConverterError("this engine has no \(helper): update the engine to convert Game Boy Advance games"))
        }
        guard let r = run(py, ["-u", repo + "/" + helper, p, "--info"], env: ["PATH": env.path], cwd: repo) else { return .failure(ConverterError("cannot start \(py)")) }
        let line = r.out.split(separator: "\n").last.map(String.init) ?? ""
        guard r.ok, let i = try? JSONDecoder().decode(Info.self, from: Data(line.utf8)) else {
            return .failure(ConverterError(line.isEmpty ? "\(helper) said nothing about the file" : line.replacingOccurrences(of: "gba_build: ", with: "")))
        }
        let profile = ["\(i.code)-\(i.sha1.prefix(8))", i.code].first { FileManager.default.fileExists(atPath: "\(repo)/library/gba/\($0).md") }
        var notes: [String] = []
        if !i.checksumOK { notes.append("the cartridge header's checksum is wrong: a hack or a bad dump may still convert") }
        return .success(SourceInfo(kind: .gba, source: p, folder: home(for: p), titleID: i.titleID, name: cleanName(p), base: true, updates: [], dlc: 0,
                                   romfsBytes: i.bytes, fileBytes: i.bytes, zbic: false, zbicInstalled: false, profile: profile, notes: notes))
    }

    static func validation(_ i: SourceInfo) -> Validation {
        var s = [CheckLine(ok: true, text: "Game Boy Advance cartridge: game \(i.titleID), no keys and no BIOS file needed")]
        if let pr = i.profile { s.append(CheckLine(ok: true, text: "NXForge profile: library/gba/\(pr).md")) }
        else { s.append(CheckLine(ok: true, text: "no profile yet: converted from the cartridge alone, and its trial run says how it went")) }
        s += i.notes.map { CheckLine(ok: false, text: $0, warn: true) }
        return Validation(ok: true, keysSummary: "no keys needed", summary: s,
                          files: [FileReport(name: "Cartridge", role: "Game", ok: true, lines: [CheckLine(ok: true, text: i.source.lastComponent)])])
    }

    // MARK: Port details

    struct Port: Decodable {
        struct Trial: Decodable {
            var frames: Int, fps: Double, blocks: Int, nativeShare: Double, missesRom: Int, missesRam: Int
            var saveKind: String, saveBytes: Int, rtc: Bool, enhancedAudio: Bool, stateCheck: Bool
        }
        struct StageTime: Decodable, Hashable { var name: String, seconds: Double }
        struct EngineRef: Decodable { var name: String, commit: String }
        var name: String, title: String, code: String, maker: String?, version: Int, sha1: String, bytes: Int64
        var engine: EngineRef, built: Double, stages: [StageTime], trial: Trial
        var blocks: Int?, ramEntryPoints: Int?, units: Int?, status: String?
    }

    static func port(app: String) -> Port? {
        guard let d = FileManager.default.contents(atPath: app + "/Contents/Resources/gba/port.json") else { return nil }
        return try? JSONDecoder().decode(Port.self, from: d)
    }

    /// What the game's last run left for the page: how much of what it ran was translated code (the player writes last-run.json when it quits).
    static func lastRun(titleID: String) -> (frames: Int, misses: Int)? {
        let p = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "nxnative/\(titleID)/last-run.json").path
        guard let d = FileManager.default.contents(atPath: p), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return ((j["frames"] as? Int) ?? 0, ((j["missesRom"] as? Int) ?? 0) + ((j["missesRam"] as? Int) ?? 0))
    }
}

/// Port details: what the conversion found and how its trial run went, from the app's port.json.
struct PortDetailsCard: View {
    let app: String
    let titleID: String
    @State private var sheet = false

    var body: some View {
        if let p = GBA.port(app: app) {
            let left = p.trial.missesRom + p.trial.missesRam
            Card(title: "Port details", subtitle: "How this Game Boy Advance game was converted, and how its trial run went.") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    row("Cartridge", "\(p.title.isEmpty ? p.name : p.title) · \(p.code) · version 1.\(p.version) · \(ByteCountFormatter.string(fromByteCount: p.bytes, countStyle: .file))")
                    row("Code translated", "\(p.trial.blocks.formatted()) blocks; \(pct(p.trial.nativeShare)) of the trial run's steps ran as translated code")
                    row("Left to the interpreter", left == 0 ? "Nothing in the trial run" : "\(left.formatted()) entry points in the trial run (they still run, more slowly)")
                    if let n = p.ramEntryPoints, n > 0 { row("Code the game copies into memory", "\(n.formatted()) entry points captured") }
                    row("Save type", p.trial.saveKind == "None" ? "No cartridge save" : "\(p.trial.saveKind), \(ByteCountFormatter.string(fromByteCount: Int64(p.trial.saveBytes), countStyle: .memory))\(p.trial.rtc ? ", with a clock" : "")")
                    row("Trial run", "\(p.trial.frames.formatted()) frames at \(Int(p.trial.fps)) frames a second without a window; save states \(p.trial.stateCheck ? "checked" : "not checked")")
                    row("Enhanced audio", p.trial.enhancedAudio ? "Available: the music is mixed again at 48 kHz" : "Smoother output only: this game's sound engine is not one the player re-renders")
                    if let r = GBA.lastRun(titleID: titleID) { row("Your last play", r.misses == 0 ? "Everything it ran was translated" : "\(r.misses.formatted()) new entry points found: Convert again takes them in") }
                    row("Engine", "\(p.engine.name) \(p.engine.commit.prefix(8)) · converted in \(Int(p.stages.map(\.seconds).reduce(0, +))) s")
                }
                .font(.callout)
                if FileManager.default.fileExists(atPath: sheetPath) {
                    Button { sheet = true } label: { Label("Show the trial run's pictures", systemImage: "photo.on.rectangle") }.buttonStyle(.stage)
                        .help("Twelve pictures from the trial run, taken as the converted game played by itself")
                }
            }
            .sheet(isPresented: $sheet) {
                VStack(spacing: 14) {
                    if let img = NSImage(contentsOfFile: sheetPath) { Image(nsImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 980) }
                    Button("Done") { sheet = false }.keyboardShortcut(.defaultAction)
                }
                .padding(20)
            }
        }
    }

    private var sheetPath: String { app + "/Contents/Resources/gba/trial.png" }
    private func pct(_ v: Double) -> String { v >= 0.9995 ? "100%" : String(format: "%.1f%%", v * 100) }
    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
    }
}
