// Updates (Converter 0.3.0): one place for the three parts NXForge ships with versions of their own (UPSTREAM.md, Versions).
// - The engine: the NXForge checkout, updated to the newest vX.Y.Z release tag on main (Engine.checkUpdates), with how far
//   upstream nxnative's main is ahead of what NXForge has merged, for information only.
// - The converter: rebuilt from that checkout and relaunched in place (ConverterUpdate), offered in a sheet at launch, or done
//   without asking when Update automatically is on.
// - The in-game sidebar: compiled into each game app, so a newer one reaches a game by rebuilding it (the build reuses its
//   cached stages). The sidebar version a game has is read from the engine commit its build record names.
// Checks run at launch, when the converter comes to the front an hour or more after the last one, and before every update.
import AppKit
import SwiftUI

enum Releases {
    static let upstreamURL = "https://github.com/seedds/nxnative.git"
    static let sidebarFile = "dm/host/quick_settings_mac.swift"
    private static let sidebarPattern = try! NSRegularExpression(pattern: #"(?m)^let SIDEBAR_VERSION = "(\d+\.\d+\.\d+)""#)

    static func git(_ repo: String, _ args: [String]) -> String? { ConverterUpdate.git(repo, args) }

    /// "v0.17.1" → "0.17.1" with prefix "v"; nil for a tag that is not prefix + X.Y.Z
    static func version(tag: String, prefix: String) -> String? {
        guard tag.hasPrefix(prefix) else { return nil }
        let v = String(tag.dropFirst(prefix.count))
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) ? v : nil
    }

    /// The newest of these tags by version (not by date or name order): "v0.10.0" beats "v0.9.1".
    static func newest(_ tags: [String], prefix: String) -> String? {
        tags.compactMap { t in version(tag: t, prefix: prefix).map { (t, $0) } }
            .max { ConverterUpdate.newer($1.1, than: $0.1) }?.0
    }

