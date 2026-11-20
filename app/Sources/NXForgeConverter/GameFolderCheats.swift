// A game's cheats, kept in its own folder as Markdown: `cheats/<build ID>.md` beside `media/` (GameFolderMedia.swift), one file per
// build of the game. The engine still runs Atmosphère's files from ~/Library/Application Support/nxnative/<title ID>/cheats
// (<build ID>.txt and its switches in <build ID>.enabled, GameExtras.swift), so the two are kept in step: what the app, Get Cheats or
// the game's sidebar changed is written to the Markdown, and a Markdown file edited by hand (newer than the engine's files) is read
// back into them. A Mac with no cheats for a game yet takes them from its folder.
//
// The Markdown: YAML front matter (title, title ID, build ID, version), then one `## Name` per cheat with its code in a ```dmnt
// block. ```dmnt on is a cheat switched on, ```dmnt master a master code (always on), and a ```dmnt master block before the first
// heading is the nameless master code at the top of an Atmosphère file. Text under a heading is a note that NXForge keeps.
import Foundation

enum GameFolderCheats {
    static let folderName = "cheats"

    /// The cheats folder beside a game's media folder: "media" → "cheats", "<App> media" → "<App> cheats"
    static func folder(media: URL) -> URL {
        let name = media.lastPathComponent
        let base = name == GameFolderMedia.folderName ? folderName
                 : name.hasSuffix(" " + GameFolderMedia.folderName) ? String(name.dropLast(GameFolderMedia.folderName.count)) + folderName
                 : folderName
        return media.deletingLastPathComponent().appending(path: base)
    }

    static func file(_ folder: URL, build: String) -> URL { folder.appending(path: build.uppercased() + ".md") }

    /// What a Markdown cheat file holds
    struct Doc: Equatable {
        var build: String?
        var entries: [CheatEntry] = []
        /// the keys of the cheats switched on (CheatFile.keys)
        var on: Set<String> = []
        /// a cheat's note by its key
        var notes: [String: String] = [:]
    }

    struct Info { var title: String; var titleID: String; var version: String? }

