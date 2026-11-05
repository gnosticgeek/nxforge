// What a failed build means and what to do next, from the script's last red line and the end of its log; and an error
// summary to paste into a report with nothing private in it (no key values, no home folder, no prod.keys path).
// After LumaNX's Worker/diagnostics.py (MIT, github.com/Xc1Ym/LumaNX), rewritten for build_ipa_from_nsp.py's own messages.
import Foundation

struct Diagnosis: Equatable {
    enum Code: String, CaseIterable {
        case stopped, diskFull, thirtyTwoBit, keys, folderBusy, gameFiles, language, metalToolchain, xcode, dotnet, python,
             missingTool, engine, memory, permission, gameStopped, rewriter, shaders, signing, unknown
    }
    let code: Code
    /// one line: what went wrong, in plain words
    let title: String
    /// what to do next
    let fix: String
    /// the page with the fix, when there is one
    var page: Page? = nil
}

enum BuildDiagnosis {
    /// A rule: any of the phrases (lowercase) in the text gives the diagnosis.
    private struct Rule { let code: Diagnosis.Code; let phrases: [String]; let title: String; let fix: String; var page: Page? = nil }

    private static let rules: [Rule] = [
        Rule(code: .stopped, phrases: ["stopped", "interrupted"],
             title: "The build was stopped", fix: "Build again when you are ready; the steps that finished are reused."),
        Rule(code: .diskFull, phrases: ["gb free on the volume", "no space left on device", "disk full", "not enough space", "enospc"],
             title: "Not enough free disk space",
             fix: "Free space on the game folder's drive (a first build needs about twice the game files plus 10 GB): Storage lists every game's build cache and older app copies with their sizes. Then build again; finished steps are reused.", page: .storage),
        Rule(code: .thirtyTwoBit, phrases: ["32-bit arm program"],
             title: "This version of the game is a 32-bit program, which NXForge cannot run",
             fix: "Add a newer update of the game to the folder: some games became 64-bit in a later version (Mario Kart 8 Deluxe from 4.0.0)."),
        Rule(code: .keys, phrases: ["prod.keys", "missingkey", "could not load keys", "title key", "key not found", "keys are missing", "header key"],
             title: "The keys could not decrypt the game",
             fix: "Choose your own complete prod.keys on Convert, dumped from a console with a system version at least as new as the game update.", page: .convert),
        Rule(code: .folderBusy, phrases: ["another build of this folder is running"],
             title: "Another build of this game folder is running",
             fix: "Wait for it to finish (it may be in another converter window or a Terminal), then build again."),
        Rule(code: .gameFiles, phrases: ["no base game nsp", "no nsp for update", "is not in the folder, which holds", "no nsp with a readable title id",
                                         "more than one game in the folder", "neither a ticket nor a [title id]", "not a folder:", "must be one the game profile registers"],
             title: "The game folder does not hold the files this build needs",
             fix: "Keep one game per folder: its base game (.nsp or .xci) and the updates and DLC you want, with the names they were dumped with. The error says which file is missing.", page: .convert),
        Rule(code: .language, phrases: ["unknown game language", "the game has no "],
             title: "The game does not have the language chosen for it",
             fix: "Choose one of the languages the error lists, or the game's default, in the game's settings window."),
        Rule(code: .metalToolchain, phrases: ["metal compiler does not run", "metal toolchain", "cannot execute tool 'metal'", "unable to find utility \"metal\""],
             title: "The Metal shader compiler is not installed",
             fix: "Install it on the Toolchain page (Fix beside Metal toolchain), or run xcodebuild -downloadComponent MetalToolchain, then build again.", page: .toolchain),
        Rule(code: .xcode, phrases: ["ios sdk is not installed", "command line tools", "xcode-select", "no developer directory", "sdk \"macosx\" cannot be located"],
             title: "Xcode is missing or not selected",
             fix: "Install Xcode from the App Store, open it once, and select it with sudo xcode-select -s /Applications/Xcode.app; the Toolchain page shows what it finds.", page: .toolchain),
        Rule(code: .dotnet, phrases: ["dotnet not found", ".net sdk", ".net 10", "dotnet_root", "the shader translator does not"],
             title: "The .NET 10 SDK is missing",
             fix: "Install the .NET 10 SDK for Arm64 Macs (brew install --cask dotnet-sdk, or Microsoft's installer); the Toolchain page checks it.", page: .toolchain),
        Rule(code: .python, phrases: ["is missing modules", "capstone", "rosetta", "the nsz tool", "no python with the script's modules", "modulenotfounderror", "cannot start"],
             title: "The converter's Python is incomplete",
             fix: "On the Toolchain page, Fix beside Python modules sets up the converter's own Python with every module the script needs.", page: .toolchain),
        Rule(code: .missingTool, phrases: ["spirv-cross is missing", "glslangvalidator not found", "tools not found", "command not found", "zstd: not found"],
             title: "A tool the build needs is not installed",
             fix: "The Toolchain page lists each tool with a Fix button (most are one brew install). Check it again, then build again.", page: .toolchain),
        Rule(code: .engine, phrases: ["no nxforge engine checkout", "cannot read the engine's git commit", "cannot find the repository root",
                                      "translator is missing from the repository"],
             title: "The NXForge engine checkout is missing or incomplete",
             fix: "Choose the engine folder on the Toolchain page, or clone it there; Update engine brings an old one up to date.", page: .toolchain),
        Rule(code: .memory, phrases: ["killed: 9", "exited with 137", "exited with -9", "out of memory", "cannot allocate memory", "memoryerror"],
             title: "The build ran out of memory",
             fix: "Quit apps that use a lot of memory (games, browsers, Xcode) and build again; the steps that finished are reused."),
        Rule(code: .permission, phrases: ["permission denied", "operation not permitted", "eperm", "read-only file system"],
             title: "macOS refused access to a file",
             fix: "If the game is on an external drive, allow the converter in System Settings › Privacy & Security › Files and Folders (or Full Disk Access). Check the folder is not read-only."),
        Rule(code: .gameStopped, phrases: ["the game stopped after", "heap check", "oodle decode run stopped", "runs the game in the mac host"],
             title: "The game stopped while the build was running it",
             fix: "Some steps start the game briefly to measure it. Copy error summary and report it with the game's version; the end of the error names its log."),
        Rule(code: .rewriter, phrases: ["patch_nso.py exit code"],
             title: "The code rewriter could not convert the game's program",
             fix: "This game version may need a profile change. Copy error summary and report it with the game and its version."),
        Rule(code: .shaders, phrases: ["shader", "dmsh_", "metallib", ".metal:"],
             title: "A shader step failed",
             fix: "Build again with Reuse cached build steps off in Settings. If it fails the same way, Copy error summary and report it with the game's version."),
        Rule(code: .signing, phrases: ["signature check failed", "codesign", "errsecinternalcomponent", "no identity found"],
             title: "The app could not be signed",
             fix: "Choose Ad-hoc (this Mac only) under Sign apps with in Settings, or unlock your login keychain if you sign with a Developer ID.", page: .settings),
    ]

