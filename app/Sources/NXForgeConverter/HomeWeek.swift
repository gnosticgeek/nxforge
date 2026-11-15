// Home's Your Week and Random Pick (Converter 0.14.0, from RetroReplay's Home widgets): the time played on each of the last seven
// days as small bars beside the shelf's heading, and a button that puts a game you have not played lately in front of you.
// Your Week counts only the time NXForge timed (playtime.json): a session over midnight is split between the two days, and
// nothing is invented for a game played while NXForge was closed.
import SwiftUI

struct PlayWeek: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        var seconds: Double = 0
        var id: Date { date }
    }
    var days: [Day]
    var games: Int
    var seconds: Double { days.reduce(0) { $0 + $1.seconds } }

    init(_ records: [String: PlayRecord], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        days = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }.map { Day(date: $0) }
        var played = Set<String>()
        for (key, r) in records {
            for s in r.sessions where s.seconds > 0 {
                let end = s.start.addingTimeInterval(s.seconds)
                for i in days.indices {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: days[i].date) else { continue }
                    let overlap = min(end, next, now).timeIntervalSince(max(s.start, days[i].date))
                    if overlap > 0 { days[i].seconds += overlap; played.insert(key) }
                }
            }
        }
        games = played.count
    }
}

/// Seven bars, today last, with the week's total
struct WeekStrip: View {
    let week: PlayWeek

    var body: some View {
        let top = max(week.days.map(\.seconds).max() ?? 0, 1)
        let cal = Calendar.current
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(week.days) { d in
                    let today = cal.isDateInToday(d.date)
                    Capsule().fill(today ? Color.white : Color.white.opacity(d.seconds > 0 ? 0.55 : 0.16))
                        .frame(width: 5, height: max(3, 22 * d.seconds / top))
                        .help("\(d.date.formatted(.dateTime.weekday(.wide))): \(d.seconds > 0 ? Playtime.text(d.seconds) : "no play")")
                }
            }
            .frame(height: 22, alignment: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(Playtime.text(week.seconds)).font(.system(size: 13, weight: .semibold))
                Text("this week · \(week.games) game\(week.games == 1 ? "" : "s")").font(.system(size: 11.5, weight: .medium)).foregroundStyle(StageLook.faint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your week: \(Playtime.text(week.seconds)) played across \(week.games) game\(week.games == 1 ? "" : "s")")
    }
}

extension AppModel {
    /// A built game to play: one not played in the last week if there is one (the one in front now passed over)
    func pickRandom(_ games: [StageGame]) {
        let built = games.filter { $0.app != nil && $0.id != libraryFocus }
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let fresh = built.filter { ($0.last ?? .distantPast) < weekAgo }
        guard let g = (fresh.isEmpty ? built : fresh).randomElement() else {
            showBanner("Build another game for Random Pick to choose from", tone: .info)
            return
        }
        libraryFocus = g.id
        randomPick = g.id
    }
}
