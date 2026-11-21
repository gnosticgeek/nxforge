// How Theatre's Showcase theme lays out your boxes (0.48.9): the same theme, the same games and the same game in focus,
// seen as a turning carousel, as a fan, or spine out along a shelf (0.51.0). Up and down on a controller step through them.

/// Showcase's ways of showing the boxes
enum ShowcaseLayout: String, Codable, CaseIterable {
    case carousel = "Carousel", fan = "Fan", shelf = "Shelf"

    var note: String {
        switch self {
        case .carousel: "A turning ring of your boxes"
        case .fan: "Your boxes fanned out like a hand of cards"
        case .shelf: "Your games spine out along a shelf"
        }
    }

    var symbol: String {
        switch self {
        case .carousel: "rotate.3d"
        case .fan: "rectangle.stack"
        case .shelf: "books.vertical"
        }
    }

    /// the next one round, or the one before
    func step(_ d: Int) -> ShowcaseLayout {
        let all = Self.allCases, i = all.firstIndex(of: self) ?? 0
        return all[((i + d) % all.count + all.count) % all.count]
    }

    /// The layout an older saved theme stood for: Carousel, or Fan (and Fan's forerunners, Gallery and the Shelf theme of 0.45,
    /// which was not this shelf); nil for the others
    static func saved(theme s: String) -> ShowcaseLayout? {
        switch s {
        case "Carousel": .carousel
        case "Fan", "Gallery", "Shelf": .fan
        default: nil
        }
    }
}
