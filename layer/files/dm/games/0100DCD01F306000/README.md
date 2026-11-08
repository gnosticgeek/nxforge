# Mina the Hollower (`0100DCD01F306000`)

Update 1.0.5 (v262144), SDK 21.4.3. Yacht Club Games' own engine on NVN; every RomFS file is a YCD container (`.yc`). Modules `main` and `sdk`. In bring-up: on the Mac (headless) it plays the intro cinematic and reaches the profile menu (Choose a profile, Register your name) with scripted input, at 60 fps with no red line.

## What it needs

| Setting | Where | Why |
|---|---|---|
| Three cuts on `main` 1.0.5: malloc's StandardAllocator 16 GB → 2 GB, the first segment of the two engine heaps 4 GB → 1 GB each | [`patches.py`](patches.py) | with virtual address memory (32 MB system resource) the game reserves 24 GB of address space at boot, which the Switch's 64 GB alias region holds and the 5 GB block does not. See [Memory](#memory) |
| The node-area cut on the SDK 21.4.3 `sdk` build | `dm/tools/sdk_patches.py` | [The SDK's address-region node area](../../../docs/reference/memory.md#the-sdks-address-region-node-area) |
| 5 GB layout: `mem_reserve 0x140000000`, `mem_alias 0x118000000` | [`game.tsv`](game.tsv) | the survey's guess for a game with virtual address memory; the cuts above fit it (62 MB node area + 2 + 1 + 1 GB in the 4.375 GB alias region). Not measured over play yet |

## Shaders

114 single-stage shaders (110 unique keys) in `shaders.pak.yc`: each `shaders/<name>.vert.bin` / `.frag.bin` is {u32 control length, u32 code length, control section, code area}, beside a `.meta` reflection file and `shaders/shader.db`. Read by `shader_split.py` `ycd_shaders` ([Shaders in Yacht Club Games' YCD paks](../../../docs/reference/shaders.md#shaders-in-yacht-club-games-ycd-paks)). Paired as single-stage programs (the cover); the intro and menus draw with all of them found.

## Memory

- **Resolved: `nn::diag` abort in `StandardAllocator::Initialize` from `nninitStartup`** (`sdk+0x141b98` ← `main+0x875c5c`). `nninitStartup` (`main+0x103d90`) makes malloc a StandardAllocator over 16 GB (`Initialize(nullptr, 0x400000000, false)`); `CentralHeap::Init` got no such region. Cut to 2 GB (`main+0x103d9c`).
- **Resolved: SIGSEGV at `main+0xddc1c`, address 0x8, right after `nnMain`.** The engine heap (`main+0xdda90`, set up from `main+0x6d8b8` and `+0x6dc18`) reserves a first segment of 4 GB with `AllocateAddressRegion` (`main+0x1089b0`) and stores through the result unchecked; with no room the region is 0. Both cut to 1 GB (`main+0x6d8ac`, `+0x6dc0c`); the heap adds segments when one is full (its list at +0x40). A third heap (`main+0x73f508`) takes 64 MB segments.
- **Resolved: SIGSEGV at `main+0xde154`, address 0x18, on the audio decoder thread**, when malloc had 1 GB: the game reads its 601 MB sound bank (`default.sndbnk.yc`) into one block through the engine heap's large-block path (`main+0xde0c0`), which falls back to malloc; malloc returned null. Hence 2 GB for malloc and 1 GB for each engine heap's first segment.
- **Open:** measure the alias region's high-water mark over play (`[mem] alias region mapped up to`); +2.84 GB at boot with the earlier 1 / 1.5 / 1.5 GB split.

## Threads

- **Resolved: black screen for good, every frame a clear only, no red line.** The game's `NxMessagePump` thread (priority 44, core 0) blocks in `oe::PopNotificationMessage`, which the host answers by waiting on a host condition variable; counted as a runnable core-0 peer, it held the audio decoder (priority 59, core 0) in a same-core handoff after each mutex unlock, so the sound banks never finished loading ([Native HLE waits release the guest core](../../../docs/reference/threads.md#native-hle-waits-release-the-guest-core)).

## Running on the Mac

`<NSP folder>/0100DCD01F306000-work/run/boot.sh <log name> [seconds] [VAR=value ...]` boots the packed Mac app's host headless and silent (`DM_KEYS`, `DM_NVN_SHOT` for scripted runs). `DM_KEYS="20:Plus*20/5,22:A*20/5"` reaches the profile menu by about frame 7200.

## Found on this game

- **YCD paks** (`ycd_members` / `ycd_shaders` in `shader_split.py`): [Shaders in Yacht Club Games' YCD paks](../../../docs/reference/shaders.md#shaders-in-yacht-club-games-ycd-paks).
- **Host-blocking HLE calls are not runnable core peers** (`dm_thread_native_wait`, `hle_thread.c`; used by `oe::PopNotificationMessage`): [Native HLE waits release the guest core](../../../docs/reference/threads.md#native-hle-waits-release-the-guest-core).
- **The SDK 21.4.3 `sdk` build's node-area cut**: [The SDK's address-region node area](../../../docs/reference/memory.md#the-sdks-address-region-node-area).

## Open

- Gameplay past the name entry; the iPhone; memory over a minute of play.
