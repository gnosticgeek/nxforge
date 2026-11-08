// iPhone and iPad (idea 20): the same game as an unsigned IPA (--platform ios), beside the game files, for AltStore, Sideloadly
// or Xcode. It shares the game's build cache with the Mac app (extraction and the rewritten code are reused; the iOS shaders are
// its own), needs Xcode's iOS platform, and replaces or records nothing: the Mac app and the Builds list stay as they are.
import AppKit
import Foundation

extension AppModel {
    /// Whether this engine's script can make an IPA (it always could; checked so an odd checkout fails with words, not a usage line).
    var canBuildIPA: Bool { ready }

    func buildIPA() {
        guard let env, let dir = settings.gameDir, ready else { return }
        guard confirm("Build an iPhone and iPad IPA?", "The converter builds \(game?.name ?? "this game") as an unsigned IPA beside its files, for AltStore, Sideloadly or Xcode. It reuses the Mac build's extracted game and code; the iOS shaders compile on their own, so a first IPA takes about as long as a first Mac build. It needs Xcode's iOS platform (Xcode › Settings › Components). The Mac app is not touched.", action: "Build IPA") else { return }
        run.start(Job(gameDir: dir, keys: needsKeys ? settings.keys : nil, sign: nil, env: env, reuseCache: true, gameFiles: source?.describe, ios: true, gameBytes: gameBytes))
    }

    /// An IPA build ended: show the IPA in Finder; the game stays on Convert.
    func ipaEnded(_ r: Result<String, ConverterError>) {
        if case .success = r, let p = run.ipa { reveal(p) }
    }
}
