// Finding a game by what is typed (Converter 0.14.0, from RetroReplay's TitleMatch and TypeSelect): case, accents and width are
// folded, so "pokemon" finds "Pokémon" and "zelda" finds "ZELDA"; words match in any order; a title that starts with what is
// typed ranks above one with a later word that does, which ranks above one that only contains it, and a leading "The" is passed
// over. Ties go to the game played last. TypeSelect is Finder's: letters typed in quick succession jump to the first title
// starting with them.
import Foundation

enum TitleMatch {
    /// Case, accent and width folded, punctuation as spaces: "Pokémon™ Legends: Z-A" → "pokemon legends z a"
    static func fold(_ s: String) -> String {
        let f = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let mapped = f.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// The title without a leading "The " (and the folding above)
    static func key(_ title: String) -> String {
        let f = fold(title)
        return f.hasPrefix("the ") ? String(f.dropFirst(4)) : f
    }

    /// Whether every word typed is in one of the texts
    static func matches(_ query: String, _ texts: [String?]) -> Bool {
        let words = fold(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let hay = texts.compactMap { $0 }.map(fold).joined(separator: " ")
        return words.allSatisfy { hay.contains($0) }
    }

    /// How well a title answers a query: 0 its start, 1 the start of a later word, 2 anywhere, nil not at all
    static func rank(_ query: String, title: String) -> Int? {
        let q = fold(query)
        guard !q.isEmpty else { return 0 }
        let t = key(title), whole = fold(title)
        if t.hasPrefix(q) || whole.hasPrefix(q) { return 0 }
        if (" " + whole).contains(" " + q) { return 1 }
        if whole.contains(q) { return 2 }
        // the words in another order
        return q.split(separator: " ").allSatisfy { whole.contains($0) } ? 2 : nil
    }

    /// Items in Quick Open's order: better matches first, then the most recently played, then by title.
    static func sorted<T>(_ items: [T], query: String, title: (T) -> String, last: (T) -> Date?) -> [T] {
        items.map { (item: $0, rank: rank(query, title: title($0)) ?? 3) }
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                let la = last(a.item) ?? .distantPast, lb = last(b.item) ?? .distantPast
                if la != lb { return la > lb }
                return title(a.item).localizedStandardCompare(title(b.item)) == .orderedAscending
            }
            .map { $0.item }
    }
}

/// Finder's type-to-select: letters typed within a second of each other build a prefix
struct TypeSelectBuffer {
    static let pause: TimeInterval = 1.0
    private(set) var text = ""
    private var lastKey: Date = .distantPast

    /// Adds a typed character and returns the prefix so far
    mutating func type(_ c: Character, at now: Date = Date()) -> String {
        if now.timeIntervalSince(lastKey) > Self.pause { text = "" }
        lastKey = now
        text.append(c)
        return text
    }

    /// Whether a prefix is being typed (a space then continues it)
    func active(at now: Date = Date()) -> Bool { !text.isEmpty && now.timeIntervalSince(lastKey) <= Self.pause }

    /// The first title, in the order shown, that starts with the prefix
    static func first<T>(_ items: [T], prefix: String, title: (T) -> String) -> T? {
        let p = TitleMatch.fold(prefix)
        guard !p.isEmpty else { return nil }
        return items.first { TitleMatch.key(title($0)).hasPrefix(p) } ?? items.first { TitleMatch.fold(title($0)).hasPrefix(p) }
    }
}
