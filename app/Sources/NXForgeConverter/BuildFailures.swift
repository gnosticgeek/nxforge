// A failed build, remembered per game (Converter 0.22.13). The Convert page shows a failure with its diagnosis and log while
// the converter is open; once it quits (an update, a restart) that was gone, and the game read "Not built yet" with nothing
// to say a build had been tried and why it stopped (Switch Sports, 2026-11-21). The last failure of each game folder is kept in
// Application Support/failed-builds.json until a build of it succeeds, and the game shows "Build failed" with the reason.
import Foundation

struct FailedBuild: Codable, Equatable {
    /// the diagnosis in plain words (Diagnosis.title)
    var title: String
    /// what to do next (Diagnosis.fix)
    var fix: String
    /// the script's error, as the Convert page showed it
    var error: String
    var at: Date
    /// the build's converter log, when one was written
    var log: String?
}

enum BuildFailures {
    static var file: URL { Settings.supportDir.appending(path: "failed-builds.json") }

    /// game folder (Source.folder) → its last failed build
    static func load() -> [String: FailedBuild] {
        guard let d = try? Data(contentsOf: file) else { return [:] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: FailedBuild].self, from: d)) ?? [:]
    }

    private static func save(_ all: [String: FailedBuild]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? enc.encode(all) { try? d.write(to: file, options: .atomic) }
    }

    static func record(_ f: FailedBuild, folder: String) { var all = load(); all[folder] = f; save(all) }

    static func clear(folder: String) {
        var all = load()
        guard all.removeValue(forKey: folder) != nil else { return }
        save(all)
    }
}
