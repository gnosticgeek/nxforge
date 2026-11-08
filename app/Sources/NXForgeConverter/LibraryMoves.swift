// Undo for the Library's tidying (idea 17): every move it makes (a game's files into a folder of their own, update and DLC files
// beside their game) is written to library-moves.log in Application Support and can be undone: the Undo button under the list,
// or Edit › Undo (⌘Z). Undo moves each file back and removes the folder a move made when it is empty again.
import AppKit
import Foundation

struct LibraryMove: Equatable {
    let label: String
    /// (from, to) per file, in the order they moved
    let files: [(from: String, to: String)]
    /// a folder the move made, removed again by Undo when nothing else is in it
    let madeFolder: String?
    let when = Date()
    static func == (a: LibraryMove, b: LibraryMove) -> Bool { a.when == b.when && a.label == b.label }
}

enum LibraryMoves {
    static var logFile: URL { Settings.supportDir.appending(path: "library-moves.log") }

    static func log(_ m: LibraryMove, undone: Bool = false) {
        let f = ISO8601DateFormatter()
        var text = "\(f.string(from: Date())) \(undone ? "undo" : "move"): \(m.label)\n"
        for x in m.files { text += undone ? "  \(x.to) -> \(x.from)\n" : "  \(x.from) -> \(x.to)\n" }
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logFile) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: logFile, atomically: true, encoding: .utf8) }
    }

    /// Moves each file back; a file that is no longer where it went, or whose old place is taken, is left and named.
    static func undo(_ m: LibraryMove) -> [String] {
        let fm = FileManager.default
        var problems: [String] = []
        for x in m.files.reversed() {
            guard fm.fileExists(atPath: x.to) else { problems.append("\(x.to.lastComponent) is no longer in \(x.to.url.deletingLastPathComponent().lastPathComponent)"); continue }
            guard !fm.fileExists(atPath: x.from) else { problems.append("\(x.from.lastComponent) is back already"); continue }
            do { try fm.moveItem(atPath: x.to, toPath: x.from) } catch { problems.append("\(x.to.lastComponent): \(error.localizedDescription)") }
        }
        if let d = m.madeFolder, ((try? fm.contentsOfDirectory(atPath: d)) ?? ["x"]).filter({ $0 != ".DS_Store" }).isEmpty {
            try? fm.removeItem(atPath: d)
        }
        log(m, undone: true)
        return problems
    }
}

extension AppModel {
    /// A move the Library made: logged, offered for Undo under the list and on Edit › Undo.
    func noteMove(_ m: LibraryMove) {
        LibraryMoves.log(m)
        lastMove = m
        if let um = NSApp.keyWindow?.undoManager {
            um.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { model.undoMove(m) } }
            um.setActionName(m.label)
        }
    }

    func undoMove(_ m: LibraryMove? = nil) {
        guard let m = m ?? lastMove, !run.running, !batchRunning else { return }
        let problems = LibraryMoves.undo(m)
        if lastMove == m { lastMove = nil }
        libraryMessage = problems.isEmpty ? nil : "Undo left some files: " + problems.joined(separator: "; ")
        scanLibrary()
    }
}

// MARK: game files on a drive or share that is not connected (idea 12)

extension AppModel {
    /// The volume a path is on when that volume is not mounted ("Gaming" for /Volumes/Gaming/roms/…), else nil.
    func offlineVolume(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        let vol = "/Volumes/\(parts[1])"
        return FileManager.default.fileExists(atPath: vol) ? nil : String(parts[1])
    }

    /// Notes each mounted network volume's address (the Library's games folder, the build records' game folders), so it can be
    /// mounted again from the converter while it is away.
    func learnRemounts() {
        let paths = ([settings.gamesRoot] + Engine.builds().map(\.gameDir)).compactMap { $0 }
        var seen = Set<String>(), found: [String: String] = [:]
        for p in paths {
            let parts = p.split(separator: "/")
            guard parts.count >= 2, parts[0] == "Volumes", seen.insert(String(parts[1])).inserted else { continue }
            let vol = URL(fileURLWithPath: "/Volumes/\(parts[1])")
            if let u = try? vol.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting { found[String(parts[1])] = u.absoluteString }
        }
        for (k, v) in found where settings.remounts[k] != v { settings.remounts[k] = v }
    }

    /// Mount a network volume again by the address noted while it was mounted (Finder asks for a password if it needs one).
    func mount(_ volume: String) -> Bool {
        guard let s = settings.remounts[volume], let u = URL(string: s) else { return false }
        NSWorkspace.shared.open(u)
        return true
    }

    /// A Rebuild whose game files are on a volume that is away: say so, and offer to mount it.
    func offlineGuard(_ gameDir: String) -> Bool {
        guard let vol = offlineVolume(gameDir) else { return true }
        let canMount = settings.remounts[vol] != nil
        if confirm("The game files are offline", "\(gameDir.tildePath) is on “\(vol)”, which is not connected. \(canMount ? "Mount it, then rebuild again once it shows in Finder." : "Connect it in Finder, then rebuild again.") If the files moved, use Locate Game Files… on the game's page.", action: canMount ? "Mount \(vol)" : "OK"), canMount {
            _ = mount(vol)
        }
        return false
    }

    /// The game files moved: point this build (and others from the same folder) at the new place.
    func locateGameFiles(_ b: BuildRecord) {
        guard let d = chooseGame(start: b.gameDir) else { return }
        for var r in Engine.builds() where r.gameDir == b.gameDir { r.gameDir = d; Engine.record(r) }
        revision += 1
    }
}
