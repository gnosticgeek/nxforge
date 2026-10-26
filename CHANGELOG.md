# Changelog

NXForge releases are tagged `vX.Y.Z` on `main` ([UPSTREAM.md](UPSTREAM.md#versions) has the rules). Each entry lists what NXForge adds on top of [nxnative](https://github.com/seedds/nxnative); upstream's own changes come in through the merges it names.

## 0.2.0 (2026-10-26)

The NXForge Converter release: everything since 0.1.0 is in the converter app (`app/`); the engine and the game profiles are as in 0.1.0, and there is no upstream merge.

**Engine versions you can read**
- Engines and builds show as releases: `0.2.0` at a release tag, `0.2.0+3` three commits after it, `pre-0.1.0` for anything built before the first release. The commit is in the tooltip.
- Build records from before release tags get their version from the engine's history, also when the checkout they were built from has moved (nxnative-src → NXForge).
- The converter checks the engine's branch for updates when it opens, and shows the newest release's first change from this changelog.
- The converter's own version is the engine's release tag.

**Rebuilding**
- Rebuild is the large blue button whenever an app was built on an older engine, on Convert and on Builds.
- Builds marks those apps with an "older" badge, and **Rebuild all** rebuilds them one after another; a failure stops the rest and says which game.
- A right-click on an app in Builds opens it, shows it in Finder, rebuilds it, removes it from the list or moves it to the Trash.

**Converting**
- A finished build clears the Convert page (folder, keys, file check, activity) and opens Builds on the new app; a failed build stays on Convert with its stages and log.
- Drop a game folder, or a file in it, on the window or the Dock icon to convert it.
- Convert shows the free disk space and what the build needs (a first build: about twice the game files plus 10 GB), in orange when it is short.
- The build's progress shows on the Dock icon, with the step number as a badge.
- An update NSP tagged with the base game's ID and only a version above v0 (Cyber Shadow) counts as an update.

**Setup and everyday use**
- **Set up** on Toolchain makes the converter's own Python (a venv in Application Support with lz4, capstone, fontTools, zstd and nsz), so it depends on no other copy of Python.
- A Build menu: Build Mac App (⌘B), Rebuild (⌘R), Rebuild All on Older Engines, Stop Build (⌘.), and ⌘O to choose a game folder.
- An app icon.

## 0.1.0 (2026-10-26)

The baseline release: nxnative's main branch as merged on 2026-10-25, plus:

- **Quick settings sidebar** on the Mac (Esc, ⇧⌘G or the Graphics menu; Liquid Glass on macOS 26 and later), with controller and keyboard navigation and remappable keys and buttons per game.
- **Picture filters:** Sharpen, Pixel-perfect, CRT, CRT-Lottes, LCD Grid and scanlines, saved per game.
- **Anisotropic filtering floor** for every game's samplers (`DM_ANISO`), with a per-game row in the sidebar.
- **Cheats:** Atmosphere dmnt cheat codes from Markdown files, one per game build ([docs/cheats.md](docs/cheats.md)).
- **Mods:** RomFS replacement folders per game.
- **Capture:** screenshots (⇧⌘S) and recordings with sound (⇧⌘R).
- **Game folder:** saves, screenshots and recordings beside the game's app.
- **Volume** control in the sidebar.
- **Rumble:** controller vibration handles opened before the controller connects, and a plain Core Haptics player for controllers that refuse the advanced one (8BitDo SN30 Pro).
- **Full screen at 60 fps** on 120 Hz ProMotion displays (no display link while full screen; also sent upstream as seedds/nxnative#194).
- **NXForge Converter:** a SwiftUI Mac app that checks the tools and game files, builds and rebuilds game apps, and shows which engine version each was built on.
- **NXForge name:** bundle IDs `org.nxforge.<title ID>` (Quick settings carried over from the old ID), NOTICE, and the upstream policy.
