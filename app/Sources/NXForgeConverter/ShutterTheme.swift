// Theatre's Shutter theme (0.48.10, to Tom's mock-up): the games' wide art as slanted panels side by side, like the blades
// of a shutter. The game in focus is the wide panel in the middle with an accent bar under it; its neighbours are narrow,
// named in italics. Left and right slide the panels along (the list goes round once it is long enough); a click on a panel
// brings it to the middle. The name, what the game is and the buttons sit below the band.
import SwiftUI

struct ShutterTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        let tint = focus.map { CoverArt.tint($0) } ?? ShutterLook.accent
        ZStack(alignment: .top) {
            ShutterLook.room.ignoresSafeArea()
            // a breath of the game's colour from the top, so the room still follows the game
            LinearGradient(colors: [tint.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea().allowsHitTesting(false)
                .animation(TheatreMotion.swapAnimation, value: focus?.id)
            GeometryReader { geo in
                let h = ShutterLayout.height * u, top = ShutterLayout.top * u, mid = geo.size.width / 2
                ZStack {
                    ForEach(ShutterLayout.places(index: index, count: games.count), id: \.game) { p in
                        let g = games[p.game], w = ShutterLayout.width(p.d) * u
                        ShutterPanel(game: g, focused: p.d == 0, width: w, height: h)
                            .opacity(ShutterLayout.opacity(p.d))
                            .position(x: mid + ShutterLayout.centre(p.d) * u, y: top + h / 2)
                            .zIndex(-Double(abs(p.d)))
                            .onTapGesture { model.theatreFocus = g.id; model.theatreTouched = Date() }
                            .help(TheatreDetails.line(model, g))
                    }
                    // the accent bar along the foot of the panel in focus (its foot starts at the slant's left)
                    if focus != nil {
                        let w = ShutterLayout.wide * u, slant = ShutterLayout.lean * h
                        Rectangle().fill(ShutterLook.accent)
                            .frame(width: w, height: 7 * u)
                            .position(x: mid - slant / 2, y: top + h + 3.5 * u)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(still ? nil : .spring(duration: 0.45, bounce: 0.12), value: index)
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                ShutterTopBar(model: model)
                Spacer()
                if let g = focus {
                    ShutterFoot(model: model, game: g)
                        .padding(.horizontal, 64 * u).padding(.bottom, 54 * u)
                }
            }
            .animation(TheatreMotion.swapAnimation, value: focus?.id)
        }
    }
}
