# Backlog

Work planned or in flight on this fork (gnosticgeek/nxnative). Upstream is
[seedds/nxnative](https://github.com/seedds/nxnative). Last updated 2026-10-25.

Status key: **Upstream PR open**, **On fork main**, **On branch**, **Next**,
**Idea**, **Research**.

## Upstream contributions

| Item | Status | Notes |
|---|---|---|
| Full-screen 60 fps fix | Upstream PR open ([#194](https://github.com/seedds/nxnative/pull/194)) | Branch `claude/project-thread-ly6qu8` (e20c2a5). No display link while full screen on 120 Hz ProMotion; verified 3 runs on an M4 Pro. Overlaps upstream #198 (silent display-link fallback). Review fixes go on the fork branch. |
| NxNative Converter app | Upstream PR open ([#209](https://github.com/seedds/nxnative/pull/209)) | Branch `mac-converter-app`. PR currently carries the Rust app. |
| Swift rewrite of the Converter | Next | SwiftUI app (macOS 26+, Liquid Glass) built to the four UI mockups: Convert, Builds, Toolchain, Settings. Full Mario build passes from the window. Replaces the Rust app on #209 once Tom signs off on the look. |
| Rumble fix | On fork main, not sent upstream | Fork PR #1 (merge 5bc2563). Vibration handles before the controller connects, plus a plain Core Haptics player fallback for controllers that refuse advanced players (8BitDo SN30 Pro). Verified in MvDK and Curse of the Moon. PR body drafted (`nxnative-pr/rumble-pr.md` in project files). |
| Rewriter jump-table fix (49a670a) | On fork main, needs splitting out | Looks 128 instructions back for an index copied before its bounds check (Curse of the Moon GLSLC). Commit is authored as `seedds` by mistake: re-author it and send it as its own small PR, separate from the sidebar. |
| Filters + Quick settings sidebar | On hold for upstream | Tom holds the upstream PR until the sidebar is finished (see the next section). |
| Cheats engine | On fork main, not sent upstream | Goes upstream after the sidebar, or alongside it. |

## Quick settings sidebar and filters

Branch `claude/project-thread-skozua`. Fork main has it up to 8a5a4dd (via
fork PR #2); the branch is ahead with the controller navigation, key remap
and game-folder work below.

| Item | Status | Notes |
|---|---|---|
| SwiftUI sidebar with Liquid Glass (Esc, ⇧⌘G, Graphics menu) | On fork main | `dm/host/quick_settings.swift`. Material fallback before macOS 26. |
| Filters: Sharpen, Pixel-perfect, CRT, scanlines | On fork main | Tested in Curse of the Moon; no measurable cost. |
| Filters: CRT-Lottes, LCD Grid, scanline fade | On fork main | Lottes is public domain. Not tried in a running game yet. |
| Capture: screenshots ⇧⌘S, recording ⇧⌘R | On fork main | Needs a hands-on check in game. |
| Volume | On fork main | Needs a hands-on check. |
| Controller navigation (Home or −/+ opens) | On branch | 367f518. Cheats added to the navigation list in 6e6be90. |
| Key and button remapping, per game | On branch | 367f518. Not tried in game yet. |
| Saves, screenshots, recordings in the game folder | On branch | c4940d7, 4529349. Old Library save is copied once, never moved. Waiting on Tom to confirm progress, rumble, a screenshot and a recording in the rebuilt Curse of the Moon. |
| Mods section (romfs folders per title) | On fork main | Untested with a real mod. |
| Merge branch into main, then open the upstream PR | Next | After Tom's hands-on checks. Split 49a670a out first. |

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

Cheats engine merged via fork PR #2: dmnt codes in Markdown keyed by title ID
and main build ID, Atmosphere `.txt` also read, sidebar switch per cheat.
Verified on Curse of the Moon 1.1.1.

| Item | Status | Notes |
|---|---|---|
| More cheats per game | Next | Port and verify more codes; Curse of the Moon has infinite HP, infinite lives and 99 weapon points. |
| Merge several matching cheat files | Idea | |
| GitHub cheat source ("Get cheats") | Idea | Fetch Markdown cheat files by title and build ID from a GitHub repo. |
| exefs / IPS / pchtxt mod loader | Next | Build on the cheats engine's load-time code writes. Unlocks most 60 fps and resolution mods. |
| iOS cheats | Research | Code patches only work on Mac (iOS code pages are signed); data cheats might work. |

## Performance and graphics

| Item | Status | Notes |
|---|---|---|
| Per-game 60 fps profiles | Idea | Build-matched mods exist for ACNH 3.0.3, Persona 5 Royal 1.0.2 (drop-in cheats, try first), Pokémon Z-A 2.0.2, Pokémon Sword 1.3.2. Most need the exefs loader. |
| Forced anisotropic filtering override | Idea | |
| MetalFX spatial upscaling | Research | Test upstream #33 against #160 on the M4 Pro before building anything. |
| General resolution scaling | Research | Hard; per-game resolution mods are the near-term route. |
| MetalFX frame interpolation ("Smooth motion") | Research | |
| EDR / HDR inverse tone-map | Idea | |
| Mac thermal and Low Power Mode awareness | Idea | `dm_thermal_now` / `dm_low_power_now` return -1 on Mac. |

## Input

| Item | Status | Notes |
|---|---|---|
| Real controller gyro via GCMotion | Idea | Six-axis in `hle_hid.c` is a synthetic shake only. Unclaimed upstream. |

## Games and housekeeping

| Item | Status | Notes |
|---|---|---|
| Longer MvDK prewarm list | Next | The current list was recorded on level 1-1 only. |
| Test MvDK past level 1-1 | Next | The game note's Mac route only covers 1-1. |
| 49 Mac host compiler warnings | Idea | Clean up in a separate PR. |
