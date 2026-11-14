// The converter's own updates (idea 1): What's New after its version changes, and one-click updating. The converter is built
// from the engine checkout (app/ in the same repository), so a newer converter is a newer CONVERTER_VERSION in that checkout,
// at HEAD (pulled, not rebuilt yet) or on the branch the engine updates from (not pulled yet). Update pulls the engine when it
// has to, then quits and lets a small shell script rebuild the app with app/bundle.sh into the same folder and open it again:
// the same name and place, never a second copy.
import AppKit
import Foundation

struct WhatsNew: Identifiable, Equatable {
    var id: String { version }
    let version: String
    /// "## X.Y.Z (date)" entries newer than the last one seen, newest first: (version, body markdown)
    let entries: [(version: String, body: String)]
    static func == (a: WhatsNew, b: WhatsNew) -> Bool { a.version == b.version }
}

/// A newer converter than the one running: where it is and what it is.
struct ConverterUpdateInfo: Equatable {
    let version: String
    /// "HEAD" when the checkout already has it (only a rebuild is needed), else the update target ("origin/main")
    let ref: String
    var needsPull: Bool { ref != "HEAD" }
}

enum ConverterUpdate {
    static let versionFile = "app/Sources/NXForgeConverter/Version.swift"
    static let changelogFile = "CONVERTER_CHANGELOG.md"
    private static let pattern = try! NSRegularExpression(pattern: #"(?m)^let CONVERTER_VERSION = "(\d+\.\d+\.\d+)""#)
    private static let heading = try! NSRegularExpression(pattern: #"^## (\d+\.\d+\.\d+) \(\d{4}-\d{2}-\d{2}\)\s*$"#)

    static func parseVersion(_ swift: String) -> String? {
        guard let m = pattern.firstMatch(in: swift, range: NSRange(swift.startIndex..., in: swift)), let r = Range(m.range(at: 1), in: swift) else { return nil }
        return String(swift[r])
    }

    static func key(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
    static func newer(_ a: String, than b: String) -> Bool { key(b).lexicographicallyPrecedes(key(a)) }

    /// The changelog's released entries, newest first.
    static func entries(_ log: String) -> [(version: String, body: String)] {
        var out: [(String, [String])] = []
        for line in log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let m = heading.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let r = Range(m.range(at: 1), in: line) {
                out.append((String(line[r]), []))
            } else if line.hasPrefix("## ") {
                out.append(("", []))   // Unreleased: not shown
            } else if !out.isEmpty {
                out[out.count - 1].1.append(line)
            }
        }
        return out.filter { !$0.0.isEmpty }.map { ($0.0, $0.1.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// What's New for `version`: its entry and every entry after `seen` (all of them up to `version` when nothing was seen yet,
    /// at most three).
    static func whatsNew(log: String, version: String, seen: String?) -> WhatsNew? {
        let all = entries(log).filter { !newer($0.version, than: version) }
        let fresh = all.filter { e in seen.map { newer(e.version, than: $0) } ?? true }
        let shown = Array((fresh.isEmpty ? all.prefix(1) : fresh.prefix(3)))
        guard !shown.isEmpty else { return nil }
        return WhatsNew(version: version, entries: shown)
    }

    static func git(_ repo: String, _ args: [String]) -> String? {
        guard let r = run("/usr/bin/env", ["git", "-C", repo] + args, env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]), r.ok else { return nil }
        return r.out
    }

    /// The converter version in the checkout at a ref ("HEAD", "origin/main").
    static func version(repo: String, ref: String) -> String? {
        git(repo, ["show", "\(ref):\(versionFile)"]).flatMap(parseVersion)
    }

    /// The changelog this app was built with (bundle.sh copies it into Resources): What's New reads it, so the notes are this
    /// version's own whatever branch the engine checkout is on. nil when run from `swift run` or a bundle made before 0.11.0.
    static func bundledChangelog(_ bundle: Bundle = .main) -> String? {
        bundle.url(forResource: "CONVERTER_CHANGELOG", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// What's New's text: the app's own copy, else the engine checkout's (which can be on another branch than this app's)
    static func ownChangelog(repo: String?) -> String? {
        bundledChangelog() ?? repo.flatMap { changelog(repo: $0) }
    }

    static func changelog(repo: String, ref: String = "HEAD") -> String? {
        if ref == "HEAD", let s = try? String(contentsOfFile: "\(repo)/\(changelogFile)", encoding: .utf8) { return s }
        return git(repo, ["show", "\(ref):\(changelogFile)"])
    }

    /// A newer converter than this one: in the checkout already, else on the update target (after a fetch). nil when this is the newest.
    static func check(repo: String, target: String?) -> ConverterUpdateInfo? {
        if let t = target, let v = version(repo: repo, ref: t), newer(v, than: CONVERTER_VERSION) {
            // the checkout may have it already, when only the converter is behind
            if let h = version(repo: repo, ref: "HEAD"), !newer(v, than: h) { return ConverterUpdateInfo(version: h, ref: "HEAD") }
            return ConverterUpdateInfo(version: v, ref: t)
        }
        if let h = version(repo: repo, ref: "HEAD"), newer(h, than: CONVERTER_VERSION) { return ConverterUpdateInfo(version: h, ref: "HEAD") }
        return nil
    }

    /// The installed app's folder when it runs from a bundle named as bundle.sh names it, so a rebuild can replace it in place.
    static var installFolder: String? {
        let b = Bundle.main.bundleURL
        guard b.pathExtension == "app", ["NXForge.app", "NXForge Converter.app"].contains(b.lastPathComponent) else { return nil }
        return b.deletingLastPathComponent().path
    }

    static var logFile: String { Settings.supportDir.appending(path: "converter-update.log").path }

    /// The shell script that waits for this process to end, rebuilds the app into the same folder and opens it (or the log
    /// when the build failed: bundle.sh builds before it removes the old app, so a failed build leaves the old one).
    static func script(repo: String, folder: String, pid: Int32) -> String {
        let app = "\(folder)/NXForge.app"
        return """
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        cd \(shq(repo)) || exit 1
        if app/bundle.sh \(shq(folder)) > \(shq(logFile)) 2>&1; then open \(shq(app)); else open -a Console \(shq(logFile)) || open \(shq(logFile)); fi
        """
    }

    /// Starts the rebuild script, detached from this process, which then quits.
    static func relaunchRebuilt(repo: String, folder: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script(repo: repo, folder: folder, pid: ProcessInfo.processInfo.processIdentifier)]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}

extension AppModel {
    /// At launch, once the engine checkout is known: What's New when this converter's version is newer than the last one shown.
    func showWhatsNewIfNeeded() {
        guard whatsNew == nil, settings.lastSeenVersion != CONVERTER_VERSION,
              ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        let seen = settings.lastSeenVersion, repo = env?.repo
        Task.detached {
            let w = ConverterUpdate.ownChangelog(repo: repo).flatMap { ConverterUpdate.whatsNew(log: $0, version: CONVERTER_VERSION, seen: seen) }
            await MainActor.run {
                if let w { self.whatsNew = w } else { self.settings.lastSeenVersion = CONVERTER_VERSION }
            }
        }
    }

    func dismissWhatsNew() {
        settings.lastSeenVersion = CONVERTER_VERSION
        whatsNew = nil
        // the launch's update offer waited for this sheet
        if let o = pendingOffer {
            pendingOffer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self.updateOffer = o } }
        }
    }

    /// The What's New of the running version, on demand (Help menu).
    func showWhatsNew() {
        let repo = env?.repo
        Task.detached {
            let w = ConverterUpdate.ownChangelog(repo: repo).flatMap { ConverterUpdate.whatsNew(log: $0, version: CONVERTER_VERSION, seen: nil) }
            await MainActor.run { self.whatsNew = w.map { WhatsNew(version: $0.version, entries: Array($0.entries.prefix(1))) } }
        }
    }

    /// After the engine's update check: is there a newer converter?
    func checkConverterUpdate(target: String?, reason: UpdateCheckReason = .manual) {
        guard let repo = env?.repo else { return }
        Task.detached {
            let u = ConverterUpdate.check(repo: repo, target: target)
            await MainActor.run { self.converterUpdate = u; self.afterUpdateCheck(reason) }
        }
    }

    /// Update the converter: pull the engine first when the newer converter is not in the checkout yet, then rebuild this app in
    /// place and open it again.
    func updateConverter(ask: Bool = true) {
        guard let u = converterUpdate, let repo = env?.repo else { return }
        guard !run.running, !batchRunning else {
            showBanner("Update the converter after this build", detail: "The update quits the converter, so it waits for the build to finish.", tone: .warning)
            return
        }
        guard let folder = ConverterUpdate.installFolder else {
            _ = confirm("Run from a build folder", "This converter does not run from an installed “NXForge.app”, so it cannot replace itself. Run app/install.sh in \(repo.tildePath) instead.", action: "OK")
            return
        }
        let what = u.needsPull ? "The engine updates to \(u.ref) first (as Update engine does), then the converter" : "The converter"
        guard !ask || confirm("Update NXForge to \(u.version)?", "\(what) is rebuilt from \(repo.tildePath) and replaces the copy in \(folder.tildePath), which takes about a minute. The converter quits now and opens again when it is built; if the build fails, the current copy stays and its log opens.", action: "Update and Relaunch") else { return }
        converterUpdating = true
        Task.detached {
            do {
                if u.needsPull { try Engine.update(repo) }
                try ConverterUpdate.relaunchRebuilt(repo: repo, folder: folder)
                await MainActor.run { NSApp.terminate(nil) }
            } catch {
                await MainActor.run {
                    self.converterUpdating = false
                    self.showBanner("Could not update the converter", detail: "\(error)", tone: .failure)
                }
            }
        }
    }
}
