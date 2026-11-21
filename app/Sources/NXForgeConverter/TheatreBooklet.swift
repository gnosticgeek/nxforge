// A booklet for every game (0.51.0). The booklet in the case's lid opens on Theatre (X with the case in the hand): two pages
// at a time, a leaf that turns over its spine, a paper sound and a tap in the controller for each turn. A game with a manual
// (a PDF, GameManual) has that as its booklet. One without gets a booklet NXForge makes from what it knows: the store's words
// about the game, its screenshots, what Quick settings does while you play, the game's facts and your own time with it.
import AppKit
import PDFKit
import simd
import SwiftUI

/// One page of a booklet
enum BookletPage: Equatable {
    /// the made booklet's front: the game's art and name
    case cover
    /// a page of the game's manual (a PDF), from 0
    case manual(Int)
    /// the store's words about the game; the first of them has the heading
    case about(first: Bool, paragraphs: [String])
    /// one or two of the store's screenshots
    case shots([URL])
    /// what the Mac adds while the game runs
    case playing
    /// the game's facts, and the player's own time with it
    case facts
    /// ruled lines, as booklets end with (it makes the pages even)
    case notes
    case back
}

enum Booklet {
    /// how much of the store's text a page takes, in characters, and how many pages of it at most
    static let pageChars = 760, aboutPages = 4
    /// how many of the store's screenshots go in, two to a page
    static let shots = 6

    /// A booklet's pages. With a manual they are the manual's; without, the made booklet's. A made booklet has an even number
    /// of pages, so its back cover is the last leaf's back.
    static func pages(manualPages: Int?, about: [String], excerpt: String?, shots: [URL]) -> [BookletPage] {
        if let n = manualPages, n > 0 { return (0..<n).map { .manual($0) } }
        var out: [BookletPage] = [.cover]
        var words = fill(about, limit: pageChars)
        if words.isEmpty, let e = excerpt, !e.isEmpty { words = [[e]] }
        for (i, p) in words.prefix(aboutPages).enumerated() { out.append(.about(first: i == 0, paragraphs: p)) }
        out.append(.playing)
        let pictures = Array(shots.prefix(Self.shots))
        for i in stride(from: 0, to: pictures.count, by: 2) { out.append(.shots(Array(pictures[i..<min(i + 2, pictures.count)]))) }
        out.append(.facts)
        if out.count % 2 == 0 { out.append(.notes) }
        out.append(.back)
        return out
    }

    /// The store's paragraphs shared out over pages of about `limit` characters: a long paragraph breaks between sentences
    static func fill(_ paragraphs: [String], limit: Int) -> [[String]] {
        var pieces: [String] = []
        for p in paragraphs.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !p.isEmpty {
            if p.count <= limit { pieces.append(p); continue }
            var now = ""
            for s in sentences(p) {
                if !now.isEmpty, now.count + s.count + 1 > limit { pieces.append(now); now = "" }
                now += (now.isEmpty ? "" : " ") + s
            }
            if !now.isEmpty { pieces.append(now) }
        }
        var pages: [[String]] = [], page: [String] = [], used = 0
        for p in pieces {
            if !page.isEmpty, used + p.count > limit { pages.append(page); page = []; used = 0 }
            page.append(p)
            used += p.count + 60   // the gap between paragraphs takes room too
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }

    static func sentences(_ p: String) -> [String] {
        var out: [String] = [], now = ""
        for word in p.split(separator: " ") {
            now += (now.isEmpty ? "" : " ") + word
            if let l = word.last, ".!?".contains(l) { out.append(now); now = "" }
        }
        if !now.isEmpty { out.append(now) }
        return out
    }

    /// The pages that face each other at each opening: the cover alone on the right, then pairs, the last page alone on the
    /// left when the count is even
    static func spreads(_ pages: Int) -> Int { pages / 2 + 1 }
    static func left(_ spread: Int) -> Int? { spread > 0 ? 2 * spread - 1 : nil }
    static func right(_ spread: Int, pages: Int) -> Int? { 2 * spread < pages ? 2 * spread : nil }
}

/// The booklet open on Theatre: whose it is, its pages, and where it is open
struct BookletState: Equatable, Identifiable {
    let id = UUID()
    /// the game's StageGame id
    let game: String
    let pages: [BookletPage]
    let manual: URL?
    /// a page's width over its height
    var aspect = 0.64
    var spread = 0
    /// the opening it is turning from, and when the turn began
    var from = 0
    var turned: Date?
    var opened = Date()
    /// when it was shut: it fades, then goes
    var leaving: Date?
    /// held still as it is (a snapshot), `held` of the way through its turn
    var frozen = false
    var held: Double?

