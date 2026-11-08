// Notifications with actions (idea 10): a finished build's has Play and Show in Finder, a failed one's Copy Error Summary, an
// IPA's Show in Finder. The app delegate answers them (UNUserNotificationCenterDelegate).
import AppKit
import UserNotifications

enum Notify {
    static let built = "nxc.built", failed = "nxc.failed", ipa = "nxc.ipa"
    static let play = "nxc.play", show = "nxc.show", copy = "nxc.copy"

    static func registerCategories() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let play = UNNotificationAction(identifier: Self.play, title: "Play", options: [.foreground])
        let show = UNNotificationAction(identifier: Self.show, title: "Show in Finder", options: [.foreground])
        let copy = UNNotificationAction(identifier: Self.copy, title: "Copy Error Summary", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: built, actions: [play, show], intentIdentifiers: []),
            UNNotificationCategory(identifier: failed, actions: [copy], intentIdentifiers: []),
            UNNotificationCategory(identifier: ipa, actions: [show], intentIdentifiers: []),
        ])
    }

    @MainActor static func handle(_ action: String, category: String, path: String?, model: AppModel) {
        switch action {
        case play: if let p = path, !p.isEmpty { model.openApp(p) }
        case show: if let p = path, !p.isEmpty { reveal(p) }
        case copy: if let s = model.lastErrorSummary { copyToClipboard(s) }
        default:
            // the notification itself: bring the window to the build's page
            NSApp.activate()
            model.page = category == built ? .builds : .convert
        }
    }
}

extension AppModel {
    /// The summary to paste into a report for a failed build (BuildDiagnosis), as Copy error summary gives it.
    func errorSummary(_ error: String, diagnosis: Diagnosis? = nil) -> String {
        let d = diagnosis ?? BuildDiagnosis.diagnose(error: error, log: run.log)
        let failed = run.done.last { !$0.ok }.map(\.line) ?? (run.stage.name.isEmpty ? nil : "[\(run.stage.k)/\(run.stage.n)] \(run.stage.name)")
        let title = settings.gameDir.flatMap { dir in Engine.apps(in: dir).first.flatMap { VerifiedGames.titleID(ofApp: $0.app) } }
        let name = game.map { g in title.map { "\(g.name) (\($0))" } ?? g.name }
        return BuildDiagnosis.summary(d, error: error, log: run.log, failedStep: failed, game: name, engine: engine?.label,
                                      xcode: checks?.first { $0.name == "Xcode" }?.detail, keysPath: settings.keys)
    }
}
