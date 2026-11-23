// The Museum wall, a Theatre theme (0.59.0): your collection in a walnut cabinet, one shelf a console (Switch 2, Switch, Game
// Boy Advance), the console itself on a plinth at the end of its shelf with a brass plaque of its games and hours. A brass
// picture light hangs over each shelf; the lights come on shelf by shelf as the room opens. The game in focus lifts out of its
// row and glows, with a brass card under it (its name, its year, what A does). The arrows go along a shelf and from shelf to
// shelf; up from the top shelf reaches the lighting switch (Classic, Daylight, Evening, Neon, Lights out), where left and
// right change the room's light. Idea from Boxshelf's museum (ideas only: Boxshelf is GPL, nothing of it is copied here).
import SwiftUI

/// The room's light on the Museum wall (Settings › Theatre › Museum lighting)
enum MuseumLighting: String, Codable, CaseIterable {
    case classic = "Classic", daylight = "Daylight", evening = "Evening", neon = "Neon", lightsOut = "Lights out"

    /// the wall behind the cabinet
    var wall: Color {
        switch self {
        case .classic: Color(red: 0.25, green: 0.18, blue: 0.13)
        case .daylight: Color(red: 0.56, green: 0.50, blue: 0.43)
        case .evening: Color(red: 0.19, green: 0.12, blue: 0.085)
        case .neon: Color(red: 0.07, green: 0.04, blue: 0.13)
        case .lightsOut: Color(red: 0.035, green: 0.03, blue: 0.03)
        }
    }
    /// the picture lights' colour, and how strongly they light their shelf (0 off)
    var lamp: Color {
        switch self {
        case .classic: Color(red: 1, green: 0.88, blue: 0.68)
        case .daylight: Color(red: 0.96, green: 0.97, blue: 1)
        case .evening: Color(red: 1, green: 0.72, blue: 0.42)
        case .neon: .white
        case .lightsOut: Color(red: 1, green: 0.85, blue: 0.65)
        }
    }
    var lampStrength: Double {
        switch self {
        case .classic: 0.75
        case .daylight: 0.35
        case .evening: 0.95
        case .neon: 0.85
        case .lightsOut: 0
        }
    }
    /// how lit the cases are away from the lamps (1 as they are)
    var ambient: Double {
        switch self {
        case .classic: 0.97
        case .daylight: 1
        case .evening: 0.9
        case .neon: 0.8
        case .lightsOut: 0.34
        }
    }
    /// the cabinet's wood, lighter by day
    var wood: Double {
        switch self {
        case .daylight: 1.35
        case .neon: 0.7
        case .lightsOut: 0.55
        default: 1
        }
    }
    func step(_ d: Int) -> MuseumLighting {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + d + all.count) % all.count]
    }
}

/// The wall's shape, in 1080ths of the height (tested)
enum MuseumLayout {
    /// the cabinet's top and the space left under it for the buttons
    static let top = 128.0, foot = 74.0, side = 34.0
    /// the console's bay at the right end of each shelf, and the room left of the first case
    static let bay = 300.0, inset = 64.0
    /// the board each shelf stands on
    static let board = 22.0
    /// a case is 105 × 170 mm; a cartridge is drawn about as wide as a case
    static let caseRatio = 105.0 / 170, cartRatio = 0.66
    /// the gap between cases, as a fraction of a case's width
    static let gap = 0.28

    static let order: [Console] = [.switch2, .switch1, .gba]

    /// The shelves: one a console that has games here, Switch 2 first
    static func shelves(_ games: [StageGame]) -> [(console: Console, games: [StageGame])] {
        order.compactMap { c in
            let g = games.filter { $0.console == c }
            return g.isEmpty ? nil : (c, g)
        }
    }

    /// a shelf's height for `count` shelves on a screen `height` tall
    static func rowHeight(count: Int, height: Double) -> Double {
        min((height - top - foot) / Double(max(count, 1)), 380)
    }

    /// where the cabinet's first shelf starts: under the plate, or lower down when one or two shelves do not fill the room
    static func cabinetTop(count: Int, height: Double) -> Double {
        let room = height - top - foot
        return top + max(room - rowHeight(count: count, height: height) * Double(max(count, 1)), 0) / 2
    }

    /// a case's height on a shelf `row` tall (a lone shelf does not fill the screen with one huge row of cases)
    static func caseHeight(row: Double) -> Double { min(row * 0.68, 330) }

    /// how many cases fit along a shelf `width` wide (the cabinet's inside, less the console's bay)
    static func visible(width: Double, caseWidth: Double) -> Int {
        max(Int((width - bay - inset) / (caseWidth * (1 + gap))), 1)
    }

