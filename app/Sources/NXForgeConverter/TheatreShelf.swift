// The shelf, Showcase's third layout (0.51.0): your games standing spine out along a shelf, as they do at home. The game in
// focus is drawn out of the row and turned to face you; left and right run along the shelf, the one in the hand slides back
// and the next comes out. The right stick turns the case in front. Each case is a real box (TheatreSolid), so the spines'
// art, the covers' edges and the turn are all the same object.
import simd
import SwiftUI

struct ShelfTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u

    var body: some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        let tint = focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
        ZStack {
            StageBackdrop(tint: tint, art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "")
            LinearGradient(stops: [.init(color: .clear, location: 0.05), .init(color: .black.opacity(0.4), location: 0.4), .init(color: .black.opacity(0.72), location: 0.75)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            GeometryReader { geo in
                // a pool of light behind the case in front, warmed by the game's colour
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.12), tint.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 460 * u))
                    .frame(width: 920 * u, height: 720 * u)
                    .blur(radius: 30 * u)
                    .position(x: geo.size.width / 2, y: geo.size.height * ShelfLayout.middleY)
                ShelfBoard(size: geo.size)
                ShelfCases(model: model, games: games, index: index, size: geo.size)
            }
            .ignoresSafeArea()
            // the shelf runs off into shadow at both ends
            RadialGradient(colors: [.clear, .black.opacity(0.6)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 560 * u, endRadius: 1250 * u)
                .ignoresSafeArea().allowsHitTesting(false)
            LinearGradient(stops: [.init(color: .clear, location: 0.7), .init(color: .black.opacity(0.85), location: 0.9), .init(color: .black, location: 1)],
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

/// The shelf's shape, in 1080ths of the height (tested)
enum ShelfLayout {
    /// a case: 105 × 170 × 10.5 mm
    static let height = 440.0, width = 440.0 * 105 / 170, depth = 440.0 * 10.5 / 170
    /// the row's middle down the screen (a fraction of the height)
    static let middleY = 0.41
    /// from one spine's middle to the next, and from the middle of the screen to the first spine either side of the case in front
    static let pitch = depth + 5, gap = 215.0
    /// how many spines either side are drawn
    static let reach = 24
    /// the case in front: how far it comes out, how much bigger it is, how far it is turned, how much it lifts
    static let out = 170.0, grow = 0.16, turn = 0.3, lift = 16.0
    static let distance = 2100.0

    static func shown(index: Int, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        return max(index - reach, 0)...min(index + reach, count - 1)
    }

    /// how far out of the row a case is, `d` places from the one in front (which may be part way between two): 1 out, 0 in the row
    static func pull(_ d: Double) -> Double { CaseSceneState.ease(1 - abs(d)) }

    /// a case's place along the shelf
    static func x(_ d: Double) -> Double {
        let a = abs(d), first = gap + pitch / 2
        return (d < 0 ? -1 : 1) * (a < 1 ? a * first : first + (a - 1) * pitch)
    }

    /// spine out in the row, turned to face you in front
    static func yaw(_ d: Double) -> Double { .pi / 2 + (turn - .pi / 2) * pull(d) }

    /// how lit a spine is, by its distance along the shelf
    static func light(_ d: Double) -> Double { max(1 - 0.022 * max(abs(d) - 1, 0), 0.45) }
}

/// The board the cases stand on: its top, seen a little from above, and its front edge
struct ShelfBoard: View {
    let size: CGSize
    @Environment(\.tu) private var u

    var body: some View {
        let foot = size.height * ShelfLayout.middleY + ShelfLayout.height / 2 * u
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
                .frame(width: size.width, height: 30 * u).position(x: size.width / 2, y: foot + 2 * u)
            Rectangle().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.16)).frame(height: 1.5 * u) }
                .frame(width: size.width, height: 26 * u).position(x: size.width / 2, y: foot + 30 * u)
                .shadow(color: .black.opacity(0.7), radius: 26 * u, y: 20 * u)
        }
        .allowsHitTesting(false)
    }
}

/// Where the shelf has slid to: it follows the game in focus a frame at a time (the picture's clock steps it)
@MainActor
final class ShelfSlide {
    private var at: Double?
    private var last: Date?

    func step(to index: Int, now: Date, still: Bool) -> Double {
        let dt = min(max(last.map { now.timeIntervalSince($0) } ?? 0, 0), 0.05)
        last = now
        let target = Double(index)
        // a long way (the filter changed, or the row went round its end): it is simply there
        guard let a = at, !still, abs(target - a) < 14 else { at = target; return target }
        let next = abs(target - a) < 0.002 ? target : a + (target - a) * min(dt * 11, 1)
        at = next
        return next
    }
}