    static let turnTime = 0.55, openTime = 0.3

    var spreads: Int { Booklet.spreads(pages.count) }
}

extension AppModel {
    /// X with the case in the hand: its booklet opens
    func openBooklet(_ g: StageGame) {
        let manual = GameManual.find(g)
        var count: Int?
        var aspect = 0.64
        if let m = manual, let doc = BookletPress.shared.document(m), doc.pageCount > 0 {
            count = doc.pageCount
            if let b = doc.page(at: 0)?.bounds(for: .cropBox), b.height > 0 { aspect = min(max(b.width / b.height, 0.5), 1.05) }
        }
        let store = settings.downloadStoreInfo ? StoreInfoStore.shared : nil
        if count == nil, settings.downloadStoreInfo { StoreInfoStore.shared.load(key: g.coverKey, titleID: g.titleID, name: g.name) }
        let info = store?.info(g.coverKey)
        let pages = Booklet.pages(manualPages: count, about: info?.about ?? [], excerpt: info?.excerpt, shots: store?.shots(g.coverKey) ?? [])
        booklet = BookletState(game: g.id, pages: pages, manual: count == nil ? nil : manual, aspect: aspect)
        theatreCue(.page)
    }

    func closeBooklet() {
        guard var b = booklet, b.leaving == nil else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || b.frozen { booklet = nil; return }
        b.leaving = Date()
        booklet = b
        let id = b.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BookletState.openTime))
            if self?.booklet?.id == id { self?.booklet = nil }
        }
    }

    /// A leaf over, forwards or back
    func turnBooklet(_ d: Int) {
        guard var b = booklet, b.leaving == nil else { return }
        let to = min(max(b.spread + d, 0), b.spreads - 1)
        guard to != b.spread else { return }
        b.from = b.spread
        b.spread = to
        b.turned = Date()
        booklet = b
        theatreCue(.page); theatreRumble(.page)
    }

    /// A controller's button, or its key, with the booklet open
    func bookletPad(_ k: PadKey) {
        guard let b = booklet else { return }
        switch k {
        case .right, .r, .down, .a: turnBooklet(1)
        case .left, .l, .up: turnBooklet(-1)
        // the manual itself, to zoom into a page
        case .y: if let m = b.manual, let g = stageGames().first(where: { $0.id == b.game }) { booklet = nil; openManual(m, title: g.name) }
        case .b, .menu, .x: closeBooklet(); theatreCue(.step)
        default: break
        }
    }
}

/// The manual's pages as pictures, drawn once each and kept
@MainActor
final class BookletPress {
    static let shared = BookletPress()
    private var url: URL?
    private var doc: PDFDocument?
    private let made = NSCache<NSString, NSImage>()

    func document(_ u: URL) -> PDFDocument? {
        if u == url, let doc { return doc }
        url = u
        doc = PDFDocument(url: u)
        return doc
    }

    /// Page `index` of the manual, `height` points high
    func page(_ u: URL, _ index: Int, height: CGFloat) -> NSImage? {
        let h = min(max((height / 200).rounded(.up) * 200, 200), 1600)
        let key = "\(u.path)#\(index)@\(Int(h))" as NSString
        if let i = made.object(forKey: key) { return i }
        guard let p = document(u)?.page(at: index) else { return nil }
        let b = p.bounds(for: .cropBox)
        guard b.height > 0 else { return nil }
        let img = p.thumbnail(of: NSSize(width: h * b.width / b.height, height: h), for: .cropBox)
        made.setObject(img, forKey: key)
        return img
    }
}

