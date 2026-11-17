// Unit tests for the converter's pure logic: the release names it shows and how it reads title IDs.
// Run with `swift test --package-path app` on a Mac (CI runs them in tests.yml's converter job).
import AppKit
import CoreGraphics
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

    @Test func afterPlaySkipsAnUnchangedSave() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "0100A00000000001")
        #expect(try SaveSnapshots.snapshotAfterPlay(loc) == nil)   // no save yet
        try write("one", loc.save + "/a")
        let first = try #require(try SaveSnapshots.snapshotAfterPlay(loc))
        #expect(first.reason == .afterPlay)
        #expect(first.device == SaveSnapshots.deviceName)
        #expect(try SaveSnapshots.snapshotAfterPlay(loc) == nil)   // nothing changed
        try write("two", loc.save + "/a")
        #expect(try SaveSnapshots.snapshotAfterPlay(loc) != nil)
        #expect(SaveSnapshots.list(loc).count == 2)
        #expect(SaveSnapshots.list(loc).first?.device == SaveSnapshots.deviceName)
    }

    @Test func sessionsNeverPushOutTheSnapshotBeforeARestore() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "0100A00000000002")
        try write("start", loc.save + "/a")
        try SaveSnapshots.snapshot(loc, reason: .beforeRestore)
        for i in 0..<(SaveSnapshots.keepAutomatic + 2) {
            try write("session \(i)", loc.save + "/a")
            try SaveSnapshots.snapshotAfterPlay(loc)
        }
        let all = SaveSnapshots.list(loc)
        #expect(all.filter { $0.reason == .afterPlay }.count == SaveSnapshots.keepAutomatic)
        #expect(all.filter { $0.reason == .beforeRestore }.count == 1)
    }

    @Test func aSnapshotMovesCheckedToAnotherFolder() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "0100A00000000003")
        try write("one", loc.save + "/a")
        let s = try #require(try SaveSnapshots.snapshot(loc, reason: .manual))
        let dest = base + "/NAS/0100A00000000003"
        #expect(try SaveSnapshots.move(s, to: dest, titleID: loc.titleID))
        #expect(!FileManager.default.fileExists(atPath: s.path))
        let moved = SaveSnapshots.list(in: dest, titleID: loc.titleID)
        #expect(moved.map(\.id) == [s.id])
        try write("two", loc.save + "/a")
        try SaveSnapshots.restore(try #require(moved.first), to: loc)
        #expect(read(loc.save + "/a") == "one")
    }

    @Test func aDamagedSnapshotStaysWhereItWas() throws {
        let base = try temp()
        let loc = SaveLocation(save: base + "/Saves/save", titleID: "0100A00000000004")
        try write("one", loc.save + "/a")
        let s = try #require(try SaveSnapshots.snapshot(loc, reason: .manual))
        try write("tampered", s.path + "/data/save/a")
        #expect(throws: ConverterError.self) { try SaveSnapshots.move(s, to: base + "/NAS", titleID: loc.titleID) }
        #expect(FileManager.default.fileExists(atPath: s.path))
        #expect(SaveSnapshots.list(in: base + "/NAS", titleID: loc.titleID).isEmpty)
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

    /// A checkout left on a release branch with commits main never got (the release went out from other commits): once
    /// main has that release or a newer one, the engine follows main's newest tag instead of the branch, which never moves
    /// again and said "Up to date" forever. A release branch ahead of main's newest release is still followed.
    @Test func staleReleaseBranchFollowsMain() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nxc-stale-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        func sh(_ cmd: String) throws {
            let r = run("/bin/bash", ["-c", "set -e; export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; \(cmd)"],
                        env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": root])
            if r?.ok != true { throw ConverterError("\(cmd): \(r?.out ?? "no shell")") }
        }
        try sh("""
        mkdir -p \(root) && cd \(root) && git init -q -b main src && cd src
        echo 1 > f && git commit -q --allow-empty -m one && git add f && git commit -qm base && git tag -a v0.1.0 -m 0.1.0
        git switch -q -c release-0.2.0 && echo b > g && git add g && git commit -qm "branch only"
        git switch -q -c release-0.4.0 main && echo c > h && git add h && git commit -qm "next release work"
        git switch -q main && echo 2 > f && git commit -qam two && git tag -a v0.2.0 -m 0.2.0
        echo 3 > f && git commit -qam three && git tag -a v0.3.0 -m 0.3.0
        cd .. && git clone -q src engine && cd engine && git switch -q --track origin/release-0.2.0
        cd .. && git clone -q src next && cd next && git switch -q --track origin/release-0.4.0
        """)
        let repo = "\(root)/engine"
        #expect(Engine.updateTarget(repo) == "origin/main")
        let u = try Engine.checkUpdates(repo)
        #expect(u.release == "0.3.0")
        try Engine.update(repo)
        #expect(Engine.current(repo)?.subject == "three")
        #expect(Engine.current(repo)?.branch == "main")
        #expect(Engine.updateTarget("\(root)/next") == "origin/release-0.4.0")
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

// Converter 0.7.0's UI changes: the sidebar's short time left, recent games, Storage deletes that can be undone and the
// settings that remember the window.
@Suite struct UIChanges {
    @Test(arguments: [(30.0, "<1 m"), (90.0, "2 m"), (3540.0, "59 m"), (4320.0, "1 h 12 m")])
    func shortTime(_ s: Double, _ expected: String) {
        #expect(shortTimeLeft(s) == expected)
    }

    @Test func recentSourcesPutTheNewestFirstWithoutRepeats() {
        var l: [String] = []
        for p in ["/a", "/b", "/c", "/b", "/d", "/e", "/f"] { l = RecentSources.adding(p, to: l) }
        #expect(l == ["/f", "/e", "/d", "/b", "/c"])
    }

    @Test func heldDeleteHidesThenUndoPutsItBack() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "nxc-held-\(UUID().uuidString)")
        let cache = root.appending(path: "0100ABC_build")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: cache.appending(path: "f"))
        defer { try? fm.removeItem(at: root) }

        let p = try PendingDeletes.hide(cache.path, bytes: 1, label: "Build cache")
        #expect(!fm.fileExists(atPath: cache.path))
        #expect(fm.fileExists(atPath: p.hidden))
        #expect(p.hidden.lastComponent.hasPrefix("."))
        #expect(!p.hidden.hasSuffix("_build"))   // so Storage's scan no longer lists it
        try PendingDeletes.restore(p)
        #expect(fm.fileExists(atPath: cache.appending(path: "f").path))

        let q = try PendingDeletes.hide(cache.path, bytes: 1, label: "Build cache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)   // a build made it again meanwhile
        #expect(throws: (any Error).self) { try PendingDeletes.restore(q) }
        PendingDeletes.purge(q)
        #expect(!fm.fileExists(atPath: q.hidden))
    }

    @Test func newSettingsRoundTripAndOldFilesStillRead() throws {
        var s = Settings()
        s.libraryCoverSize = 210; s.libraryGroupByConsole = true; s.recentSources = ["/g"]
        s.lastPage = "Storage"; s.lastBuild = "/a.app"; s.lastLibraryFocus = "id"
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"repo": "/r", "library_cover_size": 9999}"#.utf8))
        #expect(old.libraryCoverSize == Settings.coverSizes.upperBound)
        #expect(old.recentSources.isEmpty && old.lastPage == nil && !old.libraryGroupByConsole)
    }

    @Test func storageListsTheStartupDiskFirst() {
        let v = Storage.volumes()
        #expect(v.first?.kind == .startup)
        #expect(v.filter { $0.kind == .startup }.count == 1)
        #expect(v.allSatisfy { $0.total > 0 })
    }
}

@Suite struct Confirmations {
    @Test(arguments: [("Delete", true), ("Move to Trash", true), ("Stop and Quit", true), ("Stop Build", true),
                      ("Restore", false), ("Build Anyway", false), ("OK", false), ("Move and Convert", false)])
    func destructiveAnswers(_ action: String, _ expected: Bool) {
        #expect(AppModel.isDestructive(action) == expected)
    }
}

/// Converter 0.8.0: a Preview build's rows, what a rebuild would redo, and the from-scratch rebuild.
@Suite struct RebuildChoices {
    @Test func planRowsFromTheEvent() throws {
        let line = #"{"ev": "plan", "rows": [{"stage": "rewrite", "state": "reused", "why": "", "secs": null}, {"stage": "Mac shaders", "state": "redo", "why": "the translation chain changed", "secs": 900}, {"stage": "Pipeline archive", "state": "follows", "why": "", "secs": 1567}, {"stage": "Mac app", "state": "redo", "why": "it packs the new Mac shaders", "secs": 191}, {"stage": "later", "state": "unheard of"}], "est": 1091, "worst": 2658}"#
        let v = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let rows = PlanRow.rows(v)
        #expect(rows.map(\.stage) == ["rewrite", "Mac shaders", "Pipeline archive", "Mac app"])   // a state it does not know is left out
        #expect(rows.map(\.state) == [.reused, .redo, .follows, .redo])
        #expect(rows[0].seconds == nil && rows[1].seconds == 900)
        #expect(PlanRow.total(rows) == "2 steps redone, about 18 min, up to 44 min if every later step is redone too")
        #expect(PlanRow.total([rows[0]]) == "Nothing to redo: the app is up to date")
        #expect(PlanRow.total([PlanRow(stage: "Mac host", state: .redo, why: "", seconds: nil)]) == "1 step redone; no earlier build timed it")
        #expect(PlanRow.rows(["ev": "plan"]).isEmpty)
    }

    @Test func chainFromTheHeader() {
        #expect(RebuildCost.chain(header: "// generated\n#define DMSH_CHAIN \"ad5985867476\"\n") == "ad5985867476")
        #expect(RebuildCost.chain(header: "#define X \"not a chain\"\n") == nil)
    }

