// Theatre's small delights (0.48.0), on every theme: the lights go down when a game starts (the room dims, the box flies forward
// and opens, and its light fills the screen before the game comes up), soft sounds as the games turn and a thunk on launch, the
// focused game's own music when its media folder has some, a welcome back on the game played last, light that follows the time
// of day, moments when the shelf changes (confetti when a game finishes building, a spotlight on a game Theatre has not shown
// before), and a shuffle that whirls the games and lands on one to play (L3, or the Theatre menu).
import AppKit
import AVFoundation
import SwiftUI

// MARK: Moments

/// A card Theatre puts up for a moment, about one game
struct TheatreMoment: Equatable, Identifiable {
    enum Kind: Equatable {
        /// opening on the game played last: the day of play it is, and the time played
        case welcome(day: Int, total: Double, last: Date)
        /// a built game Theatre has not shown before
        case newArrival
        /// a game that finished building while Theatre was up
        case built
        /// where the shuffle landed
        case shuffle
    }
    let id = UUID()
    let kind: Kind
    /// the game's StageGame id
    let game: String

    /// how long the card stays up, left alone
    var seconds: Double {
        switch kind {
        case .welcome: 12
        case .newArrival, .built: 10
        case .shuffle: 9
        }
    }

    /// a light falls on the game from above
    var spotlight: Bool { if case .welcome = kind { false } else { true } }
}

/// The lights going down on a launch: which game, and when it began (`frozen`: a moment of it held still, for a snapshot)
struct TheatreCurtain: Equatable, Identifiable {
    let id = UUID()
    let game: String
    let start = Date()
    var frozen: Double? = nil
    /// when the launch screen comes up under the light, and when the light has gone
    static let reveal = 1.75
    static let length = 2.35
}

/// The time of day Theatre's light follows (Settings › Theatre › Light follows the time of day)
enum TheatreDaylight: String, CaseIterable {
    case morning, day, evening, night

    static func at(_ d: Date, calendar: Calendar = .current) -> TheatreDaylight {
        switch calendar.component(.hour, from: d) {
        case 5..<11: .morning
        case 11..<17: .day
        case 17..<22: .evening
        default: .night
        }
    }

    /// now, or NXC_DAYLIGHT's for a snapshot
    static var now: TheatreDaylight {
        ProcessInfo.processInfo.environment["NXC_DAYLIGHT"].flatMap { TheatreDaylight(rawValue: $0) } ?? at(Date())
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var greeting: String {
        switch self {
        case .morning: "Good morning"
        case .day: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Up late"
        }
    }

    /// the shuffle's pick: "Tonight's pick"
    var pick: String {
        switch self {
        case .morning: "This morning's pick"
        case .day: "This afternoon's pick"
        case .evening, .night: "Tonight's pick"
        }
    }
}

extension AppModel {
    /// What Theatre opens with: a spotlight on a built game it has not shown before, else a welcome back on the game played last
    /// (in the last 30 days), which it opens on. The first time Theatre ever opens, every game counts as seen.
    func theatreOpeningMoment() {
        theatreMoment = nil
        let snap = ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil
        if snap { return }   // a snapshot asks for its card (NXC_MOMENT)
        let games = theatreGames()
        let keys = stageGames().filter { $0.app != nil }.map(\.favoriteKey)
        if let seen = settings.theatreSeen.map(Set.init) {
            let fresh = games.filter { $0.app != nil && !seen.contains($0.favoriteKey) }
            if !Set(keys).isSubset(of: seen) { settings.theatreSeen = Array(seen.union(keys)).sorted() }
            // a whole library new at once (a new games folder) is no arrival: the welcome instead
            if let g = fresh.first, fresh.count <= 3 {
                theatreFocus = g.id
                theatreMoment = TheatreMoment(kind: .newArrival, game: g.id)
                theatreCueLater(.chime, after: 0.9)
                return
            }
        } else {
            settings.theatreSeen = keys.sorted()
        }
        guard let g = Self.lastPlayed(games), let last = g.last, Date().timeIntervalSince(last) < 30 * 86400 else { return }
        theatreFocus = g.id
        theatreMoment = TheatreMoment(kind: .welcome(day: Self.playDay(playRecord(app: g.app, titleID: g.titleID)), total: g.total, last: last), game: g.id)
    }

