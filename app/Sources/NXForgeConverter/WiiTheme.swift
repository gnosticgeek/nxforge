// Theatre's Wii theme (to Tom's mock-up, 2026-11-27): the Wii and GameCube games as a light blue game library. The games are white
// pill buttons down the left, the one in focus outlined in cyan with a chevron; the right is one big white card with the game's
// screenshot in a curved window, the console's wordmark in the corner the window leaves, a tray saying which controller it takes and
// for how many players, and under it the title with your stars, publisher, year, genre and age rating, a two-line blurb and the
// game's logo. Up and down browse, left and right give it stars, A plays.
//
// The artwork (Art/TheatreWii, from the mock-up) is laid out on the mock-up's own 1920 × 1080 grid, scaled to fit the screen, with the
// background filling whatever is left round it. The facts are GameTDB's, the screenshot and logo libretro's (WiiTheatreInfo.swift);
// a game they do not know shows its box art in the window and its name in place of the logo.
import AppKit
import SwiftUI

enum WiiLook {
    static let ink = Color(red: 0.11, green: 0.15, blue: 0.20)
    static let soft = Color(red: 0.24, green: 0.30, blue: 0.37)
    static let row = Color(red: 0.17, green: 0.22, blue: 0.29)
    static let selected = Color(red: 0.05, green: 0.15, blue: 0.27)
    static let cyan = Color(red: 0.13, green: 0.71, blue: 0.85)
    static let rule = Color(red: 0.80, green: 0.85, blue: 0.89)

    static func font(_ size: CGFloat, _ weight: String = "Medium") -> Font { .custom("AvenirNext-\(weight)", size: size) }

    /// The mock-up's grid
    static let width: CGFloat = 1920, height: CGFloat = 1080
    /// the game buttons: the first one's face at (62, 166), 469 × 87, one every 105 points, seven in view
    static let rowX: CGFloat = 62, rowTop: CGFloat = 166, rowStep: CGFloat = 105, rowsShown = 7
    /// the screenshot's window (the aperture mask's opening, a little over it so the rim covers the edge)
    static let window = CGRect(x: 598, y: 68, width: 1248, height: 692)

    /// The theme's artwork, read once: in the app's Resources/Art/TheatreWii, else the checkout's app/Art/TheatreWii
    @MainActor static func art(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        guard let d = artDir, let i = NSImage(contentsOf: d.appending(path: name + ".png")) else { return nil }
        cache[name] = i
        return i
    }
    @MainActor private static var cache: [String: NSImage] = [:]
    static let artDir: URL? = {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appending(path: "Art/TheatreWii"), fm.fileExists(atPath: r.path) { return r }
        var d = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let x = d else { break }
            for sub in ["Art/TheatreWii", "app/Art/TheatreWii"] where fm.fileExists(atPath: x.appending(path: sub).path) { return x.appending(path: sub) }
            d = x.deletingLastPathComponent()
        }
        return nil
    }()
}

extension View {
    /// Puts the view in a box of the mock-up's grid (x, y, width, height), at the scale the screen gives it
    func wiiBox(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat, _ alignment: Alignment = .topLeading) -> some View {
        frame(width: w * s, height: h * s, alignment: alignment).position(x: (x + w / 2) * s, y: (y + h / 2) * s)
    }
}

@MainActor
struct WiiArtImage: View {
    let name: String
    var body: some View {
        if let i = WiiLook.art(name) { Image(nsImage: i).resizable().interpolation(.high) } else { Color.clear }
    }
}

