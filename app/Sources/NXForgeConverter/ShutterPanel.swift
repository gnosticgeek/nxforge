// One panel of the Shutter theme (ShutterTheme): the game's wide art cut to a slanted blade. The neighbours are a little
// darker with their names in italics at the foot; the one in focus is clear, its name below the band.
import SwiftUI

struct ShutterPanel: View {
    let game: StageGame
    let focused: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.tu) private var u

    var body: some View {
        let slant = ShutterLayout.lean * height
        ZStack(alignment: .bottomLeading) {
            if let art = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) ?? CoverArt.front(game) {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: width + slant, height: height).clipped()
            } else {
                CoverArt.tint(game)
            }
            if !focused {
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0.2), location: 0.55),
                                       .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
                Text(game.name)
                    .font(.system(size: 34 * u, weight: .heavy).width(.condensed))
                    .italic()
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.7), radius: 8 * u, y: 2 * u)
                    .frame(width: width - 44 * u, alignment: .leading)
                    .padding(.leading, 26 * u + slant * 0.12).padding(.bottom, 44 * u)
            }
        }
        .frame(width: width + slant, height: height)
        .clipShape(ShutterSlant(slant: slant))
        .contentShape(ShutterSlant(slant: slant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name + (focused ? ", selected" : ""))
        .accessibilityAddTraits(.isButton)
    }
}