    /// The day of play a game is on: the days it was played, and today, if it has not been played yet today
    nonisolated static func playDay(_ r: PlayRecord?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set((r?.sessions ?? []).map { calendar.startOfDay(for: $0.start) })
        return days.count + (days.contains(calendar.startOfDay(for: now)) ? 0 : 1)
    }

    /// A game finished building while Theatre is up: confetti, the game in focus, and a card saying it is ready
    func theatreBuilt(app: String?) {
        guard theatre, let app else { return }
        let path = app.url.standardizedFileURL.path
        Task { @MainActor [weak self] in
            // the build's record and the library catch up a moment after the build ends
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.theatre else { return }
                guard let g = self.stageGames().first(where: { $0.app.map { $0.url.standardizedFileURL.path } == path }) else { continue }
                if self.theatreSaver { self.wakeTheatre() }
                let busy = self.theatreSpinning || self.theatreMenu != nil || self.playOptions != nil || self.gameDetail != nil || self.launching != nil
                if !busy, self.theatreGames().contains(where: { $0.id == g.id }) || self.theatreTheme == .cinema || self.theatreTheme == .trailer { self.theatreFocus = g.id }
                if var seen = self.settings.theatreSeen, !seen.contains(g.favoriteKey) { seen.append(g.favoriteKey); self.settings.theatreSeen = seen.sorted() }
                self.theatreMoment = TheatreMoment(kind: .built, game: g.id)
                self.theatreConfetti += 1
                self.theatreCue(.chime)
                return
            }
        }
    }

    /// The list the shuffle spins through: the theme's games (Cinema's row in focus)
    private func shuffleList() -> (games: [StageGame], row: Int?) {
        switch theatreTheme {
        case .cinema:
            let rows = theatreRows()
            guard !rows.isEmpty else { return ([], nil) }
            let r = cinemaRow(rows)
            return (rows[r].games, r)
        case .trailer: return (trailerGames(), nil)
        case .showcase, .shutter: return (theatreGames(), nil)
        }
    }

    /// What should I play? The games whirl past, slowing down, and land on one (a built one, when there are any) with a card
    /// to play it. B stops the spin where it is.
    func shuffleTheatre() {
        guard !theatreSpinning else { return }
        let (games, row) = shuffleList()
        guard games.count > 1 else { return }
        let n = games.count
        let cur = games.firstIndex { $0.id == theatreFocus } ?? 0
        var pool = games.indices.filter { $0 != cur && games[$0].app != nil }
        if pool.isEmpty { pool = games.indices.filter { $0 != cur } }
        guard let target = pool.randomElement() else { return }
        theatreMoment = nil
        theatreWatch = false
        theatreTouched = Date()
        let land = { [weak self] in
            guard let self else { return }
            self.theatreFocus = games[target].id
            if let row { self.theatreRow = row }
            self.theatreSpinning = false
            self.theatreTouched = Date()
            self.theatreCue(.land)
            self.theatreMoment = TheatreMoment(kind: .shuffle, game: games[target].id)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { land(); return }
        let path = Self.shufflePath(from: cur, to: target, count: n)
        theatreSpinning = true
        Task { @MainActor [weak self] in
            for (i, k) in path.dropLast().enumerated() {
                guard let self, self.theatreSpinning, self.theatre else { return }
                self.theatreFocus = games[k].id
                if let row { self.theatreRow = row }
                self.theatreTouched = Date()
                self.theatreCue(.spin)
                try? await Task.sleep(for: .seconds(Self.shuffleWait(step: i, of: path.count)))
            }
            guard let self, self.theatreSpinning, self.theatre else { return }
            land()
        }
    }

    /// The places the shuffle steps through, ending on `target`: at least 16 steps, always forwards, one game a step for the last
    /// 18 and bigger jumps before them, so a long list still spins in about four seconds
    nonisolated static func shufflePath(from cur: Int, to target: Int, count n: Int) -> [Int] {
        guard n > 1 else { return [target] }
        var total = ((target - cur) % n + n) % n
        while total < 16 { total += n }
        var out: [Int] = [], at = cur, left = total
        while left > 18 {
            let jump = min(max((left - 18) / 3, 1), n - 1, left - 18)
            at = (at + jump) % n; left -= jump
            out.append(at)
        }
        while left > 0 { at = (at + 1) % n; left -= 1; out.append(at) }
        return out
    }

    /// The pause after each of the shuffle's steps: quick at first, slowing to a stop
    nonisolated static func shuffleWait(step i: Int, of count: Int) -> Double {
        let p = count > 1 ? Double(i) / Double(count - 1) : 1
        return 0.035 + 0.38 * pow(p, 2.6)
    }

    /// Theatre's sound, when Settings has it on and nothing is muted (never while snapshotting)
    func theatreCue(_ c: TheatreSound.Cue) {
        guard theatre, settings.theatreSounds, !theatreMuted, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        TheatreSound.shared.play(c)
    }

    func theatreCueLater(_ c: TheatreSound.Cue, after s: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(s))
            self?.theatreCue(c)
        }
    }

    /// The lights go down: a launch from Theatre that has not failed yet
    func theatreLightsDown(_ l: Launching) {
        guard theatre, l.failure == nil else { return }
        let g = stageGames().first { $0.isRef(l.ref) }
        theatreMoment = nil
        theatreCurtain = TheatreCurtain(game: g?.id ?? "")
        theatreCue(.launch)
    }
}