    /// the first case shown on a shelf of `count` with `visible` places, so the one at `column` is in sight and near the middle
    static func first(column: Int, count: Int, visible: Int) -> Int {
        guard count > visible else { return 0 }
        return min(max(column - (visible - 1) / 2, 0), count - visible)
    }

    /// The focus after an arrow: along a shelf (stopping at its ends), or to the same place on the next shelf up or down
    /// (nil: up from the top shelf, which goes to the lighting switch)
    static func move(shelf: Int, column: Int, dx: Int, dy: Int, counts: [Int]) -> (shelf: Int, column: Int)? {
        guard !counts.isEmpty else { return (0, 0) }
        let s = min(max(shelf, 0), counts.count - 1)
        if dy != 0 {
            let ns = s + dy
            if ns < 0 { return nil }
            guard ns < counts.count else { return (s, column) }
            return (ns, min(column, counts[ns] - 1))
        }
        return (s, min(max(column + dx, 0), counts[s] - 1))
    }

    /// "18 games · 146 hours"
    static func stats(_ games: [StageGame]) -> String {
        let n = games.count, s = games.reduce(0) { $0 + $1.total }
        let time: String
        if s < 60 { time = "not played yet" }
        else if s < 3600 { time = "\(Int((s / 60).rounded())) min" }
        else { let h = Int((s / 3600).rounded()); time = "\(h) hour" + (h == 1 ? "" : "s") }
        return "\(n) game\(n == 1 ? "" : "s")  ·  \(time)"
    }

    /// "2023" from the store's release date ("20/10/2023")
    static func year(_ released: String?) -> String? {
        guard let r = released, let m = r.range(of: #"(19|20)\d\d"#, options: .regularExpression) else { return nil }
        return String(r[m])
    }

    /// The neon colour a console's shelf is lit in
    static func neon(_ c: Console) -> Color {
        switch c {
        case .switch2: Color(red: 1, green: 0.28, blue: 0.34)
        case .switch1: Color(red: 0.15, green: 0.78, blue: 1)
        case .gba: Color(red: 0.62, green: 0.42, blue: 1)
        }
    }
}

extension AppModel {
    /// The arrows on the Museum wall
    func museumPad(_ k: PadKey, games: [StageGame], focus: StageGame?) {
        // the lighting switch: left and right change the light, anything else comes back to the wall
        if museumLightFocus {
            switch k {
            case .left, .right:
                settings.museumLighting = settings.museumLighting.step(k == .left ? -1 : 1)
                theatreCue(.theme)
            default:
                museumLightFocus = false
                theatreCue(.step)
            }
            return
        }
        let shelves = MuseumLayout.shelves(games)
        guard !shelves.isEmpty else { return }
        let s = shelves.firstIndex { $0.console == focus?.console } ?? 0
        let c = shelves[s].games.firstIndex { $0.id == focus?.id } ?? 0
        let dx = k == .left ? -1 : k == .right ? 1 : 0, dy = k == .up ? -1 : k == .down ? 1 : 0
        guard let to = MuseumLayout.move(shelf: s, column: c, dx: dx, dy: dy, counts: shelves.map(\.games.count)) else {
            museumLightFocus = true
            theatreCue(.step)
            return
        }
        guard to.shelf != s || to.column != c else { return }
        theatreFocus = shelves[to.shelf].games[to.column].id
        theatreCue(.step)
    }
}

struct MuseumTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still
    /// when the room opened: the lights come on shelf by shelf from then
    @State private var opened = Date()

