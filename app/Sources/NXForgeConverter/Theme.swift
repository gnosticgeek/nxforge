// The converter's look, taken from the front end's stage (StageLook): its pages sit on the same dark, lit backdrop, on
// translucent cards, with the stage's capsule buttons and its heavy page titles.
import AppKit
import SwiftUI

enum Theme {
    /// behind every page, under the stage's light
    static let background = StageLook.background
    /// a card on it
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    /// a well inside a card: the log, path fields
    static let well = Color.black.opacity(0.30)
    static let tile = Color.white.opacity(0.09)
    /// the pages' side margin: the top bar's
    static let gutter: CGFloat = 40
}

/// The blue numbered circle before a card's title and above a step tile.
struct NumberBadge: View {
    let n: Int
    var color: Color = .white
    var size: CGFloat = 22

    var body: some View {
        Text("\(n)").font(.system(size: size * 0.55, weight: .heavy).monospacedDigit()).foregroundStyle(color == .white ? Color.black : Color.white)
            .frame(width: size, height: size).background(color, in: .circle)
    }
}

/// A symbol on a rounded, blue-tinted square: the page's and the build activity's mark.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(0.10), in: .rect(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.white.opacity(0.16)))
    }
}

/// A page's heading, as the front end's Library has it: the title heavy, one line beside it, the page's actions at the right.
struct PageHeading<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.system(size: 32, weight: .heavy)).tracking(-0.6).fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).foregroundStyle(StageLook.soft).lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8).padding(.bottom, 2)
    }
}

extension PageHeading where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// The converter's buttons in the front end's shape (StageButton): a white capsule for a view's main action, a translucent
/// one for the rest, sized by controlSize.
struct PillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View { PillButtonBody(configuration: configuration, primary: primary) }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let m: (h: CGFloat, font: CGFloat, pad: CGFloat) = switch size {
        case .mini, .small: (24, 12, 11)
        case .large: (36, 14, 18)
        case .extraLarge: (44, 15, 24)
        default: (30, 13, 14)
        }
        configuration.label
            .font(.system(size: m.font, weight: primary ? .bold : .semibold))
            .lineLimit(1)
            .padding(.horizontal, m.pad).frame(height: m.h)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(StageLook.card), in: .capsule)
            .overlay(Capsule().strokeBorder(primary ? AnyShapeStyle(Color.clear) : AnyShapeStyle(StageLook.edge), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var stage: PillButtonStyle { PillButtonStyle() }
    static var stagePrimary: PillButtonStyle { PillButtonStyle(primary: true) }
}
