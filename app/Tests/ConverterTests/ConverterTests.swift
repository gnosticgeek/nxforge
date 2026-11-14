// Unit tests for the converter's pure logic: the release names it shows and how it reads title IDs.
// Run with `swift test --package-path app` on a Mac (CI runs them in tests.yml's converter job).
import Foundation
import Testing
@testable import NXForgeConverter

@Suite struct ReleaseNames {
    @Test(arguments: [
        ("v0.1.0", "0.1.0"),
        ("v0.7.1-3-gabc1234", "0.7.1+3"),
        ("pre-v0.1.0", "pre-0.1.0"),
        ("v1.0.0-rc1", "1.0.0-rc1"),
        ("v1.0.0-rc1-12-g0123abc", "1.0.0-rc1+12"),
    ])
    func describeToRelease(_ input: String, _ expected: String) {
        #expect(Engine.releaseName(input) == expected)
    }

    @Test func shortFallsBackToCommit() {
        let v = EngineVersion(commit: "fc2789876d2fe577c48245b0869f469b6acdb8a2", subject: "s", date: "d", branch: "main", dirty: false)
        #expect(v.short == "fc27898")
        var tagged = v; tagged.version = "v0.8.0"; tagged.dirty = true
        #expect(tagged.short == "0.8.0")
        #expect(tagged.label.hasPrefix("0.8.0+changes · "))
    }
}

@Suite struct TitleIDs {
    @Test func applicationOfEachContentType() {
        #expect(GameFiles.appOf(0x0100_1510_0B51_4000) == 0x0100_1510_0B51_4000)   // base game
        #expect(GameFiles.appOf(0x0100_1510_0B51_4800) == 0x0100_1510_0B51_4000)   // update
        #expect(GameFiles.appOf(0x0100_1510_0B51_5001) == 0x0100_1510_0B51_4000)   // DLC
    }
}

@Suite struct SettingsFile {
    @Test func emptyJSONGivesDefaults() throws {
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)) == Settings())
    }

    @Test func unknownEnumValueFallsBack() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"cleanup": "sometimes", "appearance": "Sepia", "notify": false}"#.utf8))
        #expect(s.cleanup == .off)
        #expect(s.appearance == .system)
        #expect(s.notify == false)
    }
}

@Suite struct SupportFolder {
    private func temp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "nxc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func oldFolderMovesAndLeavesALink() throws {
        let base = try temp(), old = base.appending(path: "NxNative Converter"), new = base.appending(path: "NXForge Converter")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appending(path: "settings.json"))
        Settings.migrateSupportDir(from: old, to: new)
        #expect(FileManager.default.fileExists(atPath: new.appending(path: "settings.json").path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: old.path) == new.path)
        #expect(FileManager.default.fileExists(atPath: old.appending(path: "settings.json").path))   // through the link
    }

    @Test func existingNewFolderIsLeftAlone() throws {
        let base = try temp(), old = base.appending(path: "NxNative Converter"), new = base.appending(path: "NXForge Converter")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        Settings.migrateSupportDir(from: old, to: new)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: old.path)) == nil)
    }
}

@Suite struct PlayedOnNXForge {
    @Test func rowsByTitleID() {
        let text = "# comment\ntitle_id\tgame\tversion\trelease\tmac\tdate\tresult\tnote\n" +
            "0100152000022000\tMario Kart 8 Deluxe\t4.0.1\t0.4.0\tM4 Pro\t2026-10-27\tplays\t60 fps\n" +
            "010015100B514000\tWonder\t-\t0.7.1\tM4 Pro\t2026-10-30\tboots\tx\nbad row\n"
        let v = VerifiedGames.parse(text)
        #expect(v.count == 2)
        #expect(v["0100152000022000"]?.summary == "Plays on 0.4.0 (4.0.1, M4 Pro, 2026-10-27)")
        #expect(v["010015100B514000"]?.summary == "Boots (not yet playable) on 0.7.1 (M4 Pro, 2026-10-30)")
    }

    @Test func titleIDFromBundleID() {
        #expect(VerifiedGames.titleID(bundleID: "org.nxforge.0100152000022000") == "0100152000022000")
        #expect(VerifiedGames.titleID(bundleID: "org.nxforge.converter") == nil)
    }

    @Test func repositoryTableParses() throws {
        // the engine's own table, read the way the Builds page reads it
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(!VerifiedGames.load(repo.path).isEmpty)
    }
}

@Suite struct OlderEngine {
    @Test(arguments: [
        ("dm/host/front_mac.m", true),
        ("dm/gfx/nvn/nvn_mtl.m", true),
        ("scripts/build_ipa_from_nsp.py", true),
        ("dm/games/game.py", true),
        ("dm/games/0100D2F00D5C0000/game.tsv", true),     // this game's profile
        ("dm/games/0100F2C0115B6000/game.tsv", false),    // another game's
        ("dm/host/README.md", false),
        ("dm/host/tests/t_hid.c", false),
        ("README.md", false),
        ("app/Sources/NXForgeConverter/Model.swift", false),
        ("docs/settings.md", false),
        ("scripts/bench.py", false),
        (".github/workflows/tests.yml", false),
    ])
    func affectsTheBuild(_ path: String, _ expected: Bool) {
        #expect(Engine.affects(path, titleID: "0100D2F00D5C0000") == expected)
    }