    var body: some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let light = model.settings.museumLighting
        let frozen = ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil || still
        GeometryReader { geo in
            let W = geo.size.width / u, H = geo.size.height / u
            let shelves = MuseumLayout.shelves(games)
            let rowH = MuseumLayout.rowHeight(count: shelves.count, height: H)
            let top = MuseumLayout.cabinetTop(count: shelves.count, height: H)
            ZStack(alignment: .topLeading) {
                MuseumRoom(light: light)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: frozen)) { ctx in
                    let since = frozen ? 99 : ctx.date.timeIntervalSince(opened)
                    ZStack(alignment: .topLeading) {
                        MuseumCabinet(light: light, rows: shelves.count, rowH: rowH, width: W, top: top)
                        ForEach(Array(shelves.enumerated()), id: \.element.console) { i, shelf in
                            // each shelf's lamp warms up in turn: a third of a second apart
                            let on = min(max((since - 0.25 - 0.35 * Double(i)) / 0.5, 0), 1)
                            MuseumShelf(model: model, console: shelf.console, games: shelf.games, focus: focus, light: light,
                                        lit: CaseSceneState.ease(on), width: W, rowH: rowH, last: i == shelves.count - 1)
                                .frame(width: W * u, height: rowH * u, alignment: .topLeading)
                                .offset(y: (top + Double(i) * rowH) * u)
                                .zIndex(shelf.games.contains { $0.id == focus?.id } ? 1 : 0)
                        }
                    }
                }
                // the brass plaque over the cabinet, and the lighting switch at the top right
                MuseumTitle(filter: model.theatreShownFilter)
                    .frame(width: W * u).padding(.top, 12 * u)
                MuseumLightSwitch(light: light, focused: model.museumLightFocus) { model.settings.museumLighting = $0 }
                    .frame(width: W * u, alignment: .trailing).padding(.top, 14 * u).padding(.trailing, (MuseumLayout.side + 6) * u)
                HStack(alignment: .bottom) {
                    if shelves.count > 1 || games.count > 1 {
                        Text(model.museumLightFocus ? "←  →  CHANGE THE LIGHT" : "\(games.count)  GAMES ON THE WALL")
                            .font(.system(size: 16 * u, weight: .semibold)).tracking(3 * u).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    TheatreHints(model: model, focus: focus, size: 18)
                }
                .padding(.horizontal, 60 * u)
                .frame(width: W * u, height: MuseumLayout.foot * u)
                .offset(y: (H - MuseumLayout.foot) * u)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.45), value: light)
            .animation(.easeInOut(duration: 0.2), value: model.museumLightFocus)
        }
        .onAppear { opened = Date() }
    }
}

/// The wall behind the cabinet: plaster in the room's light, darker toward the corners
struct MuseumRoom: View {
    let light: MuseumLighting
    @Environment(\.tu) private var u