struct ShelfCases: View {
    let model: AppModel
    let games: [StageGame]
    let index: Int
    let size: CGSize
    @State private var slide = ShelfSlide()
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let frozen = ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil
        TimelineView(.animation(paused: frozen)) { ctx in
            let at = slide.step(to: index, now: ctx.date, still: still || frozen)
            ZStack {
                if let range = ShelfLayout.shown(index: index, count: games.count) {
                    ForEach(range, id: \.self) { k in
                        let d = Double(k) - at
                        ShelfCase(game: games[k], d: d, stick: abs(CaseStick.x) > 0.15 ? CaseStick.x : 0, keep: abs(d) < 1 ? model.keepsake(games[k]) : nil)
                            .zIndex(-abs(d))
                    }
                }
            }
            .offset(y: (ShelfLayout.middleY - 0.5) * size.height)
        }
        .frame(width: size.width, height: size.height)
        // a click on the left or the right of the shelf runs along it; on the case in front, it is A
        .contentShape(.rect)
        .onTapGesture { p in
            let x = p.x - size.width / 2
            model.theatrePad(abs(x) < ShelfLayout.gap * u ? .a : x < 0 ? .left : .right)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(games.indices.contains(index) ? "\(games[index].name), selected" : "No games")
    }
}

/// One case on the shelf, `d` places from the one in front
struct ShelfCase: View {
    let game: StageGame
    let d: Double
    let stick: Double
    var keep: CaseKeepsake?
    @Environment(\.tu) private var u

    var body: some View {
        let e = ShelfLayout.pull(d)
        let w = ShelfLayout.width * u, h = ShelfLayout.height * u, depth = ShelfLayout.depth * u
        let dist = ShelfLayout.distance * u
        let m = Solid.move(ShelfLayout.x(d) * u, -ShelfLayout.lift * e * u, ShelfLayout.out * e * u) * Solid.scale(1 + ShelfLayout.grow * e)
            * Solid.turnX(0.04 * e) * Solid.turnY(ShelfLayout.yaw(d) + stick * 1.1 * e)
        let red = game.console == .switch2
        let plastic = red ? Color(red: 0.62, green: 0.06, blue: 0.09) : Color(white: 0.2)
        let light = ShelfLayout.light(d)
        ZStack {
            ForEach(Solid.box(width: w, height: h, depth: depth)) { f in
                let fm = m * f.matrix
                // only the faces that look this way are laid out at all: most of a row of spines is hidden
                if Solid.facing(fm, distance: dist) > 0.001 {
                    face(f.side, plastic: plastic, e: e)
                        .solid(fm, size: f.size, distance: dist, shade: f.side == .left ? 0.25 : 0.5)
                }
            }
        }
        .brightness(light - 1)
        .shadow(color: .black.opacity(0.55 * e), radius: 34 * u * e, y: 22 * u * e)
    }

    @ViewBuilder func face(_ side: Solid.BoxSide, plastic: Color, e: Double) -> some View {
        switch side {
        case .front: art(CoverArt.front(game)).overlay(sleeve).overlay { if let keep, e > 0.01 { CaseKeepsakes(keep: keep, seed: game.coverKey).opacity(e) } }.clipShape(.rect(cornerRadius: 9 * u))
        case .back: art(CoverArt.back(game)).overlay(sleeve).clipShape(.rect(cornerRadius: 9 * u))
        case .left:
            art(CoverArt.spine(game))
                .overlay(LinearGradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
        case .right, .top, .bottom:
            LinearGradient(colors: [plastic.opacity(0.95), plastic.opacity(0.7), plastic.opacity(0.95)], startPoint: .leading, endPoint: .trailing)
        }
    }

    @ViewBuilder func art(_ img: NSImage?) -> some View {
        if let img {
            Color.black.overlay(Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)).clipped()
        } else {
            CoverArt.tint(game)
        }
    }

    /// the light on the clear sleeve
    var sleeve: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .white.opacity(0.18), location: 0.48), .init(color: .clear, location: 0.64)],
                           startPoint: UnitPoint(x: -0.3, y: 0), endPoint: UnitPoint(x: 1.3, y: 1))
            RoundedRectangle(cornerRadius: 9 * u).strokeBorder(.white.opacity(0.22), lineWidth: 1.5 * u)
        }
    }
}
