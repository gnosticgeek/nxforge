// The optional tools a particular game needs: nsz for compressed files, zbic for code compressed the system 22 way
// (Switch 2 games and newer Switch games), glslang for an OpenGL game. The Toolchain page lists them as optional, since
// most games never need them; for a game that does, the converter treats them as required and offers to install them
// before the build starts instead of the build failing halfway.
import Foundation

enum GameNeeds {
    /// The base game's title ID for a game folder: the build folder's name (<id>_build), else the first [0100…] in a file name,
    /// with its last three digits zeroed (an update ends in 800, a DLC in its index).
    static func titleID(_ dir: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        if let b = names.first(where: { $0.hasSuffix("_build") }), b.count == 22 { return String(b.prefix(16)).uppercased() }
        for n in names.sorted() {
            guard let r = n.range(of: #"\[[0-9A-Fa-f]{16}\]"#, options: .regularExpression) else { continue }
            let id = n[r].dropFirst().dropLast()
            return String(id.prefix(13)).uppercased() + "000"
        }
        return nil
    }

    /// Check name → why this game needs it.
    static func detect(dir: String, repo: String?) -> [String: String] {
        var out: [String: String] = [:]
        let files = GameFiles.list(in: dir.url)
        if files.contains(where: { ["nsz", "xcz"].contains($0.pathExtension.lowercased()) }) {
            out["nsz"] = "this folder has compressed .nsz or .xcz files"
        }
        let id = titleID(dir)
        let profile = (repo != nil && id != nil) ? Layer.file(repo!, "dm/games/\(id!)") : nil
        let tsv = profile.flatMap { try? String(contentsOfFile: $0 + "/game.tsv", encoding: .utf8) } ?? ""
        if id?.hasPrefix("04") == true {
            out["zbic"] = "Switch 2 games are built with system 22 or later, whose code is ZBIC-compressed"
        } else if let m = tsv.range(of: #"SDK (\d+)\."#, options: .regularExpression),
                  let sdk = Int(tsv[m].dropFirst(4).prefix { $0.isNumber }), sdk >= 22 {
            out["zbic"] = "its profile says SDK \(sdk): code built with system 22 or later is ZBIC-compressed"
        }
        if let profile, FileManager.default.fileExists(atPath: profile + "/gl_capture.tsv") || tsv.contains("OpenGL") {
            out["glslang"] = "it is an OpenGL game: glslang compiles its GLSL shaders"
        }
        return out
    }
}