    @Test func whatARebuildRedoes() {
        let id = "0400486024DEC000"
        // no build folder: everything again
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: nil, changed: ["dm/host/main.m"], titleID: id) == .full)
        // the folder's shaders are another chain's: every shader again, whatever else changed
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["aaaaaaaaaaaa"], changed: ["dm/host/main.m"], titleID: id) == .shaders)
        // the same chain and only the player's files: the player and the app
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["aaaaaaaaaaaa", "bbbbbbbbbbbb"], changed: ["dm/host/main.m", "dm/gfx/nvn/nvn_metal.m", "docs/development.md"], titleID: id) == .quick)
        // the build's tools or this game's own profile: some steps again; another game's profile is not read
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["bbbbbbbbbbbb"], changed: ["scripts/build_ipa_from_nsp.py"], titleID: id) == .partial)
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["bbbbbbbbbbbb"], changed: ["dm/games/\(id)/game.tsv"], titleID: id) == .partial)
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["bbbbbbbbbbbb"], changed: ["dm/games/0100000000010000/game.tsv", "dm/host/main.m"], titleID: id) == .quick)
        // a game with no chain libraries (Vulkan, OpenGL) goes by the files; git that cannot tell is not called quick
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: [], changed: ["dm/mac/pack_app.py"], titleID: id) == .quick)
        #expect(RebuildCost.kind(chain: "bbbbbbbbbbbb", built: ["bbbbbbbbbbbb"], changed: nil, titleID: id) == .partial)
    }

    @Test func rebuildTimesFromTheLastRuns() {
        let times: [String: Double] = ["unpack": 600, "Mac shaders": 2940, "Mac host": 15, "Pipeline archive": 2160, "Mac app": 13]
        #expect(RebuildCost.seconds(.quick, times: times) == 28)
        #expect(RebuildCost.seconds(.shaders, times: times) == 5128)
        #expect(RebuildCost.seconds(.full, times: times) == 5728)
        #expect(RebuildCost.seconds(.partial, times: times) == nil)
        #expect(RebuildCost.seconds(.shaders, times: ["Mac app": 13]) == nil)   // the shader step was never timed: no guess
        #expect(RebuildCost(kind: .quick, seconds: 28).title == "Quick rebuild, about 28 s")
        #expect(RebuildCost(kind: .shaders, seconds: nil).title == "Shader rebuild")
    }

    @Test func removeBuildCacheLeavesOnlyTheGameAndTheApp() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "nxc-cleanall-\(UUID().uuidString)", game = root + "/Blazing Chrome [NSP]", home = root + "/home"
        defer { try? fm.removeItem(atPath: root) }
        let build = game + "/0100C2700C252000_build", survey = game + "/0100C2700C252000_survey", app = game + "/Blazing Chrome.app"
        for d in ["\(build)/logs", "\(build)/profile/0100C2700C252000", "\(survey)/extract", app + "/Contents", home] { try fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
        for f in ["\(build)/logs/converter-2026-11-15-1209.log", "\(build)/logs/stage_times.json", "\(build)/profile/0100C2700C252000/game.tsv",
                  "\(survey)/survey.md", app + ".key", game + "/Blazing Chrome [0100C2700C252000][v0].nsp", game + "/notes_build"] {
            try "x\n".write(toFile: f, atomically: true, encoding: .utf8)
        }
        let r = BuildRun.removeBuildFolders(game, app: app, log: "\(build)/logs/converter-2026-11-15-1209.log", home: home)
        let logs = home + "/Library/Logs/NXForge/0100C2700C252000"
        #expect(r.log == logs + "/converter-2026-11-15-1209.log" && r.logDir == logs)
        #expect(r.removed == ["0100C2700C252000_build", "0100C2700C252000_survey", "Blazing Chrome.app.key"])
        #expect(try fm.contentsOfDirectory(atPath: game).sorted() == ["Blazing Chrome [0100C2700C252000][v0].nsp", "Blazing Chrome.app", "notes_build"])
        #expect(try fm.contentsOfDirectory(atPath: logs).sorted() == ["converter-2026-11-15-1209.log", "stage_times.json"])
        #expect(BuildRun.removeBuildFolders(game, app: app, log: nil, home: home).removed.isEmpty)   // nothing left to remove
    }

    @Test func builtChainsAndTheScratchRebuild() throws {
        let fm = FileManager.default
        let game = NSTemporaryDirectory() + "nxc-scratch-\(UUID().uuidString)", build = game + "/0400486024DEC000_build"
        defer { try? fm.removeItem(atPath: game) }
        for d in ["shader.noindex/cache", "extract/v0", "logs", "profile", "run/save"] { try fm.createDirectory(atPath: "\(build)/\(d)", withIntermediateDirectories: true) }
        for f in ["shader.noindex/mac-b-aaaaaaaaaaaa.key", "shader.noindex/mac-b-bbbbbbbbbbbb.key", "shader.noindex/pso.key", "rewrite.key", "logs/stage_times.json", "run/save/file"] {
            try "k\n".write(toFile: "\(build)/\(f)", atomically: true, encoding: .utf8)
        }
        #expect(RebuildCost.builtChains(buildFolder: build).sorted() == ["aaaaaaaaaaaa", "bbbbbbbbbbbb"])
        #expect(BuildRun.emptyBuildFolder(game) == 3)   // shader.noindex, extract, rewrite.key
        #expect(try fm.contentsOfDirectory(atPath: build).sorted() == ["logs", "profile", "run"])
        #expect(fm.fileExists(atPath: "\(build)/logs/stage_times.json") && fm.fileExists(atPath: "\(build)/run/save/file"))
        #expect(RebuildCost.builtChains(buildFolder: build).isEmpty)
        #expect(BuildRun.emptyBuildFolder(game) == 0)
    }

    @Test func enginefilesAChangedPatchTouches() {
        let diff = """
        diff --git a/layer/patches/0006-packing.patch b/layer/patches/0006-packing.patch
        index 1111111..2222222 100644
        --- a/layer/patches/0006-packing.patch
        +++ b/layer/patches/0006-packing.patch
         Subject: packing
         ---
        - scripts/build_ipa_from_nsp.py | 10 +-
        + scripts/build_ipa_from_nsp.py | 12 +-
         diff --git a/dm/mac/pack_app.py b/dm/mac/pack_app.py
         index aaaaaaa..bbbbbbb 100644
         --- a/dm/mac/pack_app.py
         +++ b/dm/mac/pack_app.py
         @@ -1,2 +1,3 @@
          unchanged
         diff --git a/scripts/build_ipa_from_nsp.py b/scripts/build_ipa_from_nsp.py
        -index ccccccc..ddddddd 100755
        +index ccccccc..eeeeeee 100755
         --- a/scripts/build_ipa_from_nsp.py
         +++ b/scripts/build_ipa_from_nsp.py
         @@ -5,3 +5,4 @@
          context
        ++    a new line
        diff --git a/layer/patches/0024-later.patch b/layer/patches/0024-later.patch
        --- a/layer/patches/0024-later.patch
        +++ b/layer/patches/0024-later.patch
         diff --git a/scripts/build_ipa_from_nsp.py b/scripts/build_ipa_from_nsp.py
        -index ddddddd..fffffff 100755
        +index eeeeeee..9999999 100755
        -@@ -3382,7 +3382,9 @@ def report
        +@@ -3414,7 +3414,9 @@ def report
         diff --git a/dm/games/x.tsv b/dm/games/x.tsv
          context only
        """
        // the later patch's index and hunk position moved with the earlier one's change: nothing of its own changed
        #expect(Layer.patchedFiles(diff: diff) == ["scripts/build_ipa_from_nsp.py"])
    }
}