// MARK: The booklet open

/// The booklet over the case in the hand: two pages either side of its spine, and a leaf that turns over it
struct TheatreBookletView: View {
    let model: AppModel
    let state: BookletState
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    /// the tallest a page is, and the widest the open booklet is
    static let pageHeight = 800.0, openWidth = 1640.0, distance = 2600.0

    var body: some View {
        if let g = model.stageGames().first(where: { $0.id == state.game }) {
            let _ = CoverStore.shared.revision
            let h = min(Self.pageHeight, Self.openWidth / 2 / state.aspect) * u, w = h * state.aspect
            TimelineView(.animation(paused: state.frozen)) { ctx in
                let quick = still || state.frozen
                let p = state.held ?? (quick ? 1 : CaseSceneState.ease(state.turned.map { ctx.date.timeIntervalSince($0) / BookletState.turnTime } ?? 1))
                let up = quick ? 1 : CaseSceneState.ease(ctx.date.timeIntervalSince(state.opened) / BookletState.openTime)
                let gone = state.leaving.map { quick ? 1 : CaseSceneState.ease(ctx.date.timeIntervalSince($0) / BookletState.openTime) } ?? 0
                let seen = up * (1 - gone)
                ZStack {
                    Color.black.opacity(0.62 * seen).contentShape(.rect).onTapGesture { model.theatrePad(.a) }
                    leaves(g, turn: p, w: w, h: h)
                        .scaleEffect(0.86 + 0.14 * seen)
                        .offset(y: (-14 + 60 * (1 - seen)) * u)
                        .opacity(seen)
                    words(g).opacity(seen)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(g.name)'s booklet, page \(min(max(2 * state.spread, 1), state.pages.count)) of \(state.pages.count)")
        }
    }

    /// The booklet's place across the screen at an opening: the cover and the back sit in the middle, an open pair either side of it
    func shift(_ spread: Int, w: CGFloat) -> CGFloat { spread == 0 ? -w / 2 : spread == state.spreads - 1 && state.pages.count % 2 == 0 ? w / 2 : 0 }

    @ViewBuilder func leaves(_ g: StageGame, turn p: Double, w: CGFloat, h: CGFloat) -> some View {
        // a turn either way is a leaf going over from the lower opening to the next, part of the way
        let lo = min(state.from, state.spread), moving = state.from != state.spread && p < 1
        let at = moving ? lo : state.spread
        let q = moving ? (state.spread > state.from ? p : 1 - p) : 0
        let x = moving ? shift(lo, w: w) + (shift(lo + 1, w: w) - shift(lo, w: w)) * q : shift(state.spread, w: w)
        let d = Self.distance * u
        let size = CGSize(width: w, height: h)
        let n = state.pages.count
        ZStack {
            if let i = Booklet.left(at) { paper(g, i, w: w, h: h).solid(Solid.move(x - w / 2, 0), size: size, distance: d) }
            if moving, let i = Booklet.right(at + 1, pages: n) { paper(g, i, w: w, h: h).solid(Solid.move(x + w / 2, 0), size: size, distance: d) }
            if let i = Booklet.right(at, pages: n) {
                let hinge = Solid.move(x, 0) * Solid.turnY(-q * .pi)
                // the leaf lifts a little off the pages as it goes over
                let leaf = hinge * Solid.move(w / 2, 0, sin(q * .pi) * 6 * u)
                paper(g, i, w: w, h: h).solid(leaf, size: size, distance: d, shade: 0.4)
                if moving, i + 1 < n { paper(g, i + 1, w: w, h: h).solid(leaf * Solid.turnY(.pi), size: size, distance: d, shade: 0.4) }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 30 * u, y: 18 * u)
    }

    func paper(_ g: StageGame, _ i: Int, w: CGFloat, h: CGFloat) -> some View {
        BookletPaper(model: model, game: g, page: state.pages[i], index: i, count: state.pages.count, manual: state.manual)
            .frame(width: w, height: h)
    }

    func words(_ g: StageGame) -> some View {
        let hints = TheatreHints(model: model)
        let n = state.pages.count
        let l = Booklet.left(state.spread), r = Booklet.right(state.spread, pages: n)
        let at = [l, r].compactMap { $0.map { "\($0 + 1)" } }.joined(separator: " – ")
        return VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 30 * u) {
                Text("\(at)  /  \(n)").monospacedDigit().foregroundStyle(StageLook.faint).tracking(2 * u)
                hints.hint("←", "→", "Turn the page")
                if state.manual != nil { hints.hint("Y", "Zoom") }
                hints.hint("B", "Close")
            }
            .font(.system(size: 20 * u, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 30 * u)
        }
    }
}

/// One page of a booklet, at whatever size it is given: everything on it is sized from its height
struct BookletPaper: View {
    let model: AppModel
    let game: StageGame
    let page: BookletPage
    let index: Int
    let count: Int
    let manual: URL?

    static let paper = Color(red: 0.957, green: 0.937, blue: 0.894), ink = Color(red: 0.16, green: 0.14, blue: 0.11)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height / 800
            let right = index % 2 == 0
            ZStack {
                Self.paper
                content(s: s, size: geo.size)
                // the fold: the page darkens into the spine
                LinearGradient(colors: [.black.opacity(0.26), .black.opacity(0.05), .clear], startPoint: right ? .leading : .trailing, endPoint: UnitPoint(x: right ? 0.16 : 0.84, y: 0.5))
                    .allowsHitTesting(false)
            }
            .foregroundStyle(Self.ink)
            .clipShape(.rect(cornerRadius: 3 * s))
        }
    }

