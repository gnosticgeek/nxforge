// Disk space: what a build needs before it starts, a watch while it runs that stops it cleanly before a volume fills up
// (a stopped build keeps its finished stages, so building again carries on), and the sizes the Storage page lists.
import Foundation

enum Disk {
    /// The shared Metal compile cache (dmsh_mtlcache.py), one file for every game, and the folder it lives in.
    static let cacheDir = NSHomeDirectory() + "/Library/Caches/NXForge"
    static let metalCache = cacheDir + "/metallib.db"
    /// dmsh_mtlcache.py's size limit (DMSH_MTLCACHE_GB, default 12)
    static let metalCacheLimit: Int64 = 12 << 30

    /// Free space for important use on the volume of a path (what Finder shows), nil when it cannot be read.
    static func free(_ path: String) -> Int64? {
        try? path.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    static func volumeName(_ path: String) -> String {
        (try? path.url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "the disk"
    }

    static func volumeID(_ path: String) -> String {
        ((try? path.url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier).map { "\($0)" }) ?? path
    }

    /// Bytes a file or folder takes on disk (allocated, so APFS clones and sparse files count as they use space).
    static func size(_ path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        if !isDir.boolValue {
            let v = try? path.url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = fm.enumerator(at: path.url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: Set(keys))
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func gb(_ b: Int64) -> String {
        let g = Double(b) / 1e9
        return g < 10 ? String(format: "%.1f GB", g) : String(format: "%.0f GB", g)
    }

    /// What a build of this folder needs, against what is free, worked out off the main thread (it measures the last app).
    struct Need: Hashable {
        var free: Int64
        var need: Int64
        var rebuild: Bool
        var volume: String
        var short: Bool { free < need }
        var text: String {
            short ? "Only \(Disk.gb(free)) free on \(volume): \(rebuild ? "a rebuild" : "a first build") needs about \(Disk.gb(need))"
                  : "\(Disk.gb(free)) free · \(rebuild ? "a rebuild" : "a first build") needs about \(Disk.gb(need))"
        }
    }

    /// A first build: about twice the game files plus 10 GB (the extract, the shaders and the app, as the README says).
    /// A rebuild: room for a second copy of the app (the old one stays until the new one is complete) and the shader cache's
    /// growth. Either way plus what the shared Metal cache may still grow by, when it is on the same volume.
    /// firstBuild: a Switch 2 game's own first-build need (Source.firstBuildBytes); gameBytes: the game files' size.
    static func need(gameDir: String, outDir: String?, app: String?, firstBuild: Int64? = nil, gameBytes: Int64? = nil) -> Need? {
        guard let free = free(gameDir) else { return nil }
        let cached = ((try? FileManager.default.contentsOfDirectory(atPath: gameDir)) ?? []).contains { $0.hasSuffix("_build") }
        let bytes = gameBytes ?? Estimates.gameBytes(gameDir)
        var need: Int64 = cached ? (app.map(size) ?? bytes) + (firstBuild != nil ? 10 << 30 : 4 << 30) : firstBuild ?? bytes * 2 + (10 << 30)
        if volumeID(cacheDir) == volumeID(gameDir) { need += max(0, metalCacheLimit - size(metalCache)) }
        return Need(free: free, need: need, rebuild: cached, volume: volumeName(gameDir))
    }

    /// While a build runs: below `stopBelow` on a volume the build writes to, it is stopped at once (the stage in progress is
    /// lost, the finished ones are kept); below `warnBelow` the window warns.
    static let stopBelow: Int64 = 3 << 30
    static let warnBelow: Int64 = 12 << 30

    /// The volumes a build writes to: the game folder's (the build cache and, by default, the app), the output folder's and
    /// the home folder's (the shared Metal cache and the script's temporary files there).
    static func watched(gameDir: String, outDir: String?) -> [String] {
        var seen = Set<String>()
        return [gameDir, outDir, NSHomeDirectory()].compactMap { $0 }.filter { seen.insert(volumeID($0)).inserted }
    }

    /// The lowest free space among the watched volumes: (path, bytes free).
    static func lowest(_ paths: [String]) -> (path: String, free: Int64)? {
        paths.compactMap { p in free(p).map { (p, $0) } }.min { $0.1 < $1.1 }
    }
}
