// The Shutter theme's shape (ShutterTheme), in 1080ths of the height: slanted panels side by side, the game in focus wide
// in the middle, its neighbours narrow either side, all leaning the same way like the blades of a shutter.
import CoreGraphics

enum ShutterLayout {
    /// the band of panels: its top below the top bar, and its height
    static let top: CGFloat = 116
    static let height: CGFloat = 700
    /// the panel in focus, a panel either side of it, and the dark gap between two
    static let wide: CGFloat = 812
    static let narrow: CGFloat = 276
    static let gap: CGFloat = 12
    /// how far a panel's top sits to the right of its foot, for each point of height
    static let lean: CGFloat = 0.28
    /// panels drawn either side of the middle; the outermost is out of sight, so a game wrapping round never crosses the screen
    static let reach = 3
    /// a list this long goes round in a loop with neighbours both sides; a shorter one stops at its ends
    static let loopFrom = 2 * reach + 1

    /// The panels drawn: each game's place in the list and its distance from the middle (negative to the left)
    static func places(index: Int, count: Int) -> [(game: Int, d: Int)] {
        guard count > 0, (0..<count).contains(index) else { return [] }
        if count >= loopFrom {
            return (-reach...reach).map { d in (((index + d) % count + count) % count, d) }
        }
        return (max(-index, -reach)...min(count - 1 - index, reach)).map { d in (index + d, d) }
    }

    /// a panel's width, by its distance from the middle
    static func width(_ d: Int) -> CGFloat { d == 0 ? wide : narrow }

    /// how far the middle of a panel is from the middle of the screen
    static func centre(_ d: Int) -> CGFloat {
        guard d != 0 else { return 0 }
        let out = wide / 2 + gap + narrow / 2 + CGFloat(abs(d) - 1) * (narrow + gap)
        return d < 0 ? -out : out
    }

    /// the outermost panels are drawn but not seen
    static func opacity(_ d: Int) -> Double { abs(d) < reach ? 1 : 0 }
}
