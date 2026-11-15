// A file's decoded contents, kept while the file is unchanged: builds.json and playtime.json are read by pages and menus on every
// redraw (several times per redraw), and decoding them each time was most of the cost. "Unchanged" is the same path, modification
// date and size; the converter's own writes also drop the copy (drop()).
import Foundation

final class DecodedFile<Value>: @unchecked Sendable {   // @unchecked: every access to `kept` holds `lock`
    private var kept: (key: String, value: Value)?
    private let lock = NSLock()

    /// The decoded value, or nil when the file cannot be read or decoded (nothing is kept then: the next call tries again).
    func value(_ url: URL, decode: (Data) -> Value?) -> Value? {
        guard let key = Self.key(url) else { return nil }
        lock.lock(); let hit = kept; lock.unlock()
        if let hit, hit.key == key { return hit.value }
        guard let data = try? Data(contentsOf: url), let v = decode(data) else { return nil }
        lock.lock(); kept = (key, v); lock.unlock()
        return v
    }

    func drop() {
        lock.lock(); kept = nil; lock.unlock()
    }

    static func key(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return "\(url.path)\n\((a[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0)\n\((a[.size] as? NSNumber)?.int64Value ?? -1)"
    }
}