    /// The newest prefixX.Y.Z tag in a ref's history ("v0.17.1" on origin/main), after a fetch with tags.
    static func newest(repo: String, prefix: String, in ref: String) -> String? {
        guard let out = git(repo, ["tag", "--merged", ref, "--list", "\(prefix)[0-9]*"]) else { return nil }
        return newest(out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }, prefix: prefix)
    }

    static func parseSidebar(_ swift: String) -> String? {
        guard let m = sidebarPattern.firstMatch(in: swift, range: NSRange(swift.startIndex..., in: swift)), let r = Range(m.range(at: 1), in: swift) else { return nil }
        return String(swift[r])
    }

    private static var sidebarCache: [String: String] = [:]   // commit → version, "" before the sidebar had one
    private static let lock = NSLock()
    /// The sidebar version at a commit: "" for a commit from before the sidebar was versioned (NXForge 0.16.0), nil when the
    /// checkout does not have the commit. With no commit, the checkout's working tree.
    static func sidebarVersion(repo: String, commit: String?) -> String? {
        guard let c = commit else {
            return (try? String(contentsOfFile: "\(repo)/\(sidebarFile)", encoding: .utf8)).flatMap(parseSidebar)
        }
        lock.lock(); let hit = sidebarCache[c]; lock.unlock()
        if let hit { return hit }
        guard git(repo, ["cat-file", "-e", "\(c)^{commit}"]) != nil else { return nil }
        let v = git(repo, ["show", "\(c):\(sidebarFile)"]).flatMap(parseSidebar) ?? ""
        lock.lock(); sidebarCache[c] = v; lock.unlock()
        return v
    }

    /// Changelog entries newer than `after` and no newer than `upTo`, newest first (at most `limit`).
    static func entries(_ log: String, after: String?, upTo: String, limit: Int = 3) -> [(version: String, body: String)] {
        Array(ConverterUpdate.entries(log).filter { e in
            !ConverterUpdate.newer(e.version, than: upTo) && (after.map { ConverterUpdate.newer(e.version, than: $0) } ?? true)
        }.prefix(limit))
    }

    /// "0.17.0" for git describe "v0.17.0-3-gabc" and "v0.17.0"; nil before the first release
    static func base(ofDescribe d: String?) -> String? {
        guard let d, d.hasPrefix("v") else { return nil }
        return String(d.dropFirst().split(separator: "-").first ?? "")
    }

    /// Fetches upstream nxnative's main (the checkout's "upstream" remote when it is nxnative, else the address into a ref
    /// of its own) and counts the commits on it that NXForge's main has not merged yet.
    static func upstreamStatus(repo: String) -> UpstreamStatus? {
        let remote = git(repo, ["remote", "get-url", "upstream"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let viaRemote = remote.lowercased().contains("seedds/nxnative")
        let ref = viaRemote ? "refs/remotes/upstream/main" : "refs/nxforge/upstream-main"
        guard git(repo, ["fetch", "--quiet", "--no-tags", viaRemote ? "upstream" : upstreamURL, "+refs/heads/main:\(ref)"]) != nil else { return nil }
        let main = git(repo, ["rev-parse", "--abbrev-ref", "origin/HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "origin/main"
        guard let n = git(repo, ["rev-list", "--count", "--no-merges", "\(main)..\(ref)"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return nil }
        let last = git(repo, ["log", "-1", "--format=%cs%x1f%s", ref])?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}").map(String.init) ?? []
        return UpstreamStatus(count: n, date: last.first ?? "", subject: last.count > 1 ? last[1] : "")
    }
}

/// How far upstream nxnative's main is ahead of what NXForge has merged.
struct UpstreamStatus: Equatable {
    let count: Int
    /// the newest upstream commit's date and subject
    let date: String
    let subject: String
}

/// The sheet over the window when something is newer: the engine and the converter, from and to, with their notes.
struct UpdateOffer: Identifiable {
    var id: String { key }
    var engine: (from: String, to: String)?
    var converter: (from: String, to: String)?
    var engineNotes: [(version: String, body: String)] = []
    var converterNotes: [(version: String, body: String)] = []
    /// what Skip This Version remembers: the versions offered
    var key: String { "engine \(engine?.to ?? "-") converter \(converter?.to ?? "-")" }
}

/// Why a check runs: the one at launch can offer the sheet; the hourly one only updates (when automatic) or shows the capsule.
enum UpdateCheckReason { case launch, background, manual }

extension AppModel {
    var anyUpdate: Bool { engineUpdate != nil || converterUpdate != nil }

    /// Built games (still on disk) whose sidebar is older than the engine checkout's, kept builds left out.
    var sidebarOutdated: [BuildRecord] {
        let _ = revision
        guard let cur = sidebarCurrent else { return [] }
        return Engine.builds().filter { b in
            guard b.kept != true, FileManager.default.fileExists(atPath: b.app) else { return false }
            let v = sidebarBuilds[b.app] ?? ""
            return v.isEmpty || ConverterUpdate.newer(cur, than: v)
        }
    }

    /// Kept builds with an older sidebar: left as they are, and counted on the Updates page.
    var sidebarKeptOlder: Int {
        guard let cur = sidebarCurrent else { return 0 }
        return Engine.builds().filter { b in
            b.kept == true && FileManager.default.fileExists(atPath: b.app) && { let v = sidebarBuilds[b.app] ?? ""; return v.isEmpty || ConverterUpdate.newer(cur, than: v) }()
        }.count
    }

    /// The sidebar version in the engine checkout, and in each built game, read off the main thread.
    func refreshSidebarStatus() {
        guard let repo = env?.repo else { return }
        let builds = Engine.builds()
        Task.detached {
            let cur = Releases.sidebarVersion(repo: repo, commit: nil)
            var by: [String: String] = [:]
            for b in builds { by[b.app] = Releases.sidebarVersion(repo: repo, commit: b.engine.commit) ?? "" }
            let found = by
            await MainActor.run { self.sidebarCurrent = cur; self.sidebarBuilds = found }
        }
    }

    /// Upstream nxnative's commits NXForge has not merged yet (a fetch of nxnative; quiet when offline).
    func checkUpstream() {
        guard let repo = env?.repo else { return }
        Task.detached {
            let s = Releases.upstreamStatus(repo: repo)
            await MainActor.run { if s != nil { self.upstream = s } }
        }
    }

    /// Rebuild every game with an older sidebar, one after another (the Rebuild all queue: a failure stops the rest).
    func updateSidebars() {
        let all = sidebarOutdated
        guard let first = all.first, !run.running, !batchRunning else { return }
        rebuildQueue = Array(all.dropFirst())
        queueMessage = ""
        rebuild(first)
    }

    /// An hour or more since the last check, and the converter came to the front: check again (and update, when automatic).
    func recheckUpdatesIfStale() {
        guard let last = lastUpdateCheck, Date().timeIntervalSince(last) > 3600, !engineBusy, engine != nil else { return }
        engineAction(update: false, reason: .background)
    }

    /// After a check: update without asking when Update automatically is on, else (at launch) offer the sheet once per version.
    func afterUpdateCheck(_ reason: UpdateCheckReason) {
        guard anyUpdate, reason != .manual, ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil else { return }
        if settings.autoUpdate { updateAutomatically(); return }
        guard reason == .launch else { return }
        let offer = makeOffer()
        guard settings.skippedUpdate != offer.key else { return }
        if whatsNew != nil { pendingOffer = offer } else { updateOffer = offer }
    }

    func makeOffer() -> UpdateOffer {
        var o = UpdateOffer()
        let repo = env?.repo
        if let u = engineUpdate {
            let from = engine?.short ?? "?"
            o.engine = (from, u.release ?? "\(u.count) new commit\(u.count == 1 ? "" : "s")")
            if let to = u.release, let repo, let log = ConverterUpdate.git(repo, ["show", "\(u.ref):CHANGELOG.md"]) {
                o.engineNotes = Releases.entries(log, after: Releases.base(ofDescribe: engine?.version), upTo: to)
            }
        }
        if let c = converterUpdate {
            o.converter = (CONVERTER_VERSION, c.version)
            if let repo, let log = ConverterUpdate.changelog(repo: repo, ref: c.ref) {
                o.converterNotes = Releases.entries(log, after: CONVERTER_VERSION, upTo: c.version)
            }
        }
        return o
    }

    /// Update automatically: never while a build or a queue runs (the next check tries again). A newer converter brings the
    /// engine with it (it is built from the checkout); else just the engine.
    func updateAutomatically() {
        guard !run.running, !batchRunning, rebuildQueue.isEmpty, batchStart == nil, !converterUpdating, !engineBusy else { return }
        if converterUpdate != nil, ConverterUpdate.installFolder != nil { updateConverter(ask: false) }
        else if engineUpdate != nil, engine?.dirty != true { engineAction(update: true) }
    }

    /// The sheet's Update button.
    func acceptOffer() {
        updateOffer = nil
        if converterUpdate != nil { updateConverter(ask: false) } else { engineAction(update: true) }
    }

    func skipOffer(_ o: UpdateOffer) {
        settings.skippedUpdate = o.key
        updateOffer = nil
    }
}

// MARK: The Updates page

struct UpdatesPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroHeader(symbol: "arrow.down.circle", title: "Updates", subtitle: "NXForge, the converter and the in-game sidebar, each with its own version.")
            header
            engineRow
            converterRow
            sidebarRow
        }
    }

    var header: some View {
        HStack(spacing: 14) {
            if model.engineBusy { ProgressView().frame(width: 40) }
            else { Image(systemName: model.anyUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(model.anyUpdate ? Color.accentColor : .green).frame(width: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.engineBusy ? "Checking…" : model.anyUpdate ? "Updates are available" : "Everything is up to date").font(.title3.weight(.bold))
                Text(model.lastUpdateCheck.map { "Last checked: \(relativeDay($0))." } ?? "Not checked yet.").foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Update automatically", isOn: $model.settings.autoUpdate).toggleStyle(.switch)
                .help("At launch and when the converter comes back to the front: update the engine and the converter without asking (never during a build). Games' sidebars are never rebuilt without asking.")
            Button { model.engineAction(update: false, reason: .manual) } label: { Label("Check Now", systemImage: "arrow.clockwise") }
                .buttonStyle(.glass).disabled(model.engineBusy || model.engine == nil)
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }

    var engineRow: some View {
        let u = model.engineUpdate
        let failed = model.engineMessage?.ok == false
        return UpdateRow(symbol: "gearshape.fill", colors: [.purple, .indigo], title: "NXForge engine",
                         detail: "The engine checkout in \(model.env?.repo?.tildePath ?? "?"), on NXForge's release tags.",
                         installed: model.engine.map { "\($0.short)\($0.dirty ? "+changes" : "")" } ?? "None",
                         badge: failed ? ("Check failed", .red) : u.map { ("\($0.release ?? "\($0.count) new commits") available", .blue) } ?? ("Up to date", .green)) {
            if u != nil {
                Button { model.engineAction(update: true) } label: { Label("Update", systemImage: "arrow.down.circle") }
                    .buttonStyle(.glassProminent)
                    .disabled(model.engineBusy || model.run.running || model.engine?.dirty == true)
                    .help(model.engine?.dirty == true ? "The checkout has local changes: commit or stash them first." : "Fast-forward the checkout to \(u?.ref ?? "")")
            }
        } extra: {
            if let n = model.updateNote { Label("New: \(n)", systemImage: "sparkles").font(.callout).foregroundStyle(.blue) }
            if failed, let m = model.engineMessage { Text(m.text).font(.callout).foregroundStyle(.red) }
            if let m = model.engineMessage, m.ok, m.text.hasPrefix("Updated") { Text(m.text).font(.callout).foregroundStyle(.secondary) }
            if let s = model.upstream {
                Label(s.count == 0 ? "Upstream nxnative: nothing new beyond what NXForge has merged."
                                   : "Upstream nxnative: \(s.count) commit\(s.count == 1 ? "" : "s") not in NXForge yet (newest \(s.date)). They arrive with the next NXForge release.",
                      systemImage: "arrow.triangle.branch")
                    .font(.callout).foregroundStyle(.secondary)
                    .help(s.subject.isEmpty ? "" : "Newest upstream commit: \(s.subject)")
            }
        }
    }

    var converterRow: some View {
        let u = model.converterUpdate
        return UpdateRow(symbol: "macwindow.badge.plus", colors: [.blue, .cyan], title: "NXForge Converter",
                         detail: ConverterUpdate.installFolder.map { "This app, in \($0.tildePath). An update rebuilds it from the engine checkout and opens it again." }
                            ?? "This app (run from a build folder, so it cannot replace itself).",
                         installed: CONVERTER_VERSION, badge: u.map { ("\($0.version) available", .blue) } ?? ("Up to date", .green)) {
            Button("What's New") { model.showWhatsNew() }.buttonStyle(.glass)
            if u != nil {
                Button { model.updateConverter() } label: { Label(model.converterUpdating ? "Updating…" : "Update and Relaunch", systemImage: "arrow.down.circle") }
                    .buttonStyle(.glassProminent).disabled(model.converterUpdating)
            }
        } extra: { EmptyView() }
    }

    var sidebarRow: some View {
        let old = model.sidebarOutdated
        let busy = model.run.running || model.batchRunning || !model.rebuildQueue.isEmpty
        return UpdateRow(symbol: "sidebar.right", colors: [.orange, .pink], title: "In-game sidebar",
                         detail: "Built into each game app, so a game gets a newer sidebar when it is rebuilt (its cached stages are reused).",
                         installed: model.sidebarCurrent.map { "\($0) in the engine" } ?? "?",
                         badge: old.isEmpty ? ("All games current", .green) : ("\(old.count) game\(old.count == 1 ? "" : "s") on an older sidebar", .blue)) {
            if !old.isEmpty {
                Button { model.updateSidebars() } label: {
                    Label(model.queueMessage == "" && !model.rebuildQueue.isEmpty ? "Rebuilding… \(model.rebuildQueue.count) to Go" : "Update Sidebar in \(old.count) Game\(old.count == 1 ? "" : "s")", systemImage: "hammer")
                }
                .buttonStyle(.glassProminent).disabled(busy || !model.allOK)
                .help(model.allOK ? "Rebuild each one in turn; a failure stops the rest. Each needs its game files (and keys) where it was built from." : "The Toolchain page lists what is missing to build.")
            }
        } extra: {
            if !old.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(old) { b in
                        let v = model.sidebarBuilds[b.app] ?? ""
                        HStack(spacing: 8) {
                            Text(b.app.url.deletingPathExtension().lastPathComponent).lineLimit(1)
                            Text(v.isEmpty ? "before 0.1.0" : v).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
            if model.sidebarKeptOlder > 0 {
                Text("\(model.sidebarKeptOlder) kept build\(model.sidebarKeptOlder == 1 ? "" : "s") with an older sidebar left as \(model.sidebarKeptOlder == 1 ? "it is" : "they are") (rebuild from Builds).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let m = model.queueMessage, !m.isEmpty { Text(m).font(.callout).foregroundStyle(.orange) }
        }
    }
}

/// One part: its icon, what it is, the version installed and the newer one, and its buttons; notes under it.
struct UpdateRow<Actions: View, Extra: View>: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let detail: String
    let installed: String
    let badge: (text: String, color: Color)
    @ViewBuilder var actions: Actions
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.title3.weight(.bold))
                        Text(badge.text)
                            .font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(badge.color.opacity(0.22), in: .capsule).foregroundStyle(badge.color)
                    }
                    Text(detail).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Installed").font(.caption).foregroundStyle(.secondary)
                    Text(installed).monospacedDigit().fontWeight(.medium)
                }
                HStack(spacing: 8) { actions }.fixedSize()
            }
            extra.padding(.leading, 58)
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }
}

// MARK: The sheet at launch

struct UpdateOfferSheet: View {
    @Bindable var model: AppModel
    let offer: UpdateOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A new update is available").font(.title2.weight(.bold))
                    Text(summary).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let c = offer.converter { notes("NXForge Converter \(c.to)", offer.converterNotes) }
                    if let e = offer.engine { notes("NXForge \(e.to)", offer.engineNotes) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            Toggle("Update automatically from now on", isOn: $model.settings.autoUpdate).toggleStyle(.checkbox)
            HStack {
                Button("Skip This Version") { model.skipOffer(offer) }
                Spacer()
                Button("Later") { model.updateOffer = nil }.keyboardShortcut(.cancelAction)
                Button(offer.converter != nil ? "Update and Relaunch" : "Update") { model.acceptOffer() }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.run.running)
                    .help(model.run.running ? "A build is running: update once it has finished." : "")
            }
        }
        .padding(22).frame(width: 560)
    }

    var summary: String {
        var parts: [String] = []
        if let c = offer.converter { parts.append("Converter \(c.to) (you have \(c.from))") }
        if let e = offer.engine { parts.append("NXForge \(e.to) (you have \(e.from))") }
        return parts.joined(separator: " and ") + "."
    }

    @ViewBuilder func notes(_ title: String, _ entries: [(version: String, body: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                if entries.count > 1 { Text(e.version).font(.subheadline.weight(.semibold)).padding(.top, 2) }
                ForEach(Array(e.body.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    let l = String(line)
                    if l.hasPrefix("- ") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(LocalizedStringKey(String(l.dropFirst(2))))
                        }
                    } else if !l.trimmingCharacters(in: .whitespaces).isEmpty && !l.hasPrefix("#") {
                        Text(LocalizedStringKey(l)).foregroundStyle(.secondary)
                    }
                }
            }
            if entries.isEmpty { Text("No notes for this version.").foregroundStyle(.secondary) }
        }
    }
}