    @Test func anyProfileWithoutATitleID() {
        #expect(Engine.affects("dm/games/0100F2C0115B6000/game.tsv", titleID: nil))
    }
}

@Suite struct LayeredEngine {
    @Test func layerPathsAreEnginePaths() {
        let p = Layer.enginePaths(["layer/files/dm/games/0100D2F00D5C0000/game.tsv", "layer/files/dm/games/0100F2C0115B6000/game.tsv",
                                   "layer/ENGINE", "layer/patches/0004-gfx-metal.patch", "app/Sources/NXForgeConverter/Model.swift", "CHANGELOG.md"])
        #expect(p.map { Engine.affects($0, titleID: "0100D2F00D5C0000") } == [true, false, true, true, false, false])
    }

    @Test func pinParses() {
        let sha = String(repeating: "a", count: 40)
        #expect(Layer.parsePin("# comment\nurl https://github.com/seedds/nxnative.git\ncommit \(sha)\n") == sha)
        #expect(Layer.parsePin("commit abc\n") == nil)
    }

    @Test func localEngineParsesOnlyOnItsPin() {
        let up = String(repeating: "b", count: 40), pin = String(repeating: "a", count: 40)
        #expect(Layer.parseLocal("\(up) \(pin)\n", pin: pin) == up)
        #expect(Layer.parseLocal("\(up) \(pin)\n", pin: String(repeating: "c", count: 40)) == nil)   // a release moved the pin
        #expect(Layer.parseLocal("\(pin) \(pin)\n", pin: pin) == nil)
        #expect(Layer.parseLocal("\(up)\n", pin: pin) == nil)
        #expect(Layer.parseLocal("\(up) \(pin)", pin: nil) == nil)
    }

    @Test func localClashesNameThePatches() {
        let text = "not switched: 0004-gfx-metal.patch clashes in dm/gfx/nvn/nvn_mtl.m; 0006-packing.patch clashes in dm/tools/sdk_patches.py. The engine stays on the pin; NXForge has to update the patch first."
        #expect(Layer.clashes(text) == ["gfx-metal", "packing"])
        #expect(Releases.clashMessage(text).hasPrefix("Not switched: NXForge's gfx-metal, packing patches clash with upstream"))
        let check = "  0004-gfx-metal.patch: conflicts (dm/gfx/nvn/nvn_mtl.m)\n  0008-games.patch: applies\n  0009-docs.patch: conflicts (docs/development.md)"
        #expect(Layer.clashes(check) == ["gfx-metal", "docs"])
        #expect(Layer.clashes(check + "\n" + text) == ["gfx-metal", "docs", "packing"])
        #expect(Layer.clashes("cannot start python3").isEmpty)
        #expect(Releases.clashMessage("cannot start python3") == "cannot start python3")
    }

    @Test func thisCheckoutIsLayered() {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        #expect(Layer.isLayered(repo))
        #expect(Layer.tree(repo) == repo + "/tree")
        #expect(Layer.file(repo, "dm/host/quick_settings_mac.swift").hasSuffix("/dm/host/quick_settings_mac.swift"))
    }
}

@Suite struct FrameTimeRecordings {
    @Test func parseAndSum() {
        var text = "# kind: nvn-per-frame\nframe\tname\tvalue\n"
        for n in 0..<100 {
            let ms = n == 50 ? 80.0 : 16.7
            text += "\(n)\t@t_s\t\(Double(n) * 0.0167)\n\(n)\t@frame_ms\t\(ms)\n\(n)\t@presented_ms\t\(n == 60 ? -1 : 16.7)\n"
        }
        text += "100\t@t_s\t1.6"   // a row the host is still writing: no frame time, skipped
        let frames = FrameTimes.parse(text)
        #expect(frames.count == 100)
        let s = FrameTimes.Summary(frames)
        #expect(s?.hitches == 1)
        #expect(s?.dropped == 1)
        #expect(s?.frameP50 == 16.7)
        #expect(s?.frameMax == 80)
        #expect(s?.line.contains("1 hitch ·") == true)
    }

    @Test func percentileAsBench() {
        #expect(FrameTimes.percentile([1, 2, 3, 4], 50) == 2)
        #expect(FrameTimes.percentile([1, 2, 3, 4], 99) == 4)
        #expect(FrameTimes.percentile([], 50) == nil)
    }

    @Test func noFramesNoSummary() {
        #expect(FrameTimes.Summary(FrameTimes.parse("frame\tname\tvalue\n")) == nil)
    }
}

@Suite struct DroppedFiles {
    let dirs: Set<String> = ["/g/Kirby", "/g/Other"]
    func sort(_ p: [String]) -> DropFiles.Sorted { DropFiles.sort(p) { dirs.contains($0) } }

    @Test func folderIsTheGameFolder() {
        #expect(sort(["/g/Kirby"]) == DropFiles.Sorted(gameDir: "/g/Kirby", keys: nil))
    }

    @Test func gameFilesBringTheirFolder() {
        #expect(sort(["/g/Kirby/base.nsp", "/g/Kirby/update.NSZ"]).gameDir == "/g/Kirby")
        #expect(sort(["/g/Kirby/game.xci"]).gameDir == "/g/Kirby")
    }

