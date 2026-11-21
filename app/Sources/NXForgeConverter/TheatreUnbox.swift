// Theatre's case in the hand (0.50.0): Y lifts the game in focus out of the theme, the right stick turns it, A opens it like
// the real thing (its booklet in the lid, the game card in its clip) and A again takes the card to the console under the
// screen, which starts the game. The same scene, run by the clock, is the launch from any theme (Settings › Theatre › When a
// game starts): the case comes forward and opens, the card drops into the console with a click, and its light fills the room.
import AppKit
import simd
import SwiftUI

/// How a game starts on Theatre (Settings › Theatre › When a game starts)
enum TheatreLaunch: String, Codable, CaseIterable {
    /// the card goes from its case into the console
    case card = "Game card"
    /// the box opens and its light fills the room (0.47.4 to 0.49)
    case lights = "Lights down"
}

/// The case in the hand: whose it is, and whether it is shut or open
struct TheatreUnbox: Equatable, Identifiable {
    enum Stage: Equatable { case held, open }
    let id = UUID()
    /// the game's StageGame id
    let game: String
    var stage: Stage = .held
    var picked = Date()
    /// when it was last opened or shut
    var turned: Date?
    /// when it was put back: it sinks into the theme again, then goes
    var leaving: Date?
    /// eighths of a turn asked for with left and right
    var steps = 0
    /// held still as it is (a snapshot)
    var frozen = false

    static let liftTime = 0.5, openTime = 0.65, shutTime = 0.45, leaveTime = 0.32
}

/// Where everything in the scene is, each from 0 to 1 unless it is an angle
struct CaseSceneState: Equatable {
    /// the room dims
    var room = 0.0
    /// the case comes up into the hand
    var lift = 0.0
    var yaw = 0.0
    var pitch = 0.05
    /// the lid swings open
    var open = 0.0
    /// the card comes up out of its clip, flies to the console, and goes down into it
    var cardOut = 0.0
    var cardFly = 0.0
    var cardSeat = 0.0
    /// the console comes up under the screen
    var console = 0.0
    /// the console's light, and the light that fills the room
    var lit = 0.0
    var bloom = 0.0
    /// the open case falls back as the card goes
    var away = 0.0
    /// the card already in the console (Continue from the console): no case at all
    var consoleOnly = false

    static func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    static func backOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1), s = 1.4
        return 1 + (s + 1) * pow(c - 1, 3) + s * pow(c - 1, 2)
    }

    // the launch's clock: when each part begins (seconds from the start of the whole sequence)
    static let opens = 0.6, cardLifts = 1.1, cardFlies = 1.3, cardSeats = 1.95, clicks = 2.1, blooms = 2.15, reveal = 2.55, length = 3.1
    /// from the console (the card is in it already): the card comes up a little and goes back down
    static let fromConsole = 1.72

    /// The launch at `t` seconds into the whole sequence
    static func launch(_ t: Double, consoleOnly: Bool = false) -> CaseSceneState {
        var s = CaseSceneState()
        s.consoleOnly = consoleOnly
        s.room = ease(t / 0.4)
        s.console = consoleOnly ? 1 : ease((t - 0.1) / 0.45)
        s.lift = backOut((t - 0.08) / 0.62)
        s.yaw = 0.42 * (1 - ease((t - 0.25) / 0.45))
        s.open = ease((t - opens) / 0.55)
        s.cardOut = ease((t - cardLifts) / 0.25)
        s.cardFly = ease((t - cardFlies) / 0.65)
        s.cardSeat = ease((t - cardSeats) / 0.17)
        s.away = ease((t - cardFlies) / 0.6)
        s.lit = ease((t - clicks) / 0.2)
        s.bloom = ease((t - blooms) / 0.6)
        return s
    }
}

extension AppModel {
    /// The game whose case is in the hand
    var unboxedGame: StageGame? {
        guard let u = theatreUnbox else { return nil }
        return stageGames().first { $0.id == u.game }
    }