// MARK: Sound

/// Theatre's sounds, made here rather than shipped as files: a soft click for a step, a quiet tick as the games turn, a low thunk
/// on launch, a chime for a moment. Quiet, through one small engine that rests when Theatre closes.
@MainActor
final class TheatreSound {
    static let shared = TheatreSound()
    enum Cue: CaseIterable { case step, turn, theme, open, launch, chime, spin, land }

    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: TheatreSynth.rate, channels: 1)!

    func play(_ c: Cue) {
        guard let e = start() else { return }
        if buffers[c] == nil { buffers[c] = buffer(TheatreSynth.samples(c)) }
        guard let b = buffers[c], !players.isEmpty else { return }
        let p = players[next % players.count]
        next += 1
        if !e.isRunning { try? e.start() }
        p.stop()
        p.volume = TheatreSynth.gain(c)
        p.scheduleBuffer(b, at: nil, options: [])
        p.play()
    }

    /// The engine stops (Theatre closed): the Mac's audio is left alone
    func rest() {
        engine?.stop()
        engine = nil
        players = []
    }

    private func start() -> AVAudioEngine? {
        if let engine { return engine }
        let e = AVAudioEngine()
        var ps: [AVAudioPlayerNode] = []
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            e.attach(p)
            e.connect(p, to: e.mainMixerNode, format: format)
            ps.append(p)
        }
        e.mainMixerNode.outputVolume = 0.6
        do { try e.start() } catch { return nil }
        engine = e
        players = ps
        return e
    }

    private func buffer(_ s: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count)), let ch = b.floatChannelData?[0] else { return nil }
        b.frameLength = AVAudioFrameCount(s.count)
        for (i, v) in s.enumerated() { ch[i] = v }
        return b
    }
}

/// The sounds as samples (tested: each is short, starts and ends quiet, and never clips)
enum TheatreSynth {
    static let rate = 44100.0

    static func gain(_ c: TheatreSound.Cue) -> Float {
        switch c {
        case .step: 0.22
        case .turn: 0.22
        case .theme: 0.22
        case .open: 0.22
        case .launch: 0.75
        case .chime: 0.30
        case .spin: 0.22
        case .land: 0.36
        }
    }

    static func samples(_ c: TheatreSound.Cue) -> [Float] {
        switch c {
        case .step: tok(880, length: 0.09)
        case .spin: tok(1320, length: 0.06)
        case .open: tok(660, length: 0.12)
        // only quiet ticks as the games turn (0.48.5: Tom wanted no whoosh or breeze at all)
        case .turn: tok(587, length: 0.1)
        case .theme: tok(494, length: 0.12)
        case .launch: thunk()
        case .chime: bells([1046.5, 1318.5, 1568.0, 2093.0], gap: 0.075, ring: 0.55)
        case .land: bells([783.99, 1174.66], gap: 0.1, ring: 0.7)
        }
    }

    /// a short tick: a quick sine with a breath of noise at its start
    static func click(_ hz: Double, length: Double) -> [Float] {
        var noise = Noise()
        return (0..<Int(length * rate)).map { i in
            let t = Double(i) / rate
            let v = sin(2 * .pi * hz * t) * exp(-t / 0.0045) * 0.8 + noise.next() * exp(-t / 0.0012) * 0.35
            return Float(v * fadeIn(t, 0.0008))
        }
    }

