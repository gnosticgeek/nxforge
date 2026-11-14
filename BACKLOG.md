# Backlog

Work planned or in flight on NXForge (gnosticgeek/nxforge, formerly
gnosticgeek/nxnative). Upstream is [seedds/nxnative](https://github.com/seedds/nxnative);
[UPSTREAM.md](UPSTREAM.md) has the contribution policy. Last updated 2026-11-14 (0.33.0 in progress: engine up to nxnative 8d89c3c; 0.30.2: Converter 0.6.2, Delete button visible on delete questions; 0.30.1: aspect ratio choice, NUP update icon, Ocarina PRs #2622 and #2625 and Mario Kart World #2621 taken early; 0.30.0: engine up to nxnative ce38664, Ocarina PRs #2344 (revised), #2497, #2456, #2538 and #2532 taken early; 0.29.1: frame interpolation turns itself off where full screen cannot hold 120 refreshes; 0.29.0: pixel art, with the art's own grid and MMPX; 0.28.3: frame interpolation no longer crashes a game going full screen; 0.28.2: Ocarina GPU memory low-water guard, upstream #2344 early, Sidebar 0.3.3; 0.28.1: settings window redesign with General, Graphics and Advanced tabs; 0.28.0: engine up to nxnative 637f3fa; 0.27.4: 120 fps frame interpolation, picture options in the settings window, Sidebar 0.3.2; 0.27.3: full screen hides the title bar, Sidebar 0.3.1; 0.27.1: engine up to nxnative f75ac06; 0.27.0: DLC subfolder read by the build, Converter 0.6.0; 0.26.0: engine up to nxnative 084f5aa; 0.25.0: engine up to nxnative c4ffb9d; 0.23.1: GPU memory guard measures the residency set, upstream PR #1615 as a patch; 0.22.0: engine up to nxnative d9cd9de, Converter 0.5.1 clash list; 0.21.0: Converter 0.5.0 Get Upstream Now, `layer.py local`; 0.20.0: engine up to nxnative 028a263, `layer.py continue`; 0.17.1: Converter 0.2.1 launch-hang fix; 0.17.0: Converter 0.2.0 and Sidebar 0.2.0; 0.16.0: sidebar versioned on its own; 0.15.0: thin fork, upstream main up to bd979ce).

Keep this file current: every release PR updates the rows its changes touch and the
"Last updated" line ([UPSTREAM.md](UPSTREAM.md#versions); `scripts/release_check.py` checks it).

Status key: **Upstream PR open**, **On fork main**, **On branch**, **Next**,
**Idea**, **Research**.

## Upstream contributions

| Item | Status | Notes |
|---|---|---|
| Full-screen 60 fps fix | Closed upstream, on fork main | [#194](https://github.com/seedds/nxnative/pull/194) was closed on 2026-10-28: upstream keeps the display link in fullscreen with frame latency 2 (f748a055). NXForge still presents without the display link in fullscreen. |
| NXForge Converter app | Declined upstream, on fork main | [#209](https://github.com/seedds/nxnative/pull/209) was closed on 2026-10-28: upstream wants front ends in their own repositories (CONTRIBUTING.md, "Graphical front ends"). The converter stays in `app/`. |
| Swift rewrite of the Converter | On fork main | SwiftUI app (macOS 26+, Liquid Glass): Convert, Builds, Toolchain, Settings, in `app/` since 0.2.0. |
| Rumble fix | Mostly superseded by upstream | Fork PR #1 (merge 5bc2563). Vibration handles before the controller connects, plus a plain Core Haptics player fallback for controllers that refuse advanced players (8BitDo SN30 Pro). Verified in MvDK and Curse of the Moon. PR body drafted (`nxnative-pr/rumble-pr.md` in project files). Since the 0.6.0 merge upstream's plain-player fallback (#363) and startup handles (#246) replace ours; only the permission before a controller connects is still NXForge's, a small PR candidate. |
| Rewriter jump-table fix (49a670a) | Superseded by upstream | Upstream follows the copy to the function start (Mario + Rabbids Kingdom Battle's GLSLC, the same code as Curse of the Moon's); the 0.6.0 merge takes theirs. Nothing to send. |
| Filters + Quick settings sidebar | On hold for upstream | Tom holds the upstream PR until the sidebar is finished (see the next section). |
| Cheats engine | Replaced by upstream's (0.9.0) | Upstream's `hle_cheats.c` (PR #406) took over from NXForge's Markdown engine; the sidebar's Cheats section now shows upstream's rows, and `dm/tools/cheats_md.py txt` converts old Markdown files. |
| Read marks aged above a quarter of the working set ([#2344](https://github.com/seedds/nxnative/pull/2344), revised) | Upstream PR open, carried as patch 0014 (0.28.2, revised in 0.30.0) | Ocarina of Time area loads froze late in a session. Drop `layer/patches/0014-upstream-pr-2344.patch` when nxnative lands #2344. |
| Ocarina: 60-picture movies at a 30 fps cap ([#2622](https://github.com/seedds/nxnative/pull/2622)), prewarm keeps its pipelines at quit ([#2625](https://github.com/seedds/nxnative/pull/2625)); Mario Kart World 1.8.0 build row ([#2621](https://github.com/seedds/nxnative/pull/2621)) | Upstream PRs open, carried as patches 0022-0024 (0.30.1) | Drop each patch when nxnative lands it. |
| Ocarina: full model heap retry ([#2497](https://github.com/seedds/nxnative/pull/2497)), movie pictures a frame ([#2456](https://github.com/seedds/nxnative/pull/2456)), wide screen ([#2538](https://github.com/seedds/nxnative/pull/2538)), render scale above native ([#2532](https://github.com/seedds/nxnative/pull/2532)) | Upstream PRs open, carried as patches 0016-0019 (0.30.0) | Drop each `layer/patches/00NN-upstream-pr-NNNN.patch` when nxnative lands it; #2538 and #2532 both change the frame step stub's others, so check them together. |
| GPU memory guard measures the residency set ([#1615](https://github.com/seedds/nxnative/pull/1615)) | Upstream PR open, carried as patch 0011 (0.23.1) | Ocarina of Time was stopped at a false 17.5 GB (residency set 6.7 GB). Drop `layer/patches/0011-upstream-pr-1615.patch` when nxnative lands #1615. |
| Merge upstream main | On fork main (0.14.0) | Last merges: seedds/nxnative main at d777f0a plus picks up to 32335650, and open Mario Kart World pull requests (#1594, #1229, #1179, #1230). Choices are in CHANGELOG 0.14.0. |
| China-region profanity check (Cruis'n Blast) | Closed upstream ([#789](https://github.com/seedds/nxnative/pull/789)), its fix landed there | Branch `contrib/ngc-china-profanity`, from c86bc9b. |
| pso_offline free-space check | Closed upstream ([#790](https://github.com/seedds/nxnative/pull/790)), its fix landed there | Branch `contrib/pso-offline-free-space`, from fde1e63. |
| Unity 6000.3 shader layouts | Closed upstream ([#791](https://github.com/seedds/nxnative/pull/791)), its fix landed there | Branch `contrib/unity-6000-3-shaders`, from f6388f2. |
| bench.py offline pipeline archive | Closed upstream ([#792](https://github.com/seedds/nxnative/pull/792)), on fork main | Branch `contrib/bench-pso-bundle`, from 2309513. |
| Thin-fork upstream PRs | Ready for Tom to open | Branches `contrib/vp9-late-free`, `contrib/gpu-watchdog`, `contrib/dirty-page-pool-bounds`, `contrib/c1-tables-stable-bytes`, each one commit on nxnative `main` bd979ce; bodies in project files `nxnative-pr/0.15/`. NXForge keeps its copies until upstream lands them. |
| Thin-fork: still to prepare | Next | Anisotropic filtering floor (needs an nxnative issue first), incremental pipeline archive and shared Metal cache, GameData.bundle signing, Mina the Hollower and Kirby's Return to Dream Land Deluxe profiles. |
| Fullscreen 60 fps: ours or upstream's | Needs a hands-on check | Upstream keeps the display link in fullscreen (490859e and earlier). Compare a 60 fps game at 120 Hz fullscreen with and without `DM_PRESENT_LATENCY=2` (upstream's path); drop NXForge's no-link mode if upstream's holds 60. |
| Next upstream candidates | Next | Anisotropic filtering floor, untagged and multi-application XCI dumps, the shader build speed-up with a shared Metal cache, the rumble permission before a controller connects. The present filters and MetalFX defaults need an issue first (over about 1,000 lines). |

## Quick settings sidebar and filters

Branch `claude/project-thread-skozua`. Merged into fork main in full on 2026-10-26 (earlier up to 8a5a4dd via
fork PR #2), including the controller navigation, key remap and game-folder
work below.

| Item | Status | Notes |
|---|---|---|
| SwiftUI sidebar with Liquid Glass (Esc, ⇧⌘G, Graphics menu) | On fork main | `dm/host/quick_settings.swift`. Material fallback before macOS 26. |
| Filters: Sharpen, Pixel-perfect, CRT, scanlines | On fork main | Tested in Curse of the Moon; no measurable cost. |
| Filters: CRT-Lottes, LCD Grid, scanline fade | On fork main | Lottes is public domain. Not tried in a running game yet. |
| Capture: screenshots ⇧⌘S, recording ⇧⌘R | On fork main | Needs a hands-on check in game. |
| Volume | On fork main | Needs a hands-on check. |
| Controller navigation (Home or −/+ opens) | On fork main | 367f518. Cheats added to the navigation list in 6e6be90. |
| Key and button remapping, per game | On fork main | 367f518. Not tried in game yet. |
| Saves, screenshots, recordings in the game folder | On fork main | c4940d7, 4529349. Old Library save is copied once, never moved. Waiting on Tom to confirm progress, rumble, a screenshot and a recording in the rebuilt Curse of the Moon. |
| Mods section (romfs folders per title) | On fork main | Untested with a real mod. |
| Open the upstream PR | Next | Branch merged into fork main 2026-10-26. Still wants Tom's hands-on checks. Split 49a670a out first. |

## Ideas from other front ends

From a review on 2026-10-28 of [NX Play](https://github.com/varyform/nx-native-wrapper), the [NxNative Launcher](https://github.com/rennan101/nxnative_Launcher) and [NX2Apple](https://github.com/LNPANDY/NX2Apple), all MIT. Done in 0.5.0: Keep this build, Quit game in Quick settings, Atmosphere-layout mods, issue forms. A second look at NX2Apple (0.7.4) on 2026-10-31 gave the five rows done in 0.10.0. [LumaNX](https://github.com/Xc1Ym/LumaNX) (MIT, reviewed 2026-11-05) gave the two rows marked Unreleased.

| Item | Status | Notes |
|---|---|---|
| Failure explanations and Copy error summary | On fork main (0.11.0) | LumaNX `Worker/diagnostics.py`: the cause, the next step and a redacted summary on Convert (`BuildDiagnosis.swift`). |
| Save snapshots with a checked restore | On fork main (0.11.0) | LumaNX `Worker/recovery.py`: SHA-256 checked copies in `save-snapshots/`, restore by `RENAME_SWAP`, automatic before a rebuild and Restore this version (`SaveSnapshots.swift`). Needs a hands-on restore in a real game. |
| Self-contained converter download | Idea | LumaNX bundles Python, spirv-cross, zstd and a prebuilt NSP reader so only Xcode is needed, in a DMG with a check that nothing links to Homebrew (`scripts/bundle_runtime.py`, `runtime_audit.py`). Only if NXForge is for other people. |
| Save backup to a private Git repository | Idea | NX Play: while a game plays, copy its save into `<slug>-<title ID>/` of a clone you choose each time it saves, commit and push, once more on quit. NXForge could do it from the launcher (`dm/mac/launcher.c`) or the converter, watching `Saves/save` in the game folder. |
| Copy saves between the Mac and an iPhone or iPad | Idea | NX Play and the Launcher: `xcrun devicectl device copy from/to --domain-type appDataContainer`, comparing both sides file by file first and keeping the replaced save. Needs an IPA build path in the converter. |
| Install on a device and Build IPA from the converter | Idea | NX Play, NX2Apple, Launcher. The script already builds IPAs; the converter only makes Mac apps. |
| Console mode: a controller-driven library | Idea | NX Play and the Launcher: a full-screen carousel of built games with key art, driven by a controller (A plays, B backs out), last played first. NXForge's Builds page plus controller navigation like the sidebar's. |
| Game metadata from the control data | Idea | NX Play reads `control.nacp` (title, publisher, display version, supported languages). Lets Builds show the real title and version, and a language picker list only the game's languages. |
| Custom cover art | Idea | The Launcher: pick any image as a game's art, kept per title ID. |
| Nightly upstream check | On fork main (0.8.0) | NX2Apple and the Launcher run a daily job that test-merges upstream and opens a PR, or an issue naming the conflict. Would have flagged the 245-commit gap early. |
| Per-game launch settings | On fork main (0.6.0) | Game language, frame rate, docked or handheld and render scale without a rebuild: upstream's Mac settings window does it. Otherwise a Game section in Quick settings writing the game's `env.txt`. |
| Newer Metal compiler of the tested generation | On fork main (0.10.0) | NX2Apple patch 0034 (not upstream yet: an upstream PR candidate, issue seedds/nxnative#717). |
| Hide the pointer over the game | On fork main (0.10.0) | NX2Apple patch 0032, upstream PR seedds/nxnative#755; drop ours when it merges. Needs a hands-on check. |
| "Older" only when build inputs changed | On fork main (0.10.0) | Converter, after NX2Apple's OlderTools.swift. |
| Record frame times, summed up in the converter | On fork main (0.10.0) | Quick settings › Performance; Builds page row. Needs a hands-on check. |
| Drop files on Convert | On fork main (0.10.0) | After NX2Apple's DropFiles.swift. |
| Cover art from a title database | Idea | NX2Apple's Artwork.swift fetches eShop banners through blawar/titledb (about 90 MB list). Builds already shows the game's icon. |

## Quality and consistency

From the list of ten on 2026-10-31, all in 0.8.0.

| Item | Status | Notes |
|---|---|---|
| Converter in CI | On fork main (0.8.0) | `converter` job in tests.yml: build, `swift test`, bundle, `--check`. |
| Releases from tags and a release check | On fork main (0.8.0) | `release.yml`, `scripts/release_check.py`. |
| Mac smoke test and hands-on list | On fork main (0.8.0) | `scripts/smoke_mac.sh`, `docs/release-checklist.md`. Run before each tag. |
| Nightly upstream check | On fork main (0.8.0) | `upstream-check.yml`; one issue labelled `upstream`. |
| Settings table and test | On fork main (0.8.0) | docs/settings.md, Quick settings on the Mac. |
| Played on NXForge | On fork main (0.8.0) | `docs/nxforge-games.tsv` → the converter's Builds page (dropped from the README). Add a row after each play test. |
| Frame times per release | On fork main (0.8.0) | `scripts/perf_release.py`, `docs/perf/`. More games with `bench.tsv` routes would make it sharper. |

## Save states and rewind

**Research.** Not feasible the simple way. Emulators save state by
serialising their virtual CPU and devices; nxnative runs the game's code
natively on the Mac's CPU and translates its GPU calls to Metal, so there is
no single machine state to dump. A real snapshot would have to capture and
restore, consistently:

- **Guest memory**: every mapped region (heap, stacks, TLS, module data,
  shared memory), with permissions and layout, while all guest threads are
  stopped at a safe point.
- **CPU state of every guest thread**: registers, including the ones the
  rewriter and host runtime reserve, and where each thread is parked
  (inside a service call, a futex wait or a spin loop).
- **Kernel objects and HLE services**: handles, events, mutexes, timers,
  service sessions and their internal state (HID, audio, filesystem with
  open files, time, NVN/nvdrv, haptics).
- **GPU state**: NVN objects and their Metal counterparts (textures, buffers,
  pipelines, command queues, in-flight work), or a way to drain and rebuild
  them from guest memory.
- **Audio**: renderer state and queued buffers.
- **Host-side translation state** that points into guest memory.

Rewind is the same mechanism taken many times per second (a ring of
snapshots, ideally storing only the memory pages that changed), so it costs
more than save states and only becomes realistic once a snapshot is cheap.

Possible first step: a spike that freezes all guest threads at a frame
boundary in one simple 2D game (Curse of the Moon or MvDK), dumps memory and
thread contexts, and tries to restore into the same running process before
attempting a cold restore. That would show how much service and GPU state
really has to be serialised.

## Cheats and mods

Since 0.9.0 the cheats are upstream's engine (`hle_cheats.c`: Atmosphère `.txt`
files, the Cheats menu and panel), with a switch per cheat in the sidebar too
([docs/cheats.md](docs/cheats.md)). NXForge's own Markdown engine (0.4.0 to 0.8.0)
was verified on Curse of the Moon 1.1.1.

| Item | Status | Notes |
|---|---|---|
| More cheats per game | Next | Port and verify more codes; Curse of the Moon has infinite HP, infinite lives and 99 weapon points. |
| Merge several matching cheat files | Idea | |
| GitHub cheat source ("Get cheats") | Idea | Fetch `.txt` cheat files by title and build ID from a GitHub repo. |
| exefs / IPS / pchtxt mod loader | Next | Upstream's engine writes code through main's writable alias and checks the rewriter's `main.changed.tsv`; a loader could do the same. Unlocks most 60 fps and resolution mods. |
| iOS cheats | From upstream | Upstream's engine runs data cheats on the iPhone; code writes need the writable alias, which the iPhone has not. |

## Performance and graphics

| Item | Status | Notes |
|---|---|---|
| Per-game 60 fps profiles | Idea | Build-matched mods exist for ACNH 3.0.3, Persona 5 Royal 1.0.2 (drop-in cheats, try first), Pokémon Z-A 2.0.2, Pokémon Sword 1.3.2. Most need the exefs loader. |
| Forced anisotropic filtering override | On fork main | `DM_ANISO` floor since 0.1.0 (fork PR #4), 16x by default on the Mac since 0.7.0. |
| MetalFX spatial upscaling | On fork main | On by default in Mac apps since 0.7.0, live switch in Quick settings, works together with Sharpen. FXAA (`DM_PRESENT_AA`) came with it. |
| Pixel art: sharp scaling, the art's own grid, MMPX | Shipped in 0.29.0 (`DM_PIXEL_ART`, `DM_PIXEL_GRID`; sidebar and settings window) | Tom's pick from the 2026-11-12 pixel-art list. Not done from that list: black-frame insertion at 120 Hz for scrolling clarity, CRT-Lottes and LCD Grid back in the sidebar with lines on the art's rows, border fill (blurred picture or bezel) around a Pixel-perfect picture, forced nearest texture sampling per game, ScaleFX (a five-pass port; MMPX was taken instead). |
| General resolution scaling | Research | Hard; per-game resolution mods are the near-term route. |
| 120 fps frame interpolation on ProMotion displays | Shipped in 0.27.4 (picture-based, experimental; DM_PRESENT_INTERP, sidebar and settings window); 0.28.3 fixed a crash or GPU hang going full screen (Donkey Kong Country Returns HD, play-tested by Tom); 0.29.1: in variable-refresh full screen the link gets only about 80 callbacks a second with a present on every refresh, so interpolation turns itself off there (open: whether frame latency 1 would keep 120) | Tom's ask: take 60 fps games to 120 fps by generating an in-between frame, turned on automatically when the game's screen runs at 120 Hz (ProMotion MacBook Pro, Studio Display XDR) and off on 60 Hz screens, with a sidebar switch to override. Basis: MetalFX frame interpolation, which needs motion vectors and depth the game doesn't hand to Metal, so most games would need an optical-flow fallback that estimates motion from two finished frames. Open questions: added latency (one frame held back), artefacts on HUD and text, GPU cost on battery, and pacing alongside the full-screen display-link fix (#194). Detect the refresh rate from the screen's `maximumFramesPerSecond` and re-check when the window moves screens. |
| EDR / HDR inverse tone-map | Idea | |
| Faster shader-archive starts | On branch (0.11.0) | Compaction after the first frame, fewer archive files. Mario Kart World: 16-25 s → 0.5-0.9 s before the first frame. |
| Race-load hitch from first texture uploads | Research | Mario Kart World's first race frame takes about 500 ms: residency commits of 131 MB of new textures, deswizzle encoding, the game's fence wait (`[longframe]` breakdown, 0.11.0). Copying the source out of the large pool did not help. Next idea: textures placed in resident heaps made ahead, so the commit does not allocate. |
| Memory over a long session | Research | Mario Kart World goes from about 7 to 12 GB in 15 minutes on a 24 GB Mac. The memory lines' GPU split (0.11.0) shows pool buffers 4.1 → 5.2 GB and packaged textures 1.0 → 3.1 GB in the first 2 minutes. Check for a plateau over a long session, and whether host copies of textures whose storage the game reused are released. |
| Mac thermal and Low Power Mode awareness | Idea | `dm_thermal_now` / `dm_low_power_now` return -1 on Mac. |
| Lower peak disk use of a shader build | Next (0.14.0) | Since 0.13.0 (upstream `cas.db`) an Ocarina of Time build from scratch peaks at about 52 GB: 24 GB extracted game, 13 GB `cas.db` beside the 11 GB image written from it, about 4 GB pipeline archive, and the shared Metal cache grows past its 12 GB cap during the build. Drop `cas.db` once the image is written, prune the shared cache during the build, and check free space before a build starts. |
| Smaller run-time costs found in 0.13.0 review | Next (0.14.0) | NEON for `md_rgba`, a last-hit check for the OpenGL pipeline and depth / stencil lookups, a slab for `defer_take` (profile first). Measure before and after on Mario Kart World, an OpenGL game and Ocarina of Time. Not taken: unretained pipelines in `nvn_rec.h` (the pipeline cache replaces entries, so it is unsafe) and a thread-lock redesign. |
| Ideas from other nxnative forks (0.13.0 survey) | Idea (0.14.0) | Shader tables generated without timestamps, so unchanged ones are reused on a rebuild, and the game language following the Mac's (devinhurry); opt-in Mac energy saving (skip identical presents, pause the display link when idle or hidden) and an opt-in per-step shader stage cache (AnkMister); a skipped draw instead of a crash when geometry scratch runs out, and a single-mip alias fix for Naruto's black silhouettes (widmonstertony); unwiring unused pools (TVPort); a memory-pressure trim (mianmuhammadse); a sampler pinned per bind for Super Mario Odyssey's white bloom flashes (TVPort 6ae1b1f1); output integer types learnt from a refused pipeline for Kirby and the Forgotten Land (xinerqu 3074f9dd); the Mario Kart World encode thread on (pahorema, A/B first). Hold for the next shader chain change: an image-atomic return fix (Octopath Traveler 0) and the geometry viewport index. Later, behind a switch: devinhurry's pass reuse. |

## Input

| Item | Status | Notes |
|---|---|---|
| Real controller gyro via GCMotion | Idea | Six-axis in `hle_hid.c` is a synthetic shake only. Unclaimed upstream. |

## Games and housekeeping

| Item | Status | Notes |
|---|---|---|
| Rebrand as NXForge | On fork main | Fork PR #6, then the converter and capture folders (`~/Pictures/NXForge`, `~/Movies/NXForge`) in the merge-everything PR. The repository is gnosticgeek/nxforge since 2026-10-26. The converter's last old names went in 0.8.0. |
| Longer MvDK prewarm list | Next | The current list was recorded on level 1-1 only. |
| Test MvDK past level 1-1 | Next | The game note's Mac route only covers 1-1. |
| Mac host compiler warnings | On fork main (0.8.0) | 52 warnings in 10 kinds; 3 kinds fixed and CI now fails on a new one (`dm/tools/host_warnings.py`). The 7 left are upstream's, all in `nvn_mtl.m` (Metal 4 encoder types in about 45 places, ignored ARC qualifiers on cache getters): an upstream PR candidate. |
