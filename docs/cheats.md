# Cheats

nxnative runs Atmosphere's cheat codes (the dmnt cheat VM's opcodes, the format the community cheat collections use) from Markdown files, one file per build of a game. The host's side is `dm/host/cheats.c` (the parser and the VM) and `dm/host/cheats_host.c` (finding the file, applying it); `dm/tools/cheats_md.py` converts Atmosphere's `.txt` files and checks Markdown ones.

## Where the files are

| Where | Layout |
|---|---|
| The Mac app | `~/Library/Application Support/nxnative/<title ID>/cheats/`, beside the game's `mods` folder; `DM_CHEATS=<folder>` names another |
| A Git repository (to share them) | `<title ID>/<build ID>.md` at the root, so one file is a fixed URL: `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<title ID>/<build ID>.md`. A missing file means no cheats for that build |

The title ID is the base game's (`dm/games/<id>`, the one Atmosphere's `contents/<title ID>/cheats/` uses, updates included). The build ID is main's NSO build ID; its first 16 hex digits name the file, as Atmosphere names `<build ID>.txt`. The log prints it, and the profile's `build` rows list the builds a game was brought up on. The host looks for `<build ID>.md`, then `<build ID>.txt` (Atmosphere's own file, as it is), then any `.md` in the folder whose front matter names this game and build.

## The format

~~~markdown
---
title_id: 0100B99019412000
build_id: 43AE51EE9766867D      # main's build ID, at least its first 16 hex digits
version: 1.0.1                  # shown to the player; matching is by build_id only
game: "Mario vs. Donkey Kong"
source: https://github.com/<owner>/<repo>
---

# Mario vs. Donkey Kong 1.0.1

## Infinite lives
Keeps the lives counter at 99. (This line is the cheat's description; the address is made up.)

```dmnt on
580F0000 0123ABC0
780F0000 00000010
640F0000 00000000 00000063
```
~~~

- Each `## ` heading is a cheat, named by the heading. The prose under it, before its code, is its description. Other headings and prose are free text.
- Its code is in fenced blocks whose info string starts with `dmnt`: lines of 8-digit hex words, exactly Atmosphere's. `dmnt master` marks the master code (Atmosphere's `{...}`), which always runs, first; `dmnt on` enables a cheat until the player changes it. Code blocks of other languages are text.
- A cheat with a line that is not hex words, or with more than 256 words, is left out and the log says why. All enabled cheats together may have 1,024 words (Atmosphere's limit).
- `python3 dm/tools/cheats_md.py check <file>` lists what the host will see; `cheats_md.py convert <atmosphere contents folder or .txt> <out folder>` writes `<title ID>/<build ID>.md` for each Atmosphere file.

## How they run

- **Addresses.** The rewriter keeps every module's layout (only its patch area is added), and guest pointers are host pointers, so a cheat's addresses mean what they mean on the Switch: `main` + offset is main's base + offset, and heap, alias and ASLR are the regions `svcGetInfo` reports (`hle_svc.c` `svc_cheat_regions`).
- **Code patches** (a cheat made only of type 0 stores into main's text, such as frame-rate patches): written once at load, before the game runs, while the loader still has the text writable (Mac). A word the rewriter changed (a B into the patch area) is left alone, and so are new instructions that use svc, a system register, x18 or `sub sp` from a register: the rewriter handles those, and a patch made after it cannot. A patch inside a spin-wait loop that the rewriter copied does nothing. Code patches take effect at the next launch. On iOS the code pages are signed: code patches do not apply.
- **Everything else** (data, pointer chains, conditions, button combos, loops) runs in the VM once per presented frame, as dmnt runs it on a timer. Reads and writes go through `mach_vm_read_overwrite` / `mach_vm_write`, so a stale pointer is a refused access, not a crash. A VM write into code that the loader did not already patch to the same bytes is refused.
- **Buttons.** Type 8 key masks use nn::hid's NpadButton bits (`dm_input.h`), player 1, with stick directions past half a tilt as bits 16 to 23.
- Not taken (the program stops there and the log says so): load type 5 with I above 1, C4 extended key masks, float arithmetic. FF0 / FF1 (pause / resume) do nothing.
