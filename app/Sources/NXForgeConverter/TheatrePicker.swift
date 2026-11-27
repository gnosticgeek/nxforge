// Theatre's picker (0.64.0, to Tom's mock-up): a system and its look, chosen like a shutter opening. Each system is a tall
// panel side by side (Switch 2, Switch, Wii, GameCube, Game Boy Advance, and All games for the looks that show everything);
// the one in focus fans open wide with the real Theatre inside it, live, and its neighbours stay narrow slivers with their
// names up the side in their own colour. Left and right move the opening along, up and down step through the system's
// looks (its themes), A keeps it, B puts back what was there. Y is Surprise me (the dice: Theatre's shuffle) and + Settings.
// + on Theatre opens it; the dice and the gear also sit in each theme's top bar (TheatreCorner).
import SwiftUI

/// The games a Theatre room shows: one system's, or every game. Each system has its own looks (themes), the first its default.
enum TheatreSystem: String, Codable, CaseIterable {
    case switch2 = "Switch 2", switch1 = "Switch", wii = "Wii", gamecube = "GameCube", gba = "Game Boy Advance", all = "All games"

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = TheatreSystem(rawValue: s) ?? .all
    }

    /// the console it is (nil: every game)
    var console: Console? { Console(rawValue: rawValue) }

    /// the name up the side of its sliver
    var short: String { self == .gba ? "GBA" : rawValue }

    /// its looks, in the order up and down step them
    var looks: [TheatreTheme] {
        switch self {
        case .switch2, .switch1: [.wallet, .shutter]
        case .wii, .gamecube: [.wii, .showcase]
        case .gba: [.showcase, .cinema]
        case .all: [.museum, .showcase, .cinema, .trailer, .shutter, .wallet]
        }
    }

    /// the colour of its panel
    var accent: Color {
        switch self {
        case .switch2: Color(red: 0.30, green: 0.78, blue: 0.95)
        case .switch1: Color(red: 0.93, green: 0.27, blue: 0.24)
        case .wii: Color(red: 0.36, green: 0.70, blue: 0.98)
        case .gamecube: Color(red: 0.49, green: 0.35, blue: 0.93)
        case .gba: Color(red: 0.36, green: 0.30, blue: 0.80)
        case .all: Color(red: 0.83, green: 0.62, blue: 0.34)
        }
    }

    var symbol: String {
        switch self {
        case .switch2, .switch1: "gamecontroller.fill"
        case .wii: "wand.and.rays"
        case .gamecube: "cube.fill"
        case .gba: "rectangle.portrait.and.arrow.forward"
        case .all: "square.stack.3d.up.fill"
        }
    }

    /// the line under the panel
    var note: String {
        switch self {
        case .switch2: "Your Nintendo Switch 2 games"
        case .switch1: "Your Nintendo Switch games"
        case .wii: "Your Wii games"
        case .gamecube: "Your GameCube games"
        case .gba: "Your Game Boy Advance games"
        case .all: "Every game you have, on every system"
        }
    }

    /// its look after `t`, `d` steps along (round at the ends); a look it does not have steps from its first
    func look(after t: TheatreTheme, _ d: Int) -> TheatreTheme {
        guard let i = looks.firstIndex(of: t) else { return looks[0] }
        return looks[(i + d + looks.count) % looks.count]
    }
}

/// The picker while it is open: the panel in focus, the look each panel is on, and what Theatre was on before it opened (B puts
/// it back). Theatre follows the panel in focus as it moves, unsaved, so the open panel is the real thing.
struct TheatrePickerState: Equatable {
    var system: TheatreSystem
    var looks: [TheatreSystem: TheatreTheme]
    let wasSystem: TheatreSystem
    let wasTheme: TheatreTheme

    func look(_ s: TheatreSystem) -> TheatreTheme { looks[s] ?? s.looks[0] }
}

extension AppModel {
    /// The systems with games (Settings › Library hides a system), then All games; the one Theatre is on is always there
    func theatreSystems() -> [TheatreSystem] {
        let have = Set(stageGames().map(\.console))
        return TheatreSystem.allCases.filter { s in s == .all || s == theatreSystem || s.console.map(have.contains) == true }
    }

