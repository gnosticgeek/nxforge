// The Shutter theme's foot: the game's name, big, over a line of what it is; on the right the main button (Continue, Play, or
// the step the game needs), Details and Play options, and below them Theme, Menu and Leave between accent rules
import SwiftUI

struct ShutterFoot: View {
    let model: AppModel
    let game: StageGame
    @Environment(\.tu) private var u

    var body: some View {
        let hints = TheatreHints(model: model)
        HStack(alignment: .bottom, spacing: 40 * u) {
            VStack(alignment: .leading, spacing: 6 * u) {
                Text(game.name)
                    .font(.system(size: 96 * u, weight: .bold).width(.condensed))
                    .lineLimit(1).minimumScaleFactor(0.5)
                ShutterFoot.facts(model, game)
                    .font(.system(size: 28 * u, weight: .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .opacity(0.88)
            }
            .id(game.id).transition(.opacity)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 26 * u) {
                HStack(spacing: 40 * u) {
                    Button { model.theatreFocus = game.id; model.rememberTheatreFocus(); model.fix(game) } label: {
                        HStack(spacing: 14 * u) {
                            PadGlyph(text: "A", filled: true, dark: true).fixedSize().scaleEffect(u * 1.5).frame(width: 34 * u, height: 34 * u)
                            Text(model.theatreAction(game)).font(.system(size: 32 * u, weight: .bold).width(.condensed))
                                .lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(ShutterLook.buttonInk)
                        .padding(.horizontal, 34 * u).frame(height: 70 * u)
                        .background(ShutterLook.button, in: .rect)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    hint(hints, "Y", "Pick up")
                    if game.app != nil { hint(hints, "X", "Play options") }
                }
                .font(.system(size: 28 * u, weight: .medium))
                HStack(spacing: 26 * u) {
                    HStack(spacing: 10 * u) { hints.glyph("ZL"); hints.glyph("ZR"); Text("Theme") }
                    rule
                    hint(hints, "+", "Menu")
                    rule
                    hint(hints, "B", "Leave")
                }
                .font(.system(size: 22 * u, weight: .medium))
            }
            .fixedSize()
        }
        .foregroundStyle(ShutterLook.ink)
    }

    var rule: some View { Rectangle().fill(ShutterLook.accent).frame(width: 2 * u, height: 28 * u) }

    func hint(_ hints: TheatreHints, _ k: String, _ text: String) -> some View {
        HStack(spacing: 10 * u) { hints.glyph(k); Text(text) }
    }

    /// "Switch · Arcade racing · 1–4 players  ✓ Built · 31 min played": only what is known
    @MainActor static func facts(_ model: AppModel, _ g: StageGame) -> Text {
        let _ = StoreInfoStore.shared.revision
        let info = StoreInfoStore.shared.info(g.coverKey)
        var lead = [g.console.rawValue]
        if let genre = Genres.shown(titleID: g.titleID, store: info?.genres ?? []).first ?? model.discover.genres(of: g).first { lead.append(genre) }
        if let p = info?.players { lead.append(p) }
        let st = model.status(g)
        let state = st == .ready ? "Built" : st.text
        let symbol = st == .ready ? "checkmark" : st.symbol
        let played = g.total > 60 ? " · \(Playtime.text(g.total)) played" : ""
        let first = lead.joined(separator: " · ")
        return Text("\(first)   \(Image(systemName: symbol)) \(state)\(played)")
    }
}
