# Changelog

NXForge releases are tagged `vX.Y.Z` on `main` ([UPSTREAM.md](UPSTREAM.md#versions) has the rules). Each entry lists what NXForge adds on top of [nxnative](https://github.com/seedds/nxnative); upstream's own changes come in through the merges it names.

## 0.7.1 (2026-10-30)

Merges nxnative's `main` up to `6d880d2` (102 commits since `beea17c`, 2026-10-29 and 2026-10-30). The notes below are what changes for NXForge.

**From upstream**
- **Mac pipeline archives for this Mac's macOS**: the offline pipeline archive was stamped with the SDK's major version, and Metal 4 opens an archive only on the major version it was made for, so a Mac on macOS 26 building with Xcode 27's SDK made an archive it could not open and compiled every pipeline while playing (shader stutter). The Mac host's minimum macOS is now 26.6 on its compile lines (NXForge's Quick settings object too), so the app opens on macOS 26.
- **Cloud saves**: a game's Mac and iPhone apps can share one save through an iCloud Drive folder (the settings window's Cloud saves, `DM_SAVE_SYNC`). It syncs whichever save folder the game uses, the game folder's `Saves` included.
- **Nintendo controllers by their labels**: a Switch Pro Controller or Joy-Con maps A, B, X and Y by what is printed on them, other pads by position. In NXForge this holds while the face buttons are not remapped in Quick settings' Controls; a remap applies to every pad as before.
- **New game profiles**: Pokémon Violet, Super Monkey Ball Banana Rumble, Mario Party Superstars, Portal 2, Bastion, Batman: Arkham Knight, Team Sonic Racing, Need for Speed: Hot Pursuit Remastered, EA SPORTS FC 27, Streets of Rage 4, Baba Is You, Subnautica and Below Zero, the SteamWorld games and Well Dweller.
- Rendering and host fixes: sampler LOD bias, border colours Metal lacks, NVN logic operations and alpha test, same-pass feedback without per-game lists, render passes into storage-backed textures, DrawTexture, H.264 end of stream, movies held at 30 fps under the frame step, and SDK-wide address-space rules in place of most per-build SDK cuts.
- The NSP script removes the shader libraries of older chain versions after a successful build, reads the title ID of an untagged NSP without a ticket from its meta NCA, and stops on a 32-bit program with upstream's check (NXForge's own `need_aarch64` is gone). `DM_REC` records the player's input as `DM_KEYS` steps.

**Kept from NXForge on top**
- Cartridge (`.xci`) title IDs still come from the cartridge's NCA headers first, so a cartridge with several applications still builds the game; upstream's meta NCA reader is the fallback for other packages without a ticket or tag.
- FXAA's two red-line slots moved to 140 and 141, since upstream took 122 and 123. Anisotropic filtering keeps its floor next to upstream's LOD bias.
- Mina the Hollower keeps its SDK cut row until a build checks that the SDK-wide rules give the same.
- This changes the translation chain version, so each game's next build translates its shaders again.

**Converter**
- Check for updates works after a release branch has merged. The engine checkout could stay on a release branch (such as `release-0.7.0`) whose upstream it could not resolve, and the check failed. While that branch has work `main` lacks, updates follow it; once it is merged they follow `main`, and Update engine switches the checkout to `main`.

**Super Mario Bros. Wonder**
- The game's bundled prewarm list (`pso_manifest.tsv`) was empty, so a fresh build compiled and loaded every pipeline and shader library during play, with 100 ms hitches in the first minutes. It now holds a 30-minute Mac session's list (1,459 shaders, 1,444 render and 18 compute pipelines), prepared in about 0.11 s before the first frame.

## 0.7.0 (2026-10-30)

**Picture quality on the Mac**
- MetalFX upscaling is now on by default in Mac apps and has a live switch in Quick settings (Graphics & shaders), saved together with the settings window's Upscaling choice. Sharpen now works together with MetalFX, sharpening the scaled picture. A new Anti-aliasing row (Off, FXAA; `DM_PRESENT_AA`) smooths jagged edges in games without their own anti-aliasing. Anisotropic filtering defaults to 16x on the Mac until a game's choice is saved ("Game default" keeps the game's own).

**Converter**
- `app/install.sh` builds the converter into `~/Applications` and opens it, so it opens from Spotlight, Launchpad or the Dock; run it again to update.
- The game folder picker (and File > Choose Game Folder…) also takes a game file: pick an `.xci` or `.nsp` and its folder becomes the game folder.

**Faster shader builds**
- The Metal shader step runs its tools (spirv-cross, the Metal compiler) with `posix_spawn` instead of forking the build process: each fork held Python's lock for about 6 ms, so only about half of the compile workers ran at once. Kirby's Return to Dream Land Deluxe (47,099 shaders, M4 Pro): 25:31 → 14:20, with byte-identical libraries.
- Compiled Metal libraries go to one cache for every game, `~/Library/Caches/NXForge/metallib` (`DMSH_MTLCACHE`), kept under 4 GB by dropping the least recently used (`DMSH_MTLCACHE_GB`). It survives a Mac app's cleanup, so rebuilding a game after an NXForge update compiles only the shaders whose Metal source changed: Kirby's rebuild took 5:21. A game's own cache from earlier builds (`shader/cache/cas/metallib`) moves into it on its next build. Two workers compiling the same source now compile it once, and the fetch variants go through the cache too.
- This changes the translation chain version, so each game's next build translates its shaders again (the Metal compiles come from its moved cache).

**Fixes**
- Cartridge dumps (`.xci`) named without a `[title ID]` tag (`Game.xci`) build: the script read the title ID only from a ticket or the file name, and a cartridge has no ticket, so a lone untagged XCI stopped with "no NSP with a readable title ID". It now reads the title ID from the XCI's own NCA headers with prod.keys' `header_key`. Game file extensions match in any case (`Game.XCI`).
- A cartridge with its update on it (1G+1U) shows as the base game in the converter's file check, not as an update with "no base game in the folder".
- Cruis'n Blast no longer stops after a race: its name entry's China-region profanity check (`nn::ngc::CheckProfanityWordsInTextForPlatformRegionChina`, and the matching mask) went to the `ngct:u` service, which the host does not serve; the host now answers both itself (no profanity, nothing masked).
- The Mac pipeline archive step checks free disk space before metal-tt starts and names a full disk when metal-tt fails, instead of only "applegpu-nt command failed" (Cruis'n Blast's 33,858 bases failed with 366 MB free). A failed run's temporary files are cleared from `pso/mac-work`.
- A cartridge holding several applications builds the game, not the first title ID: Castlevania: Belmont's Curse's Midnight Edition holds the game (0100BA4026E94000) and its Digital Sound & Art Gallery (01005F4027E94000), and the gallery was built. The script now takes the application with the largest program and tells `nx_extract` which one (`--title`).
- Unity 6000.3 games whose player files carry no type trees and whose bundles hold no `Shader` (Castlevania: Belmont's Curse) split their shaders: the split stopped with "no bundle has a Shader type tree of the same hash to borrow". `unityfs.py` now has 6000.3's `Shader` layout (version 4 adds the object's local identifier) and `ComputeShader` layout (a resource type per resource), checked against AssetRipper's release dumps.

## 0.6.0 (2026-10-28)

Merges nxnative's `main` up to `beea17c` (245 commits since `9a56ecf`). Most of what this brings is upstream's own work; the notes below are what changes for NXForge.

**From upstream**
- **A settings window before the game** in Mac apps (`dm/mac/Launcher.swift`): frame rate, render scale, docked or handheld, game language, display mode, MetalFX upscaling and the rumble cutoff, saved per game. `DM_LAUNCHER=0` or `--no-launcher` starts the game without it.
- **About 30 new game profiles** (Kirby and the Forgotten Land, Xenoblade Chronicles 2, 3 and Definitive Edition, Pokémon Legends: Arceus, Scarlet and Shield, Super Mario Party Jamboree, Paper Mario: The Origami King, Mario + Rabbids Kingdom Battle and Sparks of Hope, Donkey Kong Country Returns HD and Tropical Freeze, Sea of Stars and others), NSZ executables, RomFS images instead of loose files, an offline pipeline archive in Mac apps, controller motion (gyro), DualShock 4 rumble, and many host, shader and frame-pacing fixes.
- Upstream fixed three things NXForge had fixed its own way, and its versions replace ours: rumble on controllers without advanced haptic players (NXForge's 8BitDo SN30 Pro fallback), the rewriter's copy-before-check search (NXForge's 128-instruction window for Curse of the Moon's GLSLC), and HAL's `.cmp` shader containers (NXForge's Kirby's Return to Dream Land Deluxe reader). The blocking wait in `oe::PopNotificationMessage` (Mina the Hollower) also uses upstream's native HLE wait now.

**Kept from NXForge on top**
- Quick settings, filters, anisotropic filtering, cheats, captures, controls, mods and game-folder saves work as before, alongside upstream's settings window.
- Rumble permission is still given before a controller connects (Bloodstained: Curse of the Moon asks only once at startup); upstream ties it to a connected controller.
- In fullscreen the display link stays off, as in NXForge's 60 fps fix, rather than upstream's frame latency 2 (which settled at about 42 fps on Mario vs. Donkey Kong here). `DM_PRESENT_LATENCY=<n>` keeps the link at that latency, to compare.
- MetalFX upscaling applies only while the present filter is off, since the filters work on the game's own pixels.

**Fixes**
- **Quit game** no longer stays armed after the sidebar is closed and opened again: the first press after reopening arms it again.
- The iPhone build compiles again: the cheats engine used `mach_vm.h`, which the iPhone SDK does not have (upstream's new CI caught it).

## 0.5.0 (2026-10-28)

Ideas from other nxnative front ends (NX Play, the NxNative Launcher and NX2Apple, all MIT), reimplemented for NXForge; no upstream merge.

**Converter**
- **Keep this build** (after NX Play): an app that plays well can be kept as it is. It shows a lock instead of the "older" badge, Rebuild all and its count pass it by, and Rebuild asks before replacing it. A switch in the build's detail panel, or the right-click menu on Builds.

**In the game**
- **Quit game** in Quick settings (after the NxNative Launcher's couch exit): Home opens the sidebar, and Quit game, pressed twice, ends the game as ⌘Q does.
- **Mods as downloaded**: a mod folder holding Atmosphere's layout (`atmosphere/contents/<title ID>/romfs`, or `contents/<title ID>/romfs`, or `<title ID>/romfs`) overlays that `romfs` folder, so a mod unzipped as it comes works without moving its files.

**Project**
- Issue forms for a game problem and a converter or build problem (after NX2Apple's), each asking for the log or Copy diagnostics and confirming nothing attached holds keys or game files.

## 0.4.0 (2026-10-27)

Build-cache cleanup in the converter and a clear stop on 32-bit game versions; no upstream merge.

**Converter**
- `--cleanup unused|all` (and *After a build* in the converter's settings) tidies `<id>_build/` after a successful build. `unused` deletes other versions' extracted files and rewritten modules (an update replaced by a newer one), half-written folders and the survey; `all` deletes the whole build cache but its logs and profile. The NSPs, `prod.keys`, the app and the save are never touched.
- A 32-bit (AArch32) game version stops the build with a message that names the versions the game's profile registers, instead of crashing in the symbol reader (`KeyError: 6`). Apple Silicon runs only 64-bit Arm code; Mario Kart 8 Deluxe 3.0.1 is one such version.

**Games**
- Mario Kart 8 Deluxe (`0100152000022000`): 4.0.1 packs from a profile derived from 4.0.0's and runs at 60 fps on the Mac; only 3.0.1 is ruled out.

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
