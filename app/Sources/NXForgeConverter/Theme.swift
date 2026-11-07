// The window's look: a deep navy in Dark Mode (system greys in Light), the cards on it, numbered badges, icon tiles,
// and the Convert page's banner, a sunset over hills with a radio dish, drawn here so the app ships no picture.
import AppKit
import SwiftUI

enum Theme {
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    private static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    /// behind every page
    static let background = dynamic(dark: rgb(13, 20, 36), light: .windowBackgroundColor)
    /// a card on it
    static let card = dynamic(dark: rgb(20, 29, 50), light: .controlBackgroundColor)
    static let cardStroke = dynamic(dark: rgb(120, 150, 220, 0.16), light: .separatorColor)
    /// a well inside a card: the log, path fields
    static let well = dynamic(dark: rgb(11, 17, 31), light: .textBackgroundColor)
    static let tile = dynamic(dark: rgb(27, 39, 66), light: rgb(232, 238, 248))
}

/// The blue numbered circle before a card's title and above a step tile.
struct NumberBadge: View {
    let n: Int
    var color: Color = .accentColor
    var size: CGFloat = 22

    var body: some View {
        Text("\(n)").font(.system(size: size * 0.55, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            .frame(width: size, height: size).background(color, in: .circle)
    }
}

/// A symbol on a rounded, blue-tinted square: the page's and the build activity's mark.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.16), in: .rect(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Color.accentColor.opacity(0.25)))
    }
}

/// A page's own heading: its icon tile, title and one line under it.
struct HeroHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            IconTile(symbol: symbol, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Dusk over hills with a dish on the ridge (Convert), or snowy peaks at last light (Toolchain),
/// fading into the page on the left and at the bottom.
struct HeroBanner: View {
    enum Backdrop { case dish, peaks }
    var scene: Backdrop = .dish

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // sky: deep blue at the top through violet and rose to an orange horizon
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.07, green: 0.10, blue: 0.22), location: 0),
                    .init(color: Color(red: 0.30, green: 0.20, blue: 0.45), location: 0.45),
                    .init(color: Color(red: 0.86, green: 0.38, blue: 0.40), location: 0.72),
                    .init(color: Color(red: 0.98, green: 0.62, blue: 0.36), location: 0.86),
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // a few stars
            var rng = SplitMix(seed: 7)
            for _ in 0..<40 {
                let p = CGPoint(x: rng.next() * w, y: rng.next() * h * 0.45)
                let r = 0.4 + rng.next() * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)), with: .color(.white.opacity(0.35 + rng.next() * 0.5)))
            }
            if scene == .peaks {
                peaks(ctx, w: w, h: h)
            } else {
                // far hills, then the near ridge the dish stands on
                ctx.fill(hills(w: w, h: h, base: 0.80, amp: 0.10, waves: 3.2, phase: 0.6), with: .color(Color(red: 0.17, green: 0.13, blue: 0.27)))
                let ridge = hills(w: w, h: h, base: 0.90, amp: 0.13, waves: 1.6, phase: 2.2)
                ctx.fill(ridge, with: .color(Color(red: 0.06, green: 0.07, blue: 0.14)))
                dish(ctx, at: CGPoint(x: w * 0.76, y: h * 0.80), scale: h / 210)
            }
        }
        // fade into the page: away to the left, and down into the cards
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 0.55), .init(color: .black, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Three ranges of sharp peaks, the far ones lit and snow-capped, the nearest dark.
    func peaks(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let ranges: [(base: CGFloat, height: CGFloat, count: Int, seed: UInt64, color: Color, snow: Bool)] = [
            (0.78, 0.42, 7, 3, Color(red: 0.36, green: 0.34, blue: 0.55), true),
            (0.86, 0.32, 9, 11, Color(red: 0.18, green: 0.20, blue: 0.36), true),
            (0.97, 0.22, 12, 23, Color(red: 0.07, green: 0.09, blue: 0.18), false),
        ]
        for r in ranges {
            var rng = SplitMix(seed: r.seed)
            var tops: [CGPoint] = []
            let step = w / CGFloat(r.count)
            for i in 0...r.count {
                let x = CGFloat(i) * step + (rng.next() - 0.5) * step * 0.5
                tops.append(CGPoint(x: x, y: h * (r.base - r.height * (0.45 + 0.55 * rng.next()))))
            }
            var p = Path()
            p.move(to: CGPoint(x: 0, y: h))
            for (i, t) in tops.enumerated() {
                p.addLine(to: t)
                if i + 1 < tops.count {   // the saddle between two peaks
                    let n = tops[i + 1]
                    p.addLine(to: CGPoint(x: (t.x + n.x) / 2, y: max(t.y, n.y) + h * r.height * 0.35))
                }
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
            ctx.fill(p, with: .color(r.color))
            if r.snow {
                for t in tops {
                    let s = h * r.height * 0.16
                    var cap = Path()
                    cap.move(to: t)
                    cap.addLine(to: CGPoint(x: t.x - s * 0.9, y: t.y + s))
                    cap.addLine(to: CGPoint(x: t.x - s * 0.2, y: t.y + s * 0.75))
                    cap.addLine(to: CGPoint(x: t.x + s * 0.3, y: t.y + s * 1.05))
                    cap.addLine(to: CGPoint(x: t.x + s * 0.9, y: t.y + s))
                    cap.closeSubpath()
                    ctx.fill(cap, with: .color(.white.opacity(0.75)))
                }
            }
        }
    }

    func hills(w: CGFloat, h: CGFloat, base: CGFloat, amp: CGFloat, waves: CGFloat, phase: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        for i in stride(from: 0, through: 200, by: 1) {
            let x = CGFloat(i) / 200 * w
            let t = CGFloat(i) / 200
            let y = h * (base - amp * (0.6 * sin(t * waves * .pi + phase) + 0.4 * sin(t * waves * 2.3 * .pi + phase * 1.7)))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }

    /// A radio dish in silhouette: a tilted bowl on a frame, its feed arm pointing at the sky.
    func dish(_ ctx: GraphicsContext, at base: CGPoint, scale s: CGFloat) {
        var c = ctx
        c.translateBy(x: base.x, y: base.y)
        c.scaleBy(x: s, y: s)
        let dark = GraphicsContext.Shading.color(Color(red: 0.04, green: 0.05, blue: 0.10))
        var frame = Path()
        frame.move(to: CGPoint(x: -22, y: 0)); frame.addLine(to: CGPoint(x: -4, y: -46)); frame.addLine(to: CGPoint(x: 4, y: -46)); frame.addLine(to: CGPoint(x: 22, y: 0)); frame.closeSubpath()
        c.fill(frame, with: dark)
        c.rotate(by: .degrees(-32))
        var bowl = Path()
        bowl.addArc(center: CGPoint(x: 0, y: -60), radius: 44, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        bowl.addQuadCurve(to: CGPoint(x: 44, y: -60), control: CGPoint(x: 0, y: -48))
        c.fill(bowl, with: dark)
        var arm = Path()
        arm.move(to: CGPoint(x: 0, y: -52)); arm.addLine(to: CGPoint(x: 0, y: -98))
        c.stroke(arm, with: dark, lineWidth: 3)
        c.fill(Path(ellipseIn: CGRect(x: -4, y: -104, width: 8, height: 8)), with: dark)
    }
}

/// Repeatable numbers for the stars, so the sky is the same on every draw.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z % 1_000_000) / 1_000_000
    }
}