    var body: some View {
        ZStack {
            light.wall
            RadialGradient(colors: [light.lamp.opacity(0.10 * light.lampStrength + (light == .daylight ? 0.12 : 0)), .clear], center: UnitPoint(x: 0.5, y: 0.05), startRadius: 0, endRadius: 900 * u)
            RadialGradient(colors: [.clear, .black.opacity(light == .daylight ? 0.28 : 0.6)], center: .center, startRadius: 500 * u, endRadius: 1300 * u)
            Image(nsImage: StageLook.grain).resizable(resizingMode: .tile).opacity(0.05).blendMode(.overlay)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Walnut, as a fill: dark and warm, with a faint grain of long streaks
struct Walnut: View {
    var bright = 1.0
    var vertical = false
    var body: some View {
        let a = Color(red: 0.30 * bright, green: 0.17 * bright, blue: 0.10 * bright)
        let b = Color(red: 0.21 * bright, green: 0.115 * bright, blue: 0.065 * bright)
        let c = Color(red: 0.36 * bright, green: 0.21 * bright, blue: 0.12 * bright)
        LinearGradient(stops: [.init(color: b, location: 0), .init(color: a, location: 0.18), .init(color: c, location: 0.31), .init(color: a, location: 0.47),
                               .init(color: b, location: 0.63), .init(color: c, location: 0.79), .init(color: a, location: 1)],
                       startPoint: vertical ? .leading : .top, endPoint: vertical ? .trailing : .bottom)
    }
}

/// Brass, as a fill: a bright line along its top, darker at its foot
enum Brass {
    static var fill: LinearGradient {
        LinearGradient(stops: [.init(color: Color(red: 0.98, green: 0.86, blue: 0.55), location: 0), .init(color: Color(red: 0.80, green: 0.60, blue: 0.30), location: 0.35),
                               .init(color: Color(red: 0.62, green: 0.43, blue: 0.19), location: 0.8), .init(color: Color(red: 0.45, green: 0.30, blue: 0.13), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The cabinet: its frame, a dark back inside each shelf, and the boards
struct MuseumCabinet: View {
    let light: MuseumLighting
    let rows: Int
    let rowH: Double
    let width: Double
    var top = MuseumLayout.top
    @Environment(\.tu) private var u

    var body: some View {
        let x0 = MuseumLayout.side, w = width - 2 * MuseumLayout.side
        let h = rowH * Double(rows)
        ZStack(alignment: .topLeading) {
            // the frame round it all, and the back panel inside
            RoundedRectangle(cornerRadius: 6 * u).fill(.black.opacity(0.5)).blur(radius: 18 * u)
                .frame(width: (w + 16) * u, height: (h + 30) * u).offset(x: (x0 - 8) * u, y: (top - 4) * u)
            Walnut(bright: 0.8 * light.wood, vertical: true)
                .frame(width: w * u, height: (h + 14) * u).offset(x: x0 * u, y: (top - 14) * u)
            ForEach(0..<max(rows, 1), id: \.self) { i in
                let y = top + Double(i) * rowH
                // the back of the shelf: darker toward its top, where the board above shades it
                LinearGradient(colors: [Color(red: 0.07, green: 0.04, blue: 0.025).opacity(0.95), Color(red: 0.16, green: 0.09, blue: 0.05).opacity(0.75 * light.wood)], startPoint: .top, endPoint: .bottom)
                    .frame(width: (w - 52) * u, height: (rowH - MuseumLayout.board - 10) * u)
                    .offset(x: (x0 + 26) * u, y: (y + 10) * u)
                board(y: y + rowH - MuseumLayout.board, x: x0 - 8, w: w + 16)
            }
            board(y: top - 22, x: x0 - 8, w: w + 16)
        }
        .allowsHitTesting(false)
    }

    func board(y: Double, x: Double, w: Double) -> some View {
        Walnut(bright: 1.05 * light.wood)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.22)).frame(height: 1.5 * u) }
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.5)).frame(height: 3 * u) }
            .frame(width: w * u, height: MuseumLayout.board * u)
            .shadow(color: .black.opacity(0.55), radius: 10 * u, y: 8 * u)
            .offset(x: x * u, y: y * u)
    }
}

/// One shelf: its picture light, its cases (or cartridges) in a window that follows the focus, and its console on a plinth
struct MuseumShelf: View {
    let model: AppModel
    let console: Console
    let games: [StageGame]
    let focus: StageGame?
    let light: MuseumLighting
    /// how far the lamp has come on (0 off, 1 on)
    let lit: Double
    let width: Double
    let rowH: Double
    /// the bottom shelf: its card goes beside the game, as there is no room under it
    var last = false
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let cart = console == .gba
        let caseH = MuseumLayout.caseHeight(row: rowH)
        let w = cart ? caseH * 0.62 : caseH * MuseumLayout.caseRatio
        let h = cart ? w * MuseumLayout.cartRatio : caseH
        let pitch = w * (1 + MuseumLayout.gap)
        let inner = width - 2 * MuseumLayout.side
        let visible = MuseumLayout.visible(width: inner, caseWidth: w)
        let column = games.firstIndex { $0.id == focus?.id }
        // a shelf away from the focus shows from where it was left
        let first = MuseumLayout.first(column: column ?? model.museumColumns[console.rawValue] ?? 0, count: games.count, visible: visible)
        let floor = rowH - MuseumLayout.board
        let x0 = MuseumLayout.side + MuseumLayout.inset
        let lamp = light == .neon ? MuseumLayout.neon(console) : light.lamp
        let strength = light.lampStrength * lit
        let mid = (MuseumLayout.side + (width - MuseumLayout.side - MuseumLayout.bay)) / 2
        ZStack(alignment: .topLeading) {
            // the lamp's light falling down the back of the shelf
            if strength > 0 {
                // a soft pool from the lamp down the back of the shelf, brightest just under it, and its light on the board
                let span = (inner - MuseumLayout.bay) * 0.95
                Ellipse()
                    .fill(RadialGradient(colors: [lamp.opacity(0.34 * strength), lamp.opacity(0.12 * strength), .clear], center: .top, startRadius: 0, endRadius: span * 0.5 * u))
                    .frame(width: span * u, height: floor * 1.5 * u)
                    .offset(x: (mid - span / 2) * u, y: -floor * 0.25 * u)
                    .blendMode(.screen).blur(radius: 24 * u)
                Ellipse().fill(lamp.opacity(0.22 * strength)).blur(radius: 30 * u)
                    .frame(width: span * 0.7 * u, height: 36 * u).offset(x: (mid - span * 0.35) * u, y: (floor - 20) * u).blendMode(.screen)
            }
            if light == .neon {
                Rectangle().fill(lamp).frame(width: (inner - 60) * u, height: 2.5 * u).shadow(color: lamp, radius: 8 * u).shadow(color: lamp, radius: 20 * u)
                    .opacity(lit).offset(x: (MuseumLayout.side + 30) * u, y: (floor - 3) * u)
            }
            // the cases, slid along with the focus; the ones out of the window are not drawn
            ZStack(alignment: .topLeading) {
                ForEach(Array(games.enumerated()), id: \.element.id) { k, g in
                    if k >= first - 1, k <= first + visible {
                        let on = g.id == focus?.id && !model.museumLightFocus
                        // lit by the lamp toward the middle of the shelf, less at its ends
                        let cx = x0 + Double(k - first) * pitch + w / 2
                        let near = max(1 - abs(cx - mid) / (inner * 0.75), 0)
                        let glow = light == .lightsOut ? (on ? 1.0 : 0) : strength * near
                        MuseumPiece(game: g, cart: cart, focused: on, lamp: light == .lightsOut ? light.lamp : lamp, glow: glow)
                            .frame(width: w * u, height: h * u)
                            .brightness((light.ambient + 0.18 * glow) - 1 + (on ? 0.06 : 0))
                            .scaleEffect(on ? 1.1 : 1, anchor: .bottom)
                            .offset(y: on ? -8 * u : 0)
                            .offset(x: (x0 + Double(k - first) * pitch) * u, y: (floor - h - 4) * u)
                            .zIndex(on ? 2 : 0)
                            .onTapGesture {
                                if on { model.theatrePad(.a) } else { model.museumLightFocus = false; model.theatreFocus = g.id; model.theatreTouched = Date() }
                            }
                    }
                }
            }
            .animation(still ? nil : .spring(duration: 0.4, bounce: 0.15), value: first)
            .animation(still ? nil : .spring(duration: 0.3, bounce: 0.25), value: focus?.id)
            // more to see either way
            if first > 0 { arrow("chevron.compact.left").offset(x: (MuseumLayout.side + 18) * u, y: (floor - h / 2 - 22) * u) }
            if first + visible < games.count { arrow("chevron.compact.right").offset(x: (width - MuseumLayout.side - MuseumLayout.bay - 26) * u, y: (floor - h / 2 - 22) * u) }
            // the picture light on the board above
            PictureLight(lit: lit * (light == .lightsOut ? 0.15 : 1), tint: lamp)
                .frame(width: 270 * u, height: 40 * u)
                .offset(x: (mid - 135) * u, y: -26 * u)
            // the console, its plinth and its plaque
            MuseumConsoleBay(console: console, games: games, rowH: rowH, light: light, lit: lit)
                .frame(width: MuseumLayout.bay * u, height: floor * u)
                .offset(x: (width - MuseumLayout.side - MuseumLayout.bay - 10) * u)
            // the brass card under the game in focus
            if let k = column, let g = focus, !model.museumLightFocus {
                let cx = x0 + Double(k - first) * pitch + w / 2
                let right = cx + w * 0.55 + 140 < width - MuseumLayout.bay
                MuseumCaption(model: model, game: g)
                    .frame(width: 260 * u)
                    .position(x: last ? (right ? cx + w * 0.55 + 140 : cx - w * 0.55 - 140) * u : min(max(cx, 150), width - MuseumLayout.bay - 150) * u,
                              y: last ? (floor - h / 2 - 4) * u : (floor + 44) * u)
                    .animation(still ? nil : .spring(duration: 0.3), value: k)
                    .zIndex(3)
            }
        }
        .onChange(of: column) { _, c in if let c { model.museumColumns[console.rawValue] = c } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(console.fullName) shelf, \(MuseumLayout.stats(games))")
    }

    func arrow(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 36 * u, weight: .semibold)).foregroundStyle(.white.opacity(0.4)).allowsHitTesting(false)
    }
}

