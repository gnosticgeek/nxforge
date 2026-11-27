# Wii and GameCube games in NXForge

NXForge makes a Mac app for a Wii or GameCube game you own. Unlike a Switch or Game Boy Advance game, nothing is
translated: the app plays the disc with [Dolphin](https://github.com/dolphin-emu/dolphin), built as one library that
draws into the app's own window with Metal, and it has NXForge's Quick settings sidebar like every other game. The app
shows up in the Library, Discover, Theatre and its Museum wall beside the other games.

Dolphin is pinned in `wii/ENGINE` and used unchanged; NXForge adds one small library target to its build (the bridge).
No disc image, NAND or generated file is kept in this repository.

## Licence

Dolphin is GPL-2.0-or-later, so everything here that is built into Dolphin or loads it is GPL-2.0-or-later too:
`wii/bridge/` and `wii/host/mac/wii_front_mac.m` say so in their first line. The rest of NXForge stays MIT (NOTICE).
Each game app carries Dolphin's licences in `Contents/Resources/Dolphin licences`. Apps are made on your own Mac for
your own use; handing one to someone else means handing over the source too (Dolphin's, at the pinned commit, and the
files in this folder).

The bridge started from RetroReplay's `Vendor/DolphinBridge/DolphinBridge.mm` (RetroReplay c526a993, same author,
GPL-2.0-or-later).

## What is here

| Path | What it is |
|---|---|
| `wii/ENGINE` | The Dolphin commit NXForge builds (`url`, `commit`). |
| `wii/bridge/` | `nxdolphin.mm`, Dolphin's host interface as a C library (`nxdolphin_*`, ABI 1): start a disc in an `NSView`, tick, pause, input for two GameCube pads and two Wii Remotes (Nunchuk, sideways or alone), volume, live picture settings, save states to a file, screenshots, the save folder, a frame count. `CMakeLists.txt` adds it to Dolphin's build. |
| `wii/host/mac/` | The player (`wii_front_mac.m`, built by `build.sh` into `wii/build/nxwii-player`): the window, the keyboard and controllers, and the sidebar (the same Swift file the other players build). |
| `scripts/wii_engine.py` | `build` (Dolphin with the bridge, then the player), `stale`, `where`. |
| `scripts/wii_build.py` | Makes one game's app. The NXForge app runs it; it also runs by hand. |

Dolphin's source and build (about 1 GB and a few hundred MB) are the same for every checkout, so they live outside the
repository in `~/Library/Application Support/NXForge Converter/dolphin` (`NXF_DOLPHIN_HOME` moves it): `src/`, `build/`,
and `out/` with `nxdolphin.dylib`, Dolphin's `Sys` data and its licences. The first build takes 15 to 30 minutes (Xcode's
command line tools and CMake; Homebrew's CMake and Ninja are used when there, else a private Python environment gets
them); after that only the bridge is built again when it changes.

## Making an app

In NXForge: Settings › Library › Wii and GameCube folder names the folder your discs are in (left unset, folders named
`wii` or `gamecube` beside the Switch games folder or the Game Boy Advance one are used, and two levels of folders
inside are read). The games are listed under Wii and GameCube; Convert makes the app.

By hand:

```
python3 scripts/wii_build.py "Zack & Wiki - Quest for Barbaros' Treasure (USA).rvz" --home ~/Games/ZackWiki
```

The steps: Read disc, Prepare engine, Package, Trial run. Read disc takes the game ID and title from the disc header
(ISO, GCM, RVZ, WIA, WBFS, GCZ and CISO images; a WAD from its title ID; DOL and ELF homebrew from the file name).
Package copies the player, Dolphin and its data into `<Name>.app` (about 22 MB) and fetches the box art from GameTDB
for the app's icon. The trial run starts the game for 25 seconds with no window and no sound, pressing Start and A now
and then, its saves in the build folder: it checks the game reaches its first frame and keeps a picture.

**The disc stays where it is.** The app's `Contents/Resources/wii/port.json` names it, so a 4 GB disc is never copied.
If the disc is on a drive or share that is away, the app says so and does not start; Convert again after moving it.

**Title IDs.** NXForge keeps a Wii game under `0E00` and its six-character game ID in hex, a GameCube game under `0C00`
and the same (Zack & Wiki, RTZE08: `0E0052545A453038`). The app's bundle ID ends in it.

## The app

- **Saves** are where a Switch game's are, `~/Library/Application Support/nxnative/<title ID>/save/`: the Wii's NAND in
  `save/Wii`, the GameCube's memory cards in `save/GC`. NXForge's save backups and snapshots take that folder. Dolphin's
  own settings, shader cache and logs are in `dolphin/` beside it.
- **Save states**: ⌘1 to ⌘3 save the moment and ⌥⌘1 to ⌥⌘3 go back to it, or General › Save states in the sidebar. They are
  files in `states/` and are kept after the game closes (a state from another Dolphin commit may not load).
- **Quick settings** (Esc, or Home on a controller): General has the Wii Remote (upright with a Nunchuk, sideways, or
  upright alone) and the speed limit; Graphics has the aspect ratio, the widescreen hack, internal resolution (native to
  6×, 3× by default), MSAA and texture filtering, all applied at once; Controls lists the keys and buttons. Screenshots go
  to the game's Screenshots folder at the internal resolution.
- **Keys**: arrows the stick and D-pad; X A, Z B, S X, A Y, Return Start, Q L (Nunchuk Z), W R (Nunchuk C), E Z (shakes the
  Remote), Tab the Remote's −, H its Home. The mouse points the Wii Remote, with left and right click as A and B (held
  sideways, 2 and 1). A controller works by letter (A, B, X, Y), its triggers are L and R, the right shoulder Z, the left
  shoulder or Options the Remote's −, the left stick pressed Home, the right stick moves the pointer and pressed re-centres it.

## Checking a change

```
python3 scripts/wii_engine.py build
NXWII_SNAPSHOT=out.png NXWII_SNAPSHOT_SECONDS=20 NXWII_SNAPSHOT_INPUT=menus DM_ROOT=/tmp/wii-root "<Name>.app/Contents/MacOS/nxnative"
```

The player prints one line of JSON (`snapshot`, `playing`, `frames`, `fps`) and quits; `out.png` is the game's own frame.
`NXWII_SNAPSHOT_SIDEBAR=<page>` takes the window with the sidebar open on that page instead (0 is General);
`NXWII_SNAPSHOT_STATE=1` saves state 1 near the end. `NXWII_DISC`, `NXWII_LIB`, `NXWII_NAME` and `NXWII_ID` run a disc,
a Dolphin library, a name and a title ID other than the app's. `DM_ROOT` keeps saves away from your own.

## Not done yet

- Cheats (Dolphin's Gecko and Action Replay codes), texture packs and mods.
- Remapping keys and buttons, tilt and swing, the Classic Controller, the Balance Board and real Wii Remotes.
- Recording, instant replay and "my defaults" in the sidebar.
- The trial run's picture is often a health and safety screen; the box art makes the icon when GameTDB has it.
