// The build as one timeline: how long each stage should take (from this Mac's earlier builds), the time left for the
// whole build, and the bar that shows it. The script's own ETA covers only the stage it is in (the rate of its last
// minute), so the rest comes from history: the game's own <id>_build/logs/stage_times.json (the script writes how long
// each stage took the last time it did its work), else other games' recorded builds scaled by the size of the game files.
import Foundation
import SwiftUI

/// A stage's name without what varies from build to build: "extract v131072" → "extract" (the script's stage_key).
func stageKey(_ name: String) -> String {
    name.replacingOccurrences(of: #"\s+v\d+$"#, with: "", options: .regularExpression)
}

/// The order stages run in (prefixes of the script's stage names), for placing the ones still to come.
let stageOrder = ["decompress NSZ", "build ID lookup", "build nx_extract", "extract", "unpack", "pack", "unpack DLC", "pack DLC", "extract DLC",
                  "rewrite", "NRO capture", "GLSLC capture", "UE shader decode", "JIT capture", "heap check", "address regions",
                  "shader split", "Mac shaders", "Mac host", "Pipeline prebuild", "Pipeline archive", "Mac app"]

/// Where a stage sits in stageOrder (the longest matching prefix), or nil for one the list does not know.
func stageRank(_ name: String) -> Int? {
    let k = stageKey(name)
    var best: (Int, Int)?
    for (i, p) in stageOrder.enumerated() where k.hasPrefix(p) {
        if best == nil || p.count > best!.1 { best = (i, p.count) }
    }
    return best?.0
}

enum Estimates {
    /// How long each stage (by stageKey) should take for the game in this folder, in seconds; empty when nothing is known.
    static func expected(gameDir: String, gameBytes: Int64, builds: [BuildRecord]) -> [String: Double] {
        var out: [String: Double] = [:]
        // other games' builds, scaled by the game files' size: the median seconds per byte of each stage that did its work
        if gameBytes > 0 {
            var rates: [String: [Double]] = [:]
            for b in builds where b.gameDir != gameDir {
                guard let bytes = b.gameBytes, bytes > 0, let stages = b.stages else { continue }
                for s in stages where s.ok && !s.reused && s.seconds > 0 { rates[stageKey(s.name), default: []].append(Double(s.seconds) / Double(bytes)) }
            }
            for (k, r) in rates { out[k] = r.sorted()[r.count / 2] * Double(gameBytes) }
        }
        // this game's own last real times win
        for (k, v) in ownTimes(gameDir) { out[stageKey(k)] = v }
        return out
    }

    /// <game folder>/<id>_build/logs/stage_times.json
    static func ownTimes(_ gameDir: String) -> [String: Double] {
        let fm = FileManager.default
        guard let b = ((try? fm.contentsOfDirectory(atPath: gameDir)) ?? []).first(where: { $0.hasSuffix("_build") }),
              let d = try? Data(contentsOf: URL(fileURLWithPath: "\(gameDir)/\(b)/logs/stage_times.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    /// The game files' total size in bytes.
    static func gameBytes(_ dir: String) -> Int64 {
        GameFiles.list(in: dir.url).reduce(Int64(0)) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
    }

    /// The stages a build would run, in order, with their expected seconds: the ones history knows about.
    static func plan(_ expected: [String: Double]) -> [(name: String, seconds: Double)] {
        expected.map { (name: $0.key, seconds: $0.value) }.sorted { (stageRank($0.name) ?? 99) < (stageRank($1.name) ?? 99) }
    }
}

/// One piece of the timeline bar.
struct Segment: Identifiable, Hashable {
    enum State: Hashable { case done, reused, failed, running, pending }
    let id: Int
    let name: String
    let state: State
    /// seconds: actual for a finished stage, expected (or elapsed + left) for the running one, expected for one to come; nil = unknown
    let seconds: Double?
    /// how far through the running stage, 0…1
    var fraction: Double = 0
}

/// The whole build at a moment: the bar's pieces, the fraction done and the time left.
struct Overall {
    var segments: [Segment] = []
    var fraction: Double = 0
    /// seconds left for the whole build; nil while there is nothing to go on
    var remaining: Double?
    var elapsed: Double = 0
}

extension BuildRun {
    /// The timeline now: finished stages with their real times, the running one, and the ones history says come next.
    func overall(now: Date = Date()) -> Overall {
        var o = Overall()
        o.elapsed = startedAt.map { now.timeIntervalSince($0) } ?? 0
        var segs: [Segment] = done.map { s in
            Segment(id: s.k, name: s.name, state: !s.ok ? .failed : s.redo ? .pending : s.reused ? .reused : .done, seconds: Double(s.seconds))
        }
        guard running else {
            o.segments = segs
            if case .success? = result { o.fraction = 1 }
            else if !segs.isEmpty { o.fraction = Double(segs.count) / Double(max(done.last?.n ?? segs.count, segs.count)) }
            return o
        }
        var left: Double? = 0
        let k = max(stage.k, done.count + 1)
        if stage.k > 0, done.last?.k != stage.k {
            let inStage = stageStartedAt.map { now.timeIntervalSince($0) } ?? 0
            let exp = expected[stageKey(stage.name)]
            // the script's ETA (the rate of the last minute) when it has one, else what this stage took last time
            let rest: Double? = stage.eta ?? exp.map { max($0 - inStage, $0 * 0.1) }
            let frac = stage.fraction ?? (exp.map { min(inStage / max($0, 1), 0.95) } ?? 0)
            segs.append(Segment(id: stage.k, name: stage.name, state: .running, seconds: rest.map { inStage + $0 } ?? exp, fraction: frac))
            left = rest
        }
        // what comes next: the stages after this one that earlier builds ran, else unnamed places up to the planned count
        let rank = stageRank(stage.name) ?? -1
        let seen = Set((done.map(\.name) + [stage.name]).map(stageKey))
        let next = Estimates.plan(expected).filter { (stageRank($0.name) ?? 99) > rank && !seen.contains($0.name) }
        var id = k + 1
        if !next.isEmpty {
            for n in next { segs.append(Segment(id: id, name: n.name, state: .pending, seconds: n.seconds)); id += 1; left = left.map { $0 + n.seconds } }
        } else if stage.n > k {
            for _ in k..<stage.n { segs.append(Segment(id: id, name: "", state: .pending, seconds: nil)); id += 1 }
            left = nil
        }
        o.segments = segs
        o.remaining = left
        if let left, o.elapsed + left > 0 {
            o.fraction = min(o.elapsed / (o.elapsed + left), 0.99)
        } else {
            let n = Double(max(stage.n, 1))
            o.fraction = min((Double(max(stage.k - 1, 0)) + (stage.fraction ?? 0)) / n, 0.99)
        }
        return o
    }
}

/// "about 23 min left", "about 1 h 10 min left", "less than a minute left"
func timeLeft(_ s: Double) -> String {
    if s < 60 { return "Less than a minute left" }
    let m = Int((s / 60).rounded())
    return m < 60 ? "About \(m) min left" : "About \(m / 60) h \(m % 60) min left"
}

/// "47 min", "1 h 5 min", "35 s"
func duration(_ s: Double) -> String {
    if s < 60 { return "\(Int(s)) s" }
    let m = Int((s / 60).rounded())
    return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
}

/// The bar: one rounded piece per stage, its width the stage's share of the time; finished pieces solid, the running one
/// filling, the ones to come faint. Hovering a piece names its stage.
struct TimelineBar: View {
    let segments: [Segment]
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            let known = segments.compactMap(\.seconds).filter { $0 > 0 }
            let fill = known.isEmpty ? 1 : known.reduce(0, +) / Double(known.count)   // an unknown stage counts as an average one
            let weights = segments.map { max($0.seconds ?? fill, 0.001) }
            let total = weights.reduce(0, +)
            let gap: CGFloat = segments.count > 1 ? 3 : 0
            let width = max(g.size.width - gap * CGFloat(segments.count - 1), 1)
            // a floor so a two-second stage still shows as a sliver
            let floor = min(width * 0.015, width / CGFloat(max(segments.count, 1)))
            let raw = weights.map { max(CGFloat($0 / total) * width, floor) }
            let scale = width / max(raw.reduce(0, +), 1)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                    piece(s).frame(width: raw[i] * scale).help(tip(s))
                }
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
    }

    @ViewBuilder func piece(_ s: Segment) -> some View {
        switch s.state {
        case .done: Rectangle().fill(Color.green.gradient)
        case .reused: Rectangle().fill(Color.green.opacity(0.45).gradient)
        case .failed: Rectangle().fill(Color.red.gradient)
        case .pending: Rectangle().fill(.quaternary)
        case .running:
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.accentColor.opacity(0.22))
                    Rectangle().fill(Color.accentColor.gradient).frame(width: g.size.width * max(0.04, s.fraction))
                        .phaseAnimator([0.75, 1.0]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 1.1) }
                }
            }
        }
    }

    func tip(_ s: Segment) -> String {
        let name = s.name.isEmpty ? "A later step" : friendly(s.name)
        switch s.state {
        case .done: return "\(name): \(duration(s.seconds ?? 0))"
        case .reused: return "\(name): reused from the last build"
        case .failed: return "\(name): failed"
        case .running: return "\(name): running"
        case .pending: return s.seconds.map { "\(name): about \(duration($0)) last time" } ?? name
        }
    }
}