/// The light from a picture lamp: narrow at the lamp, wide at the shelf
struct LampCone: Shape {
    var spread: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.width * (1 - spread) / 2
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A brass picture light: its round mount and its long shade, glowing along its foot when on
struct PictureLight: View {
    let lit: Double
    let tint: Color
    @Environment(\.tu) private var u

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                Circle().fill(Brass.fill).frame(width: 22 * u, height: 22 * u).overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1)).offset(y: 0)
                Rectangle().fill(Brass.fill).frame(width: 5 * u, height: 12 * u).offset(y: 18 * u)
                Capsule().fill(Brass.fill).frame(width: w, height: 16 * u)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 4 * u, y: 3 * u)
                    .offset(y: 26 * u)
                Capsule().fill(tint).frame(width: w - 26 * u, height: 4 * u).blur(radius: 1 * u).opacity(0.95 * lit)
                    .shadow(color: tint.opacity(lit), radius: 10 * u).shadow(color: tint.opacity(0.7 * lit), radius: 24 * u)
                    .offset(y: 39 * u)
            }
            .frame(width: w)
        }
        .allowsHitTesting(false)
    }
}

/// A game on the shelf: a case (its cover behind the clear sleeve, white plastic round it) or, for a Game Boy Advance game, a
/// cartridge with its label
struct MuseumPiece: View {
    let game: StageGame
    let cart: Bool
    let focused: Bool
    let lamp: Color
    let glow: Double
    @Environment(\.tu) private var u