    /// The error first (the script's last red line names the failed step); when it says nothing known, the end of the log.
    static func diagnose(error: String, log: [String]) -> Diagnosis {
        if let d = match(error) { return d }
        if let d = match(log.suffix(40).joined(separator: "\n")), d.code != .stopped { return d }
        return Diagnosis(code: .unknown, title: "The build failed",
                         fix: "The error and the log show the step that failed. Copy error summary to report it, or Copy log for the whole run.")
    }

    private static func match(_ text: String) -> Diagnosis? {
        let t = text.lowercased()
        guard !t.isEmpty else { return nil }
        // a bare "stopped" is the converter's own word for Stop; elsewhere ("the game stopped after") it is not
        if t == "stopped" || t.hasSuffix("[red] interrupted") || t == "interrupted" { return make(rules[0]) }
        for r in rules.dropFirst() where r.phrases.contains(where: t.contains) { return make(r) }
        return nil
    }

    private static func make(_ r: Rule) -> Diagnosis { Diagnosis(code: r.code, title: r.title, fix: r.fix, page: r.page) }

    /// Text safe to paste in a public issue: key-like values and long hex runs go, and so do the keys file's path and the home folder.
    static func redact(_ text: String, keysPath: String? = nil, home: String = NSHomeDirectory()) -> String {
        var s = text
        if let k = keysPath, !k.isEmpty { s = s.replacingOccurrences(of: k, with: "[prod.keys]") }
        // name = value lines of a keys file, and tokens or passwords in URLs and headers
        s = s.replacingOccurrences(of: #"(?i)\b([\w-]*(?:key|kek|secret|token|password)[\w-]*\s*[=:]\s*)["']?[0-9A-Za-z+/=_-]{8,}["']?"#, with: "$1[redacted]", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#, with: "$1[redacted]@", options: .regularExpression)
        // 128-bit keys and longer; title IDs (16 hex digits) stay
        s = s.replacingOccurrences(of: #"\b[0-9A-Fa-f]{32,}\b"#, with: "[hex]", options: .regularExpression)
        if !home.isEmpty, home != "/" { s = s.replacingOccurrences(of: home, with: "~") }
        return s
    }

    /// The lines worth reading first: red lines, errors and tracebacks, then the last lines of the run.
    static func notable(_ log: [String], important: Int = 12, tail: Int = 20) -> [String] {
        let marks = ["[RED]", "error:", "Error:", "Traceback", "failed", "exit code"]
        let hits = log.filter { l in marks.contains { l.contains($0) } }.suffix(important)
        var seen = Set<String>(), out: [String] = []
        for l in Array(hits) + Array(log.suffix(tail)) where !l.isEmpty && seen.insert(l).inserted { out.append(String(l.prefix(600))) }
        return out
    }

    /// The whole summary for Copy error summary.
    static func summary(_ d: Diagnosis, error: String, log: [String], failedStep: String?, game: String?, engine: String?,
                        xcode: String?, keysPath: String?) -> String {
        var l = ["NXForge Converter: build failed", ""]
        l.append("What happened: \(d.title) [\(d.code.rawValue)]")
        l.append("Next step: \(d.fix)")
        if let s = failedStep, !s.isEmpty { l.append("Failed step: \(s)") }
        l.append("")
        if let g = game { l.append("Game: \(g)") }
        if let e = engine { l.append("Engine: \(e)") }
        let info = Bundle.main.infoDictionary
        if let v = info?["CFBundleShortVersionString"] as? String { l.append("Converter: \(v)") }
        l.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if let chip = sysctl("machdep.cpu.brand_string") { l.append("Mac: \(chip), \(ProcessInfo.processInfo.physicalMemory >> 30) GB") }
        if let x = xcode { l.append("Xcode: \(x)") }
        l += ["", "Error:", error, "", "Log (red lines and errors, then the last lines):"]
        l += notable(log)
        return redact(l.joined(separator: "\n"), keysPath: keysPath)
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
