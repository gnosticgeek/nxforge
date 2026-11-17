# Cheats

Since 0.9.0 NXForge uses nxnative's cheat engine (`dm/host/hle_cheats.c`). It runs Atmosphère's cheat files (`<build ID>.txt`, the format the community cheat collections share) with Atmosphère 1.12.1's opcodes, and adds a Cheats menu and panel to the Mac window. [docs/development.md, Cheats](development.md#cheats) describes the engine, and [docs/reference/cheats.md](reference/cheats.md) says where it differs from Atmosphère.

## Where the files are

The Mac app reads `~/Library/Application Support/nxnative/<title ID>/cheats/`, beside the game's `mods` folder, as it did before 0.9.0. `DM_CHEATS=<folder>` names another folder. Either layout works there: `<build ID>.txt` files directly in the folder, or Atmosphère's `atmosphere/contents/<title ID>/cheats/<build ID>.txt` tree. The file name is the first 16 hex digits of the main module's build ID, which the sidebar shows and copies.

The engine keeps the switches beside the file (`<build ID>.enabled`), so the Quick settings sidebar, the Cheats menu and the Cheats panel always agree.

## In the game's folder

Since 0.45.2 (Converter 0.19.2) the NXForge app also keeps every game's cheats in the game's own folder, as Markdown: `cheats/<build ID>.md` beside the game's `media` folder (for a game not built yet, in its files' folder when no other game shares it). The setting is Settings › Artwork › Keep media and cheats in each game's folder.

````markdown
---
title: "Blazing Chrome"
title_id: "0100C2700C252000"
build_id: "318F9F225A532857"
version: "1.0.3"
---

# Blazing Chrome cheats

## P1 Lives unlimited

A note of your own stays here.

```dmnt on
580F0000 0241BCE8
780F1000 000012BC
640F0000 00000000 40140000
```
````

One `## ` heading per cheat with its code in a `dmnt` block: `dmnt on` is a cheat switched on, `dmnt master` a master code that always runs, and a `dmnt master` block before the first heading is the nameless code at the top of an Atmosphère file. The engine keeps running its `.txt` and `.enabled` in Application Support; the app writes them to the Markdown whenever the Cheats card, Get Cheats or the sidebar change them (synced when the library opens, after a game ends and on each change in the Cheats card), and reads a Markdown file back when it is newer, for a file edited by hand or a Mac that has no cheats for the game yet. The engine's file as it was before such a read is kept as `<build ID>.txt.before-markdown`.

## In the Mac app

Since 0.36.0 a game's page in the NXForge app (Manage) has a Cheats card: the same switches as the sidebar, kept in the same `<build ID>.enabled` file, for while the game is not running. **Get Cheats** looks up the game's title ID and build ID in two public collections on GitHub, [switch-cheats-db](https://github.com/HamletDuFromage/switch-cheats-db) and [NX-60FPS-RES-GFX-Cheats](https://github.com/ChanseyIsTheBest/NX-60FPS-RES-GFX-Cheats), lists the cheats you do not have yet and adds the ones you tick to `<build ID>.txt`, switched off. The file as it was is kept beside it as `<build ID>.txt.before-download`. A cheat that writes into the game's code is marked "Changes game code". Codes only work on the build they were made for, so when the collections only have another build's, nothing is added. NXForge ships no cheats.

## In the game

- **Quick settings sidebar** (Esc): the Cheats page has a switch per cheat, a Refresh button that reads the file again, and a button that opens the folder. When the last run ended without a clean exit while cheats were on, every cheat starts off, and the section offers to restore the saved switches.
- **Cheats menu and panel** (⇧⌘C): everything the sidebar has, plus sections, search, the master switch, values for cheats that take one, a dry run, and the import of cheat files.

## Pointer guard

Many community cheats follow a pointer chain: they load a static pointer of the game, add or subtract an offset and store a value there. Before the game has set up the object the cheat looks for (at boot, on a title screen, while a save or a quick-save slot loads) the same static can point at something else, and the store lands inside it. On a Switch that crashes the game; it did here too, with Blazing Chrome's "P1 Lives unlimited" when a quick-save slot restarted the game.

Since 0.45.3 the engine looks at the aligned 8-byte words a cheat's store would change. When one holds a pointer into the game's memory and the store would leave something that is not a pointer, nothing is written: the log names the cheat, the address and the pointer it kept, the cheat's row counts it like any failed access, and the cheat stays on and is tried again every pass. Once the game has its object, the word holds a value (lives, health, a double) and the store goes through as before. A store that keeps a pointer a pointer, or writes over a value, is not affected. `DM_CHEATS_POINTER_GUARD=0` (in a game's `env.txt`) turns the check off.

## Markdown files from 0.4.0 to 0.8.0

Before 0.9.0, NXForge read its own Markdown cheat files (`<build ID>.md`). The engine reads only `.txt` now. Convert old files once:

```bash
python3 dm/tools/cheats_md.py txt ~/Library/Application\ Support/nxnative/<title ID>/cheats/*.md
```

Each `## ` heading becomes a cheat, a `dmnt master` block becomes a master code (`{name}`), and the `.txt` lands beside the `.md`. An existing `.txt` is left alone. The `dmnt on` marks are not carried over: switch those cheats on once in the sidebar, and the engine remembers them.