    var body: some View {
        Group {
            if cart { cartridge } else { box }
        }
        .shadow(color: .black.opacity(focused ? 0.75 : 0.55), radius: (focused ? 18 : 7) * u, x: 3 * u, y: (focused ? 12 : 4) * u)
        .shadow(color: focused ? lamp.opacity(0.85) : .clear, radius: 22 * u)
        .shadow(color: focused ? lamp.opacity(0.45) : .clear, radius: 44 * u)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name + (focused ? ", selected" : ""))
        .accessibilityAddTraits(.isButton)
    }

    var box: some View {
        let r = 5 * u
        return art(CoverArt.tile(game))
            .clipShape(.rect(cornerRadius: r))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .white.opacity(0.16), location: 0.46), .init(color: .clear, location: 0.6)],
                                    startPoint: UnitPoint(x: -0.2, y: 0), endPoint: UnitPoint(x: 1.2, y: 1)).clipShape(.rect(cornerRadius: r)))
            .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 2.5 * u))
            .overlay(focused ? RoundedRectangle(cornerRadius: r).strokeBorder(lamp.opacity(0.9), lineWidth: 2 * u) : nil)
    }

    var cartridge: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                CartShape().fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.24)], startPoint: .top, endPoint: .bottom))
                CartShape().stroke(.white.opacity(0.25), lineWidth: 1)
                // the grip's ridges along the top
                HStack(spacing: w * 0.03) { ForEach(0..<7, id: \.self) { _ in Rectangle().fill(.black.opacity(0.25)).frame(width: w * 0.035) } }
                    .frame(height: h * 0.08).offset(y: h * 0.04)
                art(CoverArt.front(game), top: true)
                    .frame(width: w * 0.82, height: h * 0.66)
                    .clipShape(.rect(cornerRadius: w * 0.02))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.02).strokeBorder(.black.opacity(0.4), lineWidth: 1))
                    .offset(y: h * 0.17)
                if focused { CartShape().stroke(lamp.opacity(0.9), lineWidth: 2 * u) }
            }
        }
    }

    @ViewBuilder func art(_ img: NSImage?, top: Bool = false) -> some View {
        if let img {
            Color.black.overlay(alignment: top ? .top : .center) { Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill) }.clipped()
        } else {
            CoverArt.tint(game).overlay(Text(game.name).font(.system(size: 14 * u, weight: .semibold)).multilineTextAlignment(.center).padding(6 * u))
        }
    }
}

/// A Game Boy Advance cartridge's outline: square at the foot, its top corners rounded and the label's shoulders cut in
struct CartShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = r.width * 0.05
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// The brass card under the game in focus: its name, its year, and what A does
struct MuseumCaption: View {
    let model: AppModel
    let game: StageGame
    @Environment(\.tu) private var u

    var body: some View {
        let year = model.settings.downloadStoreInfo ? MuseumLayout.year(StoreInfoStore.shared.info(game.coverKey)?.released) : nil
        VStack(spacing: 4 * u) {
            Text(game.name).font(.system(size: 19 * u, weight: .semibold, design: .serif)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            if let year { Text(year).font(.system(size: 15 * u, design: .serif)) }
            Rectangle().fill(Color(red: 0.35, green: 0.22, blue: 0.08).opacity(0.5)).frame(height: 1).padding(.horizontal, 18 * u).padding(.vertical, 3 * u)
            Text("Press A to \(model.theatreAction(game).lowercased())").font(.system(size: 15 * u, design: .serif))
        }
        .foregroundStyle(Color(red: 0.17, green: 0.10, blue: 0.03))
        .padding(.horizontal, 16 * u).padding(.vertical, 11 * u)
        .frame(maxWidth: .infinity)
        .background(Plaque(radius: 5 * u))
        .shadow(color: .black.opacity(0.6), radius: 14 * u, y: 8 * u)
        .id(game.id).transition(.opacity)
    }
}

/// A brass plate with a screw in each corner
struct Plaque: View {
    var radius: CGFloat
    @Environment(\.tu) private var u

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.85, blue: 0.62), Color(red: 0.84, green: 0.69, blue: 0.43), Color(red: 0.74, green: 0.57, blue: 0.32)],
                                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: radius).strokeBorder(Color(red: 0.45, green: 0.30, blue: 0.12), lineWidth: 1.5 * u)
            RoundedRectangle(cornerRadius: max(radius - 3 * u, 1)).strokeBorder(.white.opacity(0.35), lineWidth: 1 * u).padding(3 * u)
            GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Color(red: 0.5, green: 0.36, blue: 0.16)).frame(width: 5 * u, height: 5 * u)
                        .position(x: i % 2 == 0 ? 9 * u : g.size.width - 9 * u, y: i < 2 ? 9 * u : g.size.height - 9 * u)
                }
            }
        }
    }
}

