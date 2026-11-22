# Game Boy Advance games in NXForge

NXForge converts a Game Boy Advance game you own into a Mac app, the way it does a Switch game: the game's
own code is translated ahead of time into C, compiled for the Mac, and packaged with a small player. The
app plays with NXForge's Quick settings sidebar, and shows up in the Library and Theatre beside the Switch
games.

The translation is done by [gba-recomp](https://github.com/JRickey/gba-recomp) (MIT, by JRickey), pinned in
`gba/ENGINE` and used unchanged apart from two small patches. No game, BIOS or generated code is kept in
this repository: a conversion reads your own `.gba` (or a `.zip` holding one) and writes everything beside
it or in the folder NXForge builds in.

## What is here

| Path | What it is |
|---|---|
| `gba/ENGINE` | The gba-recomp commit NXForge builds on (`url`, `commit`). |
| `gba/patches/` | NXForge's changes to gba-recomp, applied in order: the translator can write the C without compiling it, in units of a chosen size, with a progress line per unit; the machine can be copied (save states). |
| `gba/tree/` | Git-ignored. `python3 scripts/gba.py assemble` makes it: gba-recomp at the pinned commit with the patches applied. |
| `gba/host/` | NXForge's own: a Rust library (`nxgba`, C API in `nxgba.h`) around gba-recomp's machine, with cartridge saves, cheats, Enhanced audio and save states; `nxgba-run`, a tool that runs a game with no window; and the Mac player (`mac/gba_front_mac.m`). |
| `scripts/gba.py` | `assemble`, `build` (the translator, the library, the player), `where`. |
| `scripts/gba_build.py` | Converts one game. The NXForge app runs it; it also runs by hand. |
| `library/gba/` | Optional notes per game (`<CODE>-<first 8 of SHA-1>.md`), and entry points earlier conversions found (`.labels`), so the next conversion of that game translates them the first time. |

## Converting a game

In NXForge: Settings › Game Boy Advance folder names the folder your games are in (a folder named `gba`
beside the Switch games folder is found by itself). The games are listed in the Library under Game Boy
Advance; Convert builds the app. Pause holds a conversion where it is and Resume carries on; a conversion
that was stopped, or cut short by a restart, carries on from the step it had reached when it is started
again.

By hand:

```
python3 scripts/gba_build.py "Kurukuru Kururin (Europe).zip" --home ~/Games/Kururin
```

The steps, in order: Read ROM, Check profile, Capture RAM code, Find code, Write C, Compile, Link, Trial
run, Package. Every step leaves its result in the build folder (`<title ID>_build`) and is skipped when
nothing it reads has changed; Compile keeps one object file per unit, so it continues at the unit it had
reached. `--fresh` starts over.

**Trial run.** The converted game is run for a minute of game time with no window, pressing buttons the way
a player gets through menus. It checks the game starts, takes the pictures the app shows, and notes any
code the first pass did not find (a game reaches some of its code through tables). When it finds some, the
conversion makes a second pass that includes it. Code that is still missed afterwards is run by gba-recomp's
interpreter, so the game keeps working, only slower in those places; the player notes what it meets while
you play, and Convert again takes those in.

**No BIOS needed.** The start-up logo is skipped and the BIOS calls games make are provided by gba-recomp's
own replacements.

## The app

`<Name>.app/Contents/MacOS/nxnative` is the player; `Contents/Resources/gba/` holds `game.gba` (your copy),
`game.dylib` (the translated code) and `port.json` (what the conversion did: steps and times, how much was
translated, the trial run). The title ID NXForge uses for a GBA game is `0BA0`, the four letters of the
cartridge's game code in hex, its version byte and `00` (Minish Cap, Europe: `0BA0425A4D500000`).

- **Saves** are the cartridge's own (`game.sav`) under `~/Library/Application Support/nxnative/<title ID>/save/`,
  written when the game saves and on quit. NXForge's save snapshots and cloud saves treat it like any game's.
- **Save states**: ⌘1 to ⌘3 keep the moment, ⌥⌘1 to ⌥⌘3 go back to it, at once. They are kept while the
  game is open; the cartridge save is what lasts between sessions.
- **Quick settings** (Esc, or Home on a controller): the same sidebar as the Switch games. General has
  Sound (Enhanced audio, Bass lift, Wider stereo) and Save states; Graphics has the picture filters (Sharp
  pixels, CRT, LCD), scaling, the border, and Handheld colours; Controls lists the keys and buttons.
- **Enhanced audio** plays the game's sampled sound at 48 kHz with smooth interpolation instead of the
  handheld's rough 8-bit output. It is on by default and can be switched off for the original sound.
- **Cheats** are GameShark / Action Replay / CodeBreaker codes in `cheats/<CODE>.txt` in the game's folder.
- **Keys**: arrows or WASD, X or J for A, Z or K for B, Q and E for L and R, Return for Start, Tab for Select,
  Space held for fast forward. A controller works as on the handheld (the right-hand button is A).

## Checking a change

```
python3 scripts/gba.py build
gba/host/target/release/nxgba-run game.gba --lib game.dylib --frames 3600 --demo --sheet out.png --json
NXGBA_SNAPSHOT=out.png NXGBA_SNAPSHOT_SIDEBAR=0 gba/build/nxgba-player game.gba game.dylib
```

`nxgba-run` prints how much of the game ran as translated code, the entry points missed and a hash of the
last picture; `--sheet` writes a contact sheet of the run. `NXGBA_SNAPSHOT` makes the player take a picture
of its own window (kept off every screen) and quit, with the sidebar open on that page (0 is General).

## Not done yet

- Save states are not kept after the game closes.
- Recording, instant replay, key remapping and "my defaults" in the sidebar are Switch-only for now.
- Link cable, the solar and tilt sensors and rumble cartridges.
- Game Boy and Game Boy Color games.