    /// a soft wooden tick: a low sine that dies away fast, no noise in it
    static func tok(_ hz: Double, length: Double) -> [Float] {
        (0..<Int(length * rate)).map { i in
            let t = Double(i) / rate
            let v = (sin(2 * .pi * hz * t) + 0.3 * sin(2 * .pi * hz * 2.01 * t) * exp(-t / 0.008)) * exp(-t / 0.022)
            return Float(v * 0.7 * fadeIn(t, 0.002) * fadeOut(t, length, 0.02))
        }
    }

    /// a box closing: a low tone falling away, with a soft knock at its start
    static func thunk() -> [Float] {
        var noise = Noise()
        var phase = 0.0, lp = 0.0
        return (0..<Int(0.62 * rate)).map { i in
            let t = Double(i) / rate
            let hz = 46 + 120 * exp(-t / 0.07)
            phase += 2 * .pi * hz / rate
            lp += 0.08 * (noise.next() - lp)
            let v = sin(phase) * exp(-t / 0.16) * 0.85 + lp * exp(-t / 0.025) * 1.4
            return Float(tanh(v * fadeIn(t, 0.002) * fadeOut(t, 0.62, 0.08)))   // soft-limited: never clips
        }
    }

    /// notes one after another, each a sine with a quieter octave, ringing away
    static func bells(_ notes: [Double], gap: Double, ring: Double) -> [Float] {
        let length = gap * Double(notes.count) + ring * 2.2
        return (0..<Int(length * rate)).map { i in
            let t = Double(i) / rate
            var v = 0.0
            for (k, hz) in notes.enumerated() {
                let s = t - gap * Double(k)
                guard s >= 0 else { continue }
                v += (sin(2 * .pi * hz * s) + 0.25 * sin(4 * .pi * hz * s)) * exp(-s / ring) * fadeIn(s, 0.003)
            }
            return Float(v * 0.32 * fadeOut(t, length, 0.1))
        }
    }

    static func fadeIn(_ t: Double, _ d: Double) -> Double { min(t / d, 1) }
    static func fadeOut(_ t: Double, _ length: Double, _ d: Double) -> Double { min(max((length - t) / d, 0), 1) }

    /// the same noise every time (a sound sounds the same each time it plays)
    struct Noise {
        var s: UInt64 = 0x2545F4914F6CDD1D
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: (s >> 11) << 11)) / Double(Int64.max)
        }
    }
}

// MARK: Music

