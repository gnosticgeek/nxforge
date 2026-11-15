// Why a game closed before its first picture (Converter 0.14.0, from RetroReplay's LaunchDiagnosis): the end of the game's own log
// (~/Library/Logs/nxnative/<title ID>.log, written by its launcher and host) is read for the reason, so the launch screen can say
// what happened and offer the step that helps, instead of quietly going away. BuildDiagnosis does the same for builds.
import Foundation

struct LaunchFailure: Equatable {
    enum Fix: Equatable { case playOptions, rebuild, showLog }
    enum Code: String { case gpuMemory, memory, cannotStart, crashed, error, closed, didNotOpen }
    let code: Code
    /// one line: what happened
    let title: String
    /// what it means and what to do
    let detail: String
    /// the main step offered (Try Again and Show Log are always there)
    let fix: Fix?
    /// the game's own last red line, when it wrote one
    var line: String? = nil
    var log: String? = nil

    var fixLabel: String? {
        switch fix {
        case .playOptions: "Play Options"
        case .rebuild: "Rebuild"
        case .showLog, nil: nil
        }
    }
}

enum LaunchDiagnosis {
    static func logPath(titleID: String, home: String = NSHomeDirectory()) -> String { "\(home)/Library/Logs/nxnative/\(titleID).log" }

    /// The log's last 16 KB when it was written since `since` (a log from an earlier run says nothing about this one)
    static func freshTail(_ path: String, since: Date, fm: FileManager = .default) -> String? {
        guard let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, m >= since.addingTimeInterval(-2),
              let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > 16384 ? end - 16384 : 0)
        return (try? h.readToEnd()).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The last line marked [RED] (the engine's own word for an error), without its prefixes
    static func lastRedLine(_ tail: String) -> String? {
        guard let l = tail.split(separator: "\n").last(where: { $0.contains("[RED]") }) else { return nil }
        var s = String(l)
        if let r = s.range(of: "[RED]") { s = String(s[r.upperBound...]) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.count > 220 ? String(s.prefix(220)) + "…" : s
    }

    /// What the end of a log says about a game that closed while starting
    static func diagnose(_ tail: String?, log: String? = nil) -> LaunchFailure {
        guard let tail, !tail.isEmpty else {
            return LaunchFailure(code: .closed, title: "The game closed before it showed anything",
                                 detail: "It wrote no log this time, so it stopped very early. Try again; if it happens again, rebuild it.", fix: .rebuild, log: log)
        }
        let t = tail.lowercased(), red = lastRedLine(tail)
        if t.contains("gpu memory guard:") && t.contains("stopping the game") {
            return LaunchFailure(code: .gpuMemory, title: "Stopped before the Mac ran out of graphics memory",
                                 detail: "The game asked for more graphics memory than this Mac can give it. Lower Memory or the resolution in Play Options, or quit other large apps, and try again.",
                                 fix: .playOptions, line: red, log: log)
        }
        if t.contains("out of memory") || t.contains("the host stopped on signal 9\n") || t.hasSuffix("the host stopped on signal 9") {
            return LaunchFailure(code: .memory, title: "macOS stopped the game for using too much memory",
                                 detail: "Quit other large apps, or lower Memory in Play Options, and try again.", fix: .playOptions, line: red, log: log)
        }
        if let r = tail.range(of: "launcher: cannot start ", options: .backwards) {
            let what = tail[r.upperBound...].prefix { $0 != "\n" }
            return LaunchFailure(code: .cannotStart, title: "The game's engine could not start",
                                 detail: "The app is missing a part or was changed after it was built (\(what)). Rebuilding it puts it right.", fix: .rebuild, line: red, log: log)
        }
        if let sig = GameAttention.crashSignal(tail) {
            return LaunchFailure(code: .crashed, title: "The game crashed while starting (signal \(sig))",
                                 detail: red.map { "Its last error: \($0)" } ?? "Its log says where. If a newer NXForge is out, rebuilding may fix it.",
                                 fix: .showLog, line: red, log: log)
        }
        if let r = tail.range(of: "the host exited with ", options: .backwards), let code = Int(tail[r.upperBound...].prefix { $0.isNumber }), code != 0 {
            return LaunchFailure(code: .error, title: "The game stopped with an error (code \(code))",
                                 detail: red.map { "Its last error: \($0)" } ?? "Its log says why.", fix: .showLog, line: red, log: log)
        }
        return LaunchFailure(code: .closed, title: "The game closed before its first picture",
                             detail: red.map { "Its last error: \($0)" } ?? "It closed on its own without an error. Try again; its log has the details.",
                             fix: .showLog, line: red, log: log)
    }
}