    @Test func keysAndAMix() {
        let s = sort(["/k/title.keys", "/k/prod.keys", "/g/Kirby/base.nsp"])
        #expect(s.keys == "/k/prod.keys")
        #expect(s.gameDir == "/g/Kirby")
        #expect(sort(["/g/Kirby/base.nsp", "/g/Other"]).gameDir == "/g/Other")   // a folder wins
    }

    @Test func nothingUsable() {
        #expect(!sort(["/x/readme.txt", "/x/icon.png"]).usable)
    }

    @Test func aNupIsTheGameItself() {
        #expect(sort(["/g/Zelda/Ocarina [0400486024DEC000][v131072].NUP"]).gameDir == "/g/Zelda/Ocarina [0400486024DEC000][v131072].NUP")
        #expect(sort(["/g/Kirby/base.nsp", "/g/Zelda/oot.nup"]).gameDir == "/g/Zelda/oot.nup")
        #expect(sort(["/g/Zelda/oot.nup", "/g/Other"]).gameDir == "/g/Other")   // a folder wins
    }
}

@Suite struct Switch2Sources {
    private func temp() throws -> String {
        let u = FileManager.default.temporaryDirectory.appending(path: "nxc-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.path
    }
    private func touch(_ p: String) throws {
        try FileManager.default.createDirectory(atPath: p.url.deletingLastPathComponent().path, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: p.url)
    }

    @Test func kindsFromTheFileSystem() throws {
        let d = try temp()
        #expect(Source.kind(of: d) == .packages)   // nothing yet: the keys check says what is missing
        try touch(d + "/game.nup")
        #expect(Source.kind(of: d) == .nup)
        #expect(Source.kind(of: d + "/game.nup") == .nup)
        #expect(Source.folder(of: d + "/game.nup") == d)
        #expect(!Source.needsKeys(d + "/game.nup"))
        try touch(d + "/base.nsp")
        #expect(Source.kind(of: d) == .packages)   // packages win, as in the script
        let dump = try temp()
        try touch(dump + "/updates/131072/exefs/main.npdm")
        #expect(Source.kind(of: dump) == .dump)
        #expect(Source.folder(of: dump) == dump)
    }

    @Test func helperOutputDecodes() throws {
        let json = #"{"kind": "nup", "source": "/g/oot.nup", "folder": "/g", "title_id": "0400486024DEC000", "name": "", "base": true, "updates": [131072], "dlc": 0, "romfs_bytes": 28000000000, "file_bytes": 25600000000, "zbic": true, "zbic_installed": false, "profile": "The Legend of Zelda: Ocarina of Time", "notes": []}"#
        let i = try JSONDecoder().decode(SourceInfo.self, from: Data(json.utf8))
        #expect(i.describe == "Base game + update")
        let v = Source.validation(i)
        #expect(!v.ok)   // ZBIC code without zbic
        #expect(v.files.map(\.name) == ["Base game", "Update v131072"])
        var ok = i; ok.zbicInstalled = true; ok.profile = nil
        let w = Source.validation(ok)
        #expect(w.ok)   // no profile is a warning, not a stop
        #expect(w.summary.contains { $0.warn && $0.text.contains("no NXForge profile") })
        #expect(Source.firstBuildBytes(i) == 28000000000 * 2 + (Int64(20) << 30))
    }

    @Test func planSummaryIsPicked() {
        #expect(BuildRun.planMessage(#"{"ev": "say", "msg": "plan (--plan: nothing was built or changed):\n  reused: rewrite"}"#)?.hasSuffix("reused: rewrite") == true)
        #expect(BuildRun.planMessage(#"{"ev": "say", "msg": "a NUP: oot.nup"}"#) == nil)
        #expect(BuildRun.planMessage("not json") == nil)
    }
}

@Suite struct FailureDiagnosis {
    @Test(arguments: [
        ("[RED] less than 12 GB free on the volume of /Volumes/Games/x_build", Diagnosis.Code.diskFull),
        ("[RED] BuildError: Mario Kart 8 Deluxe 3.0.1 is a 32-bit ARM program (main.npdm: the 64-bit instruction flag is clear): x", .thirtyTwoBit),
        ("[RED] the Metal compiler does not run (error: cannot execute tool 'metal' due to missing Metal Toolchain)", .metalToolchain),
        ("[RED] the shader translator does not run (no runtime): it needs the .NET 10 runtime for this Mac", .dotnet),
        ("[RED] spirv-cross is missing or not executable: /opt/homebrew/bin/spirv-cross", .missingTool),
        ("[RED] no base game NSP found in /Games/Mario (title ID 010015100B514000)", .gameFiles),
        ("[RED] patch_nso.py exit code 1 on main (full output: x.log)", .rewriter),
        ("[RED] dmsh_build.py exit code 2 (full output: x.log)", .shaders),
        ("another build of this folder is running (process 412); wait for it to finish", .folderBusy),
        ("signature check failed: code object is not signed at all", .signing),
        ("stopped", .stopped),
        ("[RED] something nobody has seen before", .unknown),
    ])
    func errorGivesCode(_ error: String, _ code: Diagnosis.Code) {
        #expect(BuildDiagnosis.diagnose(error: error, log: []).code == code)
    }

    @Test func logTailWhenTheErrorSaysNothing() {
        let d = BuildDiagnosis.diagnose(error: "the script exited with 1", log: ["step 3", "Killed: 9"])
        #expect(d.code == .memory)
    }

