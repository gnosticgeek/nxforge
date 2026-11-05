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
