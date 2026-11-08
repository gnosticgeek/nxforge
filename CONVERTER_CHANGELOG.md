# NXForge Converter changelog

The NXForge Converter (the Mac app under `app/`) has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `converter-vX.Y.Z` and a GitHub release "NXForge Converter X.Y.Z". The app shows its version under the NXForge name in its sidebar and in About NXForge Converter. The NXForge release that first ships a converter version is named in its entry.

What counts as the converter: everything under `app/` (the SwiftUI app, its tests, `bundle.sh`, `install.sh` and `make_icon.swift`).

## 0.2.0 (2026-11-08)

Twenty improvements, some from other nxnative forks' ideas. Ships in NXForge 0.17.0.

- **What's New and updates:** this sheet, shown once after the converter changes; Help › Update NXForge Converter… rebuilds it from the engine checkout (or its update branch) and opens the new one, with an "available" capsule over the sidebar.
- **A new look for Library and Builds:** big headings over banners of their own (an aurora, a moonlit sea), glass filter chips, and a sort menu.
- **Covers:** the Library as a grid of game icons on their own colours, with Play or Convert on hover, a check for built games and a focus ring; or the list, as before.
- **A page per game:** double-click (or Return) on a game in the Library or Builds opens one page with everything about it over a backdrop tinted from its icon.
- **Launch settings** on the game page: the game's own settings window's choices (resolution, frame rate, controls and the rest), set without opening the game, and "Show this window at launch".
- **Playtime:** each session of a built game is timed while the converter is open, however the game was started; Continue Playing over the Library, Recently played order, and a weekly chart on the game page.
- **Is a rebuild worth it?** The engine commits since a build that touch what that game's build reads, its own profile's changes marked, with a verdict and how long the last build took.
- **NXForge notes:** the game's profile README (what it is, open issues) on the game page and on Convert before a long build.
- **Menu bar progress:** a build's percent in the menu bar (only while a build runs); click it for the time left, the step, Show Log and Stop Build.
- **Notifications with actions:** Play and Show in Finder on a finished build; Show Log and Copy Error Summary on a failed one.
- **Build later:** Build selected tonight at 2:00, at a time, or once the Mac is on power; the Mac stays awake while it waits, the queue survives a quit, and games in it can be moved up, down or out.
- **Offline drives:** a games folder or game files on a drive or share that is away say so, with Mount (the address is remembered) and Locate Game Files…; Rebuild asks instead of failing.
- **Save import and export:** a save as one zip, or in from a zip, a folder or another Mac's save, with a side-by-side preview; checked and kept as snapshots both ways.
- **Git save backup:** with a repository chosen in Settings › Saves, a game's save is committed (and pushed, if chosen) each time the game quits, or from Back Up to Git Now.
- **Go to Anything (⌘K):** any game, built app, page or action by typing a few letters.
- **Controller and couch mode (⇧⌘F):** the covers full screen; the pad moves, A opens or plays, B goes back, X plays, Y previews, Menu leaves.
- **Undo for tidying:** moving a game into its own folder, or its update and DLC beside it, can be undone (Undo under the list, or ⌘Z); every move is logged.
- **Keyboard and preview:** arrow keys move between games, Space shows a quick preview (in Builds too), Return opens the game's page, ⌘[ goes back.
- **Performance history:** the game page charts every play session's frame rate, with Copy Report.
- **iPhone and iPad IPA:** Build › Build iPhone and iPad IPA… (⌥⌘B) builds the chosen game for iOS (`--platform ios`) and shows the .ipa to sideload.

## 0.1.0 (2026-11-07)

The first versioned converter: the app as it is in NXForge 0.15.0, now numbered on its own. Ships in NXForge 0.16.0.

- **Convert:** drop or choose a game folder, a Switch 2 `.nup` or a dump folder; keys are checked in under a second without showing any key; Build Mac app shows one bar with the time left, with the steps and a filterable log under Show details; Preview build lists which steps a rebuild would reuse.
- **Library:** every game under a games folder with its own name, icon, publisher and version, badges for plays / profile / older engine / newer update, Build selected as a queue with a free-space estimate, and one-click tidying of shared folders and loose DLC.
- **Builds:** every app built with its engine release, Rebuild and Rebuild all on older engines, previous builds kept as backups to restore, Keep this build, save snapshots, frame-time summaries and failure explanations with Copy error summary.
- **Toolchain:** each tool checked the way the script finds it, Fix and Set up (the converter's own Python), the engine's version with Check for updates and Update engine, and Copy diagnostics.
- **Storage:** build caches, older app copies, apps and the shared Metal cache with sizes and free space, and Clean Up; a build warns below 12 GB free and stops below 3 GB.
- **Mac app:** Settings window (⌘,), pages on ⌘1 to ⌘5, Build menu, Dock progress, guarded quit during a build, and the navy theme of the Convert, Toolchain and Storage pages.