    @Test func redactsKeysPathsAndHome() {
        let text = "header_key = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n" +
            "reading /Users/tom/keys/prod.keys for /Users/tom/Games/0100152000022000_build\n" +
            "key 00112233445566778899aabbccddeeff"
        let r = BuildDiagnosis.redact(text, keysPath: "/Users/tom/keys/prod.keys", home: "/Users/tom")
        #expect(!r.contains("0123456789abcdef0123456789abcdef"))
        #expect(!r.contains("00112233445566778899aabbccddeeff"))
        #expect(!r.contains("/Users/tom"))
        #expect(r.contains("[prod.keys]"))
        #expect(r.contains("~/Games/0100152000022000_build"))   // title IDs stay
    }
}

@Suite struct SaveSnapshotTests {
    private func temp() throws -> String {
        let p = FileManager.default.temporaryDirectory.appending(path: "nxc-saves-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
    private func write(_ s: String, _ path: String) throws {
        try FileManager.default.createDirectory(atPath: path.url.deletingLastPathComponent().path, withIntermediateDirectories: true)
        try Data(s.utf8).write(to: path.url)
    }
    private func read(_ path: String) -> String? { FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } }

    @Test func gameFolderSaveFirstThenLibrary() throws {
        let base = try temp(), home = base + "/home", app = base + "/Games/Mario.app"
        try FileManager.default.createDirectory(atPath: app, withIntermediateDirectories: true)
        let id = "010015100B514000"
        #expect(SaveSnapshots.location(app: app, titleID: id, home: home).save == base + "/Games/Saves/save")
        try write("lib", "\(home)/Library/Application Support/nxnative/\(id)/save/a")
        #expect(SaveSnapshots.location(app: app, titleID: id, home: home).save.hasPrefix(home + "/Library/"))
        try write("here", base + "/Games/Saves/save/a")
        #expect(SaveSnapshots.location(app: app, titleID: id, home: home).save == base + "/Games/Saves/save")
    }

    @Test func snapshotAndRestoreRoundTrip() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "010015100B514000")
        try write("one", loc.save + "/slot0/data.bin")
        try write("dev", loc.device + "/settings")
        let s = try #require(try SaveSnapshots.snapshot(loc, reason: .manual))
        #expect(s.files == 2)
        try write("two", loc.save + "/slot0/data.bin")
        try write("new", loc.save + "/slot1/data.bin")
        let safety = try SaveSnapshots.restore(s, to: loc)
        #expect(read(loc.save + "/slot0/data.bin") == "one")
        #expect(!FileManager.default.fileExists(atPath: loc.save + "/slot1"))
        #expect(read(loc.device + "/settings") == "dev")
        #expect(safety?.reason == .beforeRestore)
        #expect(SaveSnapshots.list(loc).count == 2)
        // nothing left over beside the save
        #expect(try FileManager.default.contentsOfDirectory(atPath: loc.folder).sorted() == ["save", "save-snapshots", "save_device"])
    }

    @Test func damagedSnapshotIsRefused() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "010015100B514000")
        try write("one", loc.save + "/a")
        let s = try #require(try SaveSnapshots.snapshot(loc, reason: .manual))
        try write("tampered", s.path + "/data/save/a")
        try write("current", loc.save + "/a")
        #expect(throws: ConverterError.self) { try SaveSnapshots.restore(s, to: loc) }
        #expect(read(loc.save + "/a") == "current")
    }

    @Test func linksAreRefused() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "010015100B514000")
        try write("one", loc.save + "/a")
        try FileManager.default.createSymbolicLink(atPath: loc.save + "/link", withDestinationPath: "/etc")
        #expect(throws: ConverterError.self) { try SaveSnapshots.snapshot(loc, reason: .manual) }
    }

    @Test func automaticSnapshotsArePruned() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "010015100B514000")
        try write("one", loc.save + "/a")
        try SaveSnapshots.snapshot(loc, reason: .manual)
        for _ in 0..<(SaveSnapshots.keepAutomatic + 2) { try SaveSnapshots.snapshot(loc, reason: .beforeRebuild) }
        let all = SaveSnapshots.list(loc)
        #expect(all.filter { $0.reason == .manual }.count == 1)
        #expect(all.filter { $0.reason != .manual }.count == SaveSnapshots.keepAutomatic)
    }
}

@Suite struct BuildTimeline {
    @Test func stageKeysDropTheVersion() {
        #expect(stageKey("extract v131072") == "extract")
        #expect(stageKey("Mac shaders") == "Mac shaders")
        #expect(stageKey("check v131072 files") == "check files")
    }

    @Test func onlyAWholeReusedStageCountsAsReused() {
        #expect(stageReused("reused"))
        #expect(stageReused("main, reused (inputs unchanged)"))
        #expect(stageReused("24.4 GB, reused (image checked)"))
        // Ocarina of Time's 51-minute Mac shader stage after a chain change
        #expect(!stageReused("42,848 of 42,848 shaders ready (Metal libraries: 9,807 reused, 33,041 compiled)"))
        #expect(!stageReused("1,200 converted, 30 reused (out)"))
    }

