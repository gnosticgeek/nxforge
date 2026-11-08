// Build selected, later (idea 11): start the queue at a time (tonight at 2:00, or any time), or once the Mac is on power. While it
// waits and while it builds, the Mac does not idle-sleep (a closed lid on battery still sleeps: plug it in). The queue is kept in
// batch-queue.json, so it survives a quit: at the next start it waits again, or offers to start at once if its time passed. Games
// waiting can be moved up or down, or taken out.
import AppKit
import Foundation
import IOKit.ps

enum BatchStart: Codable, Equatable {
    case at(Date)
    case onPower

    var text: String {
        switch self {
        case .at(let d): return "Starts \(relativeDay(d).lowercasedFirst)"
        case .onPower: return "Starts when the Mac is on power"
        }
    }
}

private struct SavedQueue: Codable {
    var games: [LibraryGame]
    var start: BatchStart?
}

enum BatchSchedule {
    static var file: URL { Settings.supportDir.appending(path: "batch-queue.json") }

    static func save(_ games: [LibraryGame], start: BatchStart?) {
        if games.isEmpty { try? FileManager.default.removeItem(at: file); return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(SavedQueue(games: games, start: start)) { try? d.write(to: file, options: .atomic) }
    }

    static func load() -> ([LibraryGame], BatchStart?)? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let q = try? dec.decode(SavedQueue.self, from: d), !q.games.isEmpty else { return nil }
        return (q.games, q.start)
    }

    /// Whether the Mac runs on its power adapter (a desktop Mac always does).
    static var onPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPMACPowerKey
    }

    /// The next 2:00 from now.
    static func tonight(at hour: Int = 2, now: Date = Date()) -> Date {
        let cal = Calendar.current
        var d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }
}

extension AppModel {
    /// Build selected now or later: later puts the queue in place and waits.
    func buildSelected(start: BatchStart?) {
        guard let start else { buildSelected(); return }
        guard !run.running, !batchRunning, batchStart == nil, let games = library?.games.filter({ librarySelection.contains($0.id) }), !games.isEmpty else { return }
        batchQueue = games
        batchResults = []
        batchMessage = nil
        librarySelection = []
        waitForBatch(start)
    }

    func waitForBatch(_ start: BatchStart) {
        batchStart = start
        BatchSchedule.save(batchQueue, start: start)
        keepAwake(true)
        batchWait?.cancel()
        batchWait = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let due: Bool
                switch start {
                case .at(let d): due = Date() >= d
                case .onPower: due = BatchSchedule.onPower
                }
                if due, !self.run.running { self.startWaitingBatch(); return }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// Start a waiting queue now.
    func startWaitingBatch() {
        batchWait?.cancel(); batchWait = nil
        batchStart = nil
        guard !batchQueue.isEmpty, !run.running else { return }
        // the games moved (tidied) or went away since they were queued: build what is still there
        batchQueue = batchQueue.filter { FileManager.default.fileExists(atPath: $0.path) || offlineVolume($0.path) != nil }
        nextInBatch()
    }

    func cancelWaitingBatch() {
        batchWait?.cancel(); batchWait = nil
        batchStart = nil
        batchQueue = []
        BatchSchedule.save([], start: nil)
        keepAwake(false)
    }

    /// The queue as it stands, for the next start (called as it changes).
    func saveBatchQueue() {
        BatchSchedule.save(batchQueue, start: batchStart)
        if batchQueue.isEmpty && batchCurrent == nil && batchStart == nil { keepAwake(false) }
    }

    func moveInQueue(_ g: LibraryGame, by d: Int) {
        guard let i = batchQueue.firstIndex(of: g) else { return }
        let j = min(max(i + d, 0), batchQueue.count - 1)
        batchQueue.swapAt(i, j)
        saveBatchQueue()
    }

    func removeFromQueue(_ g: LibraryGame) {
        batchQueue.removeAll { $0 == g }
        if batchQueue.isEmpty && batchCurrent == nil { cancelWaitingBatch() } else { saveBatchQueue() }
    }

    /// At launch: a queue left from last time waits again, or (its time passed while the converter was closed) asks.
    func restoreBatchQueue() {
        guard let (games, start) = BatchSchedule.load() else { return }
        batchQueue = games
        if case .at(let d)? = start, d < Date() {
            batchStart = .at(d)   // shown as missed on the Library, with Start Now and Clear
            return
        }
        waitForBatch(start ?? .onPower)
    }

    /// Keeps the Mac from idle sleep while a queue waits or builds (each build holds its own too).
    func keepAwake(_ on: Bool) {
        if on, batchActivity == nil {
            batchActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Build selected is waiting to start")
        } else if !on, let a = batchActivity {
            ProcessInfo.processInfo.endActivity(a); batchActivity = nil
        }
    }
}
