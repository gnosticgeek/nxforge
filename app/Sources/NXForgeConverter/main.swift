// NXForge Converter: a window over scripts/build_ipa_from_nsp.py --platform mac-app.
// 1. lists what the script needs, ticked or crossed; 2. checks a game folder against prod.keys;
// 3. converts the folder to a signed Mac app, and rebuilds it when the engine changes. The same steps run headless:
//   NXForgeConverter --check | --validate <folder> [<prod.keys>] | --convert <folder> [<prod.keys>] [--sign <identity>]
//   | --rebuild <app> [<prod.keys>] [--sign <identity>] | --engine [<folder>] | --verify <app> | --library <games folder> [<prod.keys>]
// <folder> may also be a Switch 2 game's .nup file or dump folder, which need no prod.keys.
import AppKit
import SwiftUI

func mark(_ ok: Bool, optional: Bool = false) -> String { ok ? "✓" : optional ? "–" : "✗" }

@MainActor
enum CLI {
    static func check() -> Int32 {
        let (checks, _) = Toolchain.checkAll(Settings.load())
        for c in checks {
            print("\(mark(c.ok, optional: c.optional)) \(c.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(c.detail)\(c.optional ? "  (optional)" : "")")
            if !c.ok, let f = c.fix { print("      fix: \(f)") }
        }
        return checks.allSatisfy { $0.ok || $0.optional } ? 0 : 1
    }

    static func validate(_ dir: String, _ keys: String?, env: ToolEnv? = nil) -> Int32 {
        let (v, _) = Source.validate(dir, keys: keys, env: env ?? (Source.needsKeys(dir) ? nil : Toolchain.checkAll(Settings.load()).1))
        for l in v.summary { print("\(l.warn ? "!" : mark(l.ok)) \(l.text)") }
        for f in v.files {
            print("\(mark(f.ok)) \(f.name) (\(f.role))")
            for l in f.lines { print("    \(mark(l.ok)) \(l.text)") }
        }
        return v.ok ? 0 : 1
    }

    static func engine(_ dir: String?) -> Int32 {
        let (_, env) = Toolchain.checkAll(Settings.load())
        guard let repo = env.repo else { print("✗ no NXForge engine checkout"); return 1 }
        guard let v = Engine.current(repo) else { print("✗ \(repo) is not a git checkout"); return 1 }
        print("engine \(repo) (\(v.branch)): \(v.label)")
        for (app, b) in dir.map(Engine.apps(in:)) ?? [] {
            if let b { print("\(mark(b.engine.commit == v.commit && !v.dirty)) \(app): \(b.engine.label)\(b.engine.commit == v.commit ? " (current)" : " (older engine)")") }
            else { print("✗ \(app): unknown engine (built before the converter tracked engines)") }
        }
        return 0
    }

    static func convert(_ dir: String, _ keys: String?, sign: String?, rebuild: String?) -> Int32 {
        let (checks, env) = Toolchain.checkAll(Settings.load())
        let missing = checks.filter { !$0.ok && !$0.optional }.map(\.name)
        if !missing.isEmpty { print("✗ missing: \(missing.joined(separator: ", "))"); return 1 }
        if validate(dir, keys, env: env) != 0 { return 1 }
        let run = BuildRun()
        var shown = 0, last = ""
        run.onChange = {
            for s in run.done[shown...] { print("\(mark(s.ok)) \(s.line)") }
            shown = run.done.count
            let now = "[\(run.stage.k)/\(run.stage.n)] \(run.stage.name) · \(run.stage.step)"
            if run.running && now != last { print("  … \(now)"); last = now }
        }
        run.start(Job(gameDir: dir, keys: Source.needsKeys(dir) ? keys : nil, sign: sign, env: env, rebuild: rebuild))
        while run.result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        switch run.result! {
        case .success(let m): print("✓ \(m)"); return 0
        case .failure(let e):
            print("✗ \(e)")
            let d = BuildDiagnosis.diagnose(error: e.description, log: run.log)
            if d.code != .unknown { print("  \(d.title). \(d.fix)") }
            return 1
        }
    }
}

func signArg(_ a: [String]) -> String? { a.firstIndex(of: "--sign").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
/// the keys file after the folder, when given (a NUP or a dump needs none)
func keysArg(_ a: [String]) -> String? { a.count > 2 && !a[2].hasPrefix("--") ? a[2] : nil }

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--check": exit(MainActor.assumeIsolated { CLI.check() })
case "--validate" where args.count >= 2: exit(MainActor.assumeIsolated { CLI.validate(args[1], keysArg(args)) })
case "--engine": exit(MainActor.assumeIsolated { CLI.engine(args.count > 1 ? args[1] : nil) })
case "--convert" where args.count >= 2: exit(MainActor.assumeIsolated { CLI.convert(args[1], keysArg(args), sign: signArg(args), rebuild: nil) })
case "--rebuild" where args.count >= 2:
    exit(MainActor.assumeIsolated { CLI.convert(args[1].url.deletingLastPathComponent().path, keysArg(args), sign: signArg(args), rebuild: args[1]) })
case "--library" where args.count >= 2:
    // the Library page's scan, printed: one game per line (nothing is moved or written)
    var s = GameLibrary.scan(root: args[1])
    // with a keys file: each game's own name, publisher and version from its control data, as the Library reads them
    if args.count > 2, let k = try? Keys(contentsOf: args[2].url) { s.games = s.games.map { GameLibrary.withDetails($0, keys: k) } }
    for g in s.games {
        print("\(g.console == .switch2 ? "S2" : "S1") \(g.displayName)\(g.version.map { " v\($0)" } ?? "")\(g.publisher.map { " (\($0))" } ?? "")\(g.icon != nil ? " [icon]" : "") · \(g.contents)\(g.titleID.map { " · \($0)" } ?? "")\(g.shared ? " · shares its folder" : "")\(g.app != nil ? " · built" : "")")
        print("   \(g.path)")
        for n in g.notes { print("   ! \(n)") }
        for d in g.duplicates ?? [] { print("   = also in \(d)") }
    }
    print("\(s.games.count) games in \(s.folders) folders\(s.skipped.isEmpty ? "" : ", \(s.skipped.count) skipped")\(s.stopped.map { ". \($0)" } ?? "")")
    exit(s.stopped == nil ? 0 : 1)
case "--verify" where args.count >= 2:
    do { print("✓ \(try BuildRun.verify(args[1]))"); exit(0) } catch { print("✗ \(error)"); exit(1) }
case let a? where a.hasPrefix("--") && !a.hasPrefix("-NS") && !a.hasPrefix("-Apple"):
    FileHandle.standardError.write(Data("usage: NXForgeConverter [--check | --validate <folder | game.nup> [<prod.keys>] | --convert <folder | game.nup> [<prod.keys>] [--sign <identity>] | --rebuild <app> [<prod.keys>] [--sign <identity>] | --engine [<folder>] | --verify <app> | --library <games folder> [<prod.keys>]]\n".utf8))
    exit(2)
default:
    ConverterApp.main()
}