/// Theatre's music, on every theme but Trailer (which has the trailer's sound). Two sources:
/// - Settings › Theatre › Music folder: the MP3, Opus (and M4A, AAC, WAV, AIFF, FLAC, CAF) files in a folder and the folders in
///   it, in a shuffled order, one after another, quietly in the background.
/// - A game's own music, once the focus rests on it: `music`, `theme` or `soundtrack` in the game's media folder, else a file
///   named by its title ID or its name in NXForge's Theatre Music folder. It fades in over the background music, which pauses
///   and carries on where it was when the focus moves to a game without music of its own.
@MainActor
final class TheatreMusic: NSObject, AVAudioPlayerDelegate {
    static let shared = TheatreMusic()
    nonisolated static let names = ["music", "theme", "soundtrack"]
    nonisolated static let kinds = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "caf", "flac"]
    /// what a music folder may hold
    nonisolated static let folderKinds = Set(["mp3", "opus", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"])
    static var ownFolder: URL { Settings.supportDir.appending(path: "Theatre Music") }

    /// the game's own track, looped
    private var gamePlayer: AVAudioPlayer?
    private var gameURL: URL?
    /// the music folder's: its tracks in a shuffled order, the one playing, and the folder they came from. An AVPlayer, since
    /// AVAudioPlayer opens an Ogg Opus file but will not play it
    private var folderPlayer: FolderTrack?
    private var folder: String?
    private var tracks: [URL] = []
    private var next = 0
    private var folderVolume: Float = 0
    private var leaving: [AVAudioPlayer] = []

    /// The files that would be the game's music, in the order looked for (tested)
    nonisolated static func candidates(media: URL?, own: URL, titleID: String?, name: String) -> [URL] {
        var out: [URL] = []
        if let media { for n in names { for k in kinds { out.append(media.appending(path: "\(n).\(k)")) } } }
        for base in [titleID, name].compactMap({ $0 }) where !base.isEmpty {
            for k in kinds { out.append(own.appending(path: "\(base).\(k)")) }
        }
        return out
    }

    /// The game's music file, looked for off the main thread (a game's folder can be on a slow drive)
    static func find(_ g: StageGame, model: AppModel) async -> URL? {
        let list = candidates(media: GameFolderMediaSync.shared.folder(g, model: model), own: ownFolder, titleID: g.titleID, name: g.name)
        return await Task.detached(priority: .utility) { list.first { FileManager.default.isReadableFile(atPath: $0.path) } }.value
    }

    /// The tracks in a music folder and the folders in it (no hidden files, at most 3000), in no order (tested)
    nonisolated static func tracks(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where folderKinds.contains(u.pathExtension.lowercased()) {
            out.append(u)
            if out.count >= 3000 { break }
        }
        return out
    }

    /// What plays: the game's track when it has one, else the music folder's; nothing when both are nil. `volume` 0 to 1.
    func set(game: URL?, folder f: String?, volume: Float) async {
        // the folder's list, read again when the folder changes
        if f != folder {
            folder = f
            stopFolder()
            if let f {
                let found = await Task.detached(priority: .utility) { Self.tracks(in: URL(fileURLWithPath: f)) }.value
                guard folder == f else { return }
                tracks = found.shuffled()
                next = 0
            }
        }
        if game != gameURL {
            if let old = gamePlayer { fadeAway(old) }
            gamePlayer = nil
            gameURL = game
            if let game, let p = try? AVAudioPlayer(contentsOf: game) {
                p.numberOfLoops = -1
                p.volume = 0
                p.play()
                gamePlayer = p
            }
        }
        gamePlayer?.setVolume(volume, fadeDuration: 1.8)
        // the folder's music pauses under the game's own and carries on after it
        folderVolume = volume
        if gamePlayer != nil || folder == nil {
            if let p = folderPlayer, p.isPlaying {
                p.fade(to: 0, over: 1.2) { [weak self] in if self?.gamePlayer != nil, self?.folderPlayer === p { p.pause() } }
            }
        } else if let p = folderPlayer {
            if !p.isPlaying { p.play() }
            p.fade(to: volume, over: 1.8)
        } else {
            playNextTrack(fadeIn: true)
        }
    }

    func stop() {
        Task { await set(game: nil, folder: nil, volume: 0) }
    }

    private func playNextTrack(fadeIn: Bool) {
        guard folder != nil, !tracks.isEmpty else { return }
        let u = tracks[next % tracks.count]
        next += 1
        if next >= tracks.count { next = 0; tracks.shuffle() }
        let p = FolderTrack(u, volume: fadeIn ? 0 : folderVolume)
        // at its end, or when it will not play (a broken file), the next one
        p.onEnd = { [weak self, weak p] failed in
            guard let self, let p, self.folderPlayer === p else { return }
            self.folderPlayer = nil
            self.skips = failed ? self.skips + 1 : 0
            if self.gamePlayer == nil, self.skips < 20 { self.playNextTrack(fadeIn: failed && fadeIn) }
        }
        folderPlayer = p
        p.play()
        if fadeIn { p.fade(to: folderVolume, over: 1.8) }
    }
    private var skips = 0

    private func stopFolder() {
        if let p = folderPlayer { p.onEnd = nil; p.fade(to: 0, over: 1.2) { p.stop() } }
        folderPlayer = nil
        tracks = []
        skips = 0
    }

    private func fadeAway(_ p: AVAudioPlayer) {
        p.delegate = nil
        p.setVolume(0, fadeDuration: 1.2)
        leaving.append(p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            MainActor.assumeIsolated {
                p.stop()
                self?.leaving.removeAll { $0 === p }
            }
        }
    }

}

/// One track from the music folder, on an AVPlayer: its volume eased in steps, and `onEnd` called once when it finishes
/// (false) or cannot play (true)
@MainActor
final class FolderTrack {
    let player: AVPlayer
    var onEnd: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var status: NSKeyValueObservation?
    private var fading: Task<Void, Never>?
    private var ended = false

    init(_ url: URL, volume: Float) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player.volume = volume
        player.actionAtItemEnd = .pause
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(false) }
        })
        observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(true) }
        })
        status = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.finish(true) }
        }
    }

    var isPlaying: Bool { player.rate != 0 }
    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { fading?.cancel(); player.pause(); player.replaceCurrentItem(with: nil); clear() }

    /// eases the volume to `target` in 20 steps, then runs `then`
    func fade(to target: Float, over seconds: Double, then: (@MainActor () -> Void)? = nil) {
        fading?.cancel()
        let start = player.volume
        fading = Task { @MainActor [weak self] in
            for i in 1...20 {
                try? await Task.sleep(for: .seconds(seconds / 20))
                guard let self, !Task.isCancelled else { return }
                self.player.volume = start + (target - start) * Float(i) / 20
            }
            then?()
        }
    }

    private func finish(_ failed: Bool) {
        guard !ended else { return }
        ended = true
        clear()
        onEnd?(failed)
    }

    private func clear() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        status = nil
    }
}