    static func document(_ info: Info, build: String, entries: [CheatEntry], on: Set<String>, notes: [String: String] = [:]) -> String {
        var y = ["---", "# Written by NXForge. Edit freely: switch a cheat on with ```dmnt on, add one with a ## heading and a ```dmnt block.",
                 "# NXForge reads this file back when it is newer than its own copy, and keeps the text under each heading.",
                 "nxforge_cheats: 1"]
        y.append("title: \(MiniYAML.quote(info.title))")
        y.append("title_id: \(MiniYAML.quote(info.titleID.uppercased()))")
        y.append("build_id: \(MiniYAML.quote(build.uppercased()))")
        if let v = info.version, !v.isEmpty { y.append("version: \(MiniYAML.quote(v))") }
        y.append("---")
        var m = ["", "# \(info.title) cheats", ""]
        let named = entries.filter { !$0.name.isEmpty }
        let count = named.filter { !$0.master }.count
        m.append("Build \(build.uppercased())\(info.version.map { ", version \($0)" } ?? ""). \(count) cheat\(count == 1 ? "" : "s"), \(on.count) on.")
        m.append("")
        for e in entries where e.name.isEmpty {
            m += ["```dmnt master"] + e.lines + ["```", ""]
        }
        let keys = CheatFile.keys(entries)
        for (e, key) in zip(entries, keys) where !e.name.isEmpty {
            m += ["## \(e.name)", ""]
            if let n = notes[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { m += [n, ""] }
            m += ["```dmnt" + (e.master ? " master" : on.contains(key) ? " on" : "")] + e.lines + ["```", ""]
        }
        return (y + m).joined(separator: "\n")
    }

    static func parse(_ text: String) -> Doc {
        var d = Doc()
        if let fm = MiniYAML.frontMatter(text), let b = fm["build_id"] as? String, b.count >= 16, b.prefix(16).allSatisfy(\.isHexDigit) {
            d.build = String(b.prefix(16)).uppercased()
        }
        var lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines = Array(lines[(end + 1)...])
        }
        var cur: CheatEntry?, curOn = false, note: [String] = []
        var fence: (code: Bool, master: Bool, on: Bool)?
        var entries: [(CheatEntry, Bool, String)] = []
        var top: [CheatEntry] = []
        func close() {
            if let c = cur { entries.append((c, curOn, note.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))) }
            cur = nil; curOn = false; note = []
        }
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("```") {
                if let f = fence {
                    // another kind of block under a cheat is part of its note
                    if !f.code, cur != nil { note.append(raw) }
                    fence = nil; continue
                }
                let info = s.dropFirst(3).split(separator: " ").map { $0.lowercased() }
                let code = info.first == "dmnt"
                fence = (code, info.dropFirst().contains("master"), info.dropFirst().contains("on"))
                if !code, cur != nil { note.append(raw) }
                if code {
                    if cur != nil { if fence!.master { cur!.master = true }; if fence!.on { curOn = true } }
                    else { top.append(CheatEntry(name: "", master: true)) }
                }
                continue
            }
            if let f = fence {
                if f.code, !s.isEmpty {
                    if cur != nil { cur!.lines.append(s) } else if !top.isEmpty { top[top.count - 1].lines.append(s) }
                } else if !f.code, cur != nil { note.append(raw) }
                continue
            }
            if s.hasPrefix("## ") {
                close()
                cur = CheatEntry(name: String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                continue
            }
            if cur != nil { note.append(raw) }
        }
        close()
        d.entries = top.filter { !$0.lines.isEmpty } + entries.map(\.0)
        let keys = CheatFile.keys(d.entries)
        let offset = d.entries.count - entries.count
        for (i, (e, on, n)) in entries.enumerated() {
            let key = keys[offset + i]
            if on && !e.master { d.on.insert(key) }
            if !n.isEmpty { d.notes[key] = n }
        }
        return d
    }

    /// Which way one build's cheats go
    enum Direction: Equatable { case none, toFolder, fromFolder }

    /// `folderText`/`folderDate`: the Markdown file; `engine`: whether the engine's .txt is there and when it or its switches last
    /// changed; `written`: the Markdown NXForge would write from the engine's files now.
    static func direction(folderText: String?, folderDate: Date?, engine: Date?, written: String?) -> Direction {
        guard let folderText else { return engine == nil ? .none : .toFolder }
        guard let engine, let written else { return .fromFolder }
        if folderText == written { return .none }
        return (folderDate ?? .distantPast) > engine ? .fromFolder : .toFolder
    }

    private static func date(_ path: String) -> Date? { (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date }

    /// The builds with cheats in either place
    static func builds(folder: URL, engineDir: String) -> [String] {
        let fm = FileManager.default
        var out = Set(CheatSources.localBuilds(dir: engineDir))
        for n in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where n.hasSuffix(".md") && !n.hasPrefix(".") {
            let b = String(n.dropLast(3))
            if b.count == 16, b.allSatisfy(\.isHexDigit) { out.insert(b.uppercased()) }
        }
        return out.sorted()
    }

    /// Bring every build's cheats of one game into step between its folder and the engine's. Returns false when the folder could
    /// not be written (a read-only drive).
    @discardableResult
    static func sync(_ info: Info, folder: URL, engineDir: String) -> Bool {
        let fm = FileManager.default
        var ok = true
        for build in builds(folder: folder, engineDir: engineDir) {
            let md = file(folder, build: build)
            let txt = CheatFile.path(dir: engineDir, build: build), en = CheatFile.enabledPath(dir: engineDir, build: build)
            let folderText = try? String(contentsOf: md, encoding: .utf8)
            let engineDate = fm.fileExists(atPath: txt) ? [date(txt), date(en)].compactMap { $0 }.max() ?? .distantPast : nil
            let kept = folderText.map(parse)
            // the enhancements' codes (Enhancements.swift) stay in the engine's file only
            let all = CheatFile.load(dir: engineDir, build: build)
            let entries = Enhancements.strip(all), patches = all.filter { !entries.contains($0) }
            let written = engineDate == nil ? nil
                : document(info, build: build, entries: entries, on: CheatFile.enabled(dir: engineDir, build: build), notes: kept?.notes ?? [:])
            switch direction(folderText: folderText, folderDate: date(md.path), engine: engineDate, written: written) {
            case .none: break
            case .toFolder:
                // a build with no cheats left is not written (an emptied .txt does not make an empty file on the drive)
                guard let written, !entries.isEmpty || folderText != nil else { continue }
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data(written.utf8).write(to: md, options: .atomic)
                } catch { ok = false }
            case .fromFolder:
                guard let d = kept, d.build == nil || d.build == build else { continue }
                do {
                    try fm.createDirectory(atPath: engineDir, withIntermediateDirectories: true)
                    let text = CheatFile.text(Enhancements.strip(d.entries) + patches)
                    if (try? String(contentsOfFile: txt, encoding: .utf8)) != text {
                        // the engine's file as it was, once per change from the folder
                        if fm.fileExists(atPath: txt) { try? fm.removeItem(atPath: txt + ".before-markdown"); try? fm.copyItem(atPath: txt, toPath: txt + ".before-markdown") }
                        try text.write(toFile: txt, atomically: true, encoding: .utf8)
                    }
                    try CheatFile.setEnabled(d.on, order: CheatFile.keys(d.entries), dir: engineDir, build: build)
                    // the Markdown in NXForge's own words, its notes kept
                    let again = document(info, build: build, entries: d.entries, on: d.on, notes: d.notes)
                    if again != folderText { try? Data(again.utf8).write(to: md, options: .atomic) }
                } catch { ok = false }
            }
        }
        return ok
    }
}
