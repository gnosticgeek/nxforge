// Code mods: the 60 fps, resolution and graphics patches made for a Switch's exefs folder, as enhancements. A code mod
// changes bytes of the game's program (main), and comes in two forms:
//
//   .pchtxt   IPSwitch's text: `@nsobid-<build ID>`, flags, then `// Title` sections switched by `@enabled` / `@disabled`,
//             each a list of `<offset> <hex bytes or "text">` lines, ended by `@stop`
//   .ips      the same patches assembled (IPS or IPS32), named after the build ID: offset and bytes records
//
// The engine already writes into main's code for Atmosphère codes (hle_cheats.c: a width-1/2/4/8 store through main's
// writable alias, refused where the rewriter changed or moved the words). So nothing new runs in the game: a code mod is
// translated here into such stores and becomes an enhancement (Enhancements.swift), one per titled section, with a switch,
// a build it is for and a place in the game's folder like any other. An enhancement file may also carry a ```pchtxt block
// as written; it is translated the same way when the file is read.
//
// Offsets: an IPS record's offset counts from the start of the NSO file, whose header is 0x100 bytes, so main + (offset −
// 0x100). A pchtxt's offsets are the same unless `@flag offset_shift 0x100` says they are already addresses in main (the
// shift is what IPSwitch adds to make the IPS). Values are bytes in file order (`@little-endian` reverses each value).
import AppKit
import Foundation
import UniformTypeIdentifiers

struct CodeWrite: Equatable {
    /// the address in main (0 = its first byte in memory)
    var address: UInt64
    var bytes: [UInt8]
}

struct CodeModSection: Equatable {
    var title: String
    var enabled: Bool
    var writes: [CodeWrite]
}

struct CodeMod: Equatable {
    /// the first 16 hex digits of the build ID it is for, upper case (nil: the file does not say)
    var build: String?
    var sections: [CodeModSection]
    /// the header comment's first line ("# Mario Kart 8 Deluxe 60 FPS"), for a name and a note
    var heading: String?
}

enum CodeMods {
    static let headerSize: UInt64 = 0x100

    // MARK: pchtxt

