// How Theatre's Showcase theme lays out your boxes (0.48.9): the same theme, the same games and the same game in focus,
// seen as a turning carousel or as a fan. Up and down on a controller switch between them.

/// Showcase's two ways of showing the boxes
enum ShowcaseLayout: String, Codable, CaseIterable {
    case carousel = "Carousel", fan = "Fan"

    var note: String {
        switch self {
        case .carousel: "A turning ring of your boxes"
        case .fan: "Your boxes fanned out like a hand of cards"
        }
    }

    var symbol: String {
        switch self {
        case .carousel: "rotate.3d"
        case .fan: "rectangle.stack"
        }
    }

    /// the other one (there are two, so a step either way lands on it)
    var other: ShowcaseLayout { self == .carousel ? .fan : .carousel }

    /// The layout an older saved theme stood for: Carousel, or Fan (and Fan's forerunners, Gallery and Shelf); nil for the others
    static func saved(theme s: String) -> ShowcaseLayout? {
        switch s {
        case "Carousel": .carousel
        case "Fan", "Gallery", "Shelf": .fan
        default: nil
        }
    }
}