struct WiiTheme: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let _ = WiiArt.shared.revision
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        GeometryReader { geo in
            let s = min(geo.size.width / WiiLook.width, geo.size.height / WiiLook.height)
            ZStack {
                WiiArtImage(name: "background").aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                ZStack(alignment: .topLeading) {
                    WiiGameList(model: model, games: games, index: index, s: s)
                    WiiCard(model: model, game: focus, s: s)
                }
                .frame(width: WiiLook.width * s, height: WiiLook.height * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .animation(still ? nil : .easeOut(duration: 0.18), value: focus?.id)
        .task(id: games.map(\.id).joined(separator: "|")) { fetch(games) }
    }

    /// GameTDB's facts once, and libretro's screenshot and logo for each game shown
    func fetch(_ games: [StageGame]) {
        let s = model.settings
        let wanted = games.compactMap { g -> (key: String, gameID: String, title: String, gamecube: Bool)? in
            guard let id = Wii.gameID(titleID: g.titleID) else { return nil }
            let title = WiiTDB.shared.entry(id, download: s.downloadStoreInfo)?.title ?? g.name
            return (g.coverKey, id, title, g.console == .gamecube)
        }
        if s.downloadHeroes, !wanted.isEmpty { WiiArt.shared.fetchMissing(wanted) }
    }

    /// GameTDB's facts for a game, when there are any and the setting allows them
    @MainActor static func facts(_ model: AppModel, _ g: StageGame) -> WiiTDBEntry? {
        WiiTDB.shared.entry(Wii.gameID(titleID: g.titleID), download: model.settings.downloadStoreInfo)
    }

    /// GameTDB's title ("Sonic & SEGA All-Stars Racing"), else the file's name
    @MainActor static func name(_ model: AppModel, _ g: StageGame) -> String { facts(model, g)?.title ?? g.name }
}

/// "Game Library", the games as pill buttons, and the button hints at the foot
struct WiiGameList: View {
    let model: AppModel
    let games: [StageGame]
    let index: Int
    let s: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let first = Self.first(index: index, count: games.count)
        ZStack(alignment: .topLeading) {
            Text("Game Library").font(WiiLook.font(48 * s, "DemiBold")).kerning(-0.6 * s).foregroundStyle(WiiLook.ink)
                .lineLimit(1).fixedSize()
                .wiiBox(73, 72, 330, 66, s, .leading)
            Text(countText).font(WiiLook.font(20 * s)).foregroundStyle(WiiLook.soft)
                .lineLimit(1).fixedSize()
                .wiiBox(324, 96, 200, 34, s, .trailing)
            // the buttons, seven in view: the window moves to keep the one in focus in it
            ZStack(alignment: .topLeading) {
                ForEach(Array(games.enumerated()), id: \.element.id) { i, g in
                    WiiGameRow(name: WiiTheme.name(model, g), selected: i == index, s: s)
                        .wiiBox(WiiLook.rowX - 34, WiiLook.rowTop - 35 + CGFloat(i - first) * WiiLook.rowStep - 120, 537, 156, s)
                        .opacity(i < first - 1 || i > first + WiiLook.rowsShown ? 0 : 1)
                        .onTapGesture {
                            if g.id == model.theatreFocus { model.rememberTheatreFocus(); model.fix(g) } else { model.theatreFocus = g.id }
                            model.theatreTouched = Date()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(WiiTheme.name(model, g))
                        .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(width: 600 * s, height: (WiiLook.rowStep * CGFloat(WiiLook.rowsShown) + 60) * s, alignment: .topLeading)
            .clipped()
            .offset(y: 120 * s)
            .animation(still ? nil : .spring(duration: 0.35, bounce: 0.1), value: first)
            if games.isEmpty {
                Text("Your Wii and GameCube games appear here once a Wii games folder is chosen in Settings › Library.")
                    .font(WiiLook.font(22 * s)).foregroundStyle(WiiLook.soft).lineSpacing(6 * s)
                    .wiiBox(74, 170, 440, 200, s)
            }
            Rectangle().fill(WiiLook.rule).wiiBox(74, 936, 444, 1.5, s)
            hints
        }
    }

    var countText: String {
        let n = games.count == 1 ? "1 game" : "\(games.count) games"
        let f = model.theatreShownFilter
        return f == .all ? n : "\(f.title) · \(n)"
    }

    /// The D-pad's Browse and A's Play (or Continue, or what the game needs first)
    @ViewBuilder var hints: some View {
        WiiArtImage(name: "dpad-button").wiiBox(66.5, 956.5, 45, 45, s)
        Text("Browse").font(WiiLook.font(21 * s)).foregroundStyle(WiiLook.soft).fixedSize().wiiBox(117, 962, 100, 34, s, .leading)
        if games.indices.contains(index) {
            let g = games[index]
            Button { model.theatreFocus = g.id; model.rememberTheatreFocus(); model.fix(g) } label: {
                HStack(spacing: 6 * s) {
                    WiiArtImage(name: "a-button").frame(width: 46 * s, height: 45 * s)
                    Text(model.theatreAction(g)).font(WiiLook.font(21 * s)).foregroundStyle(WiiLook.soft).fixedSize()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .wiiBox(213.5, 956.5, 300, 45, s, .leading)
        }
    }

    /// The first button in view: the one in focus stays in the window of seven, two from its edge while the list goes on
    static func first(index: Int, count: Int) -> Int {
        let n = WiiLook.rowsShown
        guard count > n else { return 0 }
        return min(max(index - (n - 3), 0), count - n)
    }
}

struct WiiGameRow: View {
    let name: String
    let selected: Bool
    let s: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            WiiArtImage(name: selected ? "row-selected" : "row")
            Text(name)
                .font(WiiLook.font(28 * s, selected ? "Bold" : "Medium"))
                .kerning(-0.4 * s)
                .foregroundStyle(selected ? WiiLook.selected : WiiLook.row)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: (selected ? 375 : 420) * s, height: 87 * s, alignment: .leading)
                .offset(x: 66 * s, y: 35 * s)
            if selected {
                WiiArtImage(name: "selected-chevron").frame(width: 27 * s, height: 27 * s).offset(x: 448.25 * s, y: 65 * s)
            }
        }
        .frame(width: 537 * s, height: 156 * s)
    }
}

/// The big white card: the screenshot in its curved window, the wordmark, the controller tray, the title, facts, blurb and logo
struct WiiCard: View {
    let model: AppModel
    let game: StageGame?
    let s: CGFloat

    var body: some View {
        let facts = game.flatMap { WiiTheme.facts(model, $0) }
        ZStack(alignment: .topLeading) {
            // the screenshot, cut to the window's curve
            media.frame(width: WiiLook.window.width * s, height: WiiLook.window.height * s).clipped()
                .position(x: WiiLook.window.midX * s, y: WiiLook.window.midY * s)
                .frame(width: WiiLook.width * s, height: WiiLook.height * s, alignment: .topLeading)
                .mask { WiiArtImage(name: "aperture") }
                .id(game?.id)
                .transition(.opacity)
            WiiArtImage(name: "card").frame(width: WiiLook.width * s, height: WiiLook.height * s)
            wordmark
            if let game { tray(game, facts); about(game, facts); logo(game, facts) }
        }
        .frame(width: WiiLook.width * s, height: WiiLook.height * s, alignment: .topLeading)
    }

    @ViewBuilder var media: some View {
        if let g = game, let snap = WiiArt.shared.image(g.coverKey, .snap) {
            Image(nsImage: snap).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else if let g = game, let front = CoverArt.front(g) {
            // no screenshot: the box, over its own colours spread out of focus
            ZStack {
                Image(nsImage: front).resizable().aspectRatio(contentMode: .fill).blur(radius: 40 * s).opacity(0.85)
                Color.white.opacity(0.18)
                Image(nsImage: front).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(height: 520 * s)
                    .shadow(color: .black.opacity(0.35), radius: 24 * s, y: 12 * s)
                    .offset(x: 90 * s, y: 20 * s)
            }
        } else {
            LinearGradient(colors: [Color(red: 0.80, green: 0.91, blue: 0.97), Color(red: 0.62, green: 0.80, blue: 0.92)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The console's wordmark in the corner the window's curve leaves, the cyan rule under it
    @ViewBuilder var wordmark: some View {
        if game?.console == .gamecube {
            Text("GameCube").font(.system(size: 54 * s, weight: .heavy, design: .rounded)).kerning(-1 * s)
                .foregroundStyle(Color(white: 0.55)).lineLimit(1).fixedSize()
                .wiiBox(1520, 100, 300, 70, s, .trailing)
        } else {
            WiiArtImage(name: "wii-system-wordmark").wiiBox(1670, 100, 151, 67, s)
        }
        WiiArtImage(name: "wordmark-accent").wiiBox(1733, 180, 91, 16, s)
    }

    /// "Wii Remote + Nunchuk, 1–2 players" in the tray at the window's foot
    func tray(_ g: StageGame, _ facts: WiiTDBEntry?) -> some View {
        let gc = g.console == .gamecube
        let (one, two) = facts?.controller(gamecube: gc) ?? (gc ? ("GameCube", "Controller") : ("Wii", nil))
        let pair = facts?.nunchuk == true && !gc
        return ZStack(alignment: .topLeading) {
            WiiArtImage(name: "tray").frame(width: 218 * s, height: 116 * s)
            Group {
                if gc || one == "Classic" {
                    Image(systemName: "gamecontroller").font(.system(size: 34 * s, weight: .regular)).foregroundStyle(WiiLook.soft)
                        .frame(width: 61 * s, height: 58 * s)
                } else if pair {
                    WiiArtImage(name: "wii-remote-and-nunchuk").frame(width: 61 * s, height: 58 * s)
                } else {
                    WiiArtImage(name: "wii-remote").frame(width: 22 * s, height: 55 * s).frame(width: 61 * s, height: 58 * s)
                }
            }
            .offset(x: 19 * s, y: 25 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(one).font(WiiLook.font(15.5 * s, "Bold"))
                if let two { Text(two).font(WiiLook.font(15.5 * s, "Bold")) }
                if let p = facts?.playersText { Text(p).font(WiiLook.font(13.5 * s, "DemiBold")).foregroundStyle(WiiLook.soft).padding(.top, 3 * s) }
            }
            .foregroundStyle(WiiLook.ink).lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: 118 * s, height: 96 * s, alignment: .leading)
            .offset(x: 93 * s, y: 10 * s)
        }
        .wiiBox(595, 645, 218, 116, s)
        .accessibilityElement(children: .combine)
    }

    /// The title and its stars, "Nintendo · 2007 · Adventure / Platformer [E Everyone]", the blurb
    func about(_ g: StageGame, _ facts: WiiTDBEntry?) -> some View {
        let line = [facts?.publisher, facts?.year.map(String.init), facts?.genreText ?? model.discover.genres(of: g).first].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 22 * s) {
                Text(WiiTheme.name(model, g)).font(WiiLook.font(48 * s, "DemiBold")).kerning(-1.4 * s).foregroundStyle(WiiLook.ink)
                    .lineLimit(1).minimumScaleFactor(0.55)
                WiiStars(stars: model.settings.gameStars[g.favoriteKey] ?? 0, s: s).padding(.top, 4 * s)
            }
            .frame(height: 70 * s)
            HStack(spacing: 14 * s) {
                ForEach(Array(line.enumerated()), id: \.offset) { i, t in
                    if i > 0 { Text("•").font(WiiLook.font(12 * s)).foregroundStyle(WiiLook.soft.opacity(0.8)) }
                    Text(t)
                }
                if let facts { WiiRatingBadge(facts: facts, s: s).padding(.leading, 4 * s) }
            }
            .font(WiiLook.font(20.5 * s)).foregroundStyle(WiiLook.soft).lineLimit(1)
            .frame(height: 40 * s)
            if let blurb = facts?.shortSynopsis {
                Text(blurb).font(WiiLook.font(22 * s, "Regular")).foregroundStyle(WiiLook.ink.opacity(0.92))
                    .lineSpacing(7 * s).lineLimit(2).padding(.top, 14 * s)
            } else {
                Text(StageLook.played(g.last) + (g.total > 60 ? " · \(Playtime.text(g.total)) played" : ""))
                    .font(WiiLook.font(22 * s, "Regular")).foregroundStyle(WiiLook.soft).padding(.top, 14 * s)
            }
        }
        .wiiBox(620, 790, 880, 200, s)
        .id(g.id).transition(.opacity)
    }

    /// The game's logo beside a thin rule, else its box
    func logo(_ g: StageGame, _ facts: WiiTDBEntry?) -> some View {
        ZStack {
            if let l = WiiArt.shared.image(g.coverKey, .logo) {
                Image(nsImage: l).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.18), radius: 6 * s, y: 3 * s)
            } else if let f = CoverStore.shared.image(g.coverKey, .front) {
                Image(nsImage: f).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 6 * s))
                    .shadow(color: .black.opacity(0.22), radius: 8 * s, y: 4 * s)
                    .padding(.vertical, 2 * s)
            }
        }
        .wiiBox(1535, 800, 295, 180, s, .center)
        .overlay { Rectangle().fill(WiiLook.rule).wiiBox(1512, 805, 1.5, 170, s) }
        .id(g.id).transition(.opacity)
    }
}

