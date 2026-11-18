# Horizon Chase 2 (`0100001019F6E000`)

Update 1.6.9 (v524288), SDK 14.3.1. Aquiris' arcade racer on Unreal Engine 4, with FMOD. Modules `main`, `subsdk0` (NintendoSDK_movie) and `sdk`. In bring-up: on the Mac (headless) it boots to the title, shows the main menu's scenes, World Tour, car select and a race (New Horizons, Saint Augustine) at the game's 30 fps, offline, with no red line. Not played through yet.

## What it needs

| Setting | Where | Why |
|---|---|---|
| One cut on `main` 1.6.9: Unreal's fallback online subsystem is `Switch`, not `NULL` | [`patches.py`](patches.py) | see [Boot](#boot) |
| `tex_flush_upload on`, `tex_dirty_upload on` | [`game.tsv`](game.tsv) | see [Rendering](#rendering) |
| 5 GB layout: `mem_reserve 0x140000000`, `mem_alias 0x118000000` | [`game.tsv`](game.tsv) | the survey's guess. The game takes a 60 GB address region at boot (`nn::os::AllocateAddressRegion`, returning to `main+0x1e59f3c`): the Mac's 64 GB alias region holds it, the iPhone layout's 4.375 GB does not. Not tried on an iPhone |

## Boot

- **Resolved: SIGSEGV at `main+0x14f71dc`, address 0, 0.8 s after boot.** The game's default online service is Epic Online Services, whose SDK (`rom:/nro/EOSSDK-Switch-Shipping.nro`) the host never loads ([Online SDKs in NROs are never loaded](../../../docs/reference/services.md#online-sdks-in-nros-are-never-loaded)). Unreal's `FOnlineSubsystemModule::LoadDefaultSubsystem` then falls back to `NULL`, which this game does not ship, so `IOnlineSubsystem::Get()` stays null and the game's own code calls through it unchecked (17 sites in `main`). The cut at `main+0x1195798` points the fallback's name at `Switch` (the UTF-16 tail of a string in `ro`): the game gets Unreal's Switch online subsystem, which it ships and which plays offline.
- **Resolved: the survey stopped with `AssertionError: no MOD0`** on an exFAT drive: the `._name.nro` files macOS writes beside each NRO there (engine patch 0039 skips them).

## Rendering

- **Resolved: magenta road, bushes and signs** in the menu scenes and in races. Unreal's streamer writes some textures' texels on the CPU after the game has first drawn them, with no NVN flush: the road's 512x256 ASTC 6x6 base colour sits in a 4 MB pool the CPU writes, not in one of the game's sparse virtual pools. The host had made each such texture a GPU texture of zeros at its first draw, which ASTC decodes as magenta, and nothing looked at it again. `tex_dirty_upload` uploads them from their storage once the CPU has written them. Found by drawing each fragment shader of the main pass flat with `DM_NVN_HILITE` (the road is `183b0debca8a9aad`), then reading the bound texture's storage with the `DM_CTL` `memdump` command: it held the asphalt while the host drew magenta.
- Its streamed textures in sparse virtual pools need nothing: each streamed 512x512 texture (texture flag SPARSE, 0x20) has a virtual pool of its own with its tiles mapped from 4 MB physical pools; the game maps a level before it writes its tiles and fills them over a few frames, and the page table reads catch up (`nvn_sparse_since`). The game picks the finest level it shows by which of the 21 texture handles it registers per texture it binds (one view per base level).

## Running on the Mac

The packed Mac app's launcher with `DM_LAUNCHER=0` and `DM_CTL=<file>` drives it with no settings window: `a` at the title gives the main menu; then `a` World Tour (United States), `a` Florida, `a` New Horizons (Saint Augustine), and `a` at car select starts the race; `zr~12` accelerates. The game sets present interval 2: 30 fps.
