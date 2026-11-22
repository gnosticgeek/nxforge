# NXForge's game library

One folder per game, named by its title ID, holding what NXForge can add to that game. Everything is Markdown, one file per item,
so each can be shared, reviewed and switched on its own.

```
library/
  010019401051C000/            Mario Strikers: Battle League
    game.md                    its title and genres
    enhancements/
      steady-60-full-screen.md
    cheats/
      2E90F0815B1F92A1.md      the cheats for one build, in the same format as a game folder's cheats/<build ID>.md
```

## Genres

Each game's genres are in `library/<title ID>/game.md`. The app bundles these files and uses them for Discover, Theatre and the game
page; a game without one falls back to the genres on its Nintendo store page.

```markdown
---
nxforge_game: 1
title: "Cuphead"
title_id: "0100A5C00D162000"
genres:
  - "Run and gun"
  - "Action"
---
```

List the most fitting genre first. A sub-genre counts under its genre too, so `Golf` alone puts a game under Sports and Golf. The
genres and their sub-genres (`Genres.tree` in `app/Sources/NXForgeConverter/Genres.swift`):

| Genre | Sub-genres |
|---|---|
| Action | |
| Run and gun | |
| Beat 'em up | |
| Platformer | 2D platformer, 3D platformer, Metroidvania |
| Adventure | |
| RPG | Action RPG, Turn-based RPG |
| Shooter | Shoot 'em up, First-person shooter |
| Fighting | Platform fighter |
| Racing | Kart racing, Arcade racing |
| Sports | Football, Golf, Baseball, Tennis, Basketball, Multi-sport |
| Puzzle, Strategy, Party | |
| Music | Rhythm |
| Arcade | Retro collection |
| Simulation, Board game, Lifestyle | |

`scripts/library.py check` refuses a genre not in that list.

## Enhancements

An enhancement is an improvement made for one game: a steadier frame rate, a 60 fps patch, a fix, a mod set up to suit it. It is
kept apart from cheats, which change how the game plays. The app's **Enhancements** card (game page, Play options › Enhancements)
lists a game's enhancements with a switch each, and **Get from Library** copies files from this folder into the game's own
`enhancements/` folder (beside `cheats/` and `media/`), switched off.

```markdown
---
nxforge_enhancement: 1
name: "Steady 60 in full screen"
title_id: "010019401051C000"
builds: "2E90F0815B1F92A1"      # optional: the build IDs it was made for, separated by spaces; leave it out for every build
on: false
source: "NXForge"
---
# Steady 60 in full screen

The summary: the first paragraph, shown under the switch.

Anything else: how it was tested, on which Mac, what to watch for.

```env
DM_SOME_SETTING=value
```
```

The blocks, in any mix:

| Block | What NXForge does with it while the enhancement is on |
|---|---|
| ` ```env ` | Launch settings, one `KEY=VALUE` a line, written to a block of `~/Library/Application Support/nxnative/<title ID>/env.txt`, which the game reads first at every launch. The game's settings window shows them greyed out. |
| ` ```dmnt ` | An Atmosphère code (a frame-rate patch and the like), added to the build's cheat file as the master code `{NXForge enhancement: <name>}`, which always runs. The Cheats card and the cheats Markdown leave it out. Give `builds:` for a code: it is only for the build it was written for. |
| ` ```mods ` | Names of mod folders (from the game's Mods), switched on with it. |

Switching an enhancement off takes back what it added. Nothing needs a rebuild.

## Sharing

`scripts/library.py collect <games folder>` copies every game folder's `enhancements/*.md` and `cheats/*.md` into this folder
(by the title ID in each file), switched off, for a commit. `scripts/library.py check` checks every file here (CI runs it).

## Game Boy Advance

`library/gba/` holds notes on Game Boy Advance games that have been converted ([gba/README.md](../gba/README.md)): `<game code>-<first 8
of the cartridge's SHA-1>.md`, and beside it an optional `.labels` file listing entry points earlier conversions found by playing, in
gba-recomp's own format (addresses only, no game code or data). A conversion of the same cartridge adds them before it starts, so its
first pass translates what play had to find. A GBA game's genres go in `library/<title ID>/game.md` like any other game's; its title
ID is `0BA0`, the game code in hex, the version byte and `00`.
