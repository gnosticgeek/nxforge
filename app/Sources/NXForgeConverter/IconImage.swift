// Game icons read from disk, kept while the file is unchanged: tiles and headers draw them on every redraw (a Library cover-size
// drag redraws every tile each step), and decoding the PNG each time was the cost. "Unchanged" is DecodedFile's key: the same
// path, modification date and size.
import AppKit

enum IconImage {
    @MainActor private static var cache: [String: (key: String, image: NSImage?)] = [:]

    @MainActor static func load(_ path: String) -> NSImage? {
        let key = DecodedFile<Data>.key(URL(fileURLWithPath: path)) ?? ""
        if let hit = cache[path], hit.key == key { return hit.image }
        let img = key.isEmpty ? nil : NSImage(contentsOfFile: path)
        cache[path] = (key, img)
        return img
    }
}