/// "Museum wall" on a brass plate over the cabinet, and the filter when it is not every game
struct MuseumTitle: View {
    let filter: TheatreFilter
    @Environment(\.tu) private var u

    var body: some View {
        VStack(spacing: 0) {
            Text("Museum wall").font(.system(size: 40 * u, weight: .regular, design: .serif))
            if filter != .all { Text(filter.title).font(.system(size: 15 * u, weight: .medium, design: .serif)).tracking(1.5 * u).opacity(0.8) }
        }
        .foregroundStyle(Color(red: 0.24, green: 0.14, blue: 0.04))
        .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
        .frame(width: 360 * u, height: (filter == .all ? 74 : 88) * u)
        .background(Plaque(radius: 6 * u))
        .padding(4 * u)
        .background(RoundedRectangle(cornerRadius: 9 * u).fill(Color(red: 0.25, green: 0.15, blue: 0.08)))
        .shadow(color: .black.opacity(0.65), radius: 16 * u, y: 8 * u)
        .accessibilityElement(children: .combine)
    }
}

/// "Lighting: Evening" and the five lights, the one on in brass; up from the top shelf reaches it
struct MuseumLightSwitch: View {
    let light: MuseumLighting
    let focused: Bool
    let pick: (MuseumLighting) -> Void
    @Environment(\.tu) private var u

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            Text("Lighting: \(light.rawValue)").font(.system(size: 18 * u, design: .serif)).foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 0) {
                ForEach(MuseumLighting.allCases, id: \.self) { l in
                    choice(l)
                    if l != MuseumLighting.allCases.last { Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18 * u) }
                }
            }
            .padding(3 * u)
            .background(Capsule().fill(.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .padding(.horizontal, 16 * u).padding(.vertical, 12 * u)
        .background(RoundedRectangle(cornerRadius: 12 * u).fill(Color(red: 0.08, green: 0.06, blue: 0.05).opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12 * u).strokeBorder(focused ? Color(red: 0.95, green: 0.78, blue: 0.45) : .white.opacity(0.1), lineWidth: focused ? 2.5 * u : 1))
        .shadow(color: focused ? Color(red: 1, green: 0.75, blue: 0.4).opacity(0.5) : .clear, radius: 16 * u)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lighting: \(light.rawValue)")
    }

    func choice(_ l: MuseumLighting) -> some View {
        let on = l == light
        let ink: Color = on ? Color(red: 0.22, green: 0.13, blue: 0.04) : .white.opacity(0.75)
        return Text(l.rawValue).font(.system(size: 14 * u, design: .serif))
            .foregroundStyle(ink)
            .padding(.horizontal, 14 * u).frame(height: 30 * u)
            .background(Capsule().fill(Brass.fill).opacity(on ? 1 : 0))
            .contentShape(.rect)
            .onTapGesture { pick(l) }
    }
}

/// The end of a shelf: the console standing on a walnut plinth, and the brass plaque under it
struct MuseumConsoleBay: View {
    let console: Console
    let games: [StageGame]
    let rowH: Double
    let light: MuseumLighting
    let lit: Double
    @Environment(\.tu) private var u

    var body: some View {
        let plaqueH = 36.0, plinthH = min(rowH * 0.09, 24)
        let room = rowH - MuseumLayout.board - plaqueH - plinthH - 30
        let w = min(MuseumLayout.bay - 70, room * (console == .gba ? 1.7 : 1.75))
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            MuseumConsoleArt(console: console)
                .frame(width: w * u, height: w / (console == .gba ? 1.7 : 1.75) * u)
                .brightness(light.ambient - 1 + 0.1 * lit * light.lampStrength)
                .shadow(color: .black.opacity(0.6), radius: 10 * u, y: 6 * u)
                .shadow(color: light == .neon ? MuseumLayout.neon(console).opacity(0.5 * lit) : .clear, radius: 24 * u)
            // the plinth
            Walnut(bright: 1.15 * light.wood)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.25)).frame(height: 1.5 * u) }
                .frame(width: (w + 40) * u, height: plinthH * u)
                .shadow(color: .black.opacity(0.5), radius: 6 * u, y: 4 * u)
            Text("\(console.fullName)  ·  \(MuseumLayout.stats(games))")
                .font(.system(size: 14.5 * u, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(Color(red: 0.22, green: 0.13, blue: 0.04))
                .padding(.horizontal, 14 * u)
                .frame(width: (MuseumLayout.bay - 20) * u, height: plaqueH * u)
                .background(Plaque(radius: 4 * u))
                .shadow(color: .black.opacity(0.5), radius: 8 * u, y: 4 * u)
                .padding(.top, 6 * u).padding(.bottom, 4 * u)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(console.fullName): \(MuseumLayout.stats(games))")
    }
}

