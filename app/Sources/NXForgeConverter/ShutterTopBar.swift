// The Shutter theme's top bar: the NXFORGE wordmark, the filter between L and R in the middle, and the theme's name beside
// the clock with an accent rule between them
import SwiftUI

struct ShutterTopBar: View {
    let model: AppModel
    @Environment(\.tu) private var u

    var body: some View {
        let hints = TheatreHints(model: model)
        HStack {
            Text("NXFORGE").font(.system(size: 28 * u, weight: .heavy)).tracking(8 * u)
            Spacer()
            HStack(spacing: 18 * u) {
                Text("Shutter").font(.system(size: 26 * u, weight: .medium)).opacity(0.9)
                Rectangle().fill(ShutterLook.accent).frame(width: 2 * u, height: 30 * u)
                TimelineView(.everyMinute) { t in
                    HStack(spacing: 10 * u) {
                        if model.settings.theatreTimeOfDay { Image(systemName: TheatreDaylight.now.symbol).font(.system(size: 20 * u, weight: .semibold)).symbolRenderingMode(.hierarchical) }
                        Text(t.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 28 * u, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 56 * u).frame(height: ShutterLayout.top * u)
        .overlay {
            // the filter, as L and R step it (only when there is more than one)
            if model.theatreFilters().count > 1 {
                HStack(spacing: 40 * u) {
                    hints.glyph("L")
                    Text(model.theatreShownFilter.title).font(.system(size: 36 * u, weight: .semibold).width(.condensed)).lineLimit(1)
                        .frame(minWidth: 220 * u)
                        .contentTransition(.opacity)
                    hints.glyph("R")
                }
                .animation(.easeInOut(duration: 0.25), value: model.theatreShownFilter)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Filter: \(model.theatreShownFilter.title), L and R change it")
            }
        }
        .foregroundStyle(ShutterLook.ink)
    }
}