    /// Y on a theme: the game in focus comes up into the hand
    func pickUpCase(_ g: StageGame) {
        guard theatreUnbox == nil else { return }
        theatreMoment = nil
        theatreWatch = false
        theatreFocus = g.id
        theatreUnbox = TheatreUnbox(game: g.id)
        theatreCue(.lift)
    }

    /// The case goes back into the theme
    func putBackCase() {
        guard var u = theatreUnbox, u.leaving == nil else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { theatreUnbox = nil; return }
        u.leaving = Date()
        theatreUnbox = u
        let id = u.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(TheatreUnbox.leaveTime))
            if self?.theatreUnbox?.id == id { self?.theatreUnbox = nil }
        }
    }

    /// A controller's button, or its key, with the case in the hand
    func unboxPad(_ k: PadKey) {
        guard var u = theatreUnbox, u.leaving == nil, let g = unboxedGame else { theatreUnbox = nil; return }
        switch (u.stage, k) {
        case (.held, .a):
            u.stage = .open; u.turned = Date(); u.steps = 0
            theatreUnbox = u
            theatreCue(.caseOpen); theatreRumble(.snap)
        case (.held, .left), (.held, .right):
            u.steps += k == .left ? -1 : 1
            theatreUnbox = u
            theatreCue(.turn)
        case (.held, .b), (.held, .menu): putBackCase(); theatreCue(.step)
        case (.open, .b), (.open, .menu):
            u.stage = .held; u.turned = Date()
            theatreUnbox = u
            theatreCue(.caseClose); theatreRumble(.snap)
        case (.open, .a): playFromCase(g)
        case (_, .x): if let m = GameManual.find(g) { theatreCue(.open); openManual(m, title: g.name) }
        case (_, .y):
            // the game's page, as Y was before the case could be picked up
            theatreUnbox = nil
            caseFlipped = false
            gameDetail = g.ref
        case (_, .options): toggleFavorite(g); theatreCue(.step)
        default: break
        }
    }

    /// A with the case open: the card goes to the console and the game starts (or the step it needs is taken, as on the themes)
    func playFromCase(_ g: StageGame) {
        rememberTheatreFocus()
        fix(g)
        if let l = launching, l.failure == nil, theatreCurtain == nil { theatreLightsDown(l) }
        if theatreCurtain == nil { theatreUnbox = nil }   // Play options, a game already running, or a step it needs
    }

    /// The game whose card is in the console: the built game played last
    func consoleGame() -> StageGame? { Self.lastPlayed(stageGames().filter { $0.app != nil && $0.last != nil }) }

    /// Continue from the console (the Theatre menu's first row): the game played last starts, its card already in the slot
    func continueFromConsole() {
        guard let g = consoleGame() else { return }
        theatreFocus = g.id
        theatreFromConsole = true
        rememberTheatreFocus()
        fix(g)
        theatreFromConsole = false
    }
}

// MARK: The scene

/// The case, the card and the console, wherever `state` says they are. Sizes are 1080ths of the picture's height (`u`).
struct TheatreCaseScene: View {
    let game: StageGame
    let state: CaseSceneState
    /// the booklet shows in the lid
    var booklet = false
    let u: CGFloat

    // a Switch case is 105 × 170 × 10.5 mm
    static let width = 372.0, height = 602.0, depth = 37.0
    /// the camera's distance, so the case turns with a little perspective, not a lot
    static let distance = 2100.0
    /// the middle of the case, above the middle of the picture
    static let restY = -72.0
    static let cardWidth = 92.0, cardHeight = 136.0
    /// the clip's middle on the tray, from the tray's middle
    static let clipY = -128.0
    static let consoleTop = 338.0, consoleWidth = 560.0, consoleHeight = 104.0, slotWidth = 150.0