/// The consoles, drawn here: a Switch 2 with its dark controllers, a Switch with its blue and red ones, a Game Boy Advance
struct MuseumConsoleArt: View {
    let console: Console

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            switch console {
            case .gba: gba(w: w, h: h)
            case .switch1: hybrid(w: w, h: h, left: Color(red: 0.0, green: 0.66, blue: 0.93), right: Color(red: 1.0, green: 0.30, blue: 0.29), ring: nil)
            case .switch2: hybrid(w: w, h: h, left: Color(white: 0.14), right: Color(white: 0.14), ring: Color(red: 0.92, green: 0.2, blue: 0.26))
            }
        }
    }

    /// a tablet with a controller either side
    func hybrid(w: CGFloat, h: CGFloat, left: Color, right: Color, ring: Color?) -> some View {
        let jw = w * 0.15, bw = w - 2 * jw
        return HStack(spacing: 0) {
            joycon(w: jw, h: h, color: left, ring: ring, leftSide: true)
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.035).fill(Color(white: 0.09))
                RoundedRectangle(cornerRadius: h * 0.02).fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.horizontal, bw * 0.05).padding(.vertical, h * 0.08)
                    .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .white.opacity(0.07), location: 0.5), .init(color: .clear, location: 0.65)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing).padding(.horizontal, bw * 0.05).padding(.vertical, h * 0.08))
            }
            .frame(width: bw, height: h)
            joycon(w: jw, h: h, color: right, ring: ring, leftSide: false)
        }
    }

    func joycon(w: CGFloat, h: CGFloat, color: Color, ring: Color?, leftSide: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leftSide ? w * 0.7 : 0, bottomLeadingRadius: leftSide ? w * 0.7 : 0,
                                           bottomTrailingRadius: leftSide ? 0 : w * 0.7, topTrailingRadius: leftSide ? 0 : w * 0.7)
        return ZStack {
            shape.fill(LinearGradient(colors: [color.opacity(1), color.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            // the stick
            Circle().fill(Color(white: 0.06)).frame(width: w * 0.48, height: w * 0.48)
                .overlay(Circle().strokeBorder(ring ?? .clear, lineWidth: w * 0.05))
                .position(x: w / 2, y: leftSide ? h * 0.3 : h * 0.6)
            // the buttons
            ForEach(0..<4, id: \.self) { i in
                let a = Double(i) * .pi / 2
                Circle().fill(Color(white: 0.07)).frame(width: w * 0.16, height: w * 0.16)
                    .position(x: w / 2 + cos(a) * w * 0.18, y: (leftSide ? h * 0.62 : h * 0.3) + sin(a) * w * 0.18)
            }
            // the controller's inner rail, in the Switch 2's red
            if let ring { Rectangle().fill(ring).frame(width: w * 0.04).frame(maxWidth: .infinity, alignment: leftSide ? .trailing : .leading).padding(.vertical, h * 0.06) }
        }
        .frame(width: w, height: h)
    }

    /// a Game Boy Advance, purple, the screen between the pad and the buttons
    func gba(w: CGFloat, h: CGFloat) -> some View {
        let body = Color(red: 0.36, green: 0.30, blue: 0.68)
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.42).fill(LinearGradient(colors: [body.opacity(1), Color(red: 0.25, green: 0.2, blue: 0.52)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: h * 0.42).strokeBorder(.white.opacity(0.2), lineWidth: 1)
            // the screen in its grey bezel
            RoundedRectangle(cornerRadius: h * 0.06).fill(Color(white: 0.32)).frame(width: w * 0.44, height: h * 0.66)
            RoundedRectangle(cornerRadius: h * 0.02).fill(LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.16), Color(white: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: w * 0.36, height: h * 0.5)
            // the pad
            ZStack {
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.12)).frame(width: w * 0.12, height: w * 0.04)
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.12)).frame(width: w * 0.04, height: w * 0.12)
            }
            .position(x: w * 0.15, y: h * 0.46)
            // A and B
            Circle().fill(Color(red: 0.62, green: 0.6, blue: 0.85)).frame(width: w * 0.065, height: w * 0.065).position(x: w * 0.87, y: h * 0.40)
            Circle().fill(Color(red: 0.62, green: 0.6, blue: 0.85)).frame(width: w * 0.065, height: w * 0.065).position(x: w * 0.79, y: h * 0.54)
        }
    }
}
