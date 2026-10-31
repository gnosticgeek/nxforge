# Backlog

Work planned or in flight on NXForge (gnosticgeek/nxforge, formerly
gnosticgeek/nxnative). Upstream is [seedds/nxnative](https://github.com/seedds/nxnative);
[UPSTREAM.md](UPSTREAM.md) has the contribution policy. Last updated 2026-10-31 (0.9.0).

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
| Merge upstream main | On branch `release-0.9.0` | Last merge: seedds/nxnative main at 2716f78 (34 commits since 6d880d2), released in 0.9.0. Choices are in CHANGELOG 0.9.0. |
| China-region profanity check (Cruis'n Blast) | Upstream PR open ([#789](https://github.com/seedds/nxnative/pull/789)), on fork main | Branch `contrib/ngc-china-profanity`, from c86bc9b. |
| pso_offline free-space check | Upstream PR open ([#790](https://github.com/seedds/nxnative/pull/790)), on fork main | Branch `contrib/pso-offline-free-space`, from fde1e63. |
| Unity 6000.3 shader layouts | Upstream PR open ([#791](https://github.com/seedds/nxnative/pull/791)), on fork main | Branch `contrib/unity-6000-3-shaders`, from f6388f2. |
| bench.py offline pipeline archive | Upstream PR open ([#792](https://github.com/seedds/nxnative/pull/792)), on fork main | Branch `contrib/bench-pso-bundle`, from 2309513. |
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

From a review on 2026-10-28 of [NX Play](https://github.com/varyform/nx-native-wrapper), the [NxNative Launcher](https://github.com/rennan101/nxnative_Launcher) and [NX2Apple](https://github.com/LNPANDY/NX2Apple), all MIT. Done in 0.5.0: Keep this build, Quit game in Quick settings, Atmosphere-layout mods, issue forms.

| Item | Status | Notes |
|---|---|---|
| Save backup to a private Git repository | Idea | NX Play: while a game plays, copy its save into `<slug>-<title ID>/` of a clone you choose each time it saves, commit and push, once more on quit. NXForge could do it from the launcher (`dm/mac/launcher.c`) or the converter, watching `Saves/save` in the game folder. |
| Copy saves between the Mac and an iPhone or iPad | Idea | NX Play and the Launcher: `xcrun devicectl device copy from/to --domain-type appDataContainer`, comparing both sides file by file first and keeping the replaced save. Needs an IPA build path in the converter. |
| Install on a device and Build IPA from the converter | Idea | NX Play, NX2Apple, Launcher. The script already builds IPAs; the converter only makes Mac apps. |
| Console mode: a controller-driven library | Idea | NX Play and the Launcher: a full-screen carousel of built games with key art, driven by a controller (A plays, B backs out), last played first. NXForge's Builds page plus controller navigation like the sidebar's. |
| Game metadata from the control data | Idea | NX Play reads `control.nacp` (title, publisher, display version, supported languages). Lets Builds show the real title and version, and a language picker list only the game's languages. |
| Custom cover art | Idea | The Launcher: pick any image as a game's art, kept per title ID. |
| Nightly upstream check | On fork main (0.8.0) | NX2Apple and the Launcher run a daily job that test-merges upstream and opens a PR, or an issue naming the conflict. Would have flagged the 245-commit gap early. |
| Per-game launch settings | On fork main (0.6.0) | Game language, frame rate, docked or handheld and render scale without a rebuild: upstream's Mac settings window does it. Otherwise a Game section in Quick settings writing the game's `env.txt`. |

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
| General resolution scaling | Research | Hard; per-game resolution mods are the near-term route. |
| 120 fps frame interpolation on ProMotion displays | Research | Tom's ask: take 60 fps games to 120 fps by generating an in-between frame, turned on automatically when the game's screen runs at 120 Hz (ProMotion MacBook Pro, Studio Display XDR) and off on 60 Hz screens, with a sidebar switch to override. Basis: MetalFX frame interpolation, which needs motion vectors and depth the game doesn't hand to Metal, so most games would need an optical-flow fallback that estimates motion from two finished frames. Open questions: added latency (one frame held back), artefacts on HUD and text, GPU cost on battery, and pacing alongside the full-screen display-link fix (#194). Detect the refresh rate from the screen's `maximumFramesPerSecond` and re-check when the window moves screens. |
| EDR / HDR inverse tone-map | Idea | |
| Mac thermal and Low Power Mode awareness | Idea | `dm_thermal_now` / `dm_low_power_now` return -1 on Mac. |

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
