// Frame-time recordings of a built game (Quick settings › Performance › Record frame times in the game). The host writes its per-frame
// timing rows (DM_NVN_TSV, timing rows only) to a new file per launch: the game folder's "Frame times" (the folder holding the .app,
// as dm/mac/launcher.c picks it), else ~/Library/Application Support/nxnative/<title ID>/frame-times. The Builds page sums the newest
// one up, counted as scripts/bench.py counts (nearest-rank percentiles), so a stutter can be seen without the command line.
// After NX2Apple's FrameTimes.swift (MIT).
import Foundation

enum FrameTimes {
    /// One frame's timing rows: @t_s (seconds from the start), @frame_ms (start to start), @presented_ms (on screen; -1 when the
    /// frame was never shown), @gpu_ms.
    struct Frame: Equatable {
        var number: Int
        var time: Double
        var frameMs: Double
        var presentedMs: Double?
        var gpuMs: Double?
    }

    /// The frames of a recording that have a time and a frame time, in frame order; other rows (call counts, a line the host is
    /// still writing) are skipped.
    static func parse(_ text: String) -> [Frame] {
        var rows: [Int: [String: Double]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count == 3, c[1].hasPrefix("@"), let n = Int(c[0].trimmingCharacters(in: .whitespaces)),
                  let v = Double(c[2].trimmingCharacters(in: .whitespaces)) else { continue }
            rows[n, default: [:]][String(c[1])] = v
        }
        return rows.keys.sorted().compactMap { n in
            let r = rows[n]!
            guard let t = r["@t_s"], let f = r["@frame_ms"] else { return nil }
            return Frame(number: n, time: t, frameMs: f, presentedMs: r["@presented_ms"], gpuMs: r["@gpu_ms"])
        }
    }

    /// Nearest-rank percentile, as scripts/bench.py's pct.
    static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, Int((p / 100 * Double(s.count)).rounded(.up)) - 1))]
    }

    struct Summary: Equatable {
        static let hitchMs = 50.0   // a frame this long is felt as a hitch
        var frames, dropped, hitches: Int
        var seconds, frameP50, frameP99, frameMax: Double
        var fps: Double { seconds > 0 ? Double(frames) / seconds : 0 }

        init?(_ frames: [Frame]) {
            let ft = frames.map(\.frameMs).filter { $0 > 0 }
            guard let first = frames.first, let last = frames.last, !ft.isEmpty else { return nil }
            self.frames = frames.count
            dropped = frames.filter { $0.presentedMs == -1 }.count
            hitches = ft.filter { $0 > Self.hitchMs }.count
            seconds = last.time - first.time
            frameP50 = FrameTimes.percentile(ft, 50)!
            frameP99 = FrameTimes.percentile(ft, 99)!
            frameMax = ft.max()!
        }

        /// "59.9 fps · 16.7 ms median, 18.2 ms p99 · 3 hitches · 0 dropped · 4 min"
        var line: String {
            let mins = seconds >= 90 ? "\(Int((seconds / 60).rounded())) min" : "\(Int(seconds.rounded())) s"
            return String(format: "%.1f fps · %.1f ms median, %.1f ms p99 · ", fps, frameP50, frameP99)
                + "\(hitches) hitch\(hitches == 1 ? "" : "es") · \(dropped) dropped · \(mins)"
        }
    }

    /// Where a built app's recordings can be: its game folder's "Frame times" (unless the app sits in /Applications or
    /// ~/Applications, which launcher.c does not use as a game folder), then the Library folder of its title ID.
    static func folders(app: String, titleID: String?) -> [URL] {
        let folder = URL(fileURLWithPath: app).deletingLastPathComponent()
        let home = NSHomeDirectory()
        var out: [URL] = []
        if folder.path != "/Applications" && folder.path != home + "/Applications" { out.append(folder.appending(path: "Frame times")) }
        if let t = titleID { out.append(URL(fileURLWithPath: home).appending(path: "Library/Application Support/nxnative/\(t)/frame-times")) }
        return out
    }

    /// The newest recording of a built app, if any (by modification date across its folders).
    static func newest(app: String, titleID: String?) -> URL? {
        let fm = FileManager.default
        let files = folders(app: app, titleID: titleID).flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "tsv" }
        }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return files.max { date($0) < date($1) }
    }

    private static var cache: [String: (date: Date, summary: Summary?)] = [:]   // path → its summary at that modification date
    /// The newest recording and its summary; nil when there is none or it holds no frames. A recording is read once per change
    /// (a long session's file is several MB), since the Builds page asks on every redraw.
    static func latest(app: String, titleID: String?) -> (file: URL, summary: Summary)? {
        guard let f = newest(app: app, titleID: titleID) else { return nil }
        let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let c = cache[f.path], c.date == date { return c.summary.map { (f, $0) } }
        let s = (try? String(contentsOf: f, encoding: .utf8)).flatMap { Summary(parse($0)) }
        cache[f.path] = (date, s)
        return s.map { (f, $0) }
    }
}