// The library front end (Converter 0.9.0): a game's option list, presets, cover matching and the new settings
@Suite struct FrontEnd {
    static let list: [LaunchSetting] = {
        let json = #"""
        [{"env":"DM_FPS_TARGET","kind":"choice","label":"Frame rate","note":"","default":"60","level":"basic","options":[["30","30 fps"],["60","60 fps"]]},
         {"env":"DM_RENDER_SCALE","kind":"range","label":"Render scale","note":"","default":"1.0","level":"basic","min":0.5,"max":1.0,"step":0.05},
         {"env":"DM_PRESENT_UPSCALE","kind":"choice","label":"Upscaling","default":"off","options":[["off","Standard"],["metalfx","MetalFX"]]},
         {"env":"DM_PRESENT_EDR","kind":"toggle","label":"HDR highlights","note":"","default":"0"},
         {"env":"DM_LANG","kind":"choice","label":"Game language","note":"","default":"en-US","level":"basic","options":[["en-US","English"],["ja","Japanese"]]},
         {"env":"DM_METAL_HUD","kind":"toggle","label":"Performance HUD","note":"","default":"0"}]
        """#
        return try! JSONDecoder().decode([LaunchSetting].self, from: Data(json.utf8))
    }()
    static var defaults: [String: String] { Dictionary(uniqueKeysWithValues: list.map { ($0.env, $0.def) }) }

    @Test func theListsDefaultKeyIsRead() {
        #expect(Self.list.count == 6)
        #expect(Self.list[0].def == "60" && Self.list[2].note == "")
    }

    @Test func presets() {
        var v = Self.defaults
        #expect(PlayOptions.current(settings: Self.list, values: v) == .balanced)
        PlayOptions.apply(.battery, settings: Self.list, to: &v)
        #expect(v["DM_FPS_TARGET"] == "30" && v["DM_RENDER_SCALE"] == "0.75" && v["DM_PRESENT_EDR"] == "0")
        #expect(v["DM_LANG"] == "en-US")   // a preset leaves the rest alone
        #expect(PlayOptions.current(settings: Self.list, values: v) == .battery)
        PlayOptions.apply(.quality, settings: Self.list, to: &v)
        #expect(v["DM_FPS_TARGET"] == "60" && v["DM_PRESENT_UPSCALE"] == "metalfx" && v["DM_PRESENT_EDR"] == "1")
        #expect(PlayOptions.current(settings: Self.list, values: v) == .quality)
        v["DM_RENDER_SCALE"] = "0.60"
        #expect(PlayOptions.current(settings: Self.list, values: v) == .custom)
    }

    @Test func aRunsOwnChoices() {
        var v = Self.defaults
        v["DM_FPS_TARGET"] = "30"
        v["DM_RENDER_SCALE"] = "1.00"   // the same number, written as a slider writes it
        #expect(PlayOptions.difference(Self.list, from: Self.defaults, to: v) == ["DM_FPS_TARGET": "30"])
    }

    @Test func tabsAndSummary() {
        #expect(PlayOptions.rows(.graphics, settings: Self.list, values: Self.defaults).map(\.env) == ["DM_FPS_TARGET", "DM_RENDER_SCALE", "DM_PRESENT_UPSCALE", "DM_PRESENT_EDR"])
        #expect(PlayOptions.rows(.general, settings: Self.list, values: Self.defaults).map(\.env) == ["DM_LANG"])
        #expect(PlayOptions.rows(.advanced, settings: Self.list, values: Self.defaults).map(\.env) == ["DM_METAL_HUD"])
        let s = PlayOptions.summary(settings: Self.list, values: Self.defaults)
        #expect(s.map(\.value) == ["60 fps", "100 %", "SDR"])
    }

    @Test func coverNames() {
        #expect(CoverSource.normalize("The Legend of Zelda™: Skyward Sword HD") == "thelegendofzeldaskywardswordhd")
        #expect(CoverSource.normalize("Pikmin 1+2") == CoverSource.normalize("Pikmin 1 + 2"))
        #expect(CoverSource.plain("Super Mario Odyssey [Starter Pack]") == "Super Mario Odyssey")
        let list = CoverSource.parse("TITLES = https://www.gametdb.com (type: Switch)\nAAAC3 = Super Mario Odyssey [Starter Pack]\nAAACA = Super Mario Odyssey\nAABPA = Mario Kart 8 Deluxe\n")
        #expect(list.count == 3)
        #expect(CoverSource.match("SUPER MARIO ODYSSEY™", in: list) == ["AAACA", "AAAC3"])
        #expect(CoverSource.match("Mario Kart World", in: list).isEmpty)
        #expect(CoverSource.urls(id: "AAACA", kind: "cover").first?.absoluteString == "https://art.gametdb.com/switch/cover/US/AAACA.jpg")
    }

    @Test func discoverGenres() {
        let json = """
        {"response":{"numFound":3,"docs":[
          {"fs_id":"2179556","application_id_s":"0100a3d008c5c000","title":"Pokémon Scarlet","pretty_game_categories_txt":["Adventure","RPG"],
           "players_to":4,"playable_on_txt":["HAC"]},
          {"fs_id":"1","application_id_s":"0400c3f00006e000","title":" Mario Kart World","playable_on_txt":["BEE"],"system_names_txt":["Nintendo Switch 2"],
           "pretty_game_categories_txt":["Racing"]},
          {"fs_id":"2","application_id_s":"0100a3d008c5c000","title":"Pokémon Scarlet - Nintendo Switch 2 Edition","pretty_game_categories_txt":["Education"]}
        ]}}
        """
        let page = DiscoverSource.parse(Data(json.utf8))
        #expect(page.total == 3 && page.items.count == 3)
        let p = page.items[0], m = page.items[1]
        #expect(p.titleID == "0100A3D008C5C000" && p.console == "Switch" && p.players == "1–4 players")
        #expect(m.console == "Switch 2" && m.title == "Mario Kart World")
        // the shortest title's genres win (a Switch 2 Edition shares the ID); no store page or no genre = Other
        let map = DiscoverSource.genreMap(page.items)
        #expect(DiscoverSource.genres(of: "0100a3d008c5c000", in: map) == ["Adventure", "RPG"])
        #expect(DiscoverSource.genres(of: "0100000000010000", in: map) == [DiscoverSource.other])
        #expect(DiscoverSource.genres(of: nil, in: map) == [DiscoverSource.other])
        #expect(DiscoverSource.order(["Other", "RPG", "Education", "Action"]) == ["Action", "RPG", "Education", "Other"])
        #expect(DiscoverSource.byIDs(["0100A3D008C5C000", "bad"])!.absoluteString.contains("0100a3d008c5c000"))
        #expect(DiscoverState.plural("Platformer") == "Platformers")
    }

    @Test func squareArtLookup() {
        let json = """
        {"response":{"docs":[
          {"application_id_s":"0100dcd01f306000","title":"Mina the Hollower - Nintendo Switch™ 2 Edition","type":"GAME","image_url_sq_s":"https://x/b.jpg"},
          {"application_id_s":"0100dcd01f306000","title":"Mina the Hollower","type":"GAME","image_url_sq_s":"https://x/a.jpg"},
          {"application_id_s":"0100dcd01f306000","title":"Mina","type":"DLC","image_url_sq_s":"https://x/d.jpg"},
          {"title":"Cyber Shadow","type":"GAME","image_url_sq_s":"//x/c.jpg"}
        ]}}
        """
        let docs = SquareSource.parse(Data(json.utf8))
        #expect(docs.count == 4)
        #expect(SquareSource.pick(docs, id: "0100DCD01F306000") == "https://x/a.jpg")
        #expect(SquareSource.pick(docs, name: "Cyber Shadow") == "https://x/c.jpg")
        #expect(SquareSource.pick(docs, name: "Cyber") == nil)
    }

    @Test func heroArtLookup() {
        let json = """
        {"response":{"docs":[
          {"application_id_s":"01000b900d8b0000","title":"Pack 3","type":"DLC"},
          {"application_id_s":"0100dcd01f306000","title":"Mina the Hollower - Nintendo Switch™ 2 Edition","type":"GAME","image_url_h2x1_s":"https://x/b_image500w.jpg"},
          {"application_id_s":"0100dcd01f306000","title":"Mina the Hollower","type":"GAME","image_url_h2x1_s":"https://x/a_image500w.jpg"},
          {"application_id_s":"01008d100de46000","title":"Cyber Shadow","type":"GAME","image_url_h2x1_s":"https://x/c_image500w.jpg"},
          {"title":"Cyber Shadow","type":"GAME","image_url_h2x1_s":"https://x/old.jpg"},
          {"application_id_s":"0400486024dec000","title":"Ocarina","type":"GAME","url":"/en-gb/Games/oot-1.html"}
        ]}}
        """
        let docs = HeroSource.parse(Data(json.utf8))
        #expect(docs.count == 5)
        #expect(HeroSource.pick(docs, id: "0400486024DEC000")?.page?.absoluteString == "https://www.nintendo.com/en-gb/Games/oot-1.html")
        #expect(HeroSource.shared(#"<meta property="og:image" content=" https://www.nintendo.com/eu/a/16x9_x_image1280w.jpg">"#) == "https://www.nintendo.com/eu/a/16x9_x_image1280w.jpg")
        #expect(HeroSource.shared(#"<meta property="og:image" content="https://evil.example/x.jpg">"#) == nil)
        #expect(HeroSource.pick(docs, id: "0100DCD01F306000")?.title == "Mina the Hollower")
        #expect(HeroSource.pick(docs, id: "01000B900D8B0000") == nil)
        #expect(HeroSource.pick(docs, name: "Cyber Shadow [NSP]")?.id == "01008D100DE46000")
        #expect(HeroSource.pick(docs, name: "Cyber") == nil)
        #expect(HeroSource.sizes("https://x/c_image500w.jpg").map(\.absoluteString) == ["https://x/c_image1600w.jpg", "https://x/c_image500w.jpg"])
        let q = HeroSource.byIDs(["0100C2700C252000", "bad"])?.absoluteString ?? ""
        #expect(q.contains("application_id_s%3A(0100c2700c252000)") || q.contains("application_id_s:(0100c2700c252000)"))
        #expect(HeroSource.byName("Cruis'n Blast™")?.absoluteString.contains("q=Cruis%20n%20Blast") == true)
    }

    @Test func nintendoLifePages() {
        #expect(NLifeSource.slugs("Mario & Luigi - Brothership").first == "mario_and_luigi_brothership")
        #expect(NLifeSource.slugs("Kirby's Return to Dream Land Deluxe").first == "kirbys_return_to_dream_land_deluxe")
        #expect(NLifeSource.slugs("Super Mario 3D World + Bowser's Fury").first == "super_mario_3d_world_plus_bowsers_fury")
        #expect(NLifeSource.slugs("New Super Mario Bros. U Deluxe [NSP]").first == "new_super_mario_bros_u_deluxe")
        #expect(NLifeSource.slugs("Shadow of the Ninja - Reborn").contains("shadow_of_the_ninja_-_reborn"))
        #expect(NLifeSource.slugs("Pac-Man Championship Edition 2 Plus").contains("pac-man_championship_edition_2_plus"))
        #expect(NLifeSource.slugs("Pac-Man Museum+").contains("pac-man_museumplus"))
        #expect(NLifeSource.slugs("The Legend of Zelda - Echoes of Wisdom").contains("legend_of_zelda_echoes_of_wisdom"))
        #expect(NLifeSource.slugs("Alpaca Ball Allstars Legacy Edition").contains("alpaca_ball_allstars"))
        #expect(NLifeSource.slugs("Pokémon™ Legends").first == "pokemon_legends")
        let p = NLifeSource.pages(name: "Mario Kart World", titleID: "0400C3F00006E000").map(\.absoluteString)
        #expect(p.first == "https://www.nintendolife.com/games/nintendo-switch-2/mario_kart_world")
        #expect(p.count == 3)
        #expect(NLifeSource.pages(name: "Pac-Man Museum+", titleID: nil).count <= NLifeSource.maxTries)
        let html = """
        <section class="hero hero-game"><div class="background accent-bg background-desktop" data-bg-image="https://images.nintendolife.com/e93460d4eb1df/cuphead-artwork.1920x350.jpg"></div>
        <div class="accent-bg"><p id="cover" class="image scanlines accent-bg"><img src="https://images.nintendolife.com/03b8fc1926726/cuphead-cover.cover_300x.jpg" width="300" height="300" alt="Cuphead Cover" /></p>
        """
        let page = NLifeSource.parse(html)
        #expect(page.hero?.absoluteString == "https://images.nintendolife.com/e93460d4eb1df/cuphead-artwork.original.jpg")
        #expect(page.cover?.absoluteString == "https://images.nintendolife.com/03b8fc1926726/cuphead-cover.original.jpg")
        #expect(NLifeSource.parse(#"<div class="background-desktop" data-bg-image="https://evil.example/a.1920x350.jpg"></div>"#).hero == nil)
        #expect(NLifeSource.parse("<p>nothing</p>") == NLifeSource.Page())
        let facts = """
        {"@type":"VideoGame","name":"Blazing Chrome","datePublished":"2019-07-11","x":1}
        <dl><dt>Publisher</dt><dd><a href="/companies/the_arcade_crew">The Arcade Crew</a></dd><dt>Developer</dt>
        <dd><a href="/companies/joymasher">JoyMasher</a>, <a href="/companies/x">Two &amp; Co</a></dd></dl>
        """
        #expect(NLifeSource.parse(facts).developer == "JoyMasher & Two & Co")
        #expect(NLifeSource.parse(facts).year == "2019")
        #expect(NLifeSource.developer("<dt>Developer</dt><dd>Nintendo EPD</dd>") == "Nintendo EPD")
    }

    @Test func standardWideArt() throws {
        func picture(_ w: Int, _ h: Int, red: Bool = false) -> Data {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(red ? CGColor(red: 0.9, green: 0, blue: 0.07, alpha: 1) : CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            return CoverSource.jpeg(Data(NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!), maxHeight: 4000)!
        }
        for (w, h) in [(2000, 600), (3840, 1154), (1600, 800), (993, 298), (1280, 1280)] {
            let out = try #require(HeroSource.standard(picture(w, h)))
            #expect(CoverSource.size(out).map { [$0.0, $0.1] } == [2560, 1280])
        }
        #expect(CoverSource.eshopStandIn(picture(864, 1400, red: true)))
        #expect(!CoverSource.eshopStandIn(picture(864, 1400)))
        #expect(NLifeSource.square(picture(500, 500)) && !NLifeSource.square(picture(1500, 2439)))
    }

    /// NXC_NL_RUN=1: the Nintendo Life pass for every game in this Mac's library, as the app runs it (real network, real artwork folder)
    @MainActor @Test func nintendoLifeRun() async throws {
        guard ProcessInfo.processInfo.environment["NXC_NL_RUN"] == "1" else { return }
        let lib = Settings.supportDir.appending(path: "library.json")
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: lib)) as? [String: Any]
        let games = (o?["games"] as? [[String: Any]] ?? []).compactMap { g -> (key: String, titleID: String?, name: String, console: String)? in
            guard let name = g["name"] as? String else { return nil }
            let tid = g["titleID"] as? String
            return (CoverStore.key(titleID: tid, name: name), tid, name, tid?.hasPrefix("04") == true ? "Switch 2" : "Switch")
        }
        CoverStore.shared.fetchNintendoLife(games, heroes: true, boxes: true)
        await CoverStore.shared.nintendoLifeTask?.value
    }

    /// NXC_ART_PREVIEW=<folder>: draws the eShop box of every <name>.square.jpg there and standardises every <name>.hero.jpg, beside them
    @MainActor @Test func artPreview() throws {
        guard let dir = ProcessInfo.processInfo.environment["NXC_ART_PREVIEW"] else { return }
        for f in try FileManager.default.contentsOfDirectory(atPath: dir) {
            let u = URL(fileURLWithPath: dir).appending(path: f), d = try Data(contentsOf: u)
            if f.hasSuffix(".square.jpg"), let box = CoverArt.eshopBox(name: String(f.dropLast(11)), console: "Switch", square: d, detail: "JoyMasher · 2019") {
                try box.write(to: URL(fileURLWithPath: dir).appending(path: f.replacingOccurrences(of: ".square.jpg", with: ".box.out.jpg")))
            }
            if f.hasSuffix(".hero.jpg"), let h = HeroSource.standard(d) {
                try h.write(to: URL(fileURLWithPath: dir).appending(path: f.replacingOccurrences(of: ".hero.jpg", with: ".hero.out.jpg")))
            }
        }
    }

    @Test func storeDetails() {
        let json = """
        {"response":{"docs":[
          {"application_id_s":"0100c2700c252000","title":"Blazing Chrome","type":"GAME","url":"/en-gb/Games/x/Blazing-Chrome-1589237.html","publisher":"The Arcade Crew",
           "pretty_date_s":"11/07/2019","pretty_game_categories_txt":["Action","Arcade"],"players_from":1,"players_to":2,"pretty_agerating_s":"PEGI 12",
           "datasize_readable_txt":["139.0 MB"],"language_availability":["japanese, english, spanish"],"excerpt":"Bring your best pal","play_mode_tv_mode_b":true,
           "play_mode_tabletop_mode_b":false,"play_mode_handheld_mode_b":true},
          {"application_id_s":"0100c2700c252000","title":"Blazing Chrome Deluxe Edition","type":"GAME"}
        ]}}
        """
        let i = StoreSource.parse(Data(json.utf8), id: "0100C2700C252000")
        #expect(i?.title == "Blazing Chrome")
        #expect(i?.players == "1–2 players")
        #expect(i?.languages == "Japanese, English, Spanish")
        #expect(i?.modes == ["TV", "Handheld"])
        #expect(i?.size == "139.0 MB")
        #expect(i?.page == "https://www.nintendo.com/en-gb/Games/x/Blazing-Chrome-1589237.html")
        #expect(StoreSource.parse(Data(json.utf8), name: "Blazing Chrome [NSP]")?.publisher == "The Arcade Crew")
        #expect(StoreSource.parse(Data(json.utf8), id: "0100000000010000") == nil)
        let html = """
        <div class="row row-content"> <div class="col-xs-12 content"> <p>In Blazing Chrome, machines rule&nbsp;the world.</p>\n<p><strong>Co-op</strong> play &amp; more, with a friend on the couch</p><p>Short caption</p><p>This description was provided by the publisher.</p></div></div>
        <div class="col-xs-12 content"><p>A second block of the designed page, long enough to keep.</p></div>
        <div class="col-xs-12 mediagallery" data-tr-lp="15"><ul><li><img alt="a" src="grey.gif" data-xs="https://www.nintendo.com/eu/media/images/06_screenshots/x/BC_01_TM_Standard.jpg" />
        <img data-xs="https://www.nintendo.com/eu/media/images/06_screenshots/x/BC_02_TM_Standard.jpg"/><img data-xs="https://evil.example/x.jpg"/></ul>
        <img data-xs="https://www.nintendo.com/eu/media/images/other.jpg"/>
        """
        #expect(StoreSource.plainText("<ul><li>Co-op</li><li>Arcade &amp; feel</li></ul>") == "• Co-op\n• Arcade & feel")
        #expect(StoreSource.about(html) == ["In Blazing Chrome, machines rule the world.", "Co-op play & more, with a friend on the couch",
                                            "A second block of the designed page, long enough to keep."])
        #expect(StoreSource.gallery(html) == ["https://www.nintendo.com/eu/media/images/06_screenshots/x/BC_01.jpg", "https://www.nintendo.com/eu/media/images/06_screenshots/x/BC_02.jpg"])
    }

    @Test func storePageTrailers() {
        let html = """
        'isVideo': true,
        'video_id': 'wgrj1meikypq63u30rji',
        'video_thumbnail_url': 'https://assets.nintendo.eu/video/private/f_auto,q_auto/wgrj1meikypq63u30rji.jpg',
        'video_content_url': 'https://production.smedia.lvp.llnw.net/81d5/By/x9/gc-trailer-all.mp4?x=0&amp;h=fa5a',
        'isVideo': false, 'video_id': '', 'video_thumbnail_url': '', 'video_content_url': '',
        <iframe src="https://www.youtube-nocookie.com/embed/VcXvnb7dHZk?rel=0&amp;modestbranding=1"></iframe>
        window.videos.push({sectionID: "1587725", id:"VcXvnb7dHZk", isPlaylist: false});
        window.videos.push({sectionID: "1587726", id:"PLxxxxxxxxx", isPlaylist: true});
        window.videos.push({sectionID: "1587727", id:"Ns1xBFGRm0c", isPlaylist: false});
        """
        let v = StoreSource.videos(html)
        #expect(v.count == 3)
        #expect(v[0].file == "https://production.smedia.lvp.llnw.net/81d5/By/x9/gc-trailer-all.mp4?x=0&h=fa5a")
        #expect(v[0].thumb == "https://assets.nintendo.eu/video/private/f_auto,q_auto/wgrj1meikypq63u30rji.jpg")
        #expect(v[1].youtube == "VcXvnb7dHZk" && v[2].youtube == "Ns1xBFGRm0c")
        #expect(v[1].thumb == "https://i.ytimg.com/vi/VcXvnb7dHZk/maxresdefault.jpg")
        #expect(StoreSource.videos("<p>no video</p>").isEmpty)
        #expect(StoreSource.oembedTitle(Data(#"{"title":"Super Mario Odyssey - Trailer"}"#.utf8)) == "Super Mario Odyssey - Trailer")
        // details kept before trailers were looked for read back with none, so the page is read again
        let old = try? JSONDecoder().decode(StoreInfo.self, from: Data(#"{"title":"X","genres":[],"about":[],"modes":[],"shots":[],"fetched":0}"#.utf8))
        #expect(old != nil && old?.trailers == nil)
        // YouTube's search: the official channel's Switch trailer, not a fan's upload or the Wii U one
        func r(_ id: String, _ title: String, _ owner: String) -> String {
            #""videoRenderer":{"videoId":"\#(id)","thumbnail":{},"title":{"runs":[{"text":"\#(title)"}]},"ownerText":{"runs":[{"text":"\#(owner)"}]}"#
        }
        let yt = "x" + r("AAAAAAAAAAA", "Gunman Clive HD Collection - Nintendo eShop Trailer (Wii U)", "Nintendo UK")
            + r("BBBBBBBBBBB", "Gunman Clive HD Collection Trailer || Nintendo Switch", "Active Hive Gaming")
            + r("CCCCCCCCCCC", "Gunman Clive HD Collection Switch Trailer", "Bertil Hörberg")
        let pick = StoreSource.pickTrailer(yt, name: "Gunman Clive HD Collection", publisher: "Bertil Hörberg")
        #expect(pick?.youtube == "CCCCCCCCCCC" && pick?.title == "Gunman Clive HD Collection Switch Trailer")
        #expect(StoreSource.pickTrailer(yt, name: "Gunman Clive HD Collection", publisher: nil)?.youtube == "AAAAAAAAAAA")
        #expect(StoreSource.pickTrailer(yt, name: "Golf Story", publisher: nil) == nil)
        let fan = "x" + r("DDDDDDDDDDD", "Gunman Clive HD Collection Switch Trailer", "Nintendo Life") + r("EEEEEEEEEEE", "Gunman Clive HD Collection Gameplay", "Nintendo UK")
        #expect(StoreSource.pickTrailer(fan, name: "Gunman Clive HD Collection", publisher: nil) == nil)
        #expect(StoreSource.officialNintendo("nintendobelgie") && !StoreSource.officialNintendo("nintendolife"))
    }

    @Test func caseMeasurementsMatchARealSwitchCase() {
        // 105 × 170 × 10.5 mm, the insert inside the plastic on every side
        #expect(abs(CaseSize.width / CaseSize.height - 105.0 / 170.0) < 1e-6)
        #expect(abs(CaseSize.depth / CaseSize.height - 10.5 / 170.0) < 1e-6)
        #expect(CaseSize.insertWidth / 2 + abs(CaseSize.insertShift) < CaseSize.width / 2)
        #expect(CaseSize.insertHeight < CaseSize.height && CaseSize.insertDepth < CaseSize.depth)
    }

    @Test func aWrapSplitsIntoBackSpineAndFront() {
        let b = CoverSource.wrap(.back), s = CoverSource.wrap(.spine), f = CoverSource.wrap(.front)
        #expect(b.minX == 0 && abs(f.maxX - 1) < 1e-9)
        #expect(abs(b.maxX - s.minX) < 1e-9 && abs(s.maxX - f.minX) < 1e-9)
        #expect(abs(b.width - f.width) < 1e-9 && s.width < 0.06)
    }

    /// A picture `w`×`h`: see-through margin `m`, then a light grey rim `r` on the right, top and bottom, then red art
    static func caseRender(w: Int, h: Int, m: Int, r: Int, clearCorners: Bool = true) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !clearCorners { ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
        ctx.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: m, y: m, width: w - 2 * m, height: h - 2 * m))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: m, y: m + r, width: w - 2 * m - r, height: h - 2 * m - 2 * r))
        return ctx.makeImage()!
    }

    @Test func aCaseRenderIsCutDownToItsCover() {
        let out = CoverSource.trimCase(Self.caseRender(w: 400, h: 640, m: 6, r: 14))
        #expect(out.width == 400 - 12 - 14 && out.height == 640 - 12 - 28)
        // a cover with no see-through corners is left as it was
        let plain = Self.caseRender(w: 400, h: 640, m: 6, r: 14, clearCorners: false)
        #expect(CoverSource.trimCase(plain).width == 400 && CoverSource.trimCase(plain).height == 640)
    }

    @Test func frontEndSettingsDefault() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"start_in": "Converter", "battery_preset": false}"#.utf8))
        #expect(s.startIn == .converter && !s.batteryPreset && s.straightPlay && s.returnToLibrary && s.downloadCovers)
    }
}

@Suite struct FrontEndExtras {
    @Test func crashIsTheLogsLastWord() {
        #expect(GameAttention.crashSignal("launcher: save x\nlauncher: the host stopped on signal 11\n") == 11)
        #expect(GameAttention.crashSignal("launcher: the host stopped on signal 6\nlauncher: Restart game\nlauncher: the host exited with 0\n") == nil)
        #expect(GameAttention.crashSignal("launcher: the host exited with 0\n") == nil)
    }

    @Test func screenshotsNewestFirstAndNamedForTheGame() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "nxf-shots-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let app = root.appending(path: "Game.app").path
        try fm.createDirectory(atPath: app + "/Contents", withIntermediateDirectories: true)
        let shots = root.appending(path: "Screenshots")
        try fm.createDirectory(at: shots, withIntermediateDirectories: true)
        for (i, n) in ["old.png", "new.png", "notes.txt"].enumerated() {
            let f = shots.appending(path: n)
            try Data([0]).write(to: f)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 + i * 100))], ofItemAtPath: f.path)
        }
        let found = GameCaptures.screenshots(app: app).map(\.lastPathComponent)
        #expect(found.first == "new.png")
        #expect(found.contains("old.png"))
        #expect(!found.contains("notes.txt"))
    }

    @Test func favouritesKeyIsTheTitleID() {
        let g = StageGame(id: "x", ref: GameRef(libraryID: "x", app: "/A.app"), name: "A", console: .switch1, titleID: "0100", icon: nil, app: "/A.app", version: nil, last: nil)
        #expect(g.favoriteKey == "0100")
        let h = StageGame(id: "y", ref: GameRef(libraryID: nil, app: "/B.app"), name: "B", console: .switch1, titleID: nil, icon: nil, app: "/B.app", version: nil, last: nil)
        #expect(h.favoriteKey == "/B.app")
    }
}

/// The keys file saved in Settings: its status, and which keys a game folder builds with.
@Suite struct SavedKeys {
    func temp() -> String {
        let d = NSTemporaryDirectory() + "keys-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @Test func status() {
        let d = temp()
        #expect(KeysFile.status(nil) == .notSet)
        #expect(KeysFile.status(d + "/none.keys") == .missing)
        try? "not keys".write(toFile: d + "/bad.keys", atomically: true, encoding: .utf8)
        #expect(KeysFile.status(d + "/bad.keys") == .unreadable)
        try? "master_key_00 = 00112233445566778899aabbccddeeff\n".write(toFile: d + "/part.keys", atomically: true, encoding: .utf8)
        #expect(KeysFile.status(d + "/part.keys") == .incomplete)
        try? "header_key = 00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\nmaster_key_00 = 00112233445566778899aabbccddeeff\n"
            .write(toFile: d + "/prod.keys", atomically: true, encoding: .utf8)
        #expect(KeysFile.status(d + "/prod.keys") == .ok(2))
    }

    @Test func savedWinsThenBesideTheGame() {
        let d = temp(), game = d + "/Game"
        try? FileManager.default.createDirectory(atPath: game, withIntermediateDirectories: true)
        try? "x".write(toFile: d + "/prod.keys", atomically: true, encoding: .utf8)
        try? "x".write(toFile: game + "/prod.keys", atomically: true, encoding: .utf8)
        #expect(KeysFile.resolve(saved: d + "/prod.keys", gameFolder: game) == d + "/prod.keys")
        #expect(KeysFile.resolve(saved: d + "/gone.keys", gameFolder: game) == game + "/prod.keys")
        #expect(KeysFile.resolve(saved: nil, gameFolder: d + "/Other") == nil)
        #expect(KeysFile.candidates(gamesRoot: "/Volumes/Games/Switch 1").prefix(2) == ["/Volumes/Games/Switch 1/prod.keys", "/Volumes/Games/prod.keys"])
    }
}

@Suite struct Cheats {
    @Test func parsesAndWritesBack() {
        let t = "[Infinite Health]\n04000000 0149D940 00000003\n\n{Master}\n580F0000 0149D940\n[Moon Jump]\n80000002\n20000000\n"
        let e = CheatFile.parse(t)
        #expect(e.map(\.name) == ["Infinite Health", "Master", "Moon Jump"])
        #expect(e[1].master && !e[0].master)
        #expect(CheatFile.parse(CheatFile.text(e)) == e)
    }

    @Test func addsOnlyWhatIsNew() {
        let old = CheatFile.parse("[Infinite Health]\n04000000 0149D940 00000003\n")
        let new = CheatFile.parse("[Unlimited HP]\n04000000  0149d940 00000003\n[Infinite Health]\n04000000 0149D940 00000063\n[Coins]\n02100000 619ED858 0000270F\n", source: "db")
        let add = CheatFile.additions(to: old, from: new)
        #expect(add.map(\.name) == ["Infinite Health (2)", "Coins"])   // the same code under another name is not added; a different code of the same name is renamed
    }

    @Test func switchKeysNameDuplicates() {
        let e = CheatFile.parse("[A]\n1\n[B]\n2\n[A]\n3\n")
        #expect(CheatFile.keys(e) == ["A", "B", "A #2"])
    }

    @Test func tellsInstructionPatches() {
        let patch = CheatFile.parse("[60 fps]\n04000000 004BF2A4 52800020\n")[0]
        let data = CheatFile.parse("[Coins]\n04000000 0149D940 0000270F\n")[0]
        let heap = CheatFile.parse("[Lives]\n04100000 0000D940 00000063\n")[0]
        #expect(patch.patchesCode(textEnd: 0xa2ad60))
        #expect(!data.patchesCode(textEnd: 0xa2ad60))
        #expect(!heap.patchesCode(textEnd: 0xa2ad60))
    }

    @Test func readsTheGeneralCollection() {
        let json = #"{"B424BE150A8E7D78": {"[Coins]": "[Coins]\n02100000 619ED858 0000270f\n\n"}, "3CA12DFAAF9C82DA": {"[X]": "[X]\n1\n"}, "attribution": {"a.txt": "By someone\n"}}"#
        let hit = CheatSources.parseGeneral(Data(json.utf8), build: "b424be150a8e7d78")
        #expect(hit.cheats.map(\.name) == ["Coins"] && hit.cheats[0].source == "switch-cheats-db")
        let miss = CheatSources.parseGeneral(Data(json.utf8), build: "0000000000000000")
        #expect(miss.cheats.isEmpty && miss.otherBuilds == ["3CA12DFAAF9C82DA", "B424BE150A8E7D78"])
    }

    @Test func findsAnUnbuiltGamesBuildByVersion() throws {
        let json = #"{"0": "B98E9D18B061B2F0", "131072": "82deca0a867052bf", "latest": 131072, "title": "Curse of the Moon"}"#
        #expect(CheatSources.parseVersions(Data(json.utf8), version: 0) == "B98E9D18B061B2F0")
        #expect(CheatSources.parseVersions(Data(json.utf8), version: 131072) == "82DECA0A867052BF")
        #expect(CheatSources.parseVersions(Data(json.utf8), version: 65536) == nil)
        let d = NSTemporaryDirectory() + "cheats-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        try "[A]\n1\n".write(toFile: d + "/0123456789ABCDEF.txt", atomically: true, encoding: .utf8)
        try "A\n".write(toFile: d + "/0123456789ABCDEF.enabled", atomically: true, encoding: .utf8)
        #expect(CheatSources.localBuilds(dir: d) == ["0123456789ABCDEF"])
        var g = LibraryGame(kind: .packages, path: "/x", name: "X", fileCount: 1, bytes: 1, base: true, updates: 0, dlc: 0)
        #expect(g.versionNumber == 0)
        g.updates = 1; g.newestUpdate = 131072
        #expect(g.versionNumber == 131072)
        g.newestUpdate = nil
        #expect(g.versionNumber == nil)
    }

    @Test func savesSwitchesAndAddsToTheFile() throws {
        let d = NSTemporaryDirectory() + "cheats-\(UUID().uuidString)"
        let n = try CheatFile.add(CheatFile.parse("[A]\n1\n[B]\n2\n"), dir: d, build: "0123456789ABCDEF")
        #expect(n == 2)
        #expect(try CheatFile.add(CheatFile.parse("[A]\n1\n[C]\n3\n"), dir: d, build: "0123456789ABCDEF") == 1)
        #expect(CheatFile.load(dir: d, build: "0123456789ABCDEF").map(\.name) == ["A", "B", "C"])
        try CheatFile.setEnabled(["C", "A"], order: ["A", "B", "C"], dir: d, build: "0123456789ABCDEF")
        #expect(try String(contentsOfFile: d + "/0123456789ABCDEF.enabled", encoding: .utf8) == "A\nC\n")
        #expect(CheatFile.enabled(dir: d, build: "0123456789ABCDEF") == ["A", "C"])
    }
}

@Suite struct ModFolders {
    let tid = "0100000000010000"

    func tree(_ files: [String]) -> String {
        let d = NSTemporaryDirectory() + "mods-\(UUID().uuidString)"
        for f in files {
            try? FileManager.default.createDirectory(atPath: (d + "/" + f as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? "x".write(toFile: d + "/" + f, atomically: true, encoding: .utf8)
        }
        return d
    }

    @Test func findsTheGameFilesInEachLayout() throws {
        let a = tree(["romfs/a.bin"])
        #expect(try Mods.locate(in: a, titleID: tid) == a)
        let b = tree(["My Mod/atmosphere/contents/0100000000010000/romfs/a.bin", "My Mod/readme.txt"])
        #expect(try Mods.locate(in: b, titleID: tid) == b + "/My Mod/atmosphere/contents/0100000000010000")
        let c = tree(["Pack/ObjectData/Mario.szs"])
        #expect(try Mods.locate(in: c, titleID: tid) == c)   // bare game files: the folder is the mod
        #expect(try Mods.locate(in: c, titleID: tid, wrapper: "pack") == c + "/Pack")   // unless its one folder is named as the download
        let other = tree(["atmosphere/contents/0100ABCDEF012000/romfs/a.bin"])
        #expect(throws: ModError.self) { try Mods.locate(in: other, titleID: tid) }
    }

    @Test func installsListsAndFindsClashes() throws {
        let mods = NSTemporaryDirectory() + "installed-\(UUID().uuidString)"
        let one = try Mods.install(from: tree(["romfs/Data/a.bin", "romfs/Data/b.bin"]), titleID: tid, name: "One: first", modsDir: mods)
        let two = try Mods.install(from: tree(["Wrap/contents/0100000000010000/romfs/Data/B.bin", "Wrap/contents/0100000000010000/exefs/main.ips"]), titleID: tid, name: "Two", modsDir: mods)
        #expect(one == "One- first" && two == "Two")
        let infos = Mods.ordered(Mods.names(dir: mods), saved: ["Two"]).map { Mods.info(dir: mods, name: $0, titleID: tid) }
        #expect(infos.map(\.name) == ["Two", "One- first"])
        #expect(infos[0].files == ["Data/B.bin"] && infos[0].hasCode && !infos[1].hasCode)
        let clash = Mods.clashes(infos)
        #expect(clash.count == 1 && clash[0].winner == "Two" && clash[0].losers == ["One- first"])
    }

    @Test func settingsFileLines() {
        let t = "# NXForge Sidebar settings for Super Mario Odyssey (0100000000010000)\nfps_counter = on\n# mods_on =    (folder names, separated by |)\n# mod_order =    (folder names, separated by |)\n"
        #expect(ModState.fileValue(t, "mods_on") == nil)
        let n = ModState.fileSetting(ModState.fileSetting(t, "mods_on", ["A", "B c"]), "mod_order", ["B c", "A"])
        #expect(ModState.fileValue(n, "mods_on").map(ModState.list) == ["A", "B c"])
        #expect(ModState.fileValue(n, "mod_order").map(ModState.list) == ["B c", "A"])
        #expect(ModState.fileValue(n, "fps_counter") == "on")
        #expect(ModState.fileSetting(n, "mods_on", []).contains("# mods_on ="))
        #expect(ModState.fileValue(ModState.fileSetting("", "mods_on", ["A"]), "mods_on") == "A")
    }
}

@Suite struct GameBananaAnswers {
    @Test func readsModsAndFiles() {
        let feed = #"{"_aMetadata": {"_nRecordCount": 640, "_nPerpage": 15}, "_aRecords": [{"_idRow": 738419, "_sModelName": "Mod", "_sName": "Remove Assist Mode Logo", "_sProfileUrl": "https://gamebanana.com/mods/738419", "_tsDateModified": 1794237711, "_sVersion": "1.4.1", "_aSubmitter": {"_sName": "Sukalibur"}, "_aRootCategory": {"_sName": "GUIs"}, "_aPreviewMedia": {"_aImages": [{"_sBaseUrl": "https://images.gamebanana.com/img/ss/mods", "_sFile": "a.jpg", "_sFile530": "530-90_a.jpg"}]}}]}"#
        let p = GameBanana.parseMods(try? JSONSerialization.jsonObject(with: Data(feed.utf8)))
        #expect(p.total == 640 && p.mods.count == 1)
        #expect(p.mods[0].author == "Sukalibur" && p.mods[0].thumb?.absoluteString == "https://images.gamebanana.com/img/ss/mods/530-90_a.jpg")
        let dl = #"{"_aFiles": [{"_idRow": 1, "_sFile": "m.zip", "_nFilesize": 1333, "_sDownloadUrl": "https://gamebanana.com/dl/1", "_sMd5Checksum": "ABC", "_sAvResult": "clean", "_sAnalysisResult": "ok"}, {"_idRow": 2, "_sFile": "bad.zip", "_nFilesize": 1, "_sDownloadUrl": "https://gamebanana.com/dl/2", "_sAvResult": "infected"}]}"#
        let f = GameBanana.parseFiles(try? JSONSerialization.jsonObject(with: Data(dl.utf8)))
        #expect(f.map(\.clean) == [true, false] && f[0].md5 == "abc" && f[0].bytes == 1333)
    }

    @Test func gameNames() {
        #expect(GameBanana.searchName("SUPER MARIO ODYSSEY™ [NSZ]") == "SUPER MARIO ODYSSEY")
        let g = [GameBanana.Game(id: 1, name: "Super Mario Odyssey 2"), GameBanana.Game(id: 2, name: "Super Mario Odyssey")]
        #expect(GameBanana.best(g, for: "SUPER MARIO ODYSSEY™")?.id == 2)
    }
}

@Suite struct Sessions {
    @Test func olderPlaytimeFilesStillRead() throws {
        let old = #"{"start": "2026-11-01T10:00:00Z", "seconds": 600}"#
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let s = try dec.decode(PlaySession.self, from: Data(old.utf8))
        #expect(s.seconds == 600 && s.peakMB == nil && s.fps == nil)
    }

    @Test func memoryAddsUp() {
        var s = PlayStats()
        s.add(0); s.add(2 * 1_048_576 * 1024); s.add(4 * 1_048_576 * 1024)
        #expect(s.peakMB == 4096 && s.averageMB == 3072)
        #expect(memoryText(4096) == "4.0 GB" && memoryText(512) == "512 MB")
    }
}

@Suite struct LocalShaderCopies {
    /// A built app with a pso folder of two files, and an empty cache root, in a new temporary folder
    private func make() throws -> (base: URL, app: String, root: URL) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "nxc-pso-\(UUID().uuidString)")
        let pso = base.appending(path: "Drive/Game.app/Contents/Resources/pso")
        try fm.createDirectory(at: pso, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: pso.appending(path: "applegpu_g16s.mtl4a"))
        try Data("chain\tabc\n".utf8).write(to: pso.appending(path: "prebuilt.tsv"))
        try Data().write(to: pso.appending(path: ".DS_Store"))
        return (base, base.appending(path: "Drive/Game.app").path, base.appending(path: "cache"))
    }

    @Test func aCopyIsMadeOnceAndAgainAfterARebuild() throws {
        let (base, app, root) = try make()
        defer { try? FileManager.default.removeItem(at: base) }
        let pso = app.url.appending(path: "Contents/Resources/pso")
        let s = try #require(LocalShaders.read(pso))
        #expect(s.bytes == 4096 + 10 && !s.stamp.contains(".DS_Store"))
        #expect(LocalShaders.ready(app: app, source: s, root: root) == nil)
        let made = LocalShaders.copy(app: app, source: s, root: root, free: 100 << 30)
        let dir = try #require(LocalShaders.ready(app: app, source: s, root: root))
        #expect(made == .ready(dir))
        #expect(try Data(contentsOf: dir.appending(path: "applegpu_g16s.mtl4a")).count == 4096)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "prebuilt.tsv").path))
        // a rebuild: another size, so another stamp, and the old copy no longer counts
        try Data(repeating: 2, count: 8192).write(to: pso.appending(path: "applegpu_g16s.mtl4a"))
        let s2 = try #require(LocalShaders.read(pso))
        #expect(s2.stamp != s.stamp && LocalShaders.ready(app: app, source: s2, root: root) == nil)
        #expect(LocalShaders.copy(app: app, source: s2, root: root, free: 100 << 30) == .ready(dir))
        #expect(try Data(contentsOf: dir.appending(path: "applegpu_g16s.mtl4a")).count == 8192)
    }

    @Test func noCopyWhenTheDiskWouldBeLeftShort() throws {
        let (base, app, root) = try make()
        defer { try? FileManager.default.removeItem(at: base) }
        let s = try #require(LocalShaders.read(app.url.appending(path: "Contents/Resources/pso")))
        let free = LocalShaders.keepFree + 100
        #expect(LocalShaders.copy(app: app, source: s, root: root, free: free) == .noRoom(needed: s.bytes, free: free))
        #expect(LocalShaders.ready(app: app, source: s, root: root) == nil)
        // an app on the home folder's own volume has nothing to copy
        #expect(LocalShaders.source(app: app, home: base.path) == nil)
        #expect(LocalShaders.source(app: base.appending(path: "None.app").path, home: "/nowhere") == nil)
    }

    @Test func aCopyGoesWithItsGameButStaysForAnUnpluggedDrive() throws {
        let (base, app, root) = try make()
        defer { try? FileManager.default.removeItem(at: base) }
        let s = try #require(LocalShaders.read(app.url.appending(path: "Contents/Resources/pso")))
        _ = LocalShaders.copy(app: app, source: s, root: root, free: 100 << 30)
        let std = app.url.standardizedFileURL.path
        #expect(LocalShaders.removeOrphans(root: root).isEmpty)                                    // the app is there
        #expect(LocalShaders.removeOrphans(root: root, exists: { _ in false }).isEmpty)            // its drive is not connected
        #expect(LocalShaders.removeOrphans(root: root, exists: { $0 != std }) == [std])            // the drive is there, the app is gone
        #expect(LocalShaders.ready(app: app, source: s, root: root) == nil)
        #expect(LocalShaders.volume(of: "/Volumes/Games/Switch 2/Zelda.app") == "/Volumes/Games")
        #expect(LocalShaders.volume(of: "/Users/tom/Applications/Zelda.app") == "/")
        #expect(LocalShaders.folder(app: "/a/Zelda: OoT.app", root: root) != LocalShaders.folder(app: "/b/Zelda: OoT.app", root: root))
        #expect(LocalShaders.folder(app: "/a/Zelda: OoT.app", root: root).lastPathComponent.hasPrefix("Zelda OoT "))
    }
}

@Suite struct GameFolderMediaFormat {
    func item(_ store: StoreInfo?) -> GameFolderMedia.Item {
        GameFolderMedia.Item(key: "0100C8B0129B4000", title: "Blazing Chrome", titleID: "0100C8B0129B4000", console: "Switch",
                             app: "/Volumes/Games/Switch 1/Blazing Chrome/Blazing Chrome.app", gameFolder: "/Volumes/Games/Switch 1/Blazing Chrome",
                             version: "1.0.2", publisher: "The Arcade Crew", gameFiles: "Base game + update", newestUpdate: 131072, record: nil,
                             store: store, manual: nil, icon: nil, preset: "Balanced", changed: [("Frame rate", "60 fps"), ("Say \"hi\": now", "On")],
                             played: 7260, dest: URL(fileURLWithPath: "/tmp/media"))
    }

    @Test func gameMdReadsBackAsTheStoresDetails() throws {
        var s = StoreInfo(title: "Blazing Chrome")
        s.publisher = "The Arcade Crew"; s.released = "11/07/2019"; s.genres = ["Action", "Platformer"]; s.playersFrom = 1; s.playersTo = 2
        s.about = ["Run and gun: \"Contra\"-style.\nTwo lines", "• Co-op"]; s.modes = ["TV", "Handheld"]; s.page = "https://www.nintendo.com/en-gb/x.html"
        s.shots = ["https://www.nintendo.com/a_01.jpg", "https://www.nintendo.com/a_02.jpg"]
        s.trailers = [StoreVideo(youtube: "abcdefghijk", thumb: "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg", title: "Launch Trailer")]
        let files = ["cover-front": "cover-front.png", "screenshots/01": "screenshots/01.jpg", "screenshots/02": "screenshots/02.jpg", "trailers/01": "trailers/01.jpg"]
        let text = GameFolderMedia.document(item(s), files: files)
        #expect(text.hasPrefix("---\n"))
        #expect(text.contains("# Blazing Chrome"))
        #expect(text.contains("\n- Co-op\n"))
        #expect(text.contains("- [Launch Trailer](https://www.youtube.com/watch?v=abcdefghijk)"))
        let doc = try #require(MiniYAML.frontMatter(text))
        #expect(doc["title"] as? String == "Blazing Chrome")
        #expect(doc["update_version"] as? Int == 131072)
        let play = try #require(doc["play"] as? [String: Any])
        #expect(play["preset"] as? String == "Balanced")
        #expect((play["settings"] as? [String: Any])?["Say \"hi\": now"] as? String == "On")
        #expect(play["played_minutes"] as? Int == 121)
        #expect((doc["media"] as? [String: Any])?["cover_front"] as? String == "cover-front.png")
        let back = try #require(GameFolderMedia.storeInfo(doc))
        #expect(back.title == s.title && back.publisher == s.publisher && back.genres == s.genres && back.about == s.about)
        #expect(back.playersFrom == 1 && back.playersTo == 2 && back.modes == s.modes && back.page == s.page)
        #expect(back.shots == s.shots)
        #expect(back.trailers == s.trailers)
    }

    @Test func noStoreDetailsStillWrites() throws {
        let text = GameFolderMedia.document(item(nil), files: [:])
        let doc = try #require(MiniYAML.frontMatter(text))
        #expect(doc["store"] == nil)
        #expect(GameFolderMedia.storeInfo(doc) == nil)
        #expect(doc["game_files"] as? String == "Base game + update")
    }

    @Test func whereTheMediaGoes() {
        let app = "/Volumes/Games/Switch 1/Odyssey/SUPER MARIO ODYSSEY.app"
        #expect(GameFolderMedia.folder(app: app, gameFolder: "/Volumes/Games/Switch 1/Odyssey", appsBeside: 1).path == "/Volumes/Games/Switch 1/Odyssey/media")
        #expect(GameFolderMedia.folder(app: "/Users/t/Games/Odyssey.app", gameFolder: "/Volumes/G/Odyssey", appsBeside: 3).path == "/Volumes/G/Odyssey/media")
        #expect(GameFolderMedia.folder(app: "/Users/t/Games/Odyssey.app", gameFolder: nil, appsBeside: 3).path == "/Users/t/Games/Odyssey media")
    }

    @Test func onlyItsOwnFilesAreTidied() {
        #expect(GameFolderMedia.ours("cover-front.png"))
        #expect(GameFolderMedia.ours("screenshots/03.jpg"))
        #expect(GameFolderMedia.ours("manual.pdf"))
        #expect(!GameFolderMedia.ours("game.md"))
        #expect(!GameFolderMedia.ours("my notes.png"))
        #expect(!GameFolderMedia.ours("screenshots/holiday.jpg"))
    }

    @Test func quotedStringsSurviveTheRoundTrip() {
        for s in ["plain", "a \"quote\" and \\ back", "line\nbreak", "tab\there", "café ™ – ‘x’", "# not a comment", "- not a list", "key: value"] {
            #expect(MiniYAML.scalar(MiniYAML.quote(s)) as? String == s)
        }
    }
}

// Converter 0.14.0: ideas from RetroReplay (TitleMatch, GameStatus, LaunchDiagnosis, PlayWeek, DataBackup)
@Suite struct RetroReplayIdeas {
    @Test func titlesFoldCaseAccentsAndThe() {
        #expect(TitleMatch.fold("Pokémon™ Legends: Z-A") == "pokemon legends z a")
        #expect(TitleMatch.matches("pokemon", ["Pokémon Scarlet"]))
        #expect(TitleMatch.matches("zelda ocarina", ["The Legend of Zelda: Ocarina of Time"]))
        #expect(!TitleMatch.matches("mario kart", ["Super Mario Odyssey"]))
        #expect(TitleMatch.rank("legend", title: "The Legend of Zelda") == 0)
        #expect(TitleMatch.rank("odyssey", title: "Super Mario Odyssey") == 1)
        #expect(TitleMatch.rank("dyss", title: "Super Mario Odyssey") == 2)
        #expect(TitleMatch.rank("kart", title: "Super Mario Odyssey") == nil)
    }

    @Test func betterMatchesThenRecentPlay() {
        let now = Date()
        let games: [(String, Date?)] = [("Super Mario Odyssey", now), ("Mario Kart World", now.addingTimeInterval(-99)), ("Mario Kart 8 Deluxe", nil)]
        let out = TitleMatch.sorted(games, query: "mario", title: { $0.0 }, last: { $0.1 }).map(\.0)
        #expect(out == ["Mario Kart World", "Mario Kart 8 Deluxe", "Super Mario Odyssey"])
    }

    @Test func typeSelectBuildsAPrefixThenStartsOver() {
        var b = TypeSelectBuffer()
        let t0 = Date()
        #expect(b.type("z", at: t0) == "z")
        #expect(b.type("e", at: t0.addingTimeInterval(0.3)) == "ze")
        #expect(b.active(at: t0.addingTimeInterval(0.5)))
        #expect(b.type("m", at: t0.addingTimeInterval(3)) == "m")
        #expect(TypeSelectBuffer.first(["Mario", "The Legend of Zelda", "Zelda II"], prefix: "zel", title: { $0 }) == "Zelda II")
        #expect(TypeSelectBuffer.first(["Mario", "The Legend of Zelda", "Zelda II"], prefix: "leg", title: { $0 }) == "The Legend of Zelda")
    }

    @Test func offlineDriveIsNamed() {
        #expect(GameStatus.offlineVolume("/Volumes/NoSuchDrive-\(UUID().uuidString)/roms/Game") != nil)
        #expect(GameStatus.offlineVolume("/Users/tom/Games/Game") == nil)
        #expect(GameStatus.offlineVolume("/Volumes") == nil)
    }

    @Test func launchFailuresAreTold() {
        #expect(LaunchDiagnosis.diagnose(nil).code == .closed)
        let guardStop = "[dm] [nvn-mtl] [RED] GPU memory guard: 17300 MB, against Metal's working set of 18186 MB (this guard stops at 17276 MB): stopping the game before the driver cannot wire more\nlauncher: the host exited with 1\n"
        #expect(LaunchDiagnosis.diagnose(guardStop).code == .gpuMemory)
        #expect(LaunchDiagnosis.diagnose(guardStop).fix == .playOptions)
        let crash = "[dm] [RED] shader cache: bad header\nlauncher: the host stopped on signal 11\n"
        let c = LaunchDiagnosis.diagnose(crash)
        #expect(c.code == .crashed)
        #expect(c.line == "shader cache: bad header")
        #expect(LaunchDiagnosis.diagnose("launcher: the host stopped on signal 9\n").code == .memory)
        #expect(LaunchDiagnosis.diagnose("[RED] launcher: cannot start dmhost: No such file\n").code == .cannotStart)
        #expect(LaunchDiagnosis.diagnose("launcher: the host exited with 3\n").code == .error)
        #expect(LaunchDiagnosis.diagnose("launcher: the host exited with 0\n").code == .closed)
    }

    @Test func weekSplitsSessionsOverMidnight() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        let lateStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23))!
        var r = PlayRecord(name: "Odyssey", app: "/A.app")
        r.sessions = [PlaySession(start: lateStart, seconds: 7200),   // 23:00 to 01:00
                      PlaySession(start: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!, seconds: 3600)]   // older than a week
        let w = PlayWeek(["0100000000010000": r], now: now, calendar: cal)
        #expect(w.days.count == 7)
        #expect(w.days[5].seconds == 3600)
        #expect(w.days[6].seconds == 3600)
        #expect(w.seconds == 7200)
        #expect(w.games == 1)
    }

    @Test func backupIsCheckedAndRestoresWhatWasThere() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "nxf-backup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appending(path: "covers"), withIntermediateDirectories: true)
        try Data("{\"a\":1}".utf8).write(to: root.appending(path: "playtime.json"))
        try Data("own".utf8).write(to: root.appending(path: "covers/0100-front-own.png"))
        try Data("downloaded".utf8).write(to: root.appending(path: "covers/0100-front.jpg"))
        #expect(DataBackup.sources(root: root) == ["playtime.json", "covers/0100-front-own.png"])
        let m = try #require(DataBackup.make(name: "2026-11-15", root: root))
        #expect(m.verified)
        #expect(m.files.count == 2)
        // the time played is lost, then put back
        try Data("{}".utf8).write(to: root.appending(path: "playtime.json"))
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let entry = DataBackupEntry(folder: root.appending(path: "backups/2026-11-15"), manifest: m)
        #expect(DataBackup.restore(entry, root: root) == 2)
        #expect(try String(contentsOf: root.appending(path: "playtime.json"), encoding: .utf8) == "{\"a\":1}")
        // what was there before the restore was kept
        let kept = try fm.contentsOfDirectory(atPath: root.appending(path: "backups").path)
        #expect(kept.contains { $0.hasSuffix("before-restore") })
        _ = dec
    }
}

@Suite struct DecodedFiles {
    @Test func keptUntilTheFileChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nxc-decoded-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "list.json")
        let cache = DecodedFile<[Int]>()
        var decodes = 0
        func read() -> [Int]? { cache.value(url) { decodes += 1; return try? JSONDecoder().decode([Int].self, from: $0) } }
        #expect(read() == nil)   // no file yet
        try Data("[1,2]".utf8).write(to: url)
        #expect(read() == [1, 2])
        #expect(read() == [1, 2])
        #expect(decodes == 1)   // the second read is the kept copy
        try Data("[1,2,3]".utf8).write(to: url)   // another size: read again
        #expect(read() == [1, 2, 3])
        #expect(decodes == 2)
        cache.drop()
        #expect(read() == [1, 2, 3])
        #expect(decodes == 3)
        try Data("not json".utf8).write(to: url)
        #expect(read() == nil)
    }

    @Test func builtAtRoundTrips() {
        let d = Engine.builtAtFormat.date(from: "2026-11-15 22:46")
        #expect(d != nil)
        #expect(d.map(Engine.builtAtFormat.string(from:)) == "2026-11-15 22:46")
    }
}

@Suite struct Theatre {
    @Test(arguments: [
        ("LG TV SSCR2", 1600.0, true),
        ("SAMSUNG", 0.0, true),
        ("SONY TV  *00", 0.0, true),
        ("BRAVIA", 0.0, true),
        ("Studio Display", 597.0, false),
        ("LG UltraFine", 600.0, false),
        ("DELL U2723QE", 597.0, false),
        ("HDMI", 1210.0, true),          // a 55-inch set that names nothing
        ("Projector", 9999.0, false),    // nonsense size
        ("Built-in Retina Display", 0.0, false),
    ])
    func tvByName(_ name: String, _ width: Double, _ tv: Bool) {
        #expect(TVScreens.isTV(name: name, widthMM: width) == tv)
    }

    @Test func ringShowsNeighbours() {
        // 20 games on a ring of 16: in front the game at the position, either side the ones next to it in the list
        let slots = CarouselRing.slots(for: 20)
        #expect(slots == 16)
        let front = 21 % slots   // position 21: game 1 in front, in place 5
        #expect(CarouselRing.game(slot: front, position: 21, slots: slots, count: 20) == 1)
        #expect(CarouselRing.game(slot: (front + 1) % slots, position: 21, slots: slots, count: 20) == 2)
        #expect(CarouselRing.game(slot: (front + slots - 1) % slots, position: 21, slots: slots, count: 20) == 0)
        #expect(CarouselRing.game(slot: (front + slots - 2) % slots, position: 21, slots: slots, count: 20) == 19)
        // backwards past zero
        #expect(CarouselRing.game(slot: ((-1 % slots) + slots) % slots, position: -1, slots: slots, count: 20) == 19)
        // fewer games than places: the ring is that small
        #expect(CarouselRing.slots(for: 5) == 5)
        let five = (0..<5).map { CarouselRing.game(slot: $0, position: 0, slots: 5, count: 5) }
        #expect(Set(five).count == 5)
    }
}

@Suite struct GameFolderCheatsFormat {
    let info = GameFolderCheats.Info(title: "Blazing Chrome", titleID: "0100C2700C252000", version: "1.0.3")
    let txt = "580F0000 01234567\n[P1 Lives unlimited]\n580F0000 0241BCE8\n780F1000 000012BC\n\n[P2 Lives unlimited]\n580F0000 0241CD08\n\n{Always}\n04000000 00001000 D65F03C0\n\n[P2 Lives unlimited]\n580F0000 00000001\n"

    @Test func markdownReadsBackAsTheSameCheatsAndSwitches() {
        let entries = CheatFile.parse(txt)
        let on: Set<String> = ["P1 Lives unlimited", "P2 Lives unlimited #2"]
        let md = GameFolderCheats.document(info, build: "318f9f225a532857", entries: entries, on: on, notes: ["P1 Lives unlimited": "Tested in stage 1."])
        #expect(md.contains("build_id: \"318F9F225A532857\""))
        #expect(md.contains("## P1 Lives unlimited\n\nTested in stage 1.\n\n```dmnt on\n580F0000 0241BCE8"))
        #expect(md.contains("## Always\n\n```dmnt master\n"))
        let d = GameFolderCheats.parse(md)
        #expect(d.build == "318F9F225A532857")
        #expect(d.entries.map(\.id) == entries.map(\.id))
        #expect(d.on == on)
        #expect(d.notes == ["P1 Lives unlimited": "Tested in stage 1."])
        #expect(CheatFile.text(d.entries) == CheatFile.text(entries))
        // written again, it reads the same
        #expect(GameFolderCheats.document(info, build: "318F9F225A532857", entries: d.entries, on: d.on, notes: d.notes) == md)
    }

    @Test func aHandWrittenFileIsRead() {
        let d = GameFolderCheats.parse("# My cheats\n\n## Infinite HP\nKeeps the bar full.\n\n```dmnt on\n580f0000 006e1c10\n```\n\n```text\nnot code\n```\n\n## Off one\n```dmnt\n04000000 0029AB30 D65F03C0\n```\n")
        #expect(d.build == nil)
        #expect(d.entries.map(\.name) == ["Infinite HP", "Off one"])
        #expect(d.entries[0].lines == ["580f0000 006e1c10"])
        #expect(d.on == ["Infinite HP"])
        #expect(d.notes["Infinite HP"]?.hasPrefix("Keeps the bar full.") == true)
        #expect(d.notes["Infinite HP"]?.hasSuffix("```text\nnot code\n```") == true)
    }

    @Test func theFolderSitsBesideMedia() {
        #expect(GameFolderCheats.folder(media: URL(fileURLWithPath: "/Volumes/Games/Switch 1/Blazing Chrome/media")).path == "/Volumes/Games/Switch 1/Blazing Chrome/cheats")
        #expect(GameFolderCheats.folder(media: URL(fileURLWithPath: "/Users/t/Games/Odyssey media")).path == "/Users/t/Games/Odyssey cheats")
    }

    @Test func theNewerSideWins() {
        let old = Date(timeIntervalSince1970: 1000), new = Date(timeIntervalSince1970: 2000)
        #expect(GameFolderCheats.direction(folderText: nil, folderDate: nil, engine: nil, written: nil) == .none)
        #expect(GameFolderCheats.direction(folderText: nil, folderDate: nil, engine: old, written: "a") == .toFolder)
        #expect(GameFolderCheats.direction(folderText: "a", folderDate: old, engine: nil, written: nil) == .fromFolder)
        #expect(GameFolderCheats.direction(folderText: "a", folderDate: old, engine: new, written: "a") == .none)
        #expect(GameFolderCheats.direction(folderText: "b", folderDate: new, engine: old, written: "a") == .fromFolder)
        #expect(GameFolderCheats.direction(folderText: "b", folderDate: old, engine: new, written: "a") == .toFolder)
    }

    @Test func syncMovesCheatsBothWays() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "nxf-cheats-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let engine = root.appending(path: "engine").path, folder = root.appending(path: "game/cheats")
        try fm.createDirectory(atPath: engine, withIntermediateDirectories: true)
        try txt.write(toFile: engine + "/318F9F225A532857.txt", atomically: true, encoding: .utf8)
        try "P1 Lives unlimited\n".write(toFile: engine + "/318F9F225A532857.enabled", atomically: true, encoding: .utf8)
        // the engine's cheats go to the folder
        #expect(GameFolderCheats.sync(info, folder: folder, engineDir: engine))
        let md = GameFolderCheats.file(folder, build: "318F9F225A532857")
        var d = GameFolderCheats.parse(try String(contentsOf: md, encoding: .utf8))
        #expect(d.on == ["P1 Lives unlimited"])
        // a hand edit (newer) comes back: P1 off, P2 on
        let edited = try String(contentsOf: md, encoding: .utf8)
            .replacingOccurrences(of: "```dmnt on\n580F0000 0241BCE8", with: "```dmnt\n580F0000 0241BCE8")
            .replacingOccurrences(of: "## P2 Lives unlimited\n\n```dmnt\n580F0000 0241CD08", with: "## P2 Lives unlimited\n\n```dmnt on\n580F0000 0241CD08")
        try Data(edited.utf8).write(to: md)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: md.path)
        #expect(GameFolderCheats.sync(info, folder: folder, engineDir: engine))
        #expect(CheatFile.enabled(dir: engine, build: "318F9F225A532857") == ["P2 Lives unlimited"])
        // a Mac with no cheats for the game takes them from the folder
        try fm.removeItem(atPath: engine)
        #expect(GameFolderCheats.sync(info, folder: folder, engineDir: engine))
        #expect(CheatFile.load(dir: engine, build: "318F9F225A532857").count == 5)
        d = GameFolderCheats.parse(try String(contentsOf: md, encoding: .utf8))
        #expect(d.on == ["P2 Lives unlimited"])
    }
}
