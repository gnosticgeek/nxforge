// The Wallet, a Theatre theme (0.52.0): your games as their game cards in a zip-up card wallet lying open, twenty-four to a
// page (two halves of twelve pockets). The card in focus stands up out of its pocket. The arrows move from pocket to pocket;
// going past a page's edge turns to the next page of cards.
import SwiftUI

/// The wallet's shape, in 1080ths of the height (tested)
enum WalletLayout {
    /// pockets across (four on each half) and down
    static let columns = 8, rows = 3
    static let perPage = columns * rows
    static let cardWidth = 118.0, cardHeight = 118.0 * 148 / 100
    static let gapX = 24.0, gapY = 26.0, spine = 54.0, edge = 34.0

    static var halfWidth: Double { Double(columns / 2) * cardWidth + Double(columns / 2 + 1) * gapX }
    static var width: Double { 2 * halfWidth + spine }
    static var height: Double { Double(rows) * cardHeight + Double(rows + 1) * gapY }

    static func pages(_ count: Int) -> Int { max((count + perPage - 1) / perPage, 1) }
    static func page(of index: Int) -> Int { max(index, 0) / perPage }

    /// a pocket's middle from the wallet's middle
    static func place(slot: Int) -> CGPoint {
        let c = slot % columns, r = slot / columns
        let half = c < columns / 2 ? 0.0 : halfWidth + spine
        let x = -width / 2 + half + gapX + cardWidth / 2 + Double(c % (columns / 2)) * (cardWidth + gapX)
        let y = -height / 2 + gapY + cardHeight / 2 + Double(r) * (cardHeight + gapY)
        return CGPoint(x: x, y: y)
    }

    /// The game the focus moves to from game `i` of `count`: along the row and up and down within a page, and over the page's
    /// edge to the same row of the next (round from the last page to the first)
    static func move(from i: Int, dx: Int = 0, dy: Int = 0, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let i = min(max(i, 0), count - 1)
        let p = i / perPage, r = (i % perPage) / columns, c = i % columns
        if dy != 0 {
            let to = p * perPage + min(max(r + dy, 0), rows - 1) * columns + c
            // a short last row: down lands on its last card
            let got = min(to, count - 1)
            return (got % perPage) / columns == r && got / perPage == p ? i : got
        }
        let n = pages(count)
        let nc = c + dx
        if (0..<columns).contains(nc) {
            let to = p * perPage + r * columns + nc
            if to < count { return to }
            // past the last card: round to the first page
            return min(r * columns, count - 1)
        }
        let np = ((p + (dx > 0 ? 1 : -1)) % n + n) % n
        return min(np * perPage + r * columns + (dx > 0 ? 0 : columns - 1), count - 1)
    }
}

extension AppModel {
    /// The arrows on the Wallet
    func walletPad(_ k: PadKey, games: [StageGame], focus: StageGame?) {
        guard !games.isEmpty else { return }
        let i = games.firstIndex { $0.id == focus?.id } ?? 0
        let to = WalletLayout.move(from: i, dx: k == .left ? -1 : k == .right ? 1 : 0, dy: k == .up ? -1 : k == .down ? 1 : 0, count: games.count)
        guard to != i else { return }
        theatreFocus = games[to].id
        // a new page of cards turns over like a leaf; a card is a tick
        theatreCue(WalletLayout.page(of: to) != WalletLayout.page(of: i) ? .page : .step)
    }
}

struct WalletTheme: View {
    @Bindable var model: AppModel
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let games = model.theatreGames()
        let focus = model.theatreFocused(games)
        let index = games.firstIndex { $0.id == focus?.id } ?? 0
        let page = WalletLayout.page(of: index), pages = WalletLayout.pages(games.count)
        let tint = focus.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
        ZStack {
            StageBackdrop(tint: tint, art: focus.flatMap { CoverArt.ambient($0) }, artKey: focus?.id ?? "")
            LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0.55), location: 0.5), .init(color: .black.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                TheatreTopBar(theme: .wallet, model: model)
                Spacer(minLength: 0)
                WalletPage(model: model, games: games, page: page, focus: focus)
                    .id(page)
                    .transition(still ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
                    .frame(width: (WalletLayout.width + 2 * WalletLayout.edge) * u, height: (WalletLayout.height + 2 * WalletLayout.edge) * u)
                // which page of cards this is
                HStack(spacing: 9 * u) {
                    ForEach(0..<pages, id: \.self) { p in
                        Capsule().fill(.white.opacity(p == page ? 0.9 : 0.28)).frame(width: (p == page ? 26 : 9) * u, height: 9 * u)
                    }
                }
                .opacity(pages > 1 ? 1 : 0)
                .padding(.top, 16 * u)
                Spacer(minLength: 0)
                if let g = focus {
                    VStack(spacing: 10 * u) {
                        Text(g.name).font(.system(size: 46 * u, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.6), radius: 18 * u, y: 4 * u)
                        Text(CarouselTheme.facts(g)).font(.system(size: 21 * u)).tracking(1.2 * u).foregroundStyle(StageLook.soft)
                    }
                    .id(g.id).transition(.opacity)
                    .padding(.horizontal, 120 * u)
                }
                HStack(alignment: .bottom) {
                    if !games.isEmpty {
                        (Text(String(format: "%02d", index + 1)).foregroundStyle(.white).fontWeight(.semibold) + Text("  /  " + String(format: "%02d", games.count) + "   CARDS").foregroundStyle(StageLook.faint))
                            .font(.system(size: 19 * u)).tracking(3 * u).monospacedDigit()
                    }
                    Spacer()
                    TheatreHints(model: model, focus: focus)
                }
                .padding(.horizontal, 96 * u).padding(.top, 22 * u).padding(.bottom, 42 * u)
            }
            .animation(TheatreMotion.swapAnimation, value: focus?.id)
            .animation(still ? nil : .easeInOut(duration: 0.3), value: page)
        }
    }
}