/// Your stars for the game (left and right on this theme): cyan, the empty ones faint
struct WiiStars: View {
    let stars: Int
    let s: CGFloat
    var body: some View {
        HStack(spacing: -1 * s) {
            ForEach(0..<5, id: \.self) { i in
                WiiArtImage(name: i < stars ? "star-filled" : "star-empty").frame(width: 26 * s, height: 26 * s)
                    .opacity(i < stars ? 1 : 0.55)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stars == 0 ? "Not rated, left and right rate it" : "\(stars) of 5 stars")
    }
}

/// The age rating: the mock-up's E for Everyone, else the same white chip with the board's letter and words
struct WiiRatingBadge: View {
    let facts: WiiTDBEntry
    let s: CGFloat
    var body: some View {
        if facts.board?.uppercased() == "ESRB", facts.rating == "E" {
            WiiArtImage(name: "rating-e-everyone").frame(width: 132 * s, height: 44 * s).padding(.horizontal, -6 * s)
        } else if let words = facts.ratingWords {
            HStack(spacing: 7 * s) {
                if facts.board?.uppercased() == "ESRB", let r = facts.rating {
                    Text(r).font(WiiLook.font(r.count > 1 ? 11 * s : 15 * s, "Bold")).foregroundStyle(.white)
                        .frame(minWidth: 22 * s, minHeight: 22 * s).padding(.horizontal, r.count > 1 ? 2 * s : 0)
                        .background(WiiLook.ink, in: .rect(cornerRadius: 3 * s))
                }
                Text(words).font(WiiLook.font(16 * s, "DemiBold")).foregroundStyle(WiiLook.ink)
            }
            .padding(.leading, 5 * s).padding(.trailing, 10 * s).frame(height: 32 * s)
            .background(.white, in: .rect(cornerRadius: 6 * s))
            .overlay(RoundedRectangle(cornerRadius: 6 * s).strokeBorder(WiiLook.rule, lineWidth: 1))
        }
    }
}