    static func parsePchtxt(_ text: String) -> CodeMod {
        var mod = CodeMod(build: nil, sections: [], heading: nil)
        var shift: UInt64 = 0, little = false, enabled = true
        var title: String?, writes: [CodeWrite] = [], sectionEnabled = true, started = false

        func close() {
            if !writes.isEmpty { mod.sections.append(CodeModSection(title: title ?? "", enabled: sectionEnabled, writes: writes)) }
            writes = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if s.hasPrefix("@") {
                let low = s.lowercased()
                if low.hasPrefix("@stop") { break }
                if low.hasPrefix("@nsobid-") {
                    let hex = s.dropFirst(8).prefix { $0.isHexDigit }
                    if hex.count >= 16 { mod.build = String(hex.prefix(16)).uppercased() }
                } else if low.hasPrefix("@flag") {
                    let parts = low.split(separator: " ").map(String.init)
                    if parts.count >= 3, parts[1] == "offset_shift" { shift = number(parts[2]) ?? 0 }
                } else if low.hasPrefix("@little-endian") { little = true }
                else if low.hasPrefix("@big-endian") { little = false }
                else if low.hasPrefix("@enabled") || low.hasPrefix("@disabled") {
                    // a switch in the middle of a section splits it: what follows is its own part
                    let on = low.hasPrefix("@enabled")
                    if !writes.isEmpty, on != sectionEnabled { close() }
                    enabled = on
                    if writes.isEmpty { sectionEnabled = on }
                }
                continue
            }
            if s.hasPrefix("#") {
                if mod.heading == nil, !started { let h = s.drop { $0 == "#" || $0 == " " }; if !h.isEmpty { mod.heading = String(h) } }
                continue
            }
            if s.hasPrefix("//") {
                // a title line starts the next section: what it holds follows its own @enabled / @disabled
                close()
                let t = s.drop { $0 == "/" || $0 == " " }.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
                title = t.isEmpty ? nil : t
                sectionEnabled = enabled
                continue
            }
            // <offset> <value>
            guard let sp = s.firstIndex(where: { $0 == " " || $0 == "\t" }), let off = UInt64(s[..<sp], radix: 16) else { continue }
            started = true
            var rest = s[s.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            var bytes: [UInt8] = []
            if rest.hasPrefix("\"") {
                bytes = string(rest)
            } else {
                if let c = rest.range(of: "//") { rest = String(rest[..<c.lowerBound]) }
                let hex = rest.filter { $0.isHexDigit }
                guard hex.count >= 2, hex.count % 2 == 0, hex.count == rest.filter({ !$0.isWhitespace }).count else { continue }
                var i = hex.startIndex
                while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); bytes.append(UInt8(hex[i..<j], radix: 16)!); i = j }
                if little { bytes.reverse() }
            }
            let at = off &+ shift
            guard !bytes.isEmpty, at >= headerSize else { continue }
            if writes.isEmpty { sectionEnabled = enabled }
            writes.append(CodeWrite(address: at - headerSize, bytes: bytes))
        }
        close()
        return mod
    }

    private static func number(_ s: String) -> UInt64? {
        s.hasPrefix("0x") ? UInt64(s.dropFirst(2), radix: 16) : UInt64(s)
    }

    /// A quoted value: the text's bytes with C's escapes, and the zero that ends a string in the game
    private static func string(_ s: String) -> [UInt8] {
        var out: [UInt8] = [], it = s.dropFirst().makeIterator(), closed = false
        while let c = it.next() {
            if c == "\"" { closed = true; break }
            if c == "\\", let n = it.next() {
                switch n {
                case "n": out.append(10)
                case "t": out.append(9)
                case "r": out.append(13)
                case "0": out.append(0)
                default: out.append(contentsOf: String(n).utf8)
                }
            } else { out.append(contentsOf: String(c).utf8) }
        }
        return closed ? out + [0] : []
    }

    // MARK: IPS

    /// The records of an IPS ("PATCH" … "EOF", 3-byte offsets) or IPS32 ("IPS32" … "EEOF", 4-byte offsets) file; nil when it is neither
    static func parseIPS(_ data: Data) -> [CodeWrite]? {
        let b = [UInt8](data)
        let wide: Bool
        if b.starts(with: Array("IPS32".utf8)) { wide = true } else if b.starts(with: Array("PATCH".utf8)) { wide = false } else { return nil }
        let end = Array((wide ? "EEOF" : "EOF").utf8), n = wide ? 4 : 3
        var i = 5, out: [CodeWrite] = []
        while i + n <= b.count {
            if Array(b[i..<(i + n)]) == end { return out }
            var off: UInt64 = 0
            for k in 0..<n { off = off << 8 | UInt64(b[i + k]) }
            i += n
            guard i + 2 <= b.count else { return nil }
            let size = Int(b[i]) << 8 | Int(b[i + 1]); i += 2
            var bytes: [UInt8]
            if size == 0 {   // a run: a count, then the byte it repeats
                guard i + 3 <= b.count else { return nil }
                bytes = Array(repeating: b[i + 2], count: Int(b[i]) << 8 | Int(b[i + 1])); i += 3
            } else {
                guard i + size <= b.count else { return nil }
                bytes = Array(b[i..<(i + size)]); i += size
            }
            if off >= headerSize, !bytes.isEmpty { out.append(CodeWrite(address: off - headerSize, bytes: bytes)) }
        }
        return nil   // no end marker: cut short
    }

    // MARK: To the engine's codes

    /// Atmosphère stores for the writes (type 0, main, no register): four bytes at a time, then two, then one
    static func dmnt(_ writes: [CodeWrite]) -> [String] {
        var out: [String] = []
        for w in writes {
            var at = w.address, i = 0
            while i < w.bytes.count {
                let left = w.bytes.count - i, n = left >= 4 ? 4 : left >= 2 ? 2 : 1
                // the store is little-endian: the value's digits are the bytes back to front
                let value = w.bytes[i..<(i + n)].reversed().map { String(format: "%02X", $0) }.joined()
                out.append(String(format: "0%ld0000%02lX %08lX ", n, Int(at >> 32) & 0xFF, Int(at & 0xFFFF_FFFF)) + String(repeating: "0", count: 8 - n * 2) + value)
                at += UInt64(n); i += n
            }
        }
        return out
    }

    // MARK: Into the game's enhancements

    struct Made: Equatable { var file: String; var name: String; var text: String }

    /// The enhancement files for a code mod: one per section (a section the file had disabled says so), switched off.
    /// `fallback` names a file without titles (the mod's file name). `build` is the game's when the mod names none.
    static func enhancements(_ mod: CodeMod, fallback: String, titleID: String, build: String?, source: String) -> [Made] {
        let sections = mod.sections.filter { !$0.writes.isEmpty }
        return sections.enumerated().map { i, s in
            var name = s.title.isEmpty ? fallback : s.title
            if sections.count > 1, s.title.isEmpty { name += " \(i + 1)" }
            let count = s.writes.reduce(0) { $0 + $1.bytes.count }
            var body = "A code mod: it changes \(count) byte\(count == 1 ? "" : "s") of the game's program at \(s.writes.count) place\(s.writes.count == 1 ? "" : "s")"
            body += (mod.build ?? build).map { ", made for build \($0)." } ?? "."
            if let h = mod.heading, h != name { body += " From \"\(h)\"." }
            if !s.enabled { body += " Its file had this part switched off." }
            let text = """
            ---
            nxforge_enhancement: 1
            name: \(MiniYAML.quote(name))
            title_id: \(MiniYAML.quote(titleID))
            builds: \(MiniYAML.quote(mod.build ?? build ?? ""))
            on: false
            source: \(MiniYAML.quote(source))
            ---
            # \(name)

            \(body)

            ```dmnt
            \(dmnt(s.writes).joined(separator: "\n"))
            ```

            """
            return Made(file: Enhancements.fileName(name), name: name, text: text)
        }
    }

    enum Problem: Error, Equatable {
        case unreadable, empty, otherBuild(String)
        var text: String {
            switch self {
            case .unreadable: return "That file is not a code mod NXForge can read (a .pchtxt or .ips file)."
            case .empty: return "That code mod changes nothing: no patch lines were found in it."
            case .otherBuild(let b): return "That code mod is for another version of the game (build \(b)). It was added, and stays off for this one."
            }
        }
    }

    /// Read a .pchtxt or .ips file (an .ips is named after its build ID)
    static func read(_ url: URL) throws -> CodeMod {
        guard let data = try? Data(contentsOf: url) else { throw Problem.unreadable }
        let stem = url.deletingPathExtension().lastPathComponent
        if let w = parseIPS(data) {
            guard !w.isEmpty else { throw Problem.empty }
            let hex = stem.prefix { $0.isHexDigit }
            return CodeMod(build: hex.count >= 16 ? String(hex.prefix(16)).uppercased() : nil, sections: [CodeModSection(title: "", enabled: true, writes: w)], heading: nil)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), text.contains("@") || url.pathExtension.lowercased() == "pchtxt" else { throw Problem.unreadable }
        let mod = parsePchtxt(text)
        guard !mod.sections.isEmpty else { throw Problem.empty }
        return mod
    }

    /// A name for a mod whose sections have no titles: its file's, unless that is only a build ID (then its folder's)
    static func fallbackName(_ url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let plain = stem.allSatisfy { $0.isHexDigit } ? url.deletingLastPathComponent().lastPathComponent : stem
        let name = plain == "exefs" ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent : plain
        return name.isEmpty || name == "/" ? "Code mod" : name
    }

    /// Add a code mod file to a game's enhancements folder. Returns the names added and, for a mod made for another build, a note.
    @discardableResult
    static func add(_ url: URL, folder: URL, titleID: String, build: String?) throws -> (names: [String], note: String?) {
        let mod = try read(url)
        let made = enhancements(mod, fallback: fallbackName(url), titleID: titleID, build: build, source: url.lastPathComponent)
        guard !made.isEmpty else { throw Problem.empty }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var names: [String] = []
        for m in made {
            var dest = folder.appending(path: m.file), i = 2
            while fm.fileExists(atPath: dest.path) {
                if (try? String(contentsOf: dest, encoding: .utf8)).map({ Enhancements.setOn($0, false) }) == m.text { break }   // the same mod again
                dest = folder.appending(path: (m.file as NSString).deletingPathExtension + "-\(i).md"); i += 1
            }
            if !fm.fileExists(atPath: dest.path) { try Data(m.text.utf8).write(to: dest, options: .atomic) }
            names.append(m.name)
        }
        if let b = mod.build, let build, b.uppercased() != build.uppercased() { return (names, Problem.otherBuild(b).text) }
        return (names, nil)
    }
}

extension EnhancementsState {
    /// Add Code Mod…: choose .pchtxt or .ips files; each becomes enhancements, switched off
    func addCodeMods() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.allowedContentTypes = ["pchtxt", "ips", "txt"].compactMap { UTType(filenameExtension: $0) }
        p.allowsOtherFileTypes = true
        p.message = "Choose a code mod: a .pchtxt or .ips file from a mod's exefs folder."
        p.prompt = "Add"
        guard p.runModal() == .OK else { return }
        addCodeMods(p.urls)
    }

    func addCodeMods(_ urls: [URL]) {
        var added: [String] = [], notes: [String] = []
        for u in urls {
            do {
                let r = try CodeMods.add(u, folder: folder, titleID: titleID, build: build)
                added += r.names
                if let n = r.note { notes.append(n) }
            } catch let e as CodeMods.Problem { notes.append("\(u.lastPathComponent): \(e.text)") }
            catch { notes.append("\(u.lastPathComponent): \(error.localizedDescription)") }
        }
        reload()
        let head = added.isEmpty ? nil : added.count == 1 ? "Added \"\(added[0])\", switched off." : "Added \(added.count) enhancements, switched off."
        note = ([head].compactMap { $0 } + notes).joined(separator: " ")
    }
}