    @Test func oldRecordsOfLongReusedStagesStillCount() {
        let e = EngineVersion(commit: "c", subject: "s", date: "d", branch: "main", dirty: false)
        let b = BuildRecord(app: "/x/Other.app", gameDir: "/x/other", engine: e, repo: "/x", builtAt: "",
                            stages: [StageRecord(name: "Mac shaders", seconds: 3000, reused: true, ok: true),
                                     StageRecord(name: "Mac host", seconds: 7, reused: true, ok: true)],
                            gameBytes: 1_000_000_000)
        let exp = Estimates.expected(gameDir: "/nonexistent/game", gameBytes: 1_000_000_000, builds: [b])
        #expect(exp["Mac shaders"] == 3000)
        #expect(exp["Mac host"] == nil)
    }

    @MainActor @Test func aSwitch2BuildTicksItsTiles() {
        let r = BuildRun()
        r.running = true
        r.done = [StageDone(k: 1, n: 8, name: "unpack v131072", ok: true, seconds: 55, summary: "24 GB"),
                  StageDone(k: 2, n: 8, name: "check v131072 files", ok: true, seconds: 4, summary: "")]
        r.stage = Stage(k: 7, n: 8, name: "Pipeline archive")
        #expect(StepTiles.state("Extract tools", r) == .skipped)
        #expect(StepTiles.state("Extract game files", r) == .done)
        #expect(StepTiles.state("Package Mac app", r) == .running)
        // earlier in the same build: the steps after the running one wait
        r.stage = Stage(k: 3, n: 8, name: "rewrite")
        #expect(StepTiles.state("Extract tools", r) == .skipped)
        #expect(StepTiles.state("Rewrite executable", r) == .running)
        #expect(StepTiles.state("Package Mac app", r) == .pending)
    }

    @Test func stagesSortInBuildOrder() {
        #expect(stageRank("extract DLC")! > stageRank("extract v0")!)
        #expect(stageRank("Pipeline archive")! < stageRank("Mac app")!)
        #expect(stageRank("shader split")! < stageRank("Mac shaders")!)
        #expect(stageRank("something new") == nil)
    }

    @Test func otherGamesScaleBySize() {
        let e = EngineVersion(commit: "c", subject: "s", date: "d", branch: "main", dirty: false)
        let b = BuildRecord(app: "/x/A.app", gameDir: "/x", engine: e, repo: "/r", builtAt: "2026-11-05 20:00",
                            stages: [StageRecord(name: "Mac shaders", seconds: 600, reused: false, ok: true),
                                     StageRecord(name: "rewrite", seconds: 30, reused: true, ok: true)],
                            gameBytes: 1_000_000_000)
        let exp = Estimates.expected(gameDir: "/nonexistent/game", gameBytes: 2_000_000_000, builds: [b])
        #expect(exp["Mac shaders"] == 1200)
        #expect(exp["rewrite"] == nil)   // a reused stage says nothing about how long the work takes
        // a game far smaller (or larger) says nothing: 1 GB's 600 s is not 24 GB's 4 h
        #expect(Estimates.expected(gameDir: "/nonexistent/game", gameBytes: 24_000_000_000, builds: [b]).isEmpty)
        #expect(Estimates.expected(gameDir: "/nonexistent/game", gameBytes: 200_000_000, builds: [b]).isEmpty)
    }

    @Test func timeLeftWords() {
        #expect(timeLeft(30) == "Less than a minute left")
        #expect(timeLeft(23 * 60) == "About 23 min left")
        #expect(timeLeft(70 * 60) == "About 1 h 10 min left")
    }

    @MainActor @Test func overallUsesHistoryForTheRest() {
        let r = BuildRun()
        r.running = true
        r.startedAt = Date(timeIntervalSinceNow: -60)
        r.expected = ["extract": 60, "Mac shaders": 600, "Mac app": 120]
        r.stage = Stage(k: 2, n: 4, name: "Mac shaders", step: "", fraction: 0.5, detail: "", eta: 300)
        r.stageStartedAt = Date(timeIntervalSinceNow: -30)
        let o = r.overall()
        #expect(o.remaining == 420)   // the script's 300 s for this stage, then Mac app's 120 s
        #expect(o.segments.map(\.name).last == "Mac app")
    }
}

@Suite struct GameNeedsTests {
    @Test func titleIDFromFileNames() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "needs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appending(path: "Game [0400486024DEC800][v131072].nsz").path, contents: Data())
        #expect(GameNeeds.titleID(dir.path) == "0400486024DEC000")
        let needs = GameNeeds.detect(dir: dir.path, repo: nil)
        #expect(needs["zbic"] != nil)
        #expect(needs["nsz"] != nil)
    }
}

@Suite struct LogLevels {
    @Test func classify() {
        #expect(LogLevel("[RED] pipeline archive: pso_offline.py failed") == .error)
        #expect(LogLevel("warning: unused variable") == .warning)
        #expect(LogLevel("pso_offline: batch 3/31: ready") == .info)
    }
}

/// The Library scan: one game per folder, games sharing a folder split apart, DLC in a subfolder folded into its game,
/// Switch 2 .nup files and dump folders, and the converter's own folders left out.
@Suite struct LibraryScanning {
    func tree(_ files: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appending(path: "nxc-lib-\(UUID().uuidString)").path
        for f in files {
            let p = "\(root)/\(f)"
            try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data([1]).write(to: URL(fileURLWithPath: p))
        }
        return root
    }