    var body: some View {
        let s = state
        let tint = CoverArt.tint(game)
        let red = game.console == .switch2
        let d = Self.distance * u
        ZStack {
            consoleBack(s)
            if !s.consoleOnly, s.lift > 0.001 {
                let m = caseMatrix(s)
                let fade = min(s.lift * 1.6, 1) * (1 - 0.55 * s.away)
                Group {
                    if s.open < 0.002 { closed(m, d: d, red: red) } else { backHalf(m, d: d, red: red, tint: tint) }
                }
                .opacity(fade)
                if s.open >= 0.002 {
                    if s.cardOut < 0.5 { card(s, d: d, red: red) }
                    lid(m, s: s, d: d, red: red, tint: tint).opacity(fade)
                    if s.cardOut >= 0.5 { card(s, d: d, red: red) }
                }
            } else if s.consoleOnly {
                card(s, d: d, red: red)
            }
            consoleFront(s, tint: tint)
            // the light pours out of the console and fills the room
            let size = max(4600 * u * s.bloom, 1)
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color(red: 1, green: 0.98, blue: 0.94), location: 0), .init(color: Color(red: 1, green: 0.98, blue: 0.94), location: 0.3),
                                             .init(color: tint.opacity(0.85), location: 0.62), .init(color: tint.opacity(0), location: 1)], center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
                .offset(y: (Self.consoleTop - 40 - 300 * s.bloom) * u)
                .opacity(s.bloom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: the case

    /// The case's place in the room: up into the hand, turned, and to the right as it opens so the open case sits in the middle
    func caseMatrix(_ s: CaseSceneState) -> Solid.Matrix {
        let k = (0.6 + 0.4 * s.lift) * (1 - 0.06 * s.open) * (1 - 0.05 * s.away)
        let x = Self.width / 2 * s.open * k
        let y = Self.restY + (1 - s.lift) * 250 - 26 * s.away
        return Solid.move(x * u, y * u, 0) * Solid.scale(k) * Solid.turnX(s.pitch) * Solid.turnY(s.yaw)
    }

    @ViewBuilder func closed(_ m: Solid.Matrix, d: Double, red: Bool) -> some View {
        ForEach(Solid.box(width: Self.width * u, height: Self.height * u, depth: Self.depth * u)) { f in
            face(f.side, half: false, red: red).solid(m * f.matrix, size: f.size, distance: d)
        }
    }

    /// The half that holds the card: its back is the cover's back, its inside the tray
    @ViewBuilder func backHalf(_ m: Solid.Matrix, d: Double, red: Bool, tint: Color) -> some View {
        let half = m * Solid.move(0, 0, -Self.depth / 4 * u)
        ForEach(Solid.box(width: Self.width * u, height: Self.height * u, depth: Self.depth / 2 * u)) { f in
            Group {
                if f.side == .front { tray(red: red, tint: tint) } else { face(f.side, half: true, red: red) }
            }
            .solid(half * f.matrix, size: f.size, distance: d, shade: f.side == .front ? 0.25 : 0.5)
        }
    }

    /// The lid, on its hinge down the spine: its outside is the cover's front, its inside holds the booklet
    @ViewBuilder func lid(_ m: Solid.Matrix, s: CaseSceneState, d: Double, red: Bool, tint: Color) -> some View {
        let hinge = m * Solid.move(-Self.width / 2 * u, 0, 0) * Solid.turnY(-s.open * 176 * .pi / 180) * Solid.move(Self.width / 2 * u, 0, Self.depth / 4 * u)
        ForEach(Solid.box(width: Self.width * u, height: Self.height * u, depth: Self.depth / 2 * u)) { f in
            Group {
                if f.side == .back { inside(red: red, tint: tint) } else { face(f.side, half: true, red: red) }
            }
            .solid(hinge * f.matrix, size: f.size, distance: d, shade: f.side == .back ? 0.25 : 0.5)
        }
    }

    /// One outside face of the case: the cover through its clear sleeve, or the plastic's edge
    @ViewBuilder func face(_ side: Solid.BoxSide, half: Bool, red: Bool) -> some View {
        let plastic = red ? Color(red: 0.62, green: 0.06, blue: 0.09) : Color(white: 0.2)
        switch side {
        case .front:
            art(CoverArt.front(game)).overlay(sleeve).clipShape(.rect(cornerRadius: 11 * u))
        case .back:
            art(CoverArt.back(game)).overlay(sleeve).clipShape(.rect(cornerRadius: 11 * u))
        case .left:
            // the spine, whole on the shut case; an open case shows each half's plastic
            if half { plastic } else { art(CoverArt.spine(game)).overlay(Color.white.opacity(0.06)) }
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

    /// The light on the clear sleeve, sliding across as the case turns
    var sleeve: some View {
        let slide = sin(state.yaw * 1.3) * 0.5
        return ZStack {
            LinearGradient(stops: [.init(color: .clear, location: 0.28 + slide), .init(color: .white.opacity(0.22), location: 0.46 + slide), .init(color: .clear, location: 0.62 + slide)],
                           startPoint: UnitPoint(x: -0.3, y: 0), endPoint: UnitPoint(x: 1.3, y: 1))
            LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
            RoundedRectangle(cornerRadius: 11 * u).strokeBorder(.white.opacity(0.22), lineWidth: 1.5 * u)
        }
    }

    /// The moulded inside of a half: dark plastic with the game's colours washed through it
    func mould(red: Bool, tint: Color) -> some View {
        ZStack {
            red ? Color(red: 0.32, green: 0.04, blue: 0.06) : Color(white: 0.13)
            if let a = CoverArt.ambient(game) { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill).opacity(0.22).saturation(0.8) }
            LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 11 * u).strokeBorder(.white.opacity(0.14), lineWidth: 2 * u)
            RoundedRectangle(cornerRadius: 7 * u).strokeBorder(.black.opacity(0.35), lineWidth: 2 * u).padding(12 * u)
        }
        .clipShape(.rect(cornerRadius: 11 * u))
    }

    /// The tray: the card's clip, and the moulded shapes under it
    func tray(red: Bool, tint: Color) -> some View {
        let w = Self.width * u, h = Self.height * u
        return ZStack {
            mould(red: red, tint: tint)
            // the well the card sits in, and the thumb notch under it
            RoundedRectangle(cornerRadius: 10 * u).fill(.black.opacity(0.42))
                .overlay(RoundedRectangle(cornerRadius: 10 * u).strokeBorder(.white.opacity(0.12), lineWidth: 1.5 * u))
                .frame(width: (Self.cardWidth + 22) * u, height: (Self.cardHeight + 22) * u)
                .position(x: w / 2, y: h / 2 + Self.clipY * u)
            Capsule().fill(.black.opacity(0.42)).frame(width: 60 * u, height: 26 * u).position(x: w / 2, y: h / 2 + (Self.clipY + Self.cardHeight / 2 + 20) * u)
            // the recycling lattice every case has, lower down
            RoundedRectangle(cornerRadius: 8 * u).strokeBorder(.white.opacity(0.07), style: StrokeStyle(lineWidth: 2 * u, dash: [10 * u, 8 * u]))
                .frame(width: w * 0.68, height: h * 0.26).position(x: w / 2, y: h * 0.74)
        }
    }

    /// The lid's inside: two clips, and the booklet they hold when the game has one
    func inside(red: Bool, tint: Color) -> some View {
        let w = Self.width * u, h = Self.height * u
        return ZStack {
            mould(red: red, tint: tint)
            if booklet { bookletCover.frame(width: w * 0.80, height: h * 0.80).position(x: w / 2, y: h / 2) }
            ForEach([0.085, 0.915], id: \.self) { y in
                RoundedRectangle(cornerRadius: 4 * u).fill(Color(white: red ? 0.5 : 0.36).opacity(0.9))
                    .frame(width: 54 * u, height: 13 * u).shadow(color: .black.opacity(0.5), radius: 3 * u, y: 2 * u)
                    .position(x: w / 2, y: h * y)
            }
        }
    }

    /// The booklet's cover: the game's wide art over its name, on cream paper
    var bookletCover: some View {
        let paper = Color(red: 0.957, green: 0.937, blue: 0.894), ink = Color(red: 0.16, green: 0.14, blue: 0.11)
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                art(CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) ?? CoverArt.front(game)).frame(height: geo.size.height * 0.56)
                Text(game.name).font(.system(size: 25 * u, weight: .bold, design: .serif)).lineLimit(3).minimumScaleFactor(0.6)
                    .padding(.top, 18 * u).padding(.horizontal, 20 * u)
                Text("INSTRUCTION BOOKLET").font(.system(size: 11.5 * u, weight: .medium, design: .serif)).tracking(2 * u).opacity(0.62)
                    .padding(.top, 6 * u).padding(.horizontal, 20 * u)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(paper)
            .clipShape(.rect(cornerRadius: 4 * u))
            // the fold down its left, and the paper's edge
            .overlay(alignment: .leading) { LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14 * u) }
            .shadow(color: .black.opacity(0.5), radius: 12 * u, y: 6 * u)
        }
    }

    // MARK: the card

    /// The card's place: in its clip, up out of it, across to the console and down into the slot
    func cardMatrix(_ s: CaseSceneState) -> (matrix: Solid.Matrix, scale: Double) {
        let slotScale = 1.22
        // above the slot, then down into it until only its top shows
        let over = SIMD3(0, (Self.consoleTop - Self.cardHeight * slotScale / 2 - 26 + (1 - s.console) * 220) * Double(u), 60 * Double(u))
        let seated = SIMD3<Double>(0, Self.cardHeight * slotScale * 0.74 * Double(u), -60 * Double(u))
        if s.consoleOnly {
            // in the console already: it comes up a little as the launch begins, and goes back down
            let up = 1 - s.cardSeat
            let p = over + seated * (1 - 0.45 * up)
            return (Solid.move(p.x, p.y, p.z) * Solid.scale(slotScale), slotScale)
        }
        let m = caseMatrix(s)
        let k = (0.6 + 0.4 * s.lift) * (1 - 0.06 * s.open) * (1 - 0.05 * s.away)
        let from = Solid.point(m, 0, Self.clipY * Double(u), (5 + 70 * s.cardOut) * Double(u))
        let f = s.cardFly
        var p = from + (over - from) * f
        p.z += sin(.pi * f) * 150 * Double(u)   // an arc towards the viewer on the way
        p += seated * s.cardSeat
        let scale = k + (slotScale - k) * f
        let spin = Solid.turnX(s.pitch * (1 - f)) * Solid.turnZ(-0.16 * sin(.pi * f))
        return (Solid.move(p.x, p.y, p.z) * Solid.scale(scale) * spin, scale)
    }

    @ViewBuilder func card(_ s: CaseSceneState, d: Double, red: Bool) -> some View {
        let c = cardMatrix(s)
        let seen = s.consoleOnly ? 1 : min(max((s.open - 0.45) / 0.3, 0), 1)
        GameCardFace(game: game, red: red, u: u)
            .shadow(color: .black.opacity(0.55 * s.cardOut), radius: 16 * u * s.cardOut, y: 10 * u * s.cardOut)
            .solid(c.matrix, size: CGSize(width: Self.cardWidth * u, height: Self.cardHeight * u), distance: d, shade: 0.3)
            .opacity(seen)
    }

    // MARK: the console

    func consoleOffset(_ s: CaseSceneState) -> CGFloat { (1 - s.console) * 220 * u }

    /// Behind the card: the console's top and the slot the card goes down into
    func consoleBack(_ s: CaseSceneState) -> some View {
        ZStack {
            // the top's far edge, seen a little from above
            RoundedRectangle(cornerRadius: 14 * u).fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                .frame(width: (Self.consoleWidth - 34) * u, height: 30 * u).offset(y: (Self.consoleTop - 9) * u)
            RoundedRectangle(cornerRadius: 6 * u).fill(.black)
                .frame(width: Self.slotWidth * u, height: 15 * u).offset(y: (Self.consoleTop - 9) * u)
        }
        .offset(y: consoleOffset(s))
        .opacity(min(s.console * 2, 1))
    }

    /// In front of the card: the console's face, its name and its light
    func consoleFront(_ s: CaseSceneState, tint: Color) -> some View {
        let w = Self.consoleWidth * u, h = Self.consoleHeight * u
        return ZStack {
            // its light on the wall behind, once the card is home
            Ellipse().fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.86).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 330 * u))
                .frame(width: 760 * u, height: 320 * u).offset(y: -120 * u).opacity(s.lit)
            RoundedRectangle(cornerRadius: 24 * u)
                .fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.10), Color(white: 0.075)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24 * u).strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * u))
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.7), radius: 40 * u, y: 22 * u)
            // the slot's near lip
            RoundedRectangle(cornerRadius: 5 * u).fill(Color(white: 0.05)).frame(width: (Self.slotWidth + 10) * u, height: 7 * u).offset(y: -h / 2 + 3.5 * u)
            HStack(spacing: 0) {
                Text("NX").font(.system(size: 17 * u, weight: .heavy))
                Text("FORGE").font(.system(size: 17 * u, weight: .light))
            }
            .tracking(6 * u).foregroundStyle(.white.opacity(0.34)).offset(x: -w / 2 + 96 * u, y: 6 * u)
            Circle().fill(s.lit > 0 ? Color(red: 0.36, green: 0.92, blue: 0.56).opacity(0.35 + 0.65 * s.lit) : Color(white: 0.2))
                .frame(width: 12 * u, height: 12 * u)
                .shadow(color: Color(red: 0.36, green: 0.92, blue: 0.56).opacity(s.lit), radius: 12 * u)
                .offset(x: w / 2 - 46 * u, y: 6 * u)
        }
        .offset(y: (Self.consoleTop + Self.consoleHeight / 2) * u + consoleOffset(s))
        .opacity(min(s.console * 2, 1))
    }
}