// MARK: Views

/// The room's light by the time of day: a cool, brighter morning, the stage as it is in the day, a warm evening, and a dim,
/// cosy room late at night
struct TheatreDaylightWash: View {
    @Environment(\.tu) private var u

    var body: some View {
        TimelineView(.everyMinute) { _ in wash(TheatreDaylight.now) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder func wash(_ d: TheatreDaylight) -> some View {
        switch d {
        case .morning:
            ZStack {
                Color(red: 0.78, green: 0.88, blue: 1).opacity(0.10).blendMode(.screen)
                LinearGradient(colors: [Color(red: 0.85, green: 0.93, blue: 1).opacity(0.14), .clear], startPoint: .top, endPoint: .center).blendMode(.screen)
            }
        case .day: Color.clear
        case .evening:
            ZStack {
                Color(red: 1, green: 0.72, blue: 0.45).opacity(0.20).blendMode(.multiply)
                RadialGradient(colors: [Color(red: 1, green: 0.6, blue: 0.3).opacity(0.16), .clear], center: UnitPoint(x: 0.08, y: 0.05), startRadius: 0, endRadius: 1100 * u)
                    .blendMode(.screen)
            }
        case .night:
            ZStack {
                Color(red: 1, green: 0.78, blue: 0.55).opacity(0.18).blendMode(.multiply)
                Color.black.opacity(0.22)
                RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 500 * u, endRadius: 1300 * u)
            }
        }
    }
}

/// The card for a moment, under the top bar: what happened, the game, and what A does; with a light falling on the game where
/// the theme has one place for it (the box in front on the Carousel and the Fan)
struct TheatreMomentCard: View {
    let model: AppModel
    let moment: TheatreMoment
    let width: CGFloat
    let height: CGFloat
    @Environment(\.tu) private var u
    @State private var shown = false

    var body: some View {
        let g = model.stageGames().first { $0.id == moment.game }
        let tint = g.map { CoverArt.tint($0) } ?? .white
        ZStack(alignment: .top) {
            if moment.spotlight, let x = beamX { beam(x: x, tint: tint) }
            // over the top bar for its moment, clear of the covers below it
            if let g { card(g, tint: tint).padding(.top, 16 * u) }
        }
        .frame(width: width, height: height, alignment: .top)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
    }

    /// where the game stands across the screen, on the themes where it stands in one place
    var beamX: CGFloat? {
        switch model.theatreTheme {
        case .showcase, .shutter: width / 2
        case .cinema, .trailer: nil
        }
    }

