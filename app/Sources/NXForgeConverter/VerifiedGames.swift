// Games played on NXForge (docs/nxforge-games.tsv in the engine checkout):
// the Builds page shows a built game's row.
import Foundation

struct VerifiedGame: Hashable {
    var game: String
    var version: String
    var release: String
    var mac: String
    var date: String
    var result: String
    var note: String

    /// "Plays on 0.4.0 (4.0.1, M4 Pro, 2026-10-27)"
    var summary: String {
        let what = ["plays": "Plays", "boots": "Boots (not yet playable)", "broken": "Broken"][result] ?? result
        let v = version == "-" ? "" : "\(version), "
        return "\(what) on \(release) (\(v)\(mac), \(date))"
    }
}

enum VerifiedGames {
    static let file = "docs/nxforge-games.tsv"

    /// Rows by title ID (upper case); comment lines and the header are skipped, malformed rows ignored (CI checks the file).
    static func parse(_ text: String) -> [String: VerifiedGame] {
        var out: [String: VerifiedGame] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") && !line.hasPrefix("title_id\t") {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count == 8, c[0].count == 16 else { continue }
            out[c[0].uppercased()] = VerifiedGame(game: c[1], version: c[2], release: c[3], mac: c[4], date: c[5], result: c[6], note: c[7])
        }
        return out
    }

    static func load(_ repo: String?) -> [String: VerifiedGame] {
        guard let repo, let text = try? String(contentsOfFile: repo + "/" + file, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// The game's title ID from a built app's bundle ID (org.nxforge.<title ID>, the packer's), nil for anything else
    static func titleID(ofApp app: String) -> String? {
        guard let id = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String else { return nil }
        return titleID(bundleID: id)
    }

    static func titleID(bundleID id: String) -> String? {
        guard let t = id.split(separator: ".").last, t.count == 16, UInt64(t, radix: 16) != nil else { return nil }
        return t.uppercased()
    }
}