/// A game card: its grip, its label (the game's icon, else its cover) and its contacts' ridge. Grey for Switch, red for Switch 2.
struct GameCardFace: View {
    let game: StageGame
    let red: Bool
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                GameCardShape().fill(LinearGradient(colors: red ? [Color(red: 0.86, green: 0.16, blue: 0.16), Color(red: 0.55, green: 0.07, blue: 0.09)]
                                                           : [Color(white: 0.36), Color(white: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
                GameCardShape().stroke(.white.opacity(0.28), lineWidth: max(w * 0.012, 0.5))
                Capsule().fill(.white.opacity(0.14)).frame(width: w * 0.36, height: h * 0.035).position(x: w * 0.27, y: h * 0.07)
                label.frame(width: w * 0.84, height: h * 0.62).clipShape(.rect(cornerRadius: w * 0.05))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.05).strokeBorder(.black.opacity(0.4), lineWidth: max(w * 0.01, 0.5)))
                    .position(x: w / 2, y: h * 0.45)
                HStack(spacing: w * 0.022) { ForEach(0..<9, id: \.self) { _ in Rectangle().fill(.white.opacity(0.13)).frame(width: w * 0.05) } }
                    .frame(height: h * 0.075).position(x: w / 2, y: h * 0.885)
            }
        }
    }

    @ViewBuilder var label: some View {
        if let i = CoverArt.icon(game) ?? CoverArt.front(game) {
            Color.black.overlay(Image(nsImage: i).resizable().interpolation(.high).aspectRatio(contentMode: .fill)).clipped()
        } else {
            CoverArt.tint(game)
        }
    }
}

