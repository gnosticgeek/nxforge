# NXForge Converter changelog

The NXForge Converter (the Mac app under `app/`) has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `converter-vX.Y.Z` and a GitHub release "NXForge Converter X.Y.Z". The app shows its version under the NXForge name in its sidebar and in About NXForge Converter. The NXForge release that first ships a converter version is named in its entry.

What counts as the converter: everything under `app/` (the SwiftUI app, its tests, `bundle.sh`, `install.sh` and `make_icon.swift`).

## 0.6.0 (2026-11-11)

Ships in NXForge 0.27.0.

- **A game's `DLC` subfolder counts.** The build now reads a subfolder named `DLC` or `DLCs` (any letter case) for the game's DLC, and the converter follows: the Convert page checks those files with the rest (shown as `DLC/<name>`), the Library counts them as the game's DLC instead of noting them as unused and offering to move them, and the build history's "Base game + 2 DLC" includes them. A base game or update put in that folder is flagged as not used, with Move Beside the Game still offered for it.

## 0.5.2 (2026-11-09)

Ships in NXForge 0.23.0.

- **Save snapshots follow a save kept off a non-APFS drive.** For a game whose folder is on an exFAT, FAT or HFS+ drive the launcher now keeps the save in the Library (NXForge 0.23.0), and the Saves tools look there too.

## 0.5.1 (2026-11-09)

Fixes for 0.5.0. Ships in NXForge 0.22.0.

- **A Switch 2 dump folder is read in seconds.** "Reading the game's container…" walked every file of the dump twice, one `stat` at a time, to size it: Mario Kart World's dump (411,696 files) on an exFAT drive took over five minutes. The game now shows as soon as its code and title are read, the Convert page says "measuring the game files…" while its size comes in the background, and that measure is one walk that gets each folder's sizes with its listing (`getattrlistbulk`): 18 s for the same dump. Choosing the game again reuses the measure while the folder is unchanged.
- **Check for updates survives a deleted branch.** An engine checkout whose remote fetches only named branches failed every check ("Check failed") once one of those branches was deleted on GitHub, since git refuses the whole fetch. The check now fetches again with every branch, and a failure shows git's own message.
- **No more 8-hour estimates for a big game.** A build's time left was scaled from other games' builds by size, however far apart: Bloodstained's 93 s for 47 MB made Mario Kart World's 24 GB look like 8 h 42 min. Only games within four times the size count now.
- **Get Upstream Now names every clashing patch.** When upstream's commits clash with NXForge's patches, the page listed only the last one the check reported (for example "0009-docs.patch: conflicts") although others clashed too. It now reads the whole report and lists each patch once.

## 0.5.0 (2026-11-09)

Ships in NXForge 0.21.0.

- **Get Upstream Now.** The Updates page's upstream line has a button that takes upstream nxnative's newest commits on this Mac, without waiting for an NXForge release. It first checks that every NXForge patch still applies to them; if one clashes, nothing changes and the page names the patches (NXForge has to update them first, which the daily sync does). If they all apply, the engine is assembled on upstream and the host unit tests run on it. The engine row then reads "+ upstream", games count as built on another engine until rebuilt, and **Back to <release>** returns to the release's engine. Updating the engine to a newer release ends it by itself.

## 0.4.1 (2026-11-08)

A fix for 0.4.0. Ships in NXForge 0.20.1.

- **Free space on network shares and non-APFS drives is read right.** macOS gives its "important usage" free space only for APFS volumes, so a game on an SMB share or an output folder on an exFAT drive read as 0.0 GB free: the converter asked "Build with too little free space?" and, during a build, could stop it as soon as it started. It now takes the plain free space there (the same as Finder and `df`), in the space check, the build's watch, Storage and save snapshots.
- **A game on a network share builds on a local drive.** macOS marks every file written to an SMB share as downloaded, so Gatekeeper killed the tools a build compiles for itself ("Apple could not verify nx_extract", exit -9 at the build ID lookup). For a game folder on a network share, the build folder (and the survey of a game without a profile) now goes to `NXForge Builds/<game folder>` in the output folder (or in ~/Documents when the output folder is on a share too), via the script's `--work-dir`; the game files are only read. Storage, the Builds page's times and the space check look there.
- **Each drive is checked for its own share of a build.** With the output folder on another drive, the build folder (beside the game files) and the app (in the output folder) are checked against their own drives, and the shared Metal cache against the home folder's, instead of the whole build against the game folder's drive. Changing the output folder checks again.

## 0.4.0 (2026-11-08)

For NXForge's new layout (an untouched nxnative engine plus NXForge's layer). Ships in NXForge 0.19.0.

- **Builds use the assembled engine.** Before a build, and in the tool check, the converter runs `scripts/layer.py assemble`, then builds in `tree/`. If assembling fails, the tool check says why and how to fix it.
- **Game notes, profiles and the library read the engine's files** from `tree/` (or `layer/files/` before the first assemble).
- **Updates:** "what changed" for a game understands a new engine pin and changed patches, the sidebar's version is read from its new place, and the upstream count is counted from the pinned commit.
- A checkout from before 0.19.0 still works as it did.

## 0.3.1 (2026-11-08)

A fix for 0.3.0. Ships in NXForge 0.18.1.

- **The pages in the sidebar can be clicked again.** 0.3.0's Updates count badge took the rows' tags, so the list could not select any page.

## 0.3.0 (2026-11-08)

One updater for everything. Ships in NXForge 0.18.0.

- **Updates page** (⌘6, and Help › Check for Updates…): the engine, the converter and the in-game sidebar side by side, each with its version, what is newer and its own Update button. The sidebar item shows how many updates wait.
- **The engine follows NXForge releases.** Check and Update go to the newest `vX.Y.Z` tag on main, never to a release PR merged but not tagged yet. Update fetches first and checks again afterwards, so the status says "Updated to 0.17.1" and then shows anything that landed meanwhile, instead of a stale "Updated". The page also says how many upstream nxnative commits NXForge has not merged yet (for information; they come with the next NXForge release).
- **A sheet at launch** when the converter or the engine has a newer release: what changed, with Update and Relaunch, Later and Skip This Version.
- **Update automatically** (on the Updates page or in the sheet): at launch and when the converter comes back to the front an hour or more after the last check, the engine and the converter update without asking, never while a build runs.
- **Sidebar in your games:** lists the built games whose sidebar is older than the engine's and rebuilds them one after another with Update Sidebar in N Games (their cached stages are reused). Kept builds are left alone.
- The capsule over the sidebar now opens the Updates page, and also appears for a new NXForge release.

## 0.2.1 (2026-11-08)

A fix for 0.2.0. Ships in NXForge 0.17.1.

- **No more hang at launch.** 0.2.0 stopped answering for 20 seconds or more each time it started: SwiftUI's menu bar item for build progress kept redrawing its button. The progress is now a plain status item, made only while a build runs (click it for the time left, the step, Show Log and Stop Build).

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
- **Menu bar progress:** a build's percent in the menu bar, with the time left, the step, Show Log and Stop Build.
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
