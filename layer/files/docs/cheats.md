# Cheats

Since 0.9.0 NXForge uses nxnative's cheat engine (`dm/host/hle_cheats.c`). It runs Atmosphère's cheat files (`<build ID>.txt`, the format the community cheat collections share) with Atmosphère 1.12.1's opcodes, and adds a Cheats menu and panel to the Mac window. [docs/development.md, Cheats](development.md#cheats) describes the engine, and [docs/reference/cheats.md](reference/cheats.md) says where it differs from Atmosphère.

## Where the files are

The Mac app reads `~/Library/Application Support/nxnative/<title ID>/cheats/`, beside the game's `mods` folder, as it did before 0.9.0. `DM_CHEATS=<folder>` names another folder. Either layout works there: `<build ID>.txt` files directly in the folder, or Atmosphère's `atmosphere/contents/<title ID>/cheats/<build ID>.txt` tree. The file name is the first 16 hex digits of the main module's build ID, which the sidebar shows and copies.

The engine keeps the switches beside the file (`<build ID>.enabled`), so the Quick settings sidebar, the Cheats menu and the Cheats panel always agree.

## In the Mac app

Since 0.36.0 a game's page in the NXForge app (Manage) has a Cheats card: the same switches as the sidebar, kept in the same `<build ID>.enabled` file, for while the game is not running. **Get Cheats** looks up the game's title ID and build ID in two public collections on GitHub, [switch-cheats-db](https://github.com/HamletDuFromage/switch-cheats-db) and [NX-60FPS-RES-GFX-Cheats](https://github.com/ChanseyIsTheBest/NX-60FPS-RES-GFX-Cheats), lists the cheats you do not have yet and adds the ones you tick to `<build ID>.txt`, switched off. The file as it was is kept beside it as `<build ID>.txt.before-download`. A cheat that writes into the game's code is marked "Changes game code". Codes only work on the build they were made for, so when the collections only have another build's, nothing is added. NXForge ships no cheats.

## In the game

- **Quick settings sidebar** (Esc): the Cheats page has a switch per cheat, a Refresh button that reads the file again, and a button that opens the folder. When the last run ended without a clean exit while cheats were on, every cheat starts off, and the section offers to restore the saved switches.
- **Cheats menu and panel** (⇧⌘C): everything the sidebar has, plus sections, search, the master switch, values for cheats that take one, a dry run, and the import of cheat files.

## Markdown files from 0.4.0 to 0.8.0

Before 0.9.0, NXForge read its own Markdown cheat files (`<build ID>.md`). The engine reads only `.txt` now. Convert old files once:

```bash
python3 dm/tools/cheats_md.py txt ~/Library/Application\ Support/nxnative/<title ID>/cheats/*.md
```

Each `## ` heading becomes a cheat, a `dmnt master` block becomes a master code (`{name}`), and the `.txt` lands beside the `.md`. An existing `.txt` is left alone. The `dmnt on` marks are not carried over: switch those cheats on once in the sidebar, and the engine remembers them.