/// A game card's outline: round corners, the top right one cut off
struct GameCardShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = r.width * 0.09, cut = r.width * 0.17
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: The case in the hand

/// The turn the right stick and the arrows give the case in the hand, eased from frame to frame (the picture's clock steps it)
@MainActor
final class UnboxSpin {
    private var yaw = 0.42
    private var free = 0.0
    private var last: Date?
    static let rest = 0.42

    /// The case's yaw now: its rest angle with a slow sway, the arrows' eighths of a turn and the stick's turning on top; face
    /// on while it opens
    func step(_ u: TheatreUnbox, now: Date, still: Bool) -> Double {
        let dt = min(max(last.map { now.timeIntervalSince($0) } ?? 0, 0), 0.05)
        last = now
        let stick = CaseStick.x
        var target: Double
        if u.stage == .open || u.leaving != nil {
            free = 0
            // the nearest way round to face on (or to rest, going back)
            let base = u.leaving != nil ? Self.rest : 0
            target = base + ((yaw - base) / (2 * .pi)).rounded() * 2 * .pi
        } else {
            if abs(stick) > 0.15 { free += stick * 2.6 * dt }
            target = Self.rest + Double(u.steps) * .pi / 4 + free
            if !still, abs(stick) <= 0.15 { target += 0.07 * sin(now.timeIntervalSinceReferenceDate * 0.8) }
        }
        if still || u.frozen { yaw = target } else { yaw += (target - yaw) * min(dt * 9, 1) }
        return yaw
    }
}