    /// Theatre's games before its theme picks from them: the system's, every game on All games (or when the system has none)
    func theatreScoped() -> [StageGame] {
        let all = stageGames()
        guard let c = theatreSystem.console else { return all }
        let mine = all.filter { $0.console == c }
        return mine.isEmpty ? all : mine
    }

    /// The look a system opens on: the one it was last left on, else its first
    func theatreLook(_ s: TheatreSystem) -> TheatreTheme {
        if s == theatreSystem, s.looks.contains(theatreTheme) { return theatreTheme }
        if let t = settings.theatreLooks[s.rawValue].flatMap(TheatreTheme.init(rawValue:)), s.looks.contains(t) { return t }
        return s.looks[0]
    }

    func openTheatrePicker() {
        theatreMenu = nil
        theatreMoment = nil
        var looks: [TheatreSystem: TheatreTheme] = [:]
        for s in theatreSystems() { looks[s] = theatreLook(s) }
        // the theme Theatre is on stays the open look, even one its system does not list (a Wii room saved before 0.64)
        looks[theatreSystem] = theatreTheme
        theatrePicker = TheatrePickerState(system: theatreSystem, looks: looks, wasSystem: theatreSystem, wasTheme: theatreTheme)
        theatreCue(.open)
    }

    /// Theatre shows the picker's panel in focus, unsaved
    private func showPicked(_ p: TheatrePickerState) {
        theatrePicker = p
        theatreSystem = p.system
        theatreTheme = p.look(p.system)
        theatreWatch = false
        museumLightFocus = false
        theatreRow = 0
        let games = theatreTheme == .trailer ? trailerGames() : theatreGames()
        if !games.contains(where: { $0.id == theatreFocus }) { theatreFocus = games.first?.id }
    }

    func pickerStep(system d: Int) {
        guard var p = theatrePicker else { return }
        let all = theatreSystems()
        let i = all.firstIndex(of: p.system) ?? 0
        let j = min(max(i + d, 0), all.count - 1)
        guard j != i else { return }
        p.system = all[j]
        showPicked(p)
        theatreCue(.step)
    }

    func pickerStep(look d: Int) {
        guard var p = theatrePicker, p.system.looks.count > 1 || !p.system.looks.contains(p.look(p.system)) else { return }
        p.looks[p.system] = p.system.look(after: p.look(p.system), d)
        showPicked(p)
        theatreCue(.theme)
    }

    func pickerFocus(_ s: TheatreSystem) {
        guard var p = theatrePicker, p.system != s else { return }
        p.system = s
        showPicked(p)
        theatreCue(.step)
    }

    /// A: Theatre keeps the system and look in focus
    func applyTheatrePicker() {
        guard let p = theatrePicker else { return }
        theatrePicker = nil
        setTheatreSystem(p.system, theme: p.look(p.system))
        theatreCue(.theme)
    }

    /// B: back to what Theatre was on
    func cancelTheatrePicker() {
        guard let p = theatrePicker else { return }
        theatrePicker = nil
        theatreSystem = p.wasSystem
        theatreTheme = p.wasTheme
        let games = theatreTheme == .trailer ? trailerGames() : theatreGames()
        if !games.contains(where: { $0.id == theatreFocus }) { theatreFocus = games.first?.id }
    }

    /// A system and its look, kept for next time (the look per system too, so each system reopens on its own)
    func setTheatreSystem(_ s: TheatreSystem, theme t: TheatreTheme) {
        theatreSystem = s
        setTheatreTheme(t)
        if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil {
            settings.theatreSystem = s
            settings.theatreLooks[s.rawValue] = t.rawValue
        }
    }

    /// A theme chosen in Settings: kept on the system Theatre is on when it is one of its looks, else on All games
    func pickTheatreTheme(_ t: TheatreTheme) {
        let s = theatreSystem.looks.contains(t) ? theatreSystem : t == .wii ? .wii : .all
        theatreSystem = s
        theatreTheme = t
        settings.theatreTheme = t
        settings.theatreSystem = s
        settings.theatreLooks[s.rawValue] = t.rawValue
    }

    /// ZL and ZR on Theatre: the system's next look
    func stepTheatreLook(_ d: Int) {
        setTheatreSystem(theatreSystem, theme: theatreSystem.look(after: theatreTheme, d))
    }

