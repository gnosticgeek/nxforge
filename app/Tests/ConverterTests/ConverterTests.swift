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
