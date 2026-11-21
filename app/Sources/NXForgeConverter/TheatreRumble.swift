// Theatre's rumble (0.50.0): a small knock in the hands as a case snaps open or shut, a firmer one as a game card clicks into
// the console. Only controllers that can rumble on a Mac feel it; the rest are left alone. One haptic engine a controller,
// made when first needed and stopped when Theatre closes.
import CoreHaptics
import GameController

@MainActor
final class TheatreRumble {
    static let shared = TheatreRumble()

    enum Knock: CaseIterable {
        /// a case's catch
        case snap
        /// a card going home
        case click
        /// a page turning
        case page

        /// the knocks that make it up: when, how hard, how sharp
        var taps: [(at: Double, intensity: Float, sharpness: Float)] {
            switch self {
            case .snap: [(0, 0.55, 0.8)]
            case .click: [(0, 0.45, 0.9), (0.07, 1, 0.55)]
            case .page: [(0, 0.3, 0.4)]
            }
        }
    }

    private var engines: [ObjectIdentifier: CHHapticEngine] = [:]

    func play(_ k: Knock) {
        for c in GCController.controllers() {
            guard let h = c.haptics else { continue }
            let id = ObjectIdentifier(c)
            if engines[id] == nil { engines[id] = h.createEngine(withLocality: .default) }
            guard let e = engines[id] else { continue }
            let events = k.taps.map { t in
                // a short continuous buzz: a transient alone is too brief for a controller's motors to speak
                CHHapticEvent(eventType: .hapticContinuous,
                              parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: t.intensity), CHHapticEventParameter(parameterID: .hapticSharpness, value: t.sharpness)],
                              relativeTime: t.at, duration: 0.05)
            }
            do {
                try e.start()
                try e.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
            } catch {
                engines[id] = nil
            }
        }
    }

    /// Theatre closed: the controllers' motors are let go
    func rest() {
        for e in engines.values { e.stop() }
        engines = [:]
    }
}