/// The case in the hand, over the theme: the room dims round it, its name at the top, what the buttons do at the foot
struct TheatreUnboxView: View {
    let model: AppModel
    let unbox: TheatreUnbox
    @State private var spin = UnboxSpin()
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        if let g = model.stageGames().first(where: { $0.id == unbox.game }) {
            let _ = CoverStore.shared.revision
            let tint = CoverArt.tint(g)
            let manual = GameManual.find(g) != nil
            TimelineView(.animation(paused: unbox.frozen)) { ctx in
                let s = state(now: ctx.date)
                ZStack {
                    Color.black.opacity(0.80 * s.room)
                    RadialGradient(colors: [tint.opacity(0.36 * s.room), tint.opacity(0.08 * s.room), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 820 * u)
                    TheatreCaseScene(game: g, state: s, booklet: manual, u: u)
                    words(g, manual: manual).opacity(s.room)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(g.name)'s case, \(unbox.stage == .open ? "open" : "in your hand")")
        }
    }

    /// Where the scene is now: up into the hand, open or shut, or on its way back
    func state(now: Date) -> CaseSceneState {
        var s = CaseSceneState()
        let quick = still || unbox.frozen
        let up = quick ? 1 : CaseSceneState.backOut(now.timeIntervalSince(unbox.picked) / TheatreUnbox.liftTime)
        let down = unbox.leaving.map { quick ? 1 : CaseSceneState.ease(now.timeIntervalSince($0) / TheatreUnbox.leaveTime) } ?? 0
        s.lift = up * (1 - down)
        s.room = min(up, 1) * (1 - down)
        s.console = (quick ? 1 : CaseSceneState.ease(now.timeIntervalSince(unbox.picked) / 0.6)) * (1 - down)
        let since = unbox.turned.map { now.timeIntervalSince($0) }
        switch unbox.stage {
        case .open: s.open = quick ? 1 : CaseSceneState.ease((since ?? 1) / TheatreUnbox.openTime)
        case .held: s.open = quick ? 0 : since.map { 1 - CaseSceneState.ease($0 / TheatreUnbox.shutTime) } ?? 0
        }
        s.yaw = spin.step(unbox, now: now, still: still) * (1 - s.open)
        s.pitch = 0.05 + 0.03 * s.open
        return s
    }

    func words(_ g: StageGame, manual: Bool) -> some View {
        let hints = TheatreHints(model: model)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10 * u) {
                Text(unbox.stage == .open ? "IN THE CASE" : "IN YOUR HAND").font(.system(size: 15 * u, weight: .semibold)).tracking(4 * u).foregroundStyle(StageLook.faint)
                Text(g.name).font(.system(size: 52 * u, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                Text(CarouselTheme.facts(g)).font(.system(size: 20 * u)).foregroundStyle(StageLook.soft)
            }
            .frame(maxWidth: 560 * u, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 96 * u).padding(.top, 62 * u)
            Spacer()
            HStack(spacing: 30 * u) {
                if unbox.stage == .open {
                    hints.hint("A", model.theatreAction(g), filled: true)
                    if manual { hints.hint("X", "Read the booklet") }
                    hints.hint("Y", "Details")
                    hints.hint("B", "Close")
                } else {
                    hints.hint("A", "Open", filled: true)
                    hints.hint("←", "→", "Turn")
                    if manual { hints.hint("X", "Booklet") }
                    hints.hint("Y", "Details")
                    hints.hint("B", "Put back")
                }
            }
            .font(.system(size: 20 * u, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 30 * u)
        }
    }
}

// MARK: The console on the top bar

/// Theatre's wordmark as the console it is: NXFORGE on its face, the card of the game played last standing in its slot and its
/// light on. With nothing played yet, an empty slot and no light. (Continue, on the Theatre menu, starts that game.)
struct TheatreConsoleMark: View {
    let model: AppModel
    var ink: Color = .white
    @Environment(\.tu) private var u

    var body: some View {
        let g = model.consoleGame()
        HStack(spacing: 16 * u) {
            ZStack(alignment: .bottom) {
                if let g {
                    GameCardFace(game: g, red: g.console == .switch2, u: u)
                        .frame(width: 30 * u, height: 44 * u)
                        .offset(x: 46 * u, y: -22 * u)
                }
                RoundedRectangle(cornerRadius: 9 * u)
                    .fill(LinearGradient(colors: [ink.opacity(0.20), ink.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9 * u).strokeBorder(ink.opacity(0.26), lineWidth: 1))
                    .background(.black.opacity(ink == .white ? 0.35 : 0), in: .rect(cornerRadius: 9 * u))
                    .frame(width: 196 * u, height: 36 * u)
                    .overlay {
                        HStack(spacing: 0) {
                            Text("NX").font(.system(size: 17 * u, weight: .heavy))
                            Text("FORGE").font(.system(size: 17 * u, weight: .light))
                            Spacer(minLength: 0)
                            Circle().fill(g != nil ? Color(red: 0.36, green: 0.92, blue: 0.56) : ink.opacity(0.25)).frame(width: 7 * u, height: 7 * u)
                                .shadow(color: Color(red: 0.36, green: 0.92, blue: 0.56).opacity(g != nil ? 0.9 : 0), radius: 5 * u)
                        }
                        .tracking(5 * u).padding(.leading, 16 * u).padding(.trailing, 14 * u)
                    }
            }
            .frame(width: 196 * u, height: 62 * u, alignment: .bottom)
            if let g {
                VStack(alignment: .leading, spacing: 2 * u) {
                    Text("IN THE CONSOLE").font(.system(size: 11.5 * u, weight: .semibold)).tracking(2.4 * u).opacity(0.55)
                    Text(g.name).font(.system(size: 17 * u, weight: .medium)).lineLimit(1).opacity(0.9)
                }
                .frame(maxWidth: 300 * u, alignment: .leading)
                .padding(.top, 20 * u)
            }
        }
        .foregroundStyle(ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(g.map { "NXForge. \($0.name) is in the console" } ?? "NXForge")
    }
}
