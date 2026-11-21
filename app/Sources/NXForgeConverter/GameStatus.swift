// Why a game cannot be played, in words (Converter 0.14.0, from RetroReplay's availability language): a game without an app is
// never just dimmed. It says what stops it (not built yet, the drive its files are on is away, its files have gone, the build
// needs keys), and Play becomes the step that fixes it.
import AppKit
import SwiftUI

enum GameStatus: Equatable {
    /// built: the app is there
    case ready
    /// the files are there and the build can start
    case notBuilt
    /// a Switch game read with prod.keys, and no keys file is saved or beside it
    case keysNeeded
    /// the files are on a drive or a share that is not connected now (its name)
    case driveOffline(String)
    /// the folder the library found the game in is gone
    case filesMissing
    /// its last build stopped, and why (BuildFailures); building again is the fix
    case buildFailed(BuildFailure)

    /// Build is the step that fixes it (Not built yet, or a build that failed)
    var buildable: Bool {
        if case .notBuilt = self { return true }
        if case .buildFailed = self { return true }
        return false
    }

    var playable: Bool { self == .ready }

    /// the word on the cover and in the status line
    var text: String {
        switch self {
        case .ready: "Ready"
        case .notBuilt: "Not built yet"
        case .keysNeeded: "Keys needed"
        case .driveOffline: "Drive offline"
        case .filesMissing: "Files missing"
        case .buildFailed: "Build failed"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "play.fill"
        case .notBuilt: "hammer.fill"
        case .keysNeeded: "key.fill"
        case .driveOffline: "externaldrive.badge.xmark"
        case .filesMissing: "questionmark.folder.fill"
        case .buildFailed: "exclamationmark.triangle.fill"
        }
    }

    /// what is wrong and what fixes it, a sentence or two
    var detail: String {
        switch self {
        case .ready: "Built and ready to play."
        case .notBuilt: "Build turns the game's files into a Mac app."
        case .keysNeeded: "Building a Switch game needs your prod.keys. Choose it once and NXForge uses it for every build."
        case .driveOffline(let d): "Its files are on \(d), which is not connected. Connect it and the game is back."
        case .filesMissing: "The folder the library found it in has gone. Scan the library again, or put the files back."
        case .buildFailed(let f):
            "Its last build (\(f.at.formatted(date: .abbreviated, time: .shortened))) failed. \(f.title). \(f.fix)"
        }
    }

    /// the main button's label, which does the fix (AppModel.fix)
    var action: String {
        switch self {
        case .ready: "Play"
        case .notBuilt: "Build"
        case .keysNeeded: "Choose Keys…"
        case .driveOffline: "Check Again"
        case .filesMissing: "Scan Again"
        case .buildFailed: "Build Again"
        }
    }

    var actionSymbol: String {
        switch self {
        case .ready: "play.fill"
        case .notBuilt, .buildFailed: "hammer.fill"
        case .keysNeeded: "key.fill"
        case .driveOffline, .filesMissing: "arrow.clockwise"
        }
    }

    /// the eyebrow over a game's name on Home
    var eyebrow: String { text.uppercased() }

    var color: Color {
        switch self {
        case .ready: Color(red: 0.29, green: 0.87, blue: 0.50)
        case .notBuilt: Color(white: 0.62)
        case .keysNeeded: Color(red: 0.98, green: 0.75, blue: 0.14)
        case .driveOffline, .filesMissing, .buildFailed: Color(red: 1, green: 0.55, blue: 0.45)
        }
    }

    /// Where a path lives when it is not there: "/Volumes/Gaming/…" with no /Volumes/Gaming is that drive, offline (nil: the
    /// drive is there, or the path is on the startup disk).
    static func offlineVolume(_ path: String, fm: FileManager = .default) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        let vol = "/Volumes/\(parts[1])"
        return fm.fileExists(atPath: vol) ? nil : String(parts[1])
    }

    /// A game's status from what is on disk (cheap: a few file checks)
    static func of(app: String?, game: LibraryGame?, keys: (String) -> String?, failure: (String) -> BuildFailure? = { _ in nil },
                   fm: FileManager = .default) -> GameStatus {
        if app != nil { return .ready }
        guard let g = game else { return .notBuilt }
        if !fm.fileExists(atPath: g.path) {
            if let v = offlineVolume(g.path, fm: fm) { return .driveOffline(v) }
            return .filesMissing
        }
        if g.kind == .packages, keys(g.folder) == nil { return .keysNeeded }
        if let f = failure(g.folder) { return .buildFailed(f) }
        return .notBuilt
    }
}

extension AppModel {
    func status(_ g: StageGame) -> GameStatus {
        GameStatus.of(app: g.app, game: g.game, keys: { [self] in keysFile(for: $0) }, failure: { [self] in buildFailures[$0] })
    }

    /// Play on a game that cannot play yet: the step that fixes what stops it.
    func fix(_ g: StageGame) {
        switch status(g) {
        case .ready: playFromStage(g.ref)
        case .notBuilt, .buildFailed: playFromStage(g.ref)
        case .keysNeeded:
            // the same question a build asks; once a keys file is saved the game shows as Not built yet, and Build goes on
            if chooseKeysForBuild() { revision += 1; showBanner("Keys saved", detail: "\(g.name) can be built now.", tone: .success) }
        case .driveOffline(let d):
            revision += 1
            if GameStatus.offlineVolume(g.game?.path ?? "") == nil { showBanner("\(d) is back", tone: .success) }
            else { showBanner("\(d) is not connected", detail: "Connect the drive or the share that holds \(g.name)'s files, then try again.", tone: .warning) }
        case .filesMissing:
            showBanner("Scanning the library again", detail: "\(g.name)'s folder has gone.", symbol: "arrow.clockwise")
            scanLibrary()
        }
    }

    /// Saves a keys file the way a build would ask for one (a prod.keys found in a usual place, else a file panel).
    @discardableResult func chooseKeysForBuild() -> Bool {
        if let s = KeysFile.suggestion(gamesRoot: settings.gamesRoot),
           confirm("Use the keys found at \(s.tildePath)?", "Builds of Switch games need your prod.keys. NXForge saves this choice in Settings and uses it for every build.", action: "Use These Keys") {
            saveKeys(s); return true
        }
        guard confirm("Choose your prod.keys", "Builds of Switch games need your prod.keys, dumped from your own console. NXForge remembers where it is in Settings, so it asks only once.", action: "Choose…") else { return false }
        guard let f = choose(folder: false, start: settings.gamesRoot) else { return false }
        saveKeys(f)
        return true
    }
}

/// The status of a game that cannot play, as a label along the foot of its cover
struct CoverStatus: View {
    let status: GameStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol).font(.system(size: 9.5, weight: .bold))
            Text(status.text).font(.system(size: 10.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(status == .notBuilt ? Color.white : Color.black)
        .padding(.horizontal, 8).frame(height: 20)
        .background(status == .notBuilt ? Color.black.opacity(0.66) : status.color, in: .capsule)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .padding(7)
        .accessibilityLabel(status.text)
    }
}