    @ViewBuilder func content(s: CGFloat, size: CGSize) -> some View {
        switch page {
        case .cover: BookletCover(game: game)
        case .manual(let i):
            if let m = manual, let img = BookletPress.shared.page(m, i, height: size.height * 2) {
                Color.white.overlay(Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit))
            }
        case .about(let first, let paragraphs):
            sheet(first ? "The game" : nil, s: s) {
                ForEach(paragraphs, id: \.self) { p in
                    Text(p).font(.system(size: 18.5 * s, design: .serif)).lineSpacing(5 * s).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .shots(let urls):
            sheet(nil, s: s) {
                ForEach(urls, id: \.self) { url in
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 4 * s))
                            .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Self.ink.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.25), radius: 6 * s, y: 3 * s)
                    }
                }
                Text("From the game's store page").font(.system(size: 13 * s, design: .serif)).italic().opacity(0.6)
            }
        case .playing:
            sheet("While you play", s: s) {
                line("Quick settings", "Esc on the keyboard, or Home on a controller, opens it over the game.", s: s)
                line("The picture", "Pixel-art scaling for 2D games, a CRT filter, sharper textures and a frame-rate counter.", s: s)
                line("Your controls", "Change what each button does, per game.", s: s)
                line("Cheats and mods", "Switch them on and off without leaving the game.", s: s)
                line("Keepsakes", "Take a screenshot or a recording. They show on the game's page.", s: s)
                line("Your save", "Kept on this Mac beside the game. NXForge can back it up each time you stop.", s: s)
            }
        case .facts:
            sheet("Your copy", s: s) {
                let r = model.playRecord(app: game.app, titleID: game.titleID)
                let info = model.settings.downloadStoreInfo ? StoreInfoStore.shared.info(game.coverKey) : nil
                fact("Played", game.total > 60 ? Playtime.text(game.total) : "Not yet", s: s)
                if let n = r?.sessions.count, n > 0 { fact("Sittings", "\(n)", s: s) }
                if let f = r?.sessions.map(\.start).min() { fact("First played", f.formatted(date: .abbreviated, time: .omitted), s: s) }
                if let l = game.last { fact("Last played", l.formatted(date: .abbreviated, time: .omitted), s: s) }
                Rectangle().fill(Self.ink.opacity(0.25)).frame(height: 1).padding(.vertical, 6 * s)
                fact("For", game.console.rawValue, s: s)
                if let p = info?.publisher ?? game.game?.publisher, !p.isEmpty { fact("Publisher", p, s: s) }
                if let d = info?.released { fact("Released", d, s: s) }
                if let p = info?.players { fact("Players", p, s: s) }
                if let g = info?.genres, !g.isEmpty { fact("Genre", g.prefix(3).joined(separator: ", "), s: s) }
                if let v = game.version, !v.isEmpty { fact("Version", v, s: s) }
                if let b = game.game?.bytes, b > 0 { fact("Size", Disk.gb(b), s: s) }
            }
        case .notes:
            sheet("Notes", s: s) {
                ForEach(0..<13, id: \.self) { _ in Rectangle().fill(Self.ink.opacity(0.22)).frame(height: 1).padding(.top, 30 * s) }
            }
        case .back:
            VStack(spacing: 10 * s) {
                Spacer()
                HStack(spacing: 0) {
                    Text("NX").font(.system(size: 22 * s, weight: .heavy))
                    Text("FORGE").font(.system(size: 22 * s, weight: .light))
                }
                .tracking(6 * s).opacity(0.7)
                Text("This booklet was made by NXForge from what it knows about the game. Add the game's own manual as a PDF on its page and it takes this one's place.")
                    .font(.system(size: 13.5 * s, design: .serif)).multilineTextAlignment(.center).lineSpacing(3 * s).opacity(0.6)
                    .padding(.horizontal, 70 * s).padding(.bottom, 64 * s)
            }
        }
    }

    /// A page of words: its heading, what is on it, and its number at the foot
    func sheet(_ heading: String?, s: CGFloat, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16 * s) {
            if let heading {
                Text(heading.uppercased()).font(.system(size: 15 * s, weight: .semibold, design: .serif)).tracking(3.5 * s).opacity(0.62)
                Rectangle().fill(Self.ink.opacity(0.5)).frame(width: 46 * s, height: 2 * s).padding(.bottom, 4 * s)
            }
            body()
            Spacer(minLength: 0)
            Text("\(index + 1)").font(.system(size: 13 * s, design: .serif)).opacity(0.5).frame(maxWidth: .infinity, alignment: index % 2 == 0 ? .trailing : .leading)
        }
        .padding(.horizontal, 54 * s).padding(.top, 58 * s).padding(.bottom, 30 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    func line(_ title: String, _ text: String, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            Text(title).font(.system(size: 18.5 * s, weight: .bold, design: .serif))
            Text(text).font(.system(size: 16.5 * s, design: .serif)).lineSpacing(3 * s).opacity(0.85).fixedSize(horizontal: false, vertical: true)
        }
    }

    func fact(_ name: String, _ value: String, s: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.system(size: 16.5 * s, design: .serif)).opacity(0.62)
            Spacer(minLength: 12 * s)
            Text(value).font(.system(size: 18 * s, weight: .semibold, design: .serif)).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}

/// A made booklet's cover: the game's wide art over its name, on cream paper
struct BookletCover: View {
    let game: StageGame

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height / 482
            VStack(alignment: .leading, spacing: 0) {
                art.frame(height: geo.size.height * 0.56)
                Text(game.name).font(.system(size: 25 * s, weight: .bold, design: .serif)).lineLimit(3).minimumScaleFactor(0.6)
                    .padding(.top, 18 * s).padding(.horizontal, 20 * s)
                Text("INSTRUCTION BOOKLET").font(.system(size: 11.5 * s, weight: .medium, design: .serif)).tracking(2 * s).opacity(0.62)
                    .padding(.top, 6 * s).padding(.horizontal, 20 * s)
                Spacer(minLength: 0)
            }
            .foregroundStyle(BookletPaper.ink)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(BookletPaper.paper)
        }
    }

    @ViewBuilder var art: some View {
        if let img = CoverStore.shared.hero(game.coverKey) ?? CoverArt.wide(game) ?? CoverArt.front(game) {
            Color.black.overlay(Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)).clipped()
        } else {
            CoverArt.tint(game)
        }
    }
}
