// Game files dropped on the Convert page (after NX2Apple's DropFiles.swift, MIT): a game folder, NSP / XCI / NSZ / XCZ files and a
// keys file, in any mix. A folder is the game folder; game files make their folder the game folder; a .keys file is the keys file.
import Foundation

enum DropFiles {
    struct Sorted: Equatable {
        var gameDir: String?
        var keys: String?
        var usable: Bool { gameDir != nil || keys != nil }
    }

    /// What a drop sets. `isDir` says whether a path is a folder (the file system, or a stand-in in the tests). A folder wins over the
    /// folder of dropped game files; of several keys files prod.keys wins.
    static func sort(_ paths: [String], isDir: (String) -> Bool) -> Sorted {
        var out = Sorted()
        let url = { (p: String) in URL(fileURLWithPath: p) }
        out.gameDir = paths.first(where: isDir)
            ?? paths.first { gameExtensions.contains(url($0).pathExtension.lowercased()) }.map { url($0).deletingLastPathComponent().path }
        let keys = paths.filter { !isDir($0) && url($0).pathExtension.lowercased() == "keys" }
        out.keys = keys.first { url($0).lastPathComponent.lowercased() == "prod.keys" } ?? keys.first
        return out
    }

    static func sort(_ urls: [URL]) -> Sorted {
        sort(urls.map(\.path)) { p in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
    }
}
