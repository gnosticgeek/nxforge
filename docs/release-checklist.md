# Release checklist

What to check on a Mac before tagging an NXForge release ([UPSTREAM.md](../UPSTREAM.md#versions) has the
release steps). GitHub's runners have no Metal 4 and no games, so these checks are local.

## Automatic

```
scripts/smoke_mac.sh [<id>_build folder ...]
```

runs the host unit tests and the GPU graphics tests for one profile, the converter's unit tests, and leaves
each game given running for 60 seconds without input (`scripts/bench.py --idle`). A game passes when it
presents frames; its frame rate, worst frame and `[RED]` lines go into `SUMMARY.md` in the output folder
(`~/Library/Logs/NXForge/smoke/<date-time>`). Give it one build folder per engine the release touches,
for example a 2D game (Curse of the Moon) and a 3D one (Super Mario Bros. Wonder or 3D World). A
release that touches speed also runs `scripts/bench.py` on the games with routes and compares with the
previous release ([docs/performance.md](performance.md)).

## Hands-on

Play one game built from the release for a few minutes and tick what was tried. Write anything that
fails into the release PR. A row that has never been tried in a running game says so in
[BACKLOG.md](../BACKLOG.md).

- [ ] The game opens from the settings window and reaches gameplay; progress is still there after quitting and reopening (saves in the game folder's `Saves`).
- [ ] Full screen holds 60 fps on the built-in display.
- [ ] Quick settings (Esc or Home) opens, and a controller moves through it; Quit game, pressed twice, ends the game.
- [ ] A filter (Sharpen, CRT-Lottes, LCD Grid, scanlines) changes the picture, and MetalFX and FXAA switch on and off.
- [ ] Volume in Quick settings changes the sound.
- [ ] A screenshot (⇧⌘S) and a short recording (⇧⌘R) land in the game folder and open.
- [ ] A remapped key or button works, and Reset puts it back.
- [ ] Rumble on a controller that has it.
- [ ] A cheat switches on and off (Curse of the Moon 1.1.1 has a cheat file).
- [ ] A RomFS mod folder is picked up (only when the release touches mods).
- [ ] The converter opens, its Toolchain page is all ticks, Check for updates answers, and a rebuild of one game passes.
