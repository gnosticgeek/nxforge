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

@Suite struct BuildTimeline {
    @Test func stageKeysDropTheVersion() {
        #expect(stageKey("extract v131072") == "extract")
        #expect(stageKey("Mac shaders") == "Mac shaders")
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
