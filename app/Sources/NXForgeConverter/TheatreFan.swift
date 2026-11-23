// The fan, one of Theatre's Showcase layouts (ShowcaseTheme; it was a theme of its own, 0.48.2 to 0.48.8): the games' boxes fanned out like a hand of cards from a point below the screen, the game in
// focus upright in the middle, lifted out of the fan and lit, the rest leaning away to either side and falling into shadow.
// Left and right scroll the fan sideways (it swings round its pivot), the right stick turns the box in front to see its edge,
// and a click on a box brings it to the middle. It took the Gallery theme's place.
import SwiftUI

struct FanTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u

    var body: some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        let tint = focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
        ZStack {
            StageBackdrop(tint: tint, art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "")
            LinearGradient(stops: [.init(color: .clear, location: 0.05), .init(color: .black.opacity(0.35), location: 0.4), .init(color: .black.opacity(0.7), location: 0.75)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            GeometryReader { geo in
                // a pool of light behind the box in front, warmed by the game's colour
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.13), tint.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 520 * u))
                    .frame(width: 1040 * u, height: 760 * u)
                    .blur(radius: 30 * u)
                    .position(x: geo.size.width / 2, y: geo.size.height * FanLayout.middleY)
                FanBoxes(model: model, games: games, index: index, size: geo.size)
            }
            .ignoresSafeArea()
            // the sides fall into shadow, so the eye goes to the middle
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 560 * u, endRadius: 1300 * u)
                .ignoresSafeArea().allowsHitTesting(false)
            LinearGradient(stops: [.init(color: .clear, location: 0.68), .init(color: .black.opacity(0.85), location: 0.9), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                TheatreTopBar(theme: .showcase, model: model)
                Spacer()
                if let g = focus {
                    VStack(spacing: 14 * u) {
                        Text(g.name).font(.system(size: 60 * u, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.6), radius: 18 * u, y: 4 * u)
                        Text(CarouselTheme.facts(g)).font(.system(size: 22 * u)).tracking(1.2 * u).foregroundStyle(StageLook.soft)
                        TheatreDetails(model: model, game: g, showSize: false).padding(.top, 2 * u)
                    }
                    .id(g.id).transition(.opacity)
                    .padding(.horizontal, 120 * u)
                }
                HStack(alignment: .bottom) {
                    if !games.isEmpty {
                        (Text(String(format: "%02d", index + 1)).foregroundStyle(.white).fontWeight(.semibold) + Text("  /  " + String(format: "%02d", games.count) + "   GAMES").foregroundStyle(StageLook.faint))
                            .font(.system(size: 19 * u)).tracking(3 * u).monospacedDigit()
                    }
                    Spacer()
                    TheatreHints(model: model, focus: focus)
                }
                .padding(.horizontal, 96 * u).padding(.top, 32 * u).padding(.bottom, 42 * u)
            }
            .animation(TheatreMotion.swapAnimation, value: focus?.id)
        }
    }
}

/// The fan's shape, in 1080ths of the height (tested)
enum FanLayout {
    /// the box in front: its height, and its middle down the screen (a fraction of the height)
    static let boxHeight: CGFloat = 470
    static let middleY: CGFloat = 0.42
    /// how far below a box's middle the fan's pivot is, and the turn between neighbours, in degrees
    static let radius: CGFloat = 1250
    static let step = 7.5
    /// how many boxes either side are drawn (the outer ones fade away)
    static let reach = 8
    /// the box in front lifts out of the fan by this much
    static let lift: CGFloat = 46

    /// the boxes drawn: those within `reach` of the one in front
    static func shown(index: Int, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        return max(index - reach, 0)...min(index + reach, count - 1)
    }

    /// a box's turn round the pivot, `d` places from the one in front
    static func angle(_ d: Int) -> Double { Double(d) * step }

    /// how lit a box is and how much of it shows, by its distance from the front
    static func light(_ d: Int) -> Double { d == 0 ? 1 : max(0.82 - 0.07 * Double(abs(d)), 0.35) }
    static func opacity(_ d: Int) -> Double { abs(d) < reach - 1 ? 1 : abs(d) == reach - 1 ? 0.5 : 0 }
}

struct FanBoxes: View {
    let model: AppModel
    let games: [StageGame]
    let index: Int
    let size: CGSize
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let h = FanLayout.boxHeight * u, w = h * CoverSource.aspect
        let anchor = UnitPoint(x: 0.5, y: 0.5 + FanLayout.radius / FanLayout.boxHeight)
        ZStack {
            if let range = FanLayout.shown(index: index, count: games.count) {
                ForEach(range, id: \.self) { k in
                    let g = games[k], d = k - index
                    FanBox(game: g, focused: d == 0, width: w, height: h)
                        .brightness(FanLayout.light(d) - 1)
                        .scaleEffect(d == 0 ? 1.07 : 1)
                        .offset(y: d == 0 ? -FanLayout.lift * u : 0)
                        .rotationEffect(.degrees(FanLayout.angle(d)), anchor: anchor)
                        .opacity(FanLayout.opacity(d))
                        .position(x: size.width / 2, y: size.height * FanLayout.middleY)
                        .zIndex(-Double(abs(d)) + (d > 0 ? 0.5 : 0))
                        .onTapGesture { model.theatreFocus = g.id; model.theatreTouched = Date() }
                        .help(TheatreDetails.line(model, g))
                        .id(g.id)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(still ? nil : .spring(duration: 0.5, bounce: 0.18), value: index)
    }
}

/// One box in the fan: the front cover in a clear case, its edge catching the light; the one in front turns with the right stick
struct FanBox: View {
    let game: StageGame
    let focused: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.tu) private var u

    var body: some View {
        if focused {
            TimelineView(.animation) { _ in box.rotation3DEffect(.degrees(abs(CaseStick.x) > 0.15 ? CaseStick.x * 50 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5) }
        } else {
            box
        }
    }

    var box: some View {
        let corner = 12 * u
        let red = game.console == .switch2
        return ZStack {
            if let art = CoverArt.front(game) {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                CoverArt.tint(game)
                Text(game.name).font(.system(size: 26 * u, weight: .bold, design: .serif)).multilineTextAlignment(.center).padding(24 * u)
            }
            // the case's plastic: a sheen down from the top left
            LinearGradient(colors: [.white.opacity(0.16), .clear, .clear, .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(red ? Color(red: 0.9, green: 0.15, blue: 0.15).opacity(0.7) : Color.white.opacity(focused ? 0.45 : 0.22), lineWidth: (focused ? 2.5 : 1.5) * u))
        .shadow(color: .black.opacity(focused ? 0.65 : 0.5), radius: (focused ? 40 : 18) * u, x: 0, y: (focused ? 26 : 10) * u)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name + (focused ? ", selected" : ""))
    }
}
