// The game to convert, in any of the forms the script takes: a folder of NSP / XCI files (read with prod.keys), or a game it needs no
// keys for, the way Switch 2 games come: a NUP container (a .nup file, or a folder holding one and no game package) or a dump folder
// (scripts/pack_dump.py's layout). Settings.gameDir holds the path as chosen: a folder, or the .nup file itself. The build folder
// (<title ID>_build) and the app go in the folder that holds the game's files, as the script puts them.
import Foundation

enum SourceKind: String, Decodable { case packages, nup, dump }

/// scripts/source_info.py's description of a NUP or a dump folder.
struct SourceInfo: Decodable, Hashable {
    var kind: SourceKind
    var source: String
    var folder: String
    var titleID: String
    var name: String
    var base: Bool
    var updates: [Int]
    var dlc: Int
    var romfsBytes: Int64
    var fileBytes: Int64
    var zbic: Bool
    var zbicInstalled: Bool
    var profile: String?
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case kind, source, folder, name, base, updates, dlc, zbic, profile, notes
        case titleID = "title_id", romfsBytes = "romfs_bytes", fileBytes = "file_bytes", zbicInstalled = "zbic_installed"
    }

    /// "a NUP container" / "a dump folder"
    var form: String { kind == .nup ? "NUP container" : "dump folder" }

    /// "Base game + update + 2 DLC", as Engine.describeFiles names a folder of NSPs
    var describe: String {
        var parts = [base ? "Base game" : "Update as the whole game"]
        if base && !updates.isEmpty { parts.append("update") }
        if dlc > 0 { parts.append("\(dlc) DLC") }
        return parts.joined(separator: " + ")
    }
}

enum Source {
    static let helper = "scripts/source_info.py"

    static func isDir(_ p: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue
    }

    static func isNupFile(_ p: String) -> Bool { p.url.pathExtension.lowercased() == "nup" && !isDir(p) }

    /// The folder holding the game's files: where <title ID>_build, the lock and the app go.
    static func folder(of p: String) -> String { isDir(p) ? p : p.url.deletingLastPathComponent().path }

    /// What the path is, from the file system alone, the way the script decides: game packages in a folder win over a .nup or a dump
    /// layout beside them.
    static func kind(of p: String) -> SourceKind {
        if !isDir(p) { return isNupFile(p) ? .nup : .packages }
        if !GameFiles.list(in: p.url).isEmpty { return .packages }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: p)) ?? []
        if names.contains(where: { $0.lowercased().hasSuffix(".nup") }) { return .nup }
        let fm = FileManager.default
        let code = { (d: String) in fm.fileExists(atPath: "\(p)/\(d)exefs/main.npdm") }
        let updates = ((try? fm.contentsOfDirectory(atPath: p + "/updates")) ?? []).filter { Int($0) != nil }
        if code("base/") || code("") || updates.contains(where: { code("updates/\($0)/") }) { return .dump }
        return .packages
    }

    static func needsKeys(_ p: String) -> Bool { kind(of: p) == .packages }

    /// The game's description from scripts/source_info.py, run with the script's Python.
    static func read(_ p: String, env: ToolEnv) -> Result<SourceInfo, ConverterError> {
        guard let repo = env.repo, let py = env.python else { return .failure(ConverterError("no engine checkout or Python yet: see Toolchain")) }
        guard FileManager.default.fileExists(atPath: repo + "/" + helper) else {
            return .failure(ConverterError("this engine has no \(helper): update the engine to build a .nup or a dump folder"))
        }
        guard let r = run(py, ["-u", repo + "/" + helper, p], env: ["PATH": env.path], cwd: repo) else { return .failure(ConverterError("cannot start \(py)")) }
        let data = Data(r.out.split(separator: "\n").last.map(String.init)?.utf8 ?? "".utf8)
        if let e = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String { return .failure(ConverterError(e)) }
        guard r.ok, let info = try? JSONDecoder().decode(SourceInfo.self, from: data) else {
            return .failure(ConverterError("\(helper) failed: \(r.out.split(separator: "\n").last ?? "no output")"))
        }
        return .success(info)
    }

    /// The check the Convert page shows: prod.keys against the packages, or the NUP or dump read by the engine.
    static func validate(_ p: String, keys: String?, env: ToolEnv?) -> (Validation, SourceInfo?) {
        if needsKeys(p) {
            guard let keys else { return (Validation(ok: false, keysSummary: "", summary: [CheckLine(ok: false, text: "choose the keys file (prod.keys)")], files: []), nil) }
            return (GameFiles.validate(dir: p.url, keysURL: keys.url), nil)
        }
        guard let env else { return (Validation(ok: false, keysSummary: "", summary: [CheckLine(ok: false, text: "the toolchain check has not finished")], files: []), nil) }
        switch read(p, env: env) {
        case .failure(let e):
            return (Validation(ok: false, keysSummary: "", summary: [CheckLine(ok: false, text: e.description)], files: []), nil)
        case .success(let i):
            return (validation(i), i)
        }
    }

    static func validation(_ i: SourceInfo) -> Validation {
        var s = [CheckLine(ok: true, text: "\(i.form): game \(i.titleID), no keys needed")]
        if let pr = i.profile { s.append(CheckLine(ok: true, text: "NXForge profile: \(pr)")) }
        else { s.append(CheckLine(ok: false, text: "no NXForge profile for \(i.titleID): the build guesses one, and the game may not start", warn: true)) }
        let zbicOK = !i.zbic || i.zbicInstalled
        if i.zbic {
            s.append(CheckLine(ok: zbicOK, text: zbicOK ? "code is ZBIC-compressed (system 22 or later): zbic is installed"
                                                       : "the game's code is ZBIC-compressed (system 22 or later): install zbic (Toolchain, Newer Switch 2 game code)"))
        }
        s += i.notes.map { CheckLine(ok: false, text: $0, warn: true) }
        let file = i.kind == .nup ? i.source.lastComponent : i.folder.lastComponent
        var files: [FileReport] = []
        if i.base { files.append(FileReport(name: "Base game", role: "Base game", ok: true, lines: [CheckLine(ok: true, text: file)])) }
        for v in i.updates {
            files.append(FileReport(name: "Update v\(v)", role: i.base ? "Update v\(v)" : "Update v\(v) (whole game)", ok: true, lines: [CheckLine(ok: true, text: file)]))
        }
        if i.dlc > 0 { files.append(FileReport(name: "DLC", role: "\(i.dlc) DLC", ok: true, lines: [CheckLine(ok: true, text: file)])) }
        return Validation(ok: zbicOK, keysSummary: "no keys needed", summary: s, files: files)
    }

    /// Free space a first build needs: the newest version's RomFS is unpacked into one image and then cloned into the app, with the
    /// shader cache and the pipeline archive beside it (Ocarina of Time, a 26 GB .nup: about 76 GB at its peak, 35 GB of app).
    static func firstBuildBytes(_ i: SourceInfo) -> Int64 { max(i.romfsBytes, i.fileBytes) * 2 + (Int64(20) << 30) }
}
