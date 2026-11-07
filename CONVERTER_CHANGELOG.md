# NXForge Converter changelog

The NXForge Converter (the Mac app under `app/`) has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `converter-vX.Y.Z` and a GitHub release "NXForge Converter X.Y.Z". The app shows its version under the NXForge name in its sidebar and in About NXForge Converter. The NXForge release that first ships a converter version is named in its entry.

What counts as the converter: everything under `app/` (the SwiftUI app, its tests, `bundle.sh`, `install.sh` and `make_icon.swift`).

## 0.1.0 (2026-11-07)

The first versioned converter: the app as it is in NXForge 0.15.0, now numbered on its own. Ships in NXForge 0.16.0.

- **Convert:** drop or choose a game folder, a Switch 2 `.nup` or a dump folder; keys are checked in under a second without showing any key; Build Mac app shows one bar with the time left, with the steps and a filterable log under Show details; Preview build lists which steps a rebuild would reuse.
- **Library:** every game under a games folder with its own name, icon, publisher and version, badges for plays / profile / older engine / newer update, Build selected as a queue with a free-space estimate, and one-click tidying of shared folders and loose DLC.
- **Builds:** every app built with its engine release, Rebuild and Rebuild all on older engines, previous builds kept as backups to restore, Keep this build, save snapshots, frame-time summaries and failure explanations with Copy error summary.
- **Toolchain:** each tool checked the way the script finds it, Fix and Set up (the converter's own Python), the engine's version with Check for updates and Update engine, and Copy diagnostics.
- **Storage:** build caches, older app copies, apps and the shared Metal cache with sizes and free space, and Clean Up; a build warns below 12 GB free and stops below 3 GB.
- **Mac app:** Settings window (⌘,), pages on ⌘1 to ⌘5, Build menu, Dock progress, guarded quit during a build, and the navy theme of the Convert, Toolchain and Storage pages.
