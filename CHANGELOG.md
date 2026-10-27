# Changelog

NXForge releases are tagged `vX.Y.Z` on `main` ([UPSTREAM.md](UPSTREAM.md#versions) has the rules). Each entry lists what NXForge adds on top of [nxnative](https://github.com/seedds/nxnative); upstream's own changes come in through the merges it names.

## Unreleased

**Converter**
- `--cleanup unused|all` (and *After a build* in the converter's settings) tidies `<id>_build/` after a successful build. `unused` deletes other versions' extracted files and rewritten modules (an update replaced by a newer one), half-written folders and the survey; `all` deletes the whole build cache but its logs and profile. The NSPs, `prod.keys`, the app and the save are never touched.

## 0.3.0 (2026-10-27)

Mina the Hollower, the first Yacht Club Games title, and Kirby's Return to Dream Land Deluxe; no upstream merge.

**New games**
- Mina the Hollower (`0100DCD01F306000`, 1.0.5, SDK 21.4.3) converts and boots on the Mac: the intro and the menus, with input. Its profile cuts the 24 GB of address space it reserves at boot (malloc and two engine heaps) to fit the 5 GB block. In bring-up: gameplay is not tested yet.
- Kirby's Return to Dream Land Deluxe (`01006B601380E000`, base game without updates, SDK 13.3.5) converts from a provisional profile and plays on the Mac at 60 fps: the 3D intro, the title and gameplay, with its movies. The first minute of a first launch hitches while Metal builds pipelines. No hand-checked profile yet.

**Engine**
- The shader split reads Yacht Club Games' YCD paks (`.yc`): the shaders of `shaders.pak.yc`.
- A guest thread blocked in the host (the blocking `oe::PopNotificationMessage`) no longer counts as running on its core, so lower-priority threads on that core are no longer held after waking it. Mina the Hollower stayed on a black screen because of it.
- The node-area cut for the SDK 21.4.3 `sdk` build.
- The shader split reads HAL Laboratory's `.cmp` files (a u32 size, then a zstd or LZ4 frame), recognised by their content: Kirby's models, effects and layouts hold 47,099 shaders, where 133 were found before, and without them its title screen and intro were black.
- The survey names files packed that way instead of listing them as unknown, and the shader split prints a `[RED]` line for RomFS files that open with an LZ4 frame or a zlib stream it does not unpack, so a build with shaders missing that way no longer goes quietly to a black screen.

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
