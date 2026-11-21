// Collector touches and the tilt (0.52.0). A case you have played a lot shows it: a sticker with its hours, wear along the
// sleeve's edges, and a COMPLETED stamp you bring down yourself (R with the case in the hand). And the case in the hand leans
// with the controller, for controllers that tell a Mac how they are held.
import GameController
import simd
import SwiftUI

/// What a case shows of its history
struct CaseKeepsake: Equatable {
    var hours = 0.0
    var completed = false
    /// the stamp coming down: 0 above the case, 1 on it
    var landed = 1.0

    /// wear begins after a few hours and is all there by sixty
    static let wearFrom = 5.0, wornAt = 60.0
    var wear: Double { min(max((hours - Self.wearFrom) / (Self.wornAt - Self.wearFrom), 0), 1) }
    /// the sticker's number: whole hours, once there is one
    var sticker: Int? { hours >= 1 ? Int(hours) : nil }
    var plain: Bool { sticker == nil && !completed }

    static let stampTime = 0.2
}

extension AppModel {
    /// What the game's case shows (nil with Collector touches off)
    func keepsake(_ g: StageGame) -> CaseKeepsake? {
        guard settings.theatreCollector else { return nil }
        return CaseKeepsake(hours: g.total / 3600, completed: settings.completed.contains(g.favoriteKey))
    }

    func isCompleted(_ g: StageGame) -> Bool { settings.completed.contains(g.favoriteKey) }

    /// The COMPLETED stamp, on or off; true when it is now on
    @discardableResult
    func toggleCompleted(_ g: StageGame) -> Bool {
        if let i = settings.completed.firstIndex(of: g.favoriteKey) { settings.completed.remove(at: i); revision += 1; return false }
        settings.completed.append(g.favoriteKey)
        revision += 1
        return true
    }
}

/// The sticker, the stamp and the wear, over a case's front (the size it is given)
struct CaseKeepsakes: View {
    let keep: CaseKeepsake
    /// the game's key: its scratches are its own, the same every time
    let seed: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, s = h / 602
            ZStack {
                if keep.wear > 0 {
                    // the sleeve's edges go pale where hands have been, and it picks up fine scratches
                    RoundedRectangle(cornerRadius: 11 * s).strokeBorder(.white.opacity(0.34 * keep.wear), lineWidth: 7 * s).blur(radius: 4 * s)
                    Canvas { ctx, size in
                        var r = Scuffs(seed: seed)
                        for _ in 0..<Int((keep.wear * 16).rounded()) {
                            let x = r.next() * size.width, y = r.next() * size.height, len = (0.05 + 0.16 * r.next()) * size.height, a = -0.9 + 0.5 * r.next()
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: y))
                            p.addLine(to: CGPoint(x: x + cos(a) * len, y: y + sin(a) * len))
                            ctx.stroke(p, with: .color(.white.opacity(0.10 + 0.12 * r.next())), lineWidth: max(0.8 * s, 0.5))
                        }
                    }
                }
                if let n = keep.sticker {
                    VStack(spacing: -2 * s) {
                        Text("\(n) h").font(.system(size: (n > 99 ? 24 : 29) * s, weight: .heavy, design: .rounded))
                        Text("PLAYED").font(.system(size: 10.5 * s, weight: .bold)).tracking(1.4 * s)
                    }
                    .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.02))
                    .frame(width: 88 * s, height: 88 * s)
                    .background(Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 0.98, green: 0.68, blue: 0.12)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 70 * s)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5 * s))
                    .shadow(color: .black.opacity(0.4), radius: 4 * s, y: 2 * s)
                    .rotationEffect(.degrees(11))
                    .position(x: w - 64 * s, y: 70 * s)
                    .accessibilityHidden(true)
                }
                if keep.completed {
                    let ink = Color(red: 0.80, green: 0.10, blue: 0.12)
                    Text("COMPLETED").font(.system(size: 37 * s, weight: .black, design: .rounded)).tracking(3 * s)
                        .padding(.horizontal, 16 * s).padding(.vertical, 7 * s)
                        .overlay(RoundedRectangle(cornerRadius: 9 * s).strokeBorder(ink, lineWidth: 5 * s))
                        .overlay(RoundedRectangle(cornerRadius: 5 * s).strokeBorder(ink, lineWidth: 1.5 * s).padding(8 * s))
                        .foregroundStyle(ink)
                        .background(Color.white.opacity(0.16), in: .rect(cornerRadius: 9 * s))
                        .opacity(0.9 * min(keep.landed * 3, 1))
                        .scaleEffect(1 + 1.1 * (1 - keep.landed))
                        .rotationEffect(.degrees(-15))
                        .position(x: w / 2, y: h * 0.63)
                        .accessibilityHidden(true)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A game's own run of numbers from 0 to 1, the same each time (its scratches stay where they are)
struct Scuffs {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        state = h | 1
    }

    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 100_000) / 100_000
    }
}

// MARK: The tilt

/// How the controller is held, as a lean for the case in the hand. A controller's rest is wherever it has been held lately, so
/// there is nothing to set up: lean it and the case leans, hold it there and the case comes slowly back upright.
@MainActor
enum CaseTilt {
    private static var rest: SIMD3<Double>?
    private static var lean = SIMD2<Double>(0, 0)
    private static var last: Date?
    private static var woke = false

    /// the most the case leans: its turn, and its tip
    static let most = SIMD2<Double>(0.55, 0.3)

    /// The lean for a pull of gravity `g` against the controller's `rest`: right side down turns the case's front to the
    /// right, its top edge down tips the case's top away
    nonisolated static func lean(gravity g: SIMD3<Double>, rest: SIMD3<Double>) -> SIMD2<Double> {
        let d = g - rest
        return SIMD2(min(max(d.x * 1.5, -most.x), most.x), min(max(d.y * 1.0, -most.y), most.y))
    }

    /// The lean now, eased from frame to frame (0 with no controller that can tell)
    static func read(now: Date) -> SIMD2<Double> {
        let dt = min(max(last.map { now.timeIntervalSince($0) } ?? 0, 0), 0.05)
        last = now
        var target = SIMD2<Double>(0, 0)
        if NSApp.isActive, let m = GCController.current?.motion {
            if m.sensorsRequireManualActivation, !m.sensorsActive { m.sensorsActive = true; woke = true }
            let a = m.hasGravityAndUserAcceleration ? m.gravity : m.acceleration
            let g = SIMD3(a.x, a.y, a.z)
            if simd_length(g) > 0.3 {
                let n = simd_normalize(g)
                let r = rest.map { $0 + (n - $0) * min(dt / 4, 1) } ?? n
                rest = r
                target = lean(gravity: n, rest: r)
            }
        }
        lean += (target - lean) * min(dt * 10, 1)
        return lean
    }

    /// The case is put down: the controller's sensors rest again, if Theatre woke them
    static func stop() {
        if woke { GCController.current?.motion?.sensorsActive = false }
        woke = false
        rest = nil
        lean = SIMD2(0, 0)
        last = nil
    }
}
