// Newly playable: when an engine update brings a profile for a game in your games folder that is not built yet, or NXForge's list
// (docs/nxforge-games.tsv) now says it boots or plays, Home says so and offers to build it tonight. What each game could do at
// the last look is kept in playable.json; the first look only records, so a fresh install announces nothing.
import Foundation
import SwiftUI
import UserNotifications

struct PlayableArrival: Codable, Hashable, Identifiable {
    var titleID: String
    var name: String
    /// 1 a profile (it can be built), 2 boots, 3 plays
    var level: Int
    var id: String { titleID }

    var what: String { ["", "can be built now", "boots now", "plays now"][min(max(level, 0), 3)] }
}

struct PlayableState: Codable {
    var levels: [String: Int] = [:]
    /// announced and not yet built or dismissed
    var pending: [PlayableArrival] = []
}

enum NewlyPlayable {
    static var file: URL { Settings.supportDir.appending(path: "playable.json") }

    /// What a game can do on this engine: 3 plays, 2 boots, 1 has a profile, 0 neither (or listed as broken)
    static func level(profile: Bool, result: String?) -> Int {
        switch result {
        case "plays": 3
        case "boots": 2
        case "broken": 0
        default: profile ? 1 : 0
        }
    }

    /// The games whose level rose since the last look, among those not built. A game the last look did not know (new to the
    /// games folder) is not an arrival: the engine did not change for it.
    static func arrivals(old: [String: Int], now: [(titleID: String, name: String, level: Int, built: Bool)]) -> [PlayableArrival] {
        now.compactMap { g in
            guard !g.built, let was = old[g.titleID], g.level > was, g.level >= 1 else { return nil }
            return PlayableArrival(titleID: g.titleID, name: g.name, level: g.level)
        }.sorted { ($0.level, $1.name) > ($1.level, $0.name) }
    }

    static func load() -> PlayableState? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(PlayableState.self, from: $0) }
    }

    static func save(_ s: PlayableState) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(s) { try? d.write(to: file, options: .atomic) }
    }

    static func headline(_ a: [PlayableArrival]) -> String {
        a.count == 1 ? "\(a[0].name) \(a[0].what)" : "\(a.count) of your games can be built now"
    }
}

extension AppModel {
    /// Look again (after the tools check, which reads the engine and its list of games, and after a scan of the games folder)
    func checkNewlyPlayable() {
        guard ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil, env?.repo != nil, let games = library?.games, !games.isEmpty else { return }
        let builds = libraryBuilds()
        var seenIDs = Set<String>()
        let now: [(titleID: String, name: String, level: Int, built: Bool)] = games.compactMap { g in
            guard let t = g.titleID?.uppercased(), seenIDs.insert(t).inserted else { return nil }
            return (t, g.displayName, NewlyPlayable.level(profile: hasProfile(g), result: verified[t]?.result), build(of: g, in: builds) != nil)
        }
        let levels = Dictionary(now.map { ($0.titleID, $0.level) }, uniquingKeysWith: { a, _ in a })
        guard var state = NewlyPlayable.load() else { NewlyPlayable.save(PlayableState(levels: levels)); return }
        let fresh = NewlyPlayable.arrivals(old: state.levels, now: now)
        let built = Set(now.filter(\.built).map(\.titleID)), known = Set(levels.keys)
        // a game built since, or gone from the games folder, leaves the list; a fresh arrival replaces its older line
        var pending = state.pending.filter { p in !built.contains(p.titleID) && known.contains(p.titleID) && !fresh.contains { $0.titleID == p.titleID } }
        pending.insert(contentsOf: fresh, at: 0)
        let changed = state.levels != levels || state.pending != pending
        state.levels = levels; state.pending = pending
        if changed { NewlyPlayable.save(state) }
        if newlyPlayable != pending { newlyPlayable = pending }
        guard !fresh.isEmpty else { return }
        let names = fresh.prefix(4).map(\.name).joined(separator: ", ") + (fresh.count > 4 ? " and \(fresh.count - 4) more" : "")
        showBanner(NewlyPlayable.headline(fresh), detail: fresh.count == 1 ? "It is in your games folder, not built yet." : names, tone: .success, symbol: "sparkles",
                   action: ("Build Tonight", { [weak self] in self?.buildNewlyPlayable(tonight: true) }), seconds: 20)
        if settings.notify, Bundle.main.bundleIdentifier != nil {
            let c = UNMutableNotificationContent()
            c.title = NewlyPlayable.headline(fresh)
            c.body = fresh.count == 1 ? "Open NXForge to build it, now or tonight." : names
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    /// Build the announced games: now, or tonight at 2:00 (Build selected's queue, with its free-space check)
    func buildNewlyPlayable(tonight: Bool) {
        let ids = Set(newlyPlayable.map(\.titleID))
        let games = (library?.games ?? []).filter { g in g.titleID.map { ids.contains($0.uppercased()) } ?? false }
        guard !games.isEmpty else { dismissNewlyPlayable(); return }
        guard !run.running, !batchRunning, batchStart == nil else {
            showBanner("A build is running or waiting already", detail: "Add these from the Converter's Game Files page when it is done.", tone: .warning)
            return
        }
        librarySelection = Set(games.map(\.id))
        if tonight {
            buildSelected(start: .at(BatchSchedule.tonight()))
            if batchStart != nil { showBanner("\(games.count == 1 ? games[0].displayName : "\(games.count) games") will build tonight at 2:00", detail: "Leave NXForge open and the Mac on power.", tone: .success, symbol: "moon.stars.fill") }
        } else {
            showConverter(); page = .library
            buildSelected()
        }
        if batchStart != nil || batchRunning { dismissNewlyPlayable() }
    }

    func dismissNewlyPlayable() {
        newlyPlayable = []
        if var s = NewlyPlayable.load() { s.pending = []; NewlyPlayable.save(s) }
    }
}

/// Home's pill beside "Your games": the games that became playable, with Build Tonight, Build Now and Dismiss
struct NewlyPlayablePill: View {
    let model: AppModel

    var body: some View {
        let a = model.newlyPlayable
        if !a.isEmpty {
            Menu {
                Section(NewlyPlayable.headline(a)) {
                    ForEach(a) { g in Text("\(g.name): \(g.what)") }
                }
                Button("Build Tonight at 2:00") { model.buildNewlyPlayable(tonight: true) }
                Button("Build Now") { model.buildNewlyPlayable(tonight: false) }
                Divider()
                Button("Dismiss") { model.dismissNewlyPlayable() }
            } label: {
                HStack(spacing: 6) { Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)); Text(a.count == 1 ? "1 newly playable" : "\(a.count) newly playable") }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.green)
            .padding(.trailing, 14)
            .help("An engine update made these games in your games folder buildable")
            .accessibilityLabel(NewlyPlayable.headline(a))
        }
    }
}