    func beam(x: CGFloat, tint: Color) -> some View {
        let top = 60 * u, spread = 260 * u, floor = height * 0.68
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: x - 40 * u, y: 0))
                p.addLine(to: CGPoint(x: x + 40 * u, y: 0))
                p.addLine(to: CGPoint(x: x + spread, y: floor))
                p.addLine(to: CGPoint(x: x - spread, y: floor))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.88).opacity(0.30), tint.opacity(0.12), .clear], startPoint: UnitPoint(x: 0.5, y: top / floor), endPoint: .bottom))
            .blur(radius: 24 * u)
            Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: spread))
                .frame(width: spread * 2, height: 120 * u).position(x: x, y: floor - 20 * u).blur(radius: 14 * u)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    func card(_ g: StageGame, tint: Color) -> some View {
        let (eyebrow, title, line, symbol) = words(g)
        return HStack(spacing: 22 * u) {
            Image(systemName: symbol).font(.system(size: 30 * u, weight: .semibold))
                .frame(width: 64 * u, height: 64 * u)
                .background(tint.opacity(0.35), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5 * u) {
                Text(eyebrow.uppercased()).font(.system(size: 15 * u, weight: .bold)).tracking(3 * u).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.5))
                Text(title).font(.system(size: 32 * u, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(line).font(.system(size: 19 * u, weight: .medium)).foregroundStyle(StageLook.soft).lineLimit(1)
            }
            Spacer(minLength: 12 * u)
            HStack(spacing: 10 * u) {
                TheatreHints(model: model).glyph("A", filled: true)
                Text(model.theatreAction(g)).font(.system(size: 21 * u, weight: .semibold))
            }
            if moment.kind == .shuffle {
                HStack(spacing: 10 * u) {
                    TheatreHints(model: model).glyph("L3")
                    Text("Again").font(.system(size: 21 * u, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 28 * u).padding(.vertical, 20 * u)
        .frame(width: 900 * u)
        .background(StageLook.panel.opacity(0.78), in: .rect(cornerRadius: 30 * u))
        .background(LinearGradient(colors: [tint.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing), in: .rect(cornerRadius: 30 * u))
        .glassEffect(.regular, in: .rect(cornerRadius: 30 * u))
        .shadow(color: .black.opacity(0.5), radius: 40 * u, y: 18 * u)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .offset(y: shown ? 0 : -24 * u)
        .accessibilityElement(children: .combine)
    }

    func words(_ g: StageGame) -> (String, String, String, String) {
        switch moment.kind {
        case .welcome(let day, let total, let last):
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            let played = total >= 60 ? "\(Playtime.text(total)) played" : "Just started"
            return ("\(TheatreDaylight.now.greeting) · Welcome back", "Day \(day) in \(g.name)", "\(played) · last played \(f.localizedString(for: last, relativeTo: Date()))", "hand.wave.fill")
        case .newArrival:
            return ("New arrival", g.name, "Just joined your shelf. Built and ready to play.", "sparkles")
        case .built:
            return ("Ready to play", g.name, "Built and signed. Its first start prepares its shaders.", "party.popper.fill")
        case .shuffle:
            return ("What should I play?", g.name, TheatreDaylight.now.pick + (g.total >= 60 ? " · \(Playtime.text(g.total)) played" : g.app == nil ? " · not built yet" : " · not played yet"), "dice.fill")
        }
    }
}

/// Confetti from both lower corners, over the whole room, for four seconds (`frozen`: one moment of it, for a snapshot)
struct TheatreConfetti: View {
    let tint: Color
    var frozen: Double? = nil
    @Environment(\.tu) private var u
    @State private var start = Date()

    static let length = 4.2

    struct Bit {
        let left: Bool, vx: Double, vy: Double, spin: Double, size: Double, colour: Int, round: Bool, sway: Double, delay: Double
    }

    /// the same burst every time
    static let bits: [Bit] = {
        var n = TheatreSynth.Noise()
        func r() -> Double { (n.next() + 1) / 2 }
        return (0..<170).map { i in
            let left = i % 2 == 0
            let angle = (50 + 32 * r()) * .pi / 180
            let speed = 2000 + 1100 * r()
            return Bit(left: left, vx: cos(angle) * speed * (left ? 1 : -1), vy: -sin(angle) * speed, spin: (r() - 0.5) * 14,
                       size: 9 + 9 * r(), colour: Int(r() * 6), round: r() < 0.25, sway: r() * 6.28, delay: r() * 0.35)
        }
    }()

    var body: some View {
        let colours: [Color] = [tint, Color(red: 1, green: 0.82, blue: 0.3), .white, Color(red: 1, green: 0.42, blue: 0.55),
                                Color(red: 0.3, green: 0.85, blue: 0.8), Color(red: 0.55, green: 0.6, blue: 1)]
        TimelineView(.animation(paused: frozen != nil)) { ctx in
            let t = frozen ?? ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                let k = 1.7, g = 1200.0
                for b in Self.bits {
                    let s = t - b.delay
                    guard s > 0 else { continue }
                    let e = (1 - exp(-k * s)) / k
                    let x = (b.left ? -20 : Double(size.width / u) + 20) + b.vx * e + sin(s * 3 + b.sway) * 18
                    let y = Double(size.height / u) + 20 + g * s / k + (b.vy - g / k) * e
                    let fade = min(max((Self.length - t) / 0.9, 0), 1)
                    guard fade > 0 else { continue }
                    var c = gc
                    c.opacity = fade
                    c.translateBy(x: x * u, y: y * u)
                    c.rotate(by: .radians(b.spin * s))
                    let w = b.size * u, h = (b.round ? b.size : b.size * 0.45) * u * abs(cos(s * 4 + b.sway)).clamped(0.2, 1)
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    c.fill(b.round ? Path(ellipseIn: rect) : Path(rect), with: .color(colours[b.colour % colours.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Double {
    func clamped(_ a: Double, _ b: Double) -> Double { Swift.min(Swift.max(self, a), b) }
}

/// The lights going down as a game starts: the room dims, the game's box flies forward and opens, and the light inside it fills
/// the screen, under which the launch screen comes up, so the game comes out of its box. With Reduce Motion only the dimming.
struct TheatreLightsDown: View {
    let model: AppModel
    let curtain: TheatreCurtain
    @Environment(\.tu) private var u
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let g = model.stageGames().first { $0.id == curtain.game }
        let tint = g.map { CoverArt.tint($0) } ?? Color(red: 0.6, green: 0.7, blue: 1)
        GeometryReader { geo in
            TimelineView(.animation(paused: curtain.frozen != nil)) { ctx in
                let t = curtain.frozen ?? ctx.date.timeIntervalSince(curtain.start)
                scene(t: t, game: g, tint: tint, size: geo.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    static func backOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1), s = 1.4
        return 1 + (s + 1) * pow(c - 1, 3) + s * pow(c - 1, 2)
    }

    @ViewBuilder func scene(t: Double, game: StageGame?, tint: Color, size: CGSize) -> some View {
        let dim = Self.ease(t / 0.45)
        let fly = Self.backOut((t - 0.1) / 0.8)
        let open = Self.ease((t - 0.85) / 0.55)
        let bloom = Self.ease((t - 1.15) / 0.6)
        let out = Self.ease((t - TheatreCurtain.reveal) / (TheatreCurtain.length - TheatreCurtain.reveal - 0.05))
        let boxW = (240 + 190 * fly) * u, boxH = boxW / CoverSource.aspect
        ZStack {
            Color.black.opacity(0.93 * dim)
            if !still, let game {
                ZStack {
                    // inside the case: its light, and the game card in its slot
                    RoundedRectangle(cornerRadius: 14 * u)
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.9), tint, tint.opacity(0.4)], center: .center, startRadius: 0, endRadius: boxW * 0.75))
                        .opacity(0.25 + 0.75 * open)
                    RoundedRectangle(cornerRadius: 6 * u).fill(game.console == .switch2 ? Color(red: 0.85, green: 0.15, blue: 0.15) : Color(white: 0.92))
                        .frame(width: boxW * 0.2, height: boxW * 0.24).offset(x: -boxW * 0.22, y: -boxH * 0.22).opacity(open * 0.9)
                    // the front opens like a door, on its spine
                    cover(game, open: open).frame(width: boxW, height: boxH)
                }
                .frame(width: boxW, height: boxH)
                .shadow(color: tint.opacity(0.5 * open), radius: 60 * u)
                .shadow(color: .black.opacity(0.6), radius: 30 * u, y: 20 * u)
                .offset(y: (90 - 100 * fly) * u)
                .opacity(min(dim * 1.4, 1))
            }
            // the light pours out and fills the room
            let d = max(max(size.width, size.height) * 2.6 * bloom, 1)
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color(red: 1, green: 0.98, blue: 0.94), location: 0), .init(color: Color(red: 1, green: 0.98, blue: 0.94), location: 0.3),
                                             .init(color: tint.opacity(0.85), location: 0.62), .init(color: tint.opacity(0), location: 1)], center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
                .opacity(still ? 0 : bloom)
        }
        .frame(width: size.width, height: size.height)
        .opacity(1 - out)
    }

    @ViewBuilder func cover(_ g: StageGame, open: Double) -> some View {
        let angle = -112 * open
        ZStack {
            if angle > -90 {
                if let art = CoverArt.front(g) {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    CoverArt.tint(g)
                    Text(g.name).font(.system(size: 26 * u, weight: .bold)).multilineTextAlignment(.center).padding(20 * u)
                }
                // a light sweeping over the front as it starts to open
                LinearGradient(colors: [.clear, .white.opacity(0.35 * sin(.pi * open)), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                // the inside of the front, past a right angle
                Color(white: 0.12).overlay(Color.white.opacity(0.06))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * u))
        .overlay(RoundedRectangle(cornerRadius: 14 * u).strokeBorder(.white.opacity(0.25), lineWidth: 1.5 * u))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
    }
}