    /// The dice: what should I play? (from the picker it applies the look in focus first)
    func surpriseTheatre() {
        if theatrePicker != nil { applyTheatrePicker() }
        theatreMenu = nil
        shuffleTheatre()
    }

    /// The gear: Settings, on Theatre's section
    func openTheatreSettings() {
        if theatrePicker != nil { cancelTheatrePicker() }
        theatreMenu = nil
        settingsFocus = StageSettingRow.theatreTheme.rawValue
        settingsSection = .theatre
        stageSettings = true
    }

    /// A controller's button while the picker is up
    func pickerPad(_ k: PadKey) {
        switch k {
        case .left, .zl: pickerStep(system: -1)
        case .right, .zr: pickerStep(system: 1)
        case .up: pickerStep(look: -1)
        case .down: pickerStep(look: 1)
        case .a: applyTheatrePicker()
        case .b: cancelTheatrePicker()
        case .y, .l3: surpriseTheatre()
        case .menu: openTheatreSettings()
        default: break
        }
    }
}

/// The dice and the gear at the top right of Theatre: Surprise me (the shuffle, L3) and Settings
struct TheatreCorner: View {
    let model: AppModel
    var ink: Color = .white
    var size: CGFloat = 52
    @Environment(\.tu) private var u

    var body: some View {
        HStack(spacing: 12 * u) {
            button("dice.fill", "Surprise me (L3)") { model.surpriseTheatre() }
            button("gearshape.fill", "Settings") { model.openTheatreSettings() }
        }
    }

