// Making room while a build runs. Before, a build was stopped once a disk it writes to dropped under 3 GB, and the step in
// progress was lost (a shader step: up to an hour). Now, when free space gets low the converter first deletes what NXForge
// can make again without a build, and if a disk still falls under 3 GB it pauses the build (every process of it stopped
// where it stands, SIGSTOP) instead of ending it: it carries on by itself once there is room again, and Stop still works.
// What goes, in this order, and nothing else: temporary files of other games' stopped builds (~/Library/Caches/NXForge/
// scratch, not the running game's); the copies of pipeline archives kept on the Mac for games on other drives (LocalShaders:
// the next Play copies one again, a few seconds), except a running game's; and through `nxforge clean` the safe categories
// that do not wait for builds: older app copies (the newest per game and anything under three days stay), logs over 30 days
// old and Metal's idle pipeline-archive folders. Build caches, the shared Metal cache, apps, saves and game files stay.
import Foundation

enum MakeRoom {
    struct Result {
        var freed: Int64
        var what: [String]
        var line: String {
            what.isEmpty ? "Low on space: nothing more could be cleared without touching builds or game files."
                : "Low on space: cleared \(Disk.gb(freed)) (\(what.joined(separator: ", ")))."
        }
    }

    /// Clear what can go. building: the folder of the game being built (its scratch stays); playing: apps running now (their
    /// pipeline copies stay); env: the engine checkout and its Python, for `nxforge clean`. Slow: off the main thread.
    static func run(building: String, playing: Set<String>, env: ToolEnv?, watch: [String]) -> Result {
        let before = watch.compactMap(Disk.free).reduce(0, +)
        var what: [String] = []
        let fm = FileManager.default
        // scratch of other games' builds that did not finish (each build empties its own when it starts)
        let mine = GameNeeds.titleID(building)
        let scratch = Disk.cacheDir + "/scratch"
        var n = 0
        for id in (try? fm.contentsOfDirectory(atPath: scratch)) ?? [] where id != mine && !id.hasPrefix(".") {
            let p = scratch + "/" + id
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m > Date().addingTimeInterval(-600) { continue }   // another build may be using it
            if (try? fm.removeItem(atPath: p)) != nil { n += 1 }
        }
        if n > 0 { what.append("temporary files of \(n) stopped build\(n == 1 ? "" : "s")") }
        // pipeline copies of games not running now
        n = 0
        for d in (try? fm.contentsOfDirectory(at: LocalShaders.root, includingPropertiesForKeys: nil)) ?? [] where d.hasDirectoryPath {
            let first = (try? String(contentsOf: d.appending(path: "copy.txt"), encoding: .utf8))?.split(separator: "\n").first.map(String.init)
            guard let first, first.hasPrefix("app\t") else { continue }   // being made now
            if playing.contains(String(first.dropFirst(4)).url.standardizedFileURL.path) { continue }
            if (try? fm.removeItem(at: d)) != nil { n += 1 }
        }
        if n > 0 { what.append("\(n) pipeline cop\(n == 1 ? "y" : "ies") on the Mac, made again at the next Play") }
        // the safe categories that run beside a build
        if let repo = env?.repo, let py = env?.python, fm.fileExists(atPath: repo + "/scripts/nxforge.py") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = [repo + "/scripts/nxforge.py", "--json", "clean", "--only", "app-backups,old-logs,gpuarchiver"]
            p.standardOutput = Pipe(); p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            var penv = ProcessInfo.processInfo.environment
            if let path = env?.path, !path.isEmpty { penv["PATH"] = path }
            p.environment = penv
            if (try? p.run()) != nil {
                let data = (p.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                p.waitUntilExit()
                if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cats = j["categories"] as? [String: [String: Any]] {
                    let names = ["app-backups": "older app copies", "old-logs": "old logs", "gpuarchiver": "Metal's idle archive folders"]
                    for (c, r) in cats.sorted(by: { $0.key < $1.key }) {
                        let items = (r["items"] as? [[String: Any]] ?? []).filter { ($0["deleted"] as? Bool) == true }
                        if !items.isEmpty, let name = names[c] { what.append(name) }
                    }
                }
            }
        }
        let after = watch.compactMap(Disk.free).reduce(0, +)
        return Result(freed: max(after - before, 0), what: what)
    }
}