    @Test func names() {
        #expect(GameLibrary.cleanName("Super Mario Odyssey [0100000000010000][v0]") == "Super Mario Odyssey")
        #expect(GameLibrary.cleanName("Yoshis_Crafted_World_[01006000040C2000][v0]") == "Yoshis Crafted World")
        #expect(GameLibrary.cleanName("Shadow of the Ninja Reborn [010072601DB8C000][v0] (1.98 GB)") == "Shadow of the Ninja Reborn")
        #expect(GameLibrary.cleanName("Kirby Star Allies[01007E3006DDA800][US][v327680]") == "Kirby Star Allies")
        #expect(GameLibrary.cleanName("Pikmin 1-2 [NSP]") == "Pikmin 1-2")
        #expect(GameLibrary.titleTag("0100f9f00c697001.nsp") == 0x0100_F9F0_0C69_7001)
        #expect(GameLibrary.titleTag("Snipperclips [UPD][0100704000b3a800][v65536].nsp") == 0x0100_7040_00B3_A800)
        #expect(GameLibrary.titleTag("Kirby and the Forgotten Land [v0].nsp") == nil)
    }

    @Test func scan() throws {
        let root = try tree([
            "Super Mario Odyssey [0100000000010000][v0].nsp", "Super Mario Odyssey [0100000000010800][v262144].nsp",
            "Metroid Prime REMASTERED [010012101468C000][v0][US].nsp", "The Legend of Zelda Skyward Sword HD.nsp",
            "Cadence [NSP]/Cadence of Hyrule [01000B900D8B0000][v0].nsp", "Cadence [NSP]/Cadence of Hyrule [01000B900D8B0800][v458752].nsp",
            "Cadence [NSP]/4 DLCs/Cadence [DLC] [01000B900D8B1001][v1].nsp", "Cadence [NSP]/4 DLCs/Cadence [DLC] [01000B900D8B1002][v1].nsp",
            "Pikmin 1-2 [NSP]/Pikmin 1 [0100AA80194B0000][v0].nsp", "Pikmin 1-2 [NSP]/Pikmin 2 [0100D680194B2000][v0].nsp",
            "Gato Roboto [NSP]/Gato Roboto [010025500C098800][v458752].nsp",
            "Echoes/Echoes of Wisdom [01008CF01BAAC000][v0][US].xci",
            "Echoes/0100ABCD00000000_build/extract/x.nsp",
            "Switch 2/The Legend of Zelda Ocarina of Time [0400486024DEC000][v131072].nup",
            "Dumps/Mario Kart World [0400C3F00006E000]/base/exefs/main.npdm", "Dumps/Mario Kart World [0400C3F00006E000]/base/romfs/a.nsp",
            "Empty/._Hidden [0100000000010000].nsp", "notes.txt",
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let s = GameLibrary.scan(root: root)
        #expect(s.stopped == nil)
        let by = Dictionary(s.games.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(s.games.count == 10, "\(s.games.map(\.name))")
        let smo = try #require(by["Super Mario Odyssey"])
        #expect(smo.shared && smo.base && smo.updates == 1 && smo.files.count == 2 && smo.path == root)
        #expect(by["The Legend of Zelda Skyward Sword HD"]?.shared == true)
        let coh = try #require(by["Cadence of Hyrule"])
        #expect(!coh.shared && coh.updates == 1 && coh.notes.count == 1)
        #expect(by["Pikmin 1"]?.shared == true && by["Pikmin 2"]?.shared == true)
        #expect(by["Gato Roboto"]?.base == false && by["Gato Roboto"]?.notes.isEmpty == false)
        #expect(by["Echoes of Wisdom"]?.fileCount == 1)   // the _build folder is not read
        #expect(by["The Legend of Zelda Ocarina of Time"]?.kind == .nup && by["The Legend of Zelda Ocarina of Time"]?.console == .switch2)
        #expect(by["Mario Kart World"]?.kind == .dump && by["Mario Kart World"]?.titleID == "0400C3F00006E000")

        // a shared game moves into a folder of its own, and is then one game there
        let p = try GameLibrary.moveToOwnFolder(smo)
        #expect(p == "\(root)/Super Mario Odyssey" && GameFiles.list(in: p.url).count == 2)
        let again = GameLibrary.scan(root: root)
        #expect(again.games.first { $0.name == "Super Mario Odyssey" }?.shared == false)
    }

    @Test func missingRoot() {
        let s = GameLibrary.scan(root: "/nonexistent-\(UUID().uuidString)")
        #expect(s.stopped != nil && s.games.isEmpty)
    }
}

/// The Library's tidying and control data: DLC in a subfolder moved beside its game, the same game in two folders, version
/// tags, and a control RomFS's files.
@Suite struct LibraryDetails {
    func tree(_ files: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appending(path: "nxc-lib2-\(UUID().uuidString)").path
        for f in files {
            let p = "\(root)/\(f)"
            try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data([1]).write(to: URL(fileURLWithPath: p))
        }
        return root
    }

    @Test func versionTags() {
        #expect(GameLibrary.versionTag("Super Mario Odyssey [0100000000010800][v1.3.0][v262144].nsp") == 262144)
        #expect(GameLibrary.versionTag("Game [0100000000010000].nsp") == nil)
    }

    @Test func strayAndDuplicates() throws {
        let root = try tree([
            "Cadence/Cadence [01000B900D8B0000][v0].nsp", "Cadence/Cadence [01000B900D8B0800][v458752].nsp",
            "Cadence/Extras/Cadence [DLC] [01000B900D8B1001][v1].nsp",
            "Cyber Shadow/Cyber Shadow [0100C1F0141AA000][v0].nsp", "Cyber Shadow [NSP]/Cyber Shadow [0100C1F0141AA000][v0].nsp",
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let s = GameLibrary.scan(root: root)
        let c = try #require(s.games.first { $0.titleID == "01000B900D8B0000" })
        #expect(c.stray?.count == 1 && c.dlc == 1 && c.newestUpdate == 458752)
        #expect(s.games.filter { $0.titleID == "0100C1F0141AA000" }.allSatisfy { $0.duplicates?.count == 1 })
        try GameLibrary.moveStray(c)
        let again = GameLibrary.scan(root: root).games.first { $0.titleID == "01000B900D8B0000" }
        #expect(again?.files.count == 3 && again?.stray == nil && again?.notes.isEmpty == true)
    }

    @Test func dlcFolder() throws {
        let root = try tree([
            "Cadence/Cadence [01000B900D8B0000][v0].nsp",
            "Cadence/dlc/Cadence [DLC] [01000B900D8B1001][v1].nsp", "Cadence/dlc/Cadence [DLC] [01000B900D8B1002][v1].nsp",
            "Cadence/dlc/Cadence [01000B900D8B0800][v458752].nsp",
            "Hades/Hades [0100535012974000][v0].nsp", "Hades/DLCs/Hades DLC.nsp",
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let s = GameLibrary.scan(root: root)
        #expect(s.games.count == 2, "\(s.games.map(\.name))")
        let c = try #require(s.games.first { $0.titleID == "01000B900D8B0000" })
        #expect(c.dlc == 2 && c.stray?.count == 1 && c.notes.count == 1)   // the update in DLC/ is not read
        let h = try #require(s.games.first { $0.titleID == "0100535012974000" })
        #expect(h.dlc == 1 && h.stray == nil && h.notes.isEmpty)   // an untagged file in DLCs/ counts as DLC
        #expect(GameFiles.buildFiles(in: "\(root)/Hades".url).map(\.lastPathComponent) == ["Hades [0100535012974000][v0].nsp", "Hades DLC.nsp"])
        #expect(Engine.describeFiles("\(root)/Cadence") == "Base game + 2 DLC")
    }

    @Test func romfsFiles() {
        // a RomFS with two files at the root: header (0x50), file table, then the data
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let names = ["control.nacp", "icon_AmericanEnglish.dat"], datas: [[UInt8]] = [[1, 2, 3], [0xFF, 0xD8, 0xFF]]
        var table: [UInt8] = [], data: [UInt8] = []
        for (n, d) in zip(names, datas) {
            let nb = Array(n.utf8)
            table += le(0, 4) + le(0, 4) + le(data.count, 8) + le(d.count, 8) + le(0, 4) + le(nb.count, 4) + nb + [UInt8](repeating: 0, count: (4 - nb.count % 4) % 4)
            data += d
        }
        let metaOff = 0x50, dataOff = metaOff + table.count
        var header = le(0x50, 8) + le(0, 8) + le(0, 8) + le(0, 8) + le(0, 8) + le(0, 8) + le(0, 8)
        header += le(metaOff, 8) + le(table.count, 8) + le(dataOff, 8)
        let files = ControlReader.romfsFiles(header + table + data)
        #expect(files["control.nacp"] == [1, 2, 3] && files["icon_AmericanEnglish.dat"] == [0xFF, 0xD8, 0xFF])
    }
}

// Converter 0.2.0: What's New, profile notes, launch settings, playtime and Build later.
@Suite struct ConverterTwo {
    let log = """
    # NXForge Converter changelog

    ## 0.3.0 (2026-12-01)

    - Third.

    ## 0.2.0 (2026-11-08)

    - Second.

    ## 0.1.0 (2026-11-07)

    - First.
    """

    @Test func versionsCompare() {
        #expect(ConverterUpdate.newer("0.10.0", than: "0.9.1"))
        #expect(!ConverterUpdate.newer("0.2.0", than: "0.2.0"))
        #expect(!ConverterUpdate.newer("0.1.9", than: "0.2.0"))
    }

    @Test func whatsNewListsUnseenEntries() {
        let w = ConverterUpdate.whatsNew(log: log, version: "0.3.0", seen: "0.1.0")
        #expect(w?.entries.map(\.version) == ["0.3.0", "0.2.0"])
        #expect(ConverterUpdate.whatsNew(log: log, version: "0.3.0", seen: "0.3.0")?.entries.map(\.version) == ["0.3.0"])
    }

    @Test func profileNotes() {
        let readme = """
        # Some Game (`0100ABCDEF000000`)

        Version 1.2.0, Unity. Plays to the credits.

        ## Issues

        - **Resolved:** crash at the title.
        - **Open:** shadows flicker in the [forest](x.md).
        """
        let n = GameInsights.parse(readme, titleID: "0100ABCDEF000000", readme: "/r")
        #expect(n.title == "Some Game")
        #expect(n.summary == "Version 1.2.0, Unity. Plays to the credits.")
        #expect(n.open == ["Open: shadows flicker in the forest."])
        #expect(n.resolved == 1)
    }

    @Test func rangeSettingsAccept() throws {
        let json = #"{"env":"X","kind":"range","label":"l","note":"n","def":"1","min":0.5,"max":2,"step":0.5}"#
        let s = try JSONDecoder().decode(LaunchSetting.self, from: Data(json.utf8))
        #expect(s.accepts("1.5"))
        #expect(!s.accepts("3"))
        #expect(!s.accepts("0x1"))
        #expect(s.isDefault("1.0"))
    }

    @Test func weeklyPlaytime() {
        let now = Date()
        let r = PlayRecord(name: "g", app: "/a.app", sessions: [PlaySession(start: now.addingTimeInterval(-60), seconds: 600)])
        let w = Playtime.weekly(r, weeks: 4, now: now)
        #expect(w.count == 4)
        #expect(w.last?.minutes == 10)
        #expect(Playtime.text(3900) == "1 h 5 min")
    }

    @Test func tonightIsAhead() {
        let now = Date()
        let t = BatchSchedule.tonight(now: now)
        #expect(t > now && t.timeIntervalSince(now) <= 86400)
        #expect(Calendar.current.component(.hour, from: t) == 2)
    }
}

@Suite struct UnifiedUpdates {
    @Test func releaseTags() {
        #expect(Releases.version(tag: "v0.17.1", prefix: "v") == "0.17.1")
        #expect(Releases.version(tag: "converter-v0.2.1", prefix: "converter-v") == "0.2.1")
        #expect(Releases.version(tag: "v0.17", prefix: "v") == nil)
        #expect(Releases.version(tag: "v0.17.1-rc1", prefix: "v") == nil)
        #expect(Releases.newest(["v0.9.1", "v0.10.0", "v0.2.0", "vnext"], prefix: "v") == "v0.10.0")
        #expect(Releases.base(ofDescribe: "v0.17.0-3-gabc1234") == "0.17.0")
        #expect(Releases.base(ofDescribe: "pre-v0.1.0") == nil)
    }

    @Test func sidebarVersionLine() {
        #expect(Releases.parseSidebar("import SwiftUI\n\nlet SIDEBAR_VERSION = \"0.2.0\"\n") == "0.2.0")
        #expect(Releases.parseSidebar("let x = 1") == nil)
    }

    @Test func notesBetweenVersions() {
        let log = "# Log\n\n## 0.17.1 (2026-11-08)\n\n- Fix.\n\n## 0.17.0 (2026-11-08)\n\n- Feature.\n\n## 0.16.0 (2026-11-07)\n\n- Old.\n"
        #expect(Releases.entries(log, after: "0.16.0", upTo: "0.17.1").map(\.version) == ["0.17.1", "0.17.0"])
        #expect(Releases.entries(log, after: "0.17.0", upTo: "0.17.0").isEmpty)
    }

    @Test func upToDateWording() {
        #expect(AppModel.describe(Engine.Update(count: 0, target: "origin/main", ref: "v0.17.1", release: "0.17.1"), branch: "main") == "Up to date")
        #expect(AppModel.describe(Engine.Update(count: 3, target: "origin/main", ref: "v0.17.1", release: "0.17.1"), branch: "main") == "0.17.1 available")
        #expect(AppModel.describe(Engine.Update(count: 2, target: "origin/main", ref: "origin/main", release: nil), branch: "release-0.17.0") == "2 updates available on main")
    }

    /// A clone of a repository whose main has release tags and a commit after the newest one (a release PR merged, not
    /// tagged yet): the engine updates to the tag, not past it, and stays on main.
    @Test func engineUpdatesToNewestReleaseTag() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nxc-upd-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        func sh(_ cmd: String) throws {
            let r = run("/bin/bash", ["-c", "set -e; export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; \(cmd)"],
                        env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": root])
            if r?.ok != true { throw ConverterError("\(cmd): \(r?.out ?? "no shell")") }
        }
        try sh("""
        mkdir -p \(root) && cd \(root) && git init -q -b main src && cd src
        echo 1 > f && git add f && git commit -qm one && git tag v0.1.0
        cd .. && git clone -q src engine && cd src
        echo 2 > f && git commit -qam two && git tag -a v0.2.0 -m 0.2.0
        echo 3 > f && git commit -qam three
        """)
        let repo = "\(root)/engine"
        let u = try Engine.checkUpdates(repo)
        #expect(u.release == "0.2.0")
        #expect(u.ref == "v0.2.0")
        #expect(u.count == 1)
        try Engine.update(repo)
        #expect(Engine.current(repo)?.subject == "two")
        #expect(Engine.current(repo)?.branch == "main")
        #expect(try Engine.checkUpdates(repo).count == 0)
    }
}

@Suite struct BuildHome {
    @Test func localGameBuildsBesideItsFiles() {
        let dir = NSTemporaryDirectory() + "nxf-buildhome-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(!Disk.isNetwork(dir))
        #expect(Disk.buildHome(dir) == dir)
        #expect(Disk.workDir(dir) == nil)
        #expect(Disk.free(dir).map { $0 > 0 } == true)
    }
}

@Suite struct Confirmations {
    @Test(arguments: [("Delete", true), ("Move to Trash", true), ("Stop and Quit", true), ("Stop Build", true),
                      ("Restore", false), ("Build Anyway", false), ("OK", false), ("Move and Convert", false)])
    func destructiveAnswers(_ action: String, _ expected: Bool) {
        #expect(AppModel.isDestructive(action) == expected)
    }
}