    func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.42 * u, weight: .semibold))
                .frame(width: size * u, height: size * u)
                .background(ink.opacity(0.10), in: .circle)
                .overlay(Circle().strokeBorder(ink.opacity(0.18), lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Sizes on the picker, in 1080ths of the height
enum PickerLayout {
    static let side: CGFloat = 64
    static let top: CGFloat = 180
    static let height: CGFloat = 560
    static let sliver: CGFloat = 124
    static let gap: CGFloat = 14
    static let widest: CGFloat = 1180

    /// the open panel's width for `n` panels across `width`
    static func open(_ n: Int, width: CGFloat) -> CGFloat {
        min(width - 2 * side - CGFloat(n - 1) * (sliver + gap), widest)
    }
}

struct TheatrePickerView: View {
    @Bindable var model: AppModel
    let state: TheatrePickerState
    /// Theatre's room, drawn at the open panel's size
    let stage: AnyView
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let systems = model.theatreSystems()
        let focus = state.system
        let at = systems.firstIndex(of: focus) ?? 0
        GeometryReader { geo in
            let W = geo.size.width / u
            let open = PickerLayout.open(systems.count, width: W)
            let rowW = open + CGFloat(systems.count - 1) * (PickerLayout.sliver + PickerLayout.gap)
            ZStack(alignment: .topLeading) {
                background(focus.accent)
                header(W)
                HStack(alignment: .center, spacing: PickerLayout.gap * u) {
                    ForEach(Array(systems.enumerated()), id: \.element) { i, s in
                        if s == focus {
                            openPanel(s, width: open)
                        } else {
                            sliver(s, side: i < at ? -1 : 1, distance: abs(i - at))
                                .onTapGesture { model.pickerFocus(s) }
                        }
                    }
                }
                .frame(width: rowW * u, height: PickerLayout.height * u)
                .position(x: geo.size.width / 2, y: (PickerLayout.top + PickerLayout.height / 2) * u)
                .animation(still ? nil : .spring(duration: 0.5, bounce: 0.14), value: focus)
                foot(W)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    // MARK: the room

    func background(_ accent: Color) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.20), Color(red: 0.04, green: 0.04, blue: 0.11), Color(red: 0.10, green: 0.05, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [accent.opacity(0.30), .clear], center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 900 * u)
                .animation(.easeInOut(duration: 0.5), value: state.system)
        }
        .ignoresSafeArea()
        .onTapGesture { model.cancelTheatrePicker() }
    }

    func header(_ W: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Theatre").font(.system(size: 30 * u, weight: .semibold)).opacity(0.8)
                Text("Theme Picker").font(.system(size: 64 * u, weight: .bold)).tracking(-0.8 * u)
            }
            Spacer()
            HStack(alignment: .top, spacing: 22 * u) {
                VStack(spacing: 10 * u) {
                    round("dice.fill", "Surprise me (Y)") { model.surpriseTheatre() }
                    HStack(spacing: 8 * u) { TheatreHints(model: model).glyph("Y"); Text("Surprise me") }
                        .font(.system(size: 18 * u, weight: .semibold))
                        .padding(.horizontal, 14 * u).padding(.vertical, 6 * u)
                        .background(.white.opacity(0.10), in: .capsule).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                        .fixedSize()
                }
                round("gearshape.fill", "Settings (+)") { model.openTheatreSettings() }
            }
        }
        .padding(.horizontal, PickerLayout.side * u).padding(.top, 34 * u)
        .frame(width: W * u)
    }

    func round(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 36 * u, weight: .semibold))
                .frame(width: 84 * u, height: 84 * u)
                .background(.white.opacity(0.10), in: .circle).overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    // MARK: the panels

    func openPanel(_ s: TheatreSystem, width: CGFloat) -> some View {
        let r = 30 * u
        let w = width * u, h = PickerLayout.height * u
        // the room at the panel's size: its own 1080ths of the panel's height, so it lays out as on the TV, smaller
        let pu = u * PickerLayout.height / 1080
        return stage
            .environment(\.tu, pu)
            .frame(width: w, height: h)
            .allowsHitTesting(false)
            .id(state.look(s).rawValue + s.rawValue)
            .transition(.opacity)
            .clipShape(.rect(cornerRadius: r))
            .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(s.accent.mix(with: .white, by: 0.45), lineWidth: 4 * u))
            .shadow(color: s.accent.opacity(0.75), radius: 30 * u)
            .contentShape(.rect(cornerRadius: r))
            .onTapGesture { model.applyTheatrePicker() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(s.rawValue), \(state.look(s).rawValue), selected")
            .accessibilityAddTraits([.isButton, .isSelected])
    }

    func sliver(_ s: TheatreSystem, side: Int, distance: Int) -> some View {
        let r = 22 * u
        let w = PickerLayout.sliver * u, h = PickerLayout.height * u * (distance > 1 ? 0.9 : 0.96)
        return ZStack {
            LinearGradient(colors: [s.accent, s.accent.mix(with: .black, by: 0.55)], startPoint: .top, endPoint: .bottom)
            if let art = art(s) {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h * 0.55).clipped()
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .center))
                    .frame(width: w, height: h, alignment: .bottom)
                    .opacity(0.85)
            }
            LinearGradient(colors: [s.accent.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
        }
        .frame(width: w, height: h)
        // the name up the side, turned about its top left corner so it reads from the foot up, starting near the top
        .overlay(alignment: .topLeading) {
            Text(s.short)
                .font(.system(size: 46 * u, weight: .bold)).lineLimit(1).fixedSize()
                .shadow(color: .black.opacity(0.4), radius: 6 * u)
                .rotationEffect(.degrees(-90), anchor: .topLeading)
                .offset(x: 30 * u, y: 36 * u + textLength(s))
        }
        .overlay(alignment: .bottom) {
            Image(systemName: s.symbol).font(.system(size: 22 * u, weight: .semibold)).opacity(0.85).padding(.bottom, 22 * u)
        }
        .clipShape(.rect(cornerRadius: r))
        .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(.white.opacity(0.22), lineWidth: 1.5))
        .brightness(distance > 1 ? -0.08 : 0)
        .rotation3DEffect(.degrees(Double(side) * -14), axis: (x: 0, y: 1, z: 0), anchor: side < 0 ? .trailing : .leading, perspective: 0.6)
        .shadow(color: .black.opacity(0.5), radius: 18 * u, y: 10 * u)
        .contentShape(.rect)
        .help("\(s.rawValue): \(s.note)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.rawValue)
        .accessibilityAddTraits(.isButton)
    }

    /// how far the turned name reaches up the sliver (it is turned about its top left corner)
    func textLength(_ s: TheatreSystem) -> CGFloat {
        let a = NSAttributedString(string: s.short, attributes: [.font: NSFont.systemFont(ofSize: 46 * u, weight: .bold)])
        return a.size().width
    }

    /// a system's art for its sliver: the wide art of its game played last (else its first), on All games any game's
    func art(_ s: TheatreSystem) -> NSImage? {
        let games = model.stageGames().filter { g in s.console.map { g.console == $0 } ?? true }
        let built = games.filter { $0.app != nil }
        let pick = AppModel.lastPlayed(built.isEmpty ? games : built) ?? games.first
        guard let g = pick else { return nil }
        return CoverStore.shared.hero(g.coverKey) ?? CoverArt.wide(g) ?? CoverArt.front(g)
    }

    // MARK: the words under the band, and the buttons

    func foot(_ W: CGFloat) -> some View {
        let s = state.system
        let look = state.look(s)
        let looks = s.looks.contains(look) ? s.looks : [look] + s.looks
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 22 * u) {
                Text(s.rawValue).font(.system(size: 58 * u, weight: .bold)).tracking(-0.6 * u)
                Text(s.note).font(.system(size: 24 * u, weight: .medium)).opacity(0.7)
            }
            .contentTransition(.opacity)
            // the system's looks: the one on, and ↑ ↓ to step them
            HStack(spacing: 12 * u) {
                if looks.count > 1 {
                    HStack(spacing: 4 * u) { Image(systemName: "arrow.up"); Image(systemName: "arrow.down") }
                        .font(.system(size: 18 * u, weight: .bold)).opacity(0.7).padding(.trailing, 4 * u)
                }
                ForEach(looks, id: \.self) { t in
                    let on = t == look
                    Button { pickLook(t) } label: {
                        HStack(spacing: 8 * u) {
                            Image(systemName: t == .showcase ? model.showcaseLayout.symbol : t.symbol)
                            Text(t.rawValue)
                        }
                        .font(.system(size: 20 * u, weight: .semibold))
                        .padding(.horizontal, 16 * u).frame(height: 42 * u)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background(on ? Color.white : Color.white.opacity(0.08), in: .capsule)
                        .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.16), lineWidth: 1))
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
                Text(look.note).font(.system(size: 20 * u)).opacity(0.7).lineLimit(1).padding(.leading, 8 * u)
            }
            .padding(.top, 14 * u)
            .animation(.easeInOut(duration: 0.2), value: look)
            Spacer(minLength: 0)
            // the bar of buttons along the foot
            HStack(spacing: 34 * u) {
                hint("←", "→", "Browse")
                if looks.count > 1 { hint("↑", "↓", "Look") }
                hint("A", "Apply", filled: true)
                hint("B", "Back")
                Spacer()
                hint("Y", "Surprise me")
                hint("+", "Settings")
            }
            .font(.system(size: 20 * u, weight: .medium))
            .padding(.horizontal, 30 * u).frame(height: 66 * u)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 18 * u))
            .overlay(RoundedRectangle(cornerRadius: 18 * u).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .padding(.horizontal, PickerLayout.side * u)
        .padding(.top, (PickerLayout.top + PickerLayout.height + 30) * u)
        .padding(.bottom, 34 * u)
        .frame(width: W * u)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    func pickLook(_ t: TheatreTheme) {
        guard let p = model.theatrePicker, let i = p.system.looks.firstIndex(of: t) else { return }
        let now = p.system.looks.firstIndex(of: p.look(p.system)) ?? 0
        if i != now { model.pickerStep(look: i - now) }
    }

    func hint(_ k: String, _ text: String, filled: Bool = false) -> some View {
        HStack(spacing: 8 * u) { key(k, filled: filled); Text(text) }
    }

    func hint(_ k1: String, _ k2: String, _ text: String) -> some View {
        HStack(spacing: 8 * u) { key(k1); key(k2); Text(text) }
    }

    /// a controller's button, or an arrow drawn as the d-pad's
    @ViewBuilder func key(_ k: String, filled: Bool = false) -> some View {
        if ["←", "→", "↑", "↓"].contains(k) {
            Image(systemName: ["←": "dpad.left.filled", "→": "dpad.right.filled", "↑": "dpad.up.filled", "↓": "dpad.down.filled"][k] ?? "dpad")
                .font(.system(size: 28 * u, weight: .regular)).opacity(0.9)
        } else {
            TheatreHints(model: model).glyph(k, filled: filled)
        }
    }
}