/// One page of the wallet: its fabric, its zip, the fold down the middle, and twenty-four pockets with the cards in them
struct WalletPage: View {
    let model: AppModel
    let games: [StageGame]
    let page: Int
    let focus: StageGame?
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let w = (WalletLayout.width + 2 * WalletLayout.edge) * u, h = (WalletLayout.height + 2 * WalletLayout.edge) * u
        let first = page * WalletLayout.perPage
        ZStack {
            fabric(w: w, h: h)
            ForEach(0..<WalletLayout.perPage, id: \.self) { slot in
                let p = WalletLayout.place(slot: slot)
                let k = first + slot
                let game = games.indices.contains(k) ? games[k] : nil
                let on = game != nil && game?.id == focus?.id
                WalletPocket(game: game, focused: on)
                    .frame(width: WalletLayout.cardWidth * u, height: WalletLayout.cardHeight * u)
                    .scaleEffect(on ? 1.3 : 1)
                    .offset(y: on ? -12 * u : 0)
                    .position(x: w / 2 + p.x * u, y: h / 2 + p.y * u)
                    .zIndex(on ? 1 : 0)
                    .onTapGesture {
                        guard let game else { return }
                        if on { model.theatrePad(.a) } else { model.theatreFocus = game.id; model.theatreTouched = Date() }
                    }
            }
        }
        .frame(width: w, height: h)
        .animation(still ? nil : .spring(duration: 0.32, bounce: 0.25), value: focus?.id)
    }

    /// The open wallet: dark woven fabric, the zip's teeth round its edge, and the fold between its halves
    func fabric(w: CGFloat, h: CGFloat) -> some View {
        let r = 34 * u
        return ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.17), Color(red: 0.07, green: 0.075, blue: 0.095)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.75), radius: 44 * u, y: 26 * u)
            // the zip: its tape, and its teeth
            RoundedRectangle(cornerRadius: r).strokeBorder(Color(white: 0.04), lineWidth: 11 * u)
            RoundedRectangle(cornerRadius: r - 3 * u).strokeBorder(Color(white: 0.62).opacity(0.8), style: StrokeStyle(lineWidth: 4 * u, dash: [3 * u, 4 * u])).padding(3.5 * u)
            // the stitching inside the zip
            RoundedRectangle(cornerRadius: r - 14 * u).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.2 * u, dash: [7 * u, 6 * u])).padding(17 * u)
            // the fold
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.7), .black.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: WalletLayout.spine * 1.5 * u, height: h - 24 * u)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1.5 * u, height: h - 40 * u)
        }
    }
}

/// A pocket and the card in it: the card shows whole behind a clear sleeve; an empty pocket is just the sleeve
struct WalletPocket: View {
    let game: StageGame?
    let focused: Bool
    @Environment(\.tu) private var u

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // the pocket's back
                RoundedRectangle(cornerRadius: 9 * u).fill(.black.opacity(0.38))
                    .overlay(RoundedRectangle(cornerRadius: 9 * u).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                    .padding(-7 * u)
                if let game {
                    GameCardFace(game: game, red: game.console == .switch2, u: u)
                        .shadow(color: .black.opacity(focused ? 0.7 : 0.4), radius: (focused ? 16 : 5) * u, y: (focused ? 12 : 3) * u)
                        .shadow(color: focused ? CoverArt.tint(game).opacity(0.75) : .clear, radius: 18 * u)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(game.name + (focused ? ", selected" : ""))
                }
                // the clear sleeve over the pocket's lower part (the card in focus has come up out of it)
                if !focused {
                    UnevenRoundedRectangle(bottomLeadingRadius: 9 * u, bottomTrailingRadius: 9 * u)
                        .fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.3)).frame(height: 1.2 * u) }
                        .frame(width: w + 14 * u, height: h * 0.62 + 7 * u)
                        .position(x: w / 2, y: h - (h * 0.62 + 7 * u) / 2 + 7 * u)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
