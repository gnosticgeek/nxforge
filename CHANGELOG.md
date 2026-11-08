# Changelog

NXForge releases are tagged `vX.Y.Z` on `main` ([UPSTREAM.md](UPSTREAM.md#versions) has the rules). Each entry lists what NXForge adds on top of [nxnative](https://github.com/seedds/nxnative); upstream's own changes come in through the merges it names.

## 0.20.0 (2026-11-08)

- **Up to nxnative `028a263`** (4 commits past 0.19's engine `c78d737`): cloud saves can ask which copy to keep when both changed (nxnative #1785, `DM_SAVE_SYNC_CHOICE`), Minecraft Dungeons II runs at 60 or 120 fps, Luigi's Mansion 3 holds 60 fps, and a README pointer to nxnative's Discussions. Only the packing patch needed a hand (a test file both sides added to). No shader chain change, so no game's shaders are translated again.
- **`scripts/layer.py continue [--skip]`:** after fixing a patch that stopped an update, this finishes it and applies the patches after it. Before, `git -C tree am --continue` finished only the stopped patch, and `layer.py export` then dropped the rest; export now refuses until they are applied.

## 0.19.0 (2026-11-08)

The engine-and-layer release: nxnative's engine is no longer merged into NXForge commit by commit. NXForge pins an untouched nxnative commit and keeps its own changes as a layer on top ([UPSTREAM.md](UPSTREAM.md#engine-and-layer-from-0190)).

- **The engine is pinned, not merged.** `layer/ENGINE` names the nxnative commit (now `c78d737`, nxnative's `main` of 2026-11-08). NXForge's changes to nxnative's files are nine patches by theme in `layer/patches/` (player, host threads, video, Metal, shader tools, packing, dev tools, game profiles, docs), and the files NXForge adds are in `layer/files/`. `python3 scripts/layer.py assemble` puts them together in `tree/`, where builds run; the Converter and the `nxforge` command line do it for you before a build.
- **Taking nxnative's changes is one step:** `scripts/layer.py update` moves the pin to nxnative's newest `main` and carries the patches over; `scripts/layer.py try` first shows which patches would need a hand.
- **Up to nxnative `c78d737`** (14 commits past 0.18's engine), with nxnative's own versions of two things NXForge carried copies of: the mesh-shader prewarm fix (nxnative #1368) and the pipeline archive compaction (NXForge keeps its higher file limit, 24, its 5-minute flush spacing and the flush at exit). Shader chain `98747cde2289`: every game's shaders are translated again on its next build.
- **NXForge Converter 0.4.0** ([CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md)): works with the new layout.
- The repository's root is now NXForge's own: the Converter (`app/`), its scripts and tests, its docs and changelogs. nxnative's README, docs and tools are in `tree/` once assembled, and on [nxnative's GitHub](https://github.com/seedds/nxnative).

## 0.18.1 (2026-11-08)

- **NXForge Converter 0.3.1:** the sidebar's pages can be clicked again (0.3.0 left the list unable to select any page).

## 0.18.0 (2026-11-08)

- **NXForge Converter 0.3.0: one updater.** An Updates page for the engine, the converter and the in-game sidebar, each with its own Update button; the engine now updates to the newest release tag (and fetches before it updates, so it no longer says "Updated" while a newer release exists); a sheet at launch when something is newer, with an Update automatically switch; upstream nxnative commits not merged yet are shown for information; games on an older sidebar can be rebuilt in one go. [CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md) has the details.

## 0.17.1 (2026-11-08)

- **NXForge Converter 0.2.1** ([CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md)): the converter no longer hangs for 20 seconds or more at launch (the menu bar build progress is now a plain status item, shown only while a build runs).

## 0.17.0 (2026-11-08)

- **NXForge Sidebar 0.2.0** ([SIDEBAR_CHANGELOG.md](SIDEBAR_CHANGELOG.md)): pause while the sidebar is open, a save backup button, Full screen and Picture size (Fit, Stretch, Pixel-perfect), control swaps, mod load order, mute, recent captures, a frame-time graph, defaults for every game, cheat sections and search, and each game's settings in a plain text file (`NXForge settings.txt` in the game folder).
- **NXForge Converter 0.2.0** ([CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md)): a page per game (launch settings, playtime, whether a rebuild is worth it, the profile's notes, save import, export and Git backup, frame-rate history), the Library as covers with Continue Playing, keyboard and controller navigation and a couch mode, Go to Anything (⌘K), Build selected later (tonight, at a time or on power), Undo for tidying, offline-drive handling, menu bar progress, notification actions, an iPhone and iPad IPA build, and What's New with self-update.

## 0.16.0 (2026-11-07)

- **The sidebar has its own version.** The in-game Quick settings sidebar is now versioned and released on its own, starting at **NXForge Sidebar 0.1.0** (tag `sidebar-v0.1.0`), with its own [SIDEBAR_CHANGELOG.md](SIDEBAR_CHANGELOG.md). The sidebar shows its version under the button legend. NXForge's releases keep their `vX.Y.Z` tags; `scripts/release_check.py` and the `release` workflow handle both kinds (UPSTREAM.md, Versions).
- **The Converter has its own version.** The NXForge Converter app is versioned the same way, starting at **NXForge Converter 0.1.0** (tag `converter-v0.1.0`), with its own [CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md). It shows its version under the NXForge name in the sidebar, in About NXForge Converter (with the engine's release) and in Copy diagnostics and error summaries. The engine row and the app's build number still come from the `v*` tags only.

## 0.15.0 (2026-11-07)

The thin-fork release: NXForge is now the Converter plus a Mac player layer on nxnative's engine ([UPSTREAM.md](UPSTREAM.md#engine-and-layer-from-0190)). Merges nxnative's `main` up to `bd979ce` (19 commits since `d777f0a` and the picks). The shader chain changes (`4f4abb1e5355`), so every NVN game's shaders rebuild once.

**From upstream `main`**
- Pikmin 4 and DRAGON BALL Sparking! ZERO play at 60 fps, and up to 120 on the Mac (Unreal's fixed frame rate). DRAGON BALL's encrypted IoStore containers split their shaders.
- The controller applet's player prompt: a game that asks for more players than have joined waits for them behind a prompt (on the keyboard, Return or J is done and Escape or K closes it).
- Every package's title ID and version come from its content metas, not its file name.
- WaitSynchronization keeps the objects it waits on, Ori and the Will of the Wisps finds copied programs' keys, Ocarina of Time's foliage no longer flashes, and counter reports take their time from Metal's paired CPU sample.
- Landed versions of pull requests NXForge carried early replace NXForge's copies: the shared pixel-shader body (#1520) and the shader-code pools left out of the residency set (#1484, `mtl_addr_known`).

**Thin fork**
- The in-game sidebar's glue, its controller navigation, control remapping and the present filters live in NXForge's own files (`dm/host/nxforge/`, `dm/gfx/nvn/nxforge/`), which nxnative's files include at one line each. `front_mac.m` differs from nxnative's by 159 lines instead of 468.
- NXForge's own red lines have a table of their own (`NXF_RED_ONCE`), so upstream's `RED_ONCE` keys keep their numbers and no merge renumbers them again.
- Kept until upstream lands them: the open upstream pull requests NXForge already carries, and NXForge's fixes headed upstream. Four of those are ready as single commits on nxnative's `main` (`contrib/vp9-late-free`, `contrib/gpu-watchdog`, `contrib/dirty-page-pool-bounds`, `contrib/c1-tables-stable-bytes`).
- Kept on top of upstream's content-meta scan: a cartridge with several applications (Belmont's Curse and its Art Gallery) still packs the largest program.
- README and UPSTREAM.md describe NXForge as the Converter plus a Mac player, and UPSTREAM.md has the thin-fork merge rules.

## 0.14.0 (2026-11-07)

Merges nxnative's `main` up to `5636e7a7` (20 commits since `04df08d`), mostly Ocarina of Time fixes. The shader chain changes, so every NVN game's shaders rebuild once.

**From upstream `main`**
- Ocarina of Time: the ground no longer opens in holes after walking (#1604: an uncompressed texture is taken from its storage unless the GPU wrote that storage, not its pool; this replaces NXForge's range tracking from #1390), the dotted rows across fog and light are gone (an HMMA outside a chain no longer overwrites a chain's accumulator, #1537), and the game no longer crashes at the first note of the ocarina (#1527).
- Translator fixes: I2F / F2F directed rounding (#1411), half-pair swizzles and HSETP2 .FTZ (#1410), Ampere IADD3 / PLOP3 / POPC / FLO / LEA (#1329), ATOMS.INC / DEC / CAS (#1413), large-turn MUFU.SIN / COS (#1234). The LDSM subgroup barriers are upstream's landed version (#1376), which replaces NXForge's.
- Landed versions of pull requests 0.13.0 carried: the pool table notes (#1489) and bound render targets kept across submissions (#1502). A GPU whose access macOS revoked stops the game (#1332); NXForge keeps its own alert, which quits as ⌘Q does.
- A damaged `.zs` file in a NUP or dump stops the build (#1530), Sonic Superstars plays on the Mac, and a jump table's bound is the compare its branch acts on (#1515).

Then merges `main` up to `d777f0a` (35 more commits). The shader chain changes again (`34c912566064`).

**From upstream `main`, second merge**
- Ocarina of Time: the foliage mesh pipelines build again (mesh shaders get the outputs their pixel shaders read, #1590, #1628), Kokiri Forest loses its white blotches (#1575), command allocators no longer grow to 36-80 MB each (#1556), the dynamic-resolution depth buffer no longer keeps 15-16 sizes alive (#1557), terrain tile maps the CPU rewrites are read again (#1558), and a prewarm seed list for a first start (#1493, #1488; replaces the open pull request copy 0.13.0 carried).
- Compute pipelines in the pipeline archives as upstream landed them (#1307), in place of #1522. NXForge's compute prefetch at program creation and its incremental archive batches stay.
- Shared-memory byte stores are one Metal store (#1503 as landed). A texture ID with no texture drops its cached view (GPU page faults, #1607). GPU copies into write-protected pool pages are kept (#1591).
- Controllers: press a button to join (`DM_PAD_PRESS_TO_JOIN`, #1596), identical pads each get a player (#1595), HID pads wait for GameController (#859). NXForge's button remap stays.
- Tetris 99, Pokémon Friends, Trails in the Sky, Splatoon Raiders, Super Smash Bros. Ultimate, Super Mario 3D All-Stars and Hyrule Warriors: Age of Calamity fixes; a packer update keeps an intact NUP image (#1630).

**Mario Kart World** (open upstream pull requests)
- Free roam stays near 4 GB: `MapPhysicalMemory` past the 9 GB pool fails as on Horizon, so the game frees its own blocks (#1594, `mem_map_limit on`).
- Dynamic resolution works: timestamp reports take their segment's GPU time (#1229, `gpu_timestamps segment`), as on Donkey Kong Bananza.
- Indirect-count multi-draws are copied before the pass opens, so the scene passes are no longer split: GPU p50 13.65-14.1 to 13.0 ms on an M4 Pro (#1179).
- Texture samples overlap better on the GPU (#1230, `shader_border_emu 0`, `shader_nan_coord fmax`), measured on an M1 Pro.
- Not taken: #1350 (segment times without the GPU's idle gaps: written before upstream's in-buffer segment boundaries, and with them two reports in one command buffer read the same time), #1251 (cube-map prefilter split by output; written before the one-file shader libraries, its MSL copy does not fit them), #1292 (1.8.0 image slots; this Mac has the base game), the LAN and iOS work in progress (#1321, #1383).

**Converter: Library**
- A **Library** page lists every game under a games folder you choose (Library or Settings; for example a share at `/Volumes/Gaming/roms/switch`): folders of NSP / XCI / NSZ / XCZ files, Switch 2 `.nup` files and dump folders, in every folder below it. Each row has the game's name, console, base / update / DLC, title ID, size and whether it is built, and **Convert** makes it the game on Convert. Games whose files share a folder are listed one by one and moved into a folder of their own (a rename) before they build, since the build takes one game per folder. Folders with only an update or DLC, and DLC in a subfolder the build does not read, get a note.
- Made for slow network shares: names come from file names (nothing is opened), one listing per folder with a 20-second limit, a folder that does not answer is skipped, three in a row stop the scan (keeping what it found), and the list is kept between starts in `library.json`. `NXForgeConverter --library <folder> [<prod.keys>]` prints the same scan.
- Each game's own name, icon, publisher and version, read from its Control NCA with `prod.keys` (a few hundred KB per game: 31 games on a network share in about 3 s), kept between scans.
- Badges for games NXForge lists as playing, booting or broken, or has a profile for, and for built games (on the current or an older engine; apps are matched by title ID wherever they were built), with a filter: not built, plays, has a profile, built on an older engine, newer update than the build, needs attention.
- **Build selected**: tick games and they build one after another, after a free-space estimate per drive; a failed game is noted and the next starts, a stop or low disk ends the run, and a summary (and notification) follows.
- A folder holding a newer update than the one the app was built with says so. Update and DLC files in a subfolder move beside the game in one click, and the same game in two folders gets a note on each.
- The games folder is scanned again when its drive or share mounts, and when the Library opens on a list over a day old.

**Converter: Apple Human Interface Guidelines pass**
- Settings is its own window from the app menu (⌘,), laid out as a grouped form; a signing failure links to it.
- Mac-sized type: the window title names the page (the game on Convert), page titles and oversized buttons are gone, sidebar rows use the system size.
- Builds is a real list: arrow keys select, ⌘⌫ moves the app to the Trash, double-click opens it; the detail scrolls beside it in a resizable split.
- Page actions (Rebuild All, Scan Again, Run Checks, Measure Again, console filter, sort) and search live in the window toolbar; search is the standard field.
- Confirmations are sheets on the window; Trash, Stop, Quit and Clear buttons are red; a notice has just OK.
- One blue button per view, on Return (Build Mac app; Open app or Rebuild on Builds); Library's row Convert buttons are plain.
- Native empty states on Builds and Library; the window goes down to 820×580 and Convert's cards stack when narrow.
- View menu switches pages with ⌘1 to ⌘5; Help › NXForge Converter Help opens the README.
- Convert restyled after Tom's mockup: navy theme in Dark Mode, the app's name over the sidebar, a drawn dusk banner behind the page heading, numbered Source files and Mac app cards with a drop zone (Choose Game… / Choose Keys…), seven numbered step tiles in Build activity, and the log always below with All / Warnings / Errors tabs.
- Toolchain restyled the same way: a peaks banner, a green Liquid Glass Ready to build bar, the tool table grouped with icons and an ⓘ per tool, and an Engine card with glass Change location / Check for updates, the environment details, Advanced configuration, Copy environment and Copy diagnostics.
- Storage restyled too: a disk card with a used/free bar, Reclaimable space with Clean Up…, glass filter chips by type with counts, search and sort, and a selectable table with coloured type icons and badges, folder and … buttons, and Delete Selected….
- Convert has a Remove build folder after building switch (the same choice as Settings › After a build: Remove build cache).

**Small fixes and tweaks**
- `c1_full.tsv` and `cb_extent.tsv` keep their bytes when a full shader build finds the same rows, and a new one carries no clock time, so a rebuild that changes no shader changes no packed table (from devinhurry's fork, f6c3b82b).
- `nxforge status`: a running build shows from its script (`build_ipa_from_nsp.py --mac base.nsp ...`) instead of the Python framework's path, once instead of twice (the converter's `caffeinate` wrapper), and recorded builds whose app was deleted are counted on one line.
- `nxforge doctor [game folder]` also checks the optional tools the converter's Toolchain page lists (glslang, nsz, zbic) with the command that installs each; given a game folder, the ones that game needs count as required (as the converter decides it), and doctor exits 1 when a required tool is missing. The MCP tool takes `game_dir` too. `nxforge build` refuses up front, with the install command, when the game needs one that is missing, as the converter does, instead of stopping partway.
- CI: the tests and both lint workflows also run on pushes to a `release-*` branch (a newer push cancels the older run there), so a break on the day's release branch shows before its release pull request opens.
- Verified on NXForge (`docs/nxforge-games.tsv`, the converter's Builds page): Mario Kart World and The Legend of Zelda: Ocarina of Time, as played on this Mac on 2026-11-06 and 2026-11-07.
- The C lint ratchet is green again after the upstream merges: a texture without a pool no longer dereferences a null pool in the first-use log line (#1604), and two tests stop cleanly when a Metal lookup returns nothing.
- After the second upstream merge of the day: `t_present_rescue`'s 30 fps checks (#1555) run with `DM_PRESENT_LATENCY` set, the one case where NXForge keeps the display link in fullscreen, and the device-shared range table grows through a temporary pointer (C lint).
- `uepak.py` unpacks its cached image before `find_key`, so the Python lint passes with upstream #1646.

**From upstream `main`, 13:30 check (picked, not merged)**
- Ocarina of Time no longer faults on the GPU 15-45 minutes into play (#1644): a retired texture stays resident while any serial entry still draws with it. NXForge's shared-texture release (`alias_let_go`) follows the same rule.
- The NSP script's fallback tool folders come after the caller's `PATH` (#1475).
- Not taken yet: upstream's landed #1520 (readable-tile split, a new shader chain) and #1484 (pool residency for shader keys). NXForge already carries both as pull-request heads; the landed versions come with the next full merge.

**From upstream `main`, 13:45 check (picked)**
- A texture copy into an uncompressed alias of a compressed texture writes the compressed texture (#1617, Monster Jam Steel Titans 2's arena floor). Its red-line key is 159 here (156 is taken). `DM_NVN_BC_ALIAS=0` turns it off.
- The shader split reads legacy Unreal paks with encrypted indexes (#1646), and `--progress json` sends a game event before the shader stages (#1627).
- Not taken yet: the NSP script's title IDs from content metas (5c4dc18f) and its ShaderWatch test follow-up (0caa6f93), which conflict with NXForge's build script; they come with the next full merge.

**From upstream `main`, 15:45 check**
- Picked: the graphics and sanitizer test targets run from a checkout path with a space (12ddb1fb).
- Mario Kart World's blob shadows draw again (32335650, #1648, merged by hand): an image slot takes a view of the Metal type its shader declares, alongside NXForge's sRGB image views in `img_fit`. Its red-line key is 160 here (157 is taken).
- Left for the next full merge: the controller applet waits for players (24fe1e5a; meets NXForge's `front_mac.m`).

**From upstream pull requests (not yet on `main`)**
- Ocarina of Time's foliage no longer draws as flat white, blue and cream shapes for its first seconds (#1368): a task / mesh pipeline missing at its first draw is built there instead of the draw being left out until a background build finished (3.5 to 7 s each on an M4 Pro), and it is recorded in the prewarm list, so later starts build it during the prepare screen.

## 0.13.0 (2026-11-06)

A performance release. Merges nxnative's `main` up to `04df08d` (11 commits since `88c7e03`) and upstream pull requests that are still open, picked for build and run-time speed. The shader chain changes, so every NVN game's shaders rebuild once.

**From upstream `main`**
- Raw global memory lookups start from the entry they chose last (#1464): about 2 ms less GPU a frame in Ocarina of Time's Kokiri Forest.
- The HMMA title-movie network keeps its matrices in SIMD-group registers (#1456): 26.7 to 18.9 ms of compute a frame on an M4.
- A storage takeover asks the live texture objects in one lookup (#1439): Ocarina of Time's long frames in Kokiri Forest fall from 332 to 212.
- A shader build keeps finished shaders in `cas.db` and writes the image from there, so a build folder holds a few hundred files instead of tens of thousands. It needs more free disk at its peak, though: `cas.db` and the image it writes sit side by side, so a first Ocarina of Time build peaks at about 52 GB (24 GB extracted game, 13 GB `cas.db`, 11 GB image, about 4 GB pipeline archive). Leave that much free before a game's first 0.13.0 build.
- Minecraft Dungeons II and ŌKAMI HD play on the Mac.

**Build speed** (open upstream pull requests)
- Faster cold Metal shader builds (#1520): `metal` and `metallib` are launched directly, a fragment shader's body is compiled once instead of once per integer entry, and the fetch variant comes out of the same compile.
- Compute pipelines go into the bundled pipeline archive and load from it in about 0.3 ms instead of compiling at their first dispatch (#1522).
- The shader folder is `shader.noindex` (#1438), so Spotlight no longer indexes a shader build. An existing `shader/` folder is moved there on the next build, and the Mac app is packed again once.
- The shader split decompresses zstd in-process (#1463) and no longer hangs at 88 % on Ocarina of Time.

**Run-time speed** (open upstream pull requests)
- Ocarina of Time has a pipeline prewarm list (#1493), so a first start prepares its pipelines instead of showing a black title for minutes.
- Memory: pools that hold shader code are no longer made resident (#1484, 334 MB in Ocarina of Time); a pool's render targets share one placement heap (#1453); a pool table is rebuilt only where a change reaches it (#1489).
- Shared-memory byte stores use atomic AND and OR instead of a compare-and-swap loop (#1503).
- Submit thread: guest thread wakes after the lock is released (#1466), a cached texture class check (#1467), fewer feedback-snapshot lookups (#1469), argument tables copied when only uniform buffers changed (#1472), no retain per texture lookup (#1473).
- A long render pass starts on the GPU while it is still translated (#1468, `DM_NVN_PASS_SPLIT`, default 256 draws, `0` turns it off).
- Bound render targets stay alive across command submissions (#1502, a crash fix).
- NXForge: dirty-page tracking rejects an address outside every memory pool before it walks them (each file read and write fault walked up to about 5,000 pools in Mario Kart World), and an OpenGL partial clear reuses its depth / stencil state instead of making one each time.

**Fixes**
- `vk_shaders.py` closes its children's standard input, so a Vulkan game's shader build can no longer hang on a `spirv-cross` waiting for input (from xinerqu/ns2ios-shell).
- Mario Kart World no longer aborts after a race (0x1c286f): the VP9 player's first "free" signal, when its worker takes it after Start, now reads as a picture instead of an error.

**Kept in NXForge**
- The LDSM subgroup barriers stay, and now also fence the compute form of LDSM that upstream's HMMA rework lowers in `TensorPass`.
- NXForge's shared Metal library cache, its `posix_spawn` launches and its smaller translator runs stay. NXForge's own finish scheduler (0.11.0) gives way to upstream's batch pipeline, which translates the next batch while it finishes this one.

## 0.12.0 (2026-11-06)

Merges nxnative's `main` up to `88c7e03` (25 commits since `865cc35`, 2026-11-04 to 2026-11-06), resolved on the Ocarina of Time branch (`claude/project-thread-27ja4m`). That branch built and passed its tests on the Mac, then ran a 10-minute Kokiri Forest check. The notes below are what changes for NXForge.

**From upstream**
- **The Legend of Zelda: Ocarina of Time (Switch 2) is on upstream's `main`.** Upstream closed the bring-up pull requests NXForge had merged ahead of it (#1299, #1300, #1312, #1343, #1345, #1353, #1354, #1359, #1360, #1373, #1428, #1430, #1434) and landed its own versions. NXForge now takes those versions whole, translator, host and tests together, instead of keeping the pull-request copies. #1394, #1393 (`pool_skip_retired`) and #1368's mesh prewarm are dropped too, because upstream's new versions replace them. Measured against the 0.11.0-based app on the same save and route: median frame 22.0 ms (was 26.1), p95 23.8 ms (was 28.2), peak resident memory 10.1 GB (was 14.2), no crashes and no red lines.
- **Kirby Air Riders (Switch 2)** plays at 60 fps, and Mario Strikers: Battle League gets past its black screen after the loading text.
- A failed command buffer now names its game shaders (upstream's version of the hang names NXForge carried from an open pull request). Each audio renderer plays from its own PCM blocks. The Mac's alias region is the Switch's 64 GB. A 5:4 cutscene crop fills a 16:9 screen again (Galaxy 2).

**Kept in NXForge**
- NXForge keeps its own `dm/tools/romfs_image.py` (#1354 as NXForge merged it, which also accepts stamps written before the change). Upstream's landed version differs only in that check. The packer's bytes are part of the image stamp, so keeping NXForge's copy means no game's RomFS image is packed again; Ocarina of Time's is 26 GB.
- Upstream pull requests that are still open stay merged: #1414 (ATOMG.CAS), the LDSM barrier and the rest that `.github/upstream-watch.tsv` does not skip. NXForge's own GPU watchdog (`DM_NVN_GPU_WATCHDOG`) and the stop when macOS revokes GPU access are kept as well.
- The FXAA warnings move to `RED_ONCE` slots 156 and 157, because upstream took 153 and 154.
- The shader chain is now `053e94e1fda9`, so every NVN game's shaders rebuild once.

**Fixes**
- `shader_split.py`: a damaged NARC or NDSR pack is a red line, not a crash (found by the nightly fuzz job).

## 0.11.0 (2026-11-05)

Merges nxnative's `main` up to `975bb4c` (260 commits since `2716f78`, 2026-10-31 to 2026-11-04). The notes below are what changes for NXForge.

**From upstream**
- **Switch 2 games**: Donkey Kong Bananza, Splatoon Raiders, Fire Emblem Fortune's Weave, Pokémon Pokopia, Hyrule Warriors: Age of Imprisonment, Mario Kart World and Mario Tennis Fever play on the Mac. They are built from one `.nup` file or a dump folder, not from NSPs, and need no `prod.keys` (README › Switch 2 games). Switch 2 (Ampere) shaders translate natively, and textures untile in the Switch 2's order.
- **New game profiles** include Mario & Luigi: Brothership, Super Mario 3D All-Stars (one app of several programs), DAVE THE DIVER, Princess Peach: Showtime!, Skyward Sword HD, Super Mario RPG, SUPER ROBOT WARS Y, Castlevania: Belmont's Curse, TRIANGLE STRATEGY, Hollow Knight and DRAGON QUEST I & II HD-2D Remake.
- AV1 movies through dav1d where VideoToolbox has none; the Shift + arrow keys are the right stick; game file extensions in any letter case; merged packages (base game, update and DLC in one file); `LSSupportsGameMode` off, since macOS's Game Mode held the GPU at its lowest clock.
- Frame latency 2 now only on variable-refresh screens in fullscreen, and `DM_PRESENT_LATENCY` is clamped to 1 or 2 (all the display link takes).
- The tested Metal compiler is Xcode 27.2's (32023.922.4).
- Mario Kart World's sky panels are gone: task and mesh draws read their storage buffers from the right table (c0 0x670 / 0x770) instead of a dummy buffer.
- 120 fps for a profile with `fps_max 120` (Fire Emblem Fortune's Weave first).

**Games** (NXForge, ahead of upstream)
- **The Legend of Zelda: Ocarina of Time (Switch 2, `0400486024DEC000`) builds from its .nup and plays.** Upstream's open bring-up pull requests are merged ahead of upstream: #1299 (profile, title screen, Kokiri Forest), #1300, #1312, #1331, #1343, #1345, #1353, #1359 (the washed-out glow), #1360 (the GPU hang about 10 minutes in, combined by hand with #1299's pool table hints), #1368, #1376, #1377, #1379, and the Mac-side fixes #1304, #1305, #1308, #1320, #1332, #1354, #1355, #1356, #1373 and #1382. The alias region is 8 GB (an abort 5-15 minutes outdoors, from upstream f3ac5ead). 7 of its 42,854 shaders still do not translate (Ampere 0x3a9 ATOMG.CAS and 0x481).

**Automation**
- **`scripts/nxforge.py`, a command line for the converter's functions, and `scripts/nxforge_mcp.py`, the same as an MCP server** ([docs/automation.md](docs/automation.md)): status, builds and rebuilds (with `--plan`), background build jobs, engine updates, a tool check, a disk report, and a cleanup by category. `clean --safe` is the set an hourly job can run: idle Metal build folders, build folders' temporary files, the shared Metal cache trimmed to 12 GB, older app backups (the newest per game stays) and logs over 30 days old; it never touches game files, keys, apps outside `app-backups/` or saves, and waits while a build runs.
- **Watched games.** The nightly `upstream-check` workflow also lists upstream pull requests about the games in `.github/upstream-watch.tsv` (Ocarina of Time for now) that no NXForge branch holds yet, looking at their changes, since upstream lands pull requests as new commits. With issues turned off for the repository, the report is the run's summary; both jobs had failed every night on that.

**Kept in NXForge**
- Fullscreen still goes without the display link (the 30 fps fix); `DM_PRESENT_LATENCY=1|2` keeps the link there to compare.
- A controller's Home button still opens Quick settings. nxnative's new hold-Home-to-quit prompt is off unless `DM_HOME_QUIT=1`.
- A cartridge with several applications (Belmont's Curse and its Art Gallery) still packs the largest program, now by passing it to nx_extract's new `--app` (the old `--title <id>` option is gone).
- The FXAA warnings moved to `RED_ONCE` slots 153 and 154. The shader chain is now `907b404e076d`, so every NVN game's shaders rebuild once.

**Building**
- **Rebuilds redo only what changed.** After a shader fix, the pipeline archive compiles only the bases whose shaders changed, in a new group beside the groups it keeps, instead of every group a changed shader sits in. Ocarina of Time's 31 groups (30,515 bases) took 26 minutes after each translator fix; a fix that touches a few hundred shaders now takes one group.
- **The shared Metal cache holds a large game.** Its limit is now 12 GB (`DMSH_MTLCACHE_GB`, was 4), and a build never removes a library it used itself. Ocarina of Time's 7 GB of libraries pruned themselves at 4 GB, so the next translator change compiled 12,000 of them again.
- **`--plan`** (`--platform mac-app`) says which stages a build would reuse and which it would redo, with how long each took last time, and builds nothing. `pso_offline.py --check` and `pack_app.py --check` answer the same for the pipeline archive and the app.
- **Signing reads the game data once.** The Mac app's RomFS image, shader libraries and pipeline archive now sit in a signed resource bundle of their own (`Contents/PlugIns/GameData.bundle`, with links in `Contents/Resources` where they were). The build keeps it in `<id>_build/app/data` and clones it into each new app while its inputs are unchanged, so a rebuild signs a few MB instead of hashing the whole game. Measured on Ocarina of Time (35 GB, M4 Pro): signing the app went from 157 s to under a tenth of a second once the data bundle is signed, which costs the 150 s once, when the game data changes. A game of several programs keeps the old layout.
- **The shader step's end is shorter.** The translator runs in more, smaller groups that the workers take from one queue. Paired vertex shaders start as soon as their own pixel shaders are done, instead of waiting for every other shader, and the shaders to compile go before cache hits. The change is to `dmsh_build.py`, so the shader chain is now `d4f0ef1fcb82` and each NVN game's next build translates its shaders again (the Metal libraries come from the cache).
- **The converter keeps a build at full speed in the background.** The build runs at user-initiated priority (performance cores first), and the converter holds off App Nap and idle sleep until it ends.
- The build folder is excluded from Time Machine (`tmutil addexclusion`), since every build rewrites it from the game files.

**Converter**
- **Switch 2 games build from the app.** Choose a game's `.nup` file (or a folder holding one, or a dump folder) on Convert: no keys are asked for, and the converter lists the container's base game, updates and DLC, says whether NXForge has a profile for the game, and stops before the build when the game's code needs `zbic` and it is not installed. The disk check allows for a Switch 2 build's size (about twice the game plus 20 GB), and **Preview build** runs `--plan` on an engine that has it. The converter's own Python now installs `zbic`. The command line takes `--convert <game>.nup` without keys.
- **Failed builds say what went wrong and what to do next.** The Convert page names the cause (not enough disk space, a 32-bit game version, keys, game files, the Metal toolchain, Xcode, .NET, Python modules, a missing tool, memory, file access, the rewriter, shaders, signing) with the next step, a button to the page that fixes it, and **Copy error summary**: the diagnosis, the failed step, the Mac, Xcode and engine versions and the log's red lines, with key values, the keys file's path and the home folder taken out. `--convert` and `--rebuild` print the same line. After LumaNX's `Worker/diagnostics.py`.
- **Save snapshots** on the Builds page: a copy of the game's save (and its device save) checked file by file with SHA-256, kept beside it in `save-snapshots/`. Restore checks the snapshot again, keeps the current save as a snapshot, and swaps each save folder in with one rename (`renamex_np` `RENAME_SWAP`), so a save is never half restored; it refuses while the game is running. A rebuild and Restore this version make a snapshot first; the newest 10 automatic ones stay. After LumaNX's `Worker/recovery.py`.
- The failure explanations and save snapshots are two ideas from [LumaNX](https://github.com/Xc1Ym/LumaNX) (MIT), another nxnative front end, reimplemented in the converter.
- **One progress bar with the time left.** The build shows as a timeline: a piece per step, sized by how long it takes, with "About 23 min left" and when it should be done. The estimate comes from this game's last build (`<id>_build/logs/stage_times.json`), or other games' builds scaled by size, and the script's own rate for the step it is in. The Dock badge shows the minutes left. Every step and the log are behind Show details.
- **The pipeline archive shows its batches** (12 of 31) instead of one quiet 26 minute step, and any step that has been quiet for a minute says it is still working.
- **Disk space is watched during the build.** Below 12 GB free on a volume the build writes to, the window warns; below 3 GB it stops the build cleanly, so building again carries on from the steps that finished. The estimate before a build now counts a rebuild's second copy of the app and the shared Metal cache.
- **Long builds are harder to lose.** Quitting asks first, Stop says what is kept, closing the window lets the build carry on, and the Mac does not idle-sleep during a build.
- **Tools a game needs are required for that game**: zbic for Switch 2 games and code built with system 22 or later, nsz for compressed files, glslang for OpenGL games, each with an Install button on Convert. The converter's own Python now includes zbic.
- **Fix all** on Toolchain runs every fix in one Terminal window, and the checks run again when you come back. **Copy environment** gives the PATH, DOTNET_ROOT and command to run the build by hand.
- **Build reports**: each build keeps its step times and log (`<id>_build/logs/converter-<time>.log`), shown in Builds with the build's timeline.
- **Storage page**: every game's build cache, older app copies, apps and the shared shader cache, with sizes, free space per disk and Delete for what can be made again.
- **Log viewer**: All, Warnings and Errors filters, search, follow the newest line, and Open log file.
- A new app says that its first launch prepares shaders and is slow, until it has been opened once.

**Quick settings (in the game)**
- **Pages instead of fold-out sections.** Quick settings has six pages in tabs (Graphics, FPS, Capture, Mods, Cheats, Controls). L and R on a controller, or Tab and Shift-Tab on the keyboard, turn the page, and the last page shown is remembered per game.
- **A quick bar on every page**: Screenshot, Record, the FPS counter and the volume. The Sound section is gone; its slider lives here.
- **A button legend** at the bottom says what works on the selected item ("A Change · ◀▶ Adjust · B Close · L R Page"), in the controller's own button glyphs, or as keys while the keyboard drives it. Opened from a controller, the sidebar starts with the page's first item selected.
- **One "needs a restart" signal.** Anisotropic filtering, Record frame times and mods carry a Next launch tag, orange while the choice differs from the running game. The footer counts those changes and offers **Restart game** (pressed twice), which quits and starts the game again through the app's launcher.
- **Simpler Graphics page.** The filter is now just a CRT switch, with Strength and Line size shown only while it is on; the page is split into Look and Image quality. Sharpen, Pixel-perfect, CRT-Lottes and LCD Grid left Quick settings and the Graphics menu (a saved choice of one starts as off); `DM_PRESENT_FILTER` still reaches them. A dot marks each setting changed from its default, and Graphics and FPS have a Reset button. Record frame times moved under FPS › Advanced.

**From Mario Kart World's logs** (NXForge)
- **Starts no longer wait for the shader archive's compaction.** Every play session left 40-120 small pipeline archive files, so every start compacted the archive again, recompiling each base before the first frame: Mario Kart World waited 16-25 s at "Preparing shaders". The prepare step now takes the bases from the archive (0.5-0.9 s on an M4 Pro, measured), and the compaction's recapture runs after the first frame in parallel at utility QoS. While playing, the archive is written at most every 300 s instead of 10 s after every new pipeline, with a last write at exit, and it compacts past 24 files instead of 8 (`DM_PSO_ARCH_COMPACT=<n>`).
- **Long frames say where the time went.** Each `[longframe]` line adds the upload sub-steps (texture making, write protection, GPU deswizzle encoding, CPU route), submit wall / CPU / kernel / off-CPU time, residency commits, write-protection faults and `mprotect`, the present and drawable wait, the game's own fence waits and the acquire wait. Mario Kart World's first race frame (about 500 ms) is mostly residency commits of its 131 MB of new textures (100-210 ms), deswizzle encoding (80-150 ms) and the game waiting for the GPU (100-130 ms).
- **GPU memory by kind**: next to each memory line, the GPU allocation split into the game's pool buffers (its own pages, no copy), packaged textures, other host textures and the rest.
- **A full movie decoder queue is not an error.** `nn::codec` answers a packet with "not now" (3603) when 12 pictures wait for a buffer and the player sends it again, so it is logged once per decoder and counted at end of stream instead of as a red line. Mario Kart World's menu movie loses no packet (its streams end after exactly 300, 600, … pictures).
- The CPU texture uploads (storage not in a pool buffer) name their first few textures.

## 0.10.0 (2026-10-31)

Five ideas from [NX2Apple](https://github.com/LNPANDY/NX2Apple) (MIT), another nxnative front end; no upstream merge.

**Building**
- **A newer Metal compiler of the tested generation builds.** Xcode updates its Metal compiler on its own (27.1's 32023.921 to 27.2's 32023.922), and the exact match against `dmsh_chain.lock` stopped every NVN game's build at the shader step. A newer compiler of the same generation now builds with a note in the log; an older one, another generation or an unreadable version still stops unless `--allow-other-metal` is given. NX2Apple's patch 0034, by LNPANDY.

**In the game**
- **The pointer hides over the game** after 3 seconds without movement, in a window and in fullscreen, and comes back on the next movement, click or scroll. It stays while Quick settings is open or the pointer is outside the game. `DM_CURSOR_HIDE=<seconds>` changes the wait, `0` keeps the pointer. NX2Apple's patch 0032, by v0lumehi (upstream PR seedds/nxnative#755).
- **Record frame times** in Quick settings › Performance: from the next launch, each launch writes the host's per-frame timing rows to a new file in the game folder's `Frame times` (else `~/Library/Application Support/nxnative/<title ID>/frame-times`). `DM_FRAME_TIMES=1` or `0` does the same for one run.

**Converter**
- **Builds are "older" only when something they use changed.** A new engine commit marked every build older and queued it for Rebuild all, even when only notes or the converter changed. Now a build is older when a file its build reads changed since its commit: the host, graphics, tools, app shells, third-party code, the NSP script, the profile code or that game's own profile. A build on an older commit with nothing changed says "nothing it uses changed" instead.
- **Frame times on the Builds page**: a build's newest recording summed up (frames per second, median and 99th-percentile frame time, hitches over 50 ms, frames never shown), counted as `scripts/bench.py` counts.
- **Drop files on Convert**: a game folder, NSP / XCI / NSZ / XCZ files or `prod.keys`, in any mix, fill the Source files card.

## 0.9.0 (2026-10-31)

Merges nxnative's `main` up to `2716f78` (34 commits since `6d880d2`, 2026-10-30 and 2026-10-31). The notes below are what changes for NXForge.

**From upstream**
- **Cheats**: nxnative's cheat engine (`hle_cheats.c`) replaces NXForge's. It runs Atmosphère `.txt` cheat files with Atmosphère 1.12.1's opcodes, never writes over the rewriter's changes, keeps the switches beside the file (`<build ID>.enabled`), and starts every cheat off after a run that ended without a clean exit. The Mac window gets a Cheats menu and a Cheats panel (⇧⌘C) with sections, search, values and imports. `scripts/cheat_anchor.py` carries a cheat file across game updates.
- **New game profiles**: Metroid Prime Remastered, Hyrule Warriors: Definitive Edition, DRAGON QUEST III HD-2D Remake and Atelier Ryza.
- Rendering and host fixes: NVN attachment capacity and combined depth/stencil pairing, buffer offsets that guest ring allocators write, cube textures bound as 2D, Echoes of Wisdom's archive depth (and seven other profiles'), lock acquires made `ldaxr` by the rewriter (BotW ran a job twice), `hid::IsVibrationDeviceMounted`, `nv::GetGraphicsMemoryInfo` on SDK 10 and older, and AudioOut on the big host stack.
- Faster rewriter scans (in parallel), Unreal engine-region and console-variable rules in place of per-game rows, and the host's own Metal shaders compiled during the build instead of at run time.
- The NSP script takes `--work-dir` for the build folder.
- CI: clang-tidy for C and Objective-C, and coverage of the host, texture and tool tests, both as ratchets.

**Kept from NXForge on top**
- The Quick settings sidebar's Cheats section now lists the engine's rows, the same ones as the Cheats menu, with a switch each, Refresh, Open cheats folder and Restore saved cheats in safe mode. Cheats no longer save their switches in the app's preferences.
- The cheats folder is unchanged: `~/Library/Application Support/nxnative/<title ID>/cheats/`.
- NXForge's Markdown cheat files (`<build ID>.md`) are no longer read. `python3 dm/tools/cheats_md.py txt <file.md>` converts one into the `.txt` beside it ([docs/cheats.md](docs/cheats.md)). `DM_CHEATS_ON` now takes names separated by commas, as upstream's does; `all` is gone.
- The present filters, FXAA and Sharpen moved into upstream's `dm/gfx/msl/present.metal`, so they are compiled during the build like the rest of the host's shaders.
- `IsVibrationPermitted` still answers from the rumble setting before a controller connects.
- This changes the translation chain version, so each game's next build translates its shaders again.

**Sent upstream**
- Four fixes as their own pull requests: the China-region profanity check ([#789](https://github.com/seedds/nxnative/pull/789)), the free-space check before metal-tt ([#790](https://github.com/seedds/nxnative/pull/790)), Unity 6000.3 shader layouts ([#791](https://github.com/seedds/nxnative/pull/791)) and bench.py's offline pipeline archive ([#792](https://github.com/seedds/nxnative/pull/792)).

## 0.8.0 (2026-10-31)

Quality and consistency: checks that catch problems before a release, one place for each kind of fact, and the converter's last old names; no upstream merge.

**Converter**
- **NXForge names throughout**: the Toolchain page's engine row is "NXForge engine" ("No NXForge engine checkout found" when it is missing), the executable is `NXForgeConverter`, and a game folder's build lock is `.nxforge-converter.lock`. Settings, build records and the converter's own Python move to `~/Library/Application Support/NXForge Converter` on the first start, with a link left at the old `NxNative Converter` name so saved paths still work. A new clone of the engine goes to its `nxforge` folder; an existing `nxnative` one is still found.
- **On NXForge** in a build's details on the Builds page: the last time that game was played on NXForge, with the release, version, Mac and result, from the engine's `docs/nxforge-games.tsv`.
- Unit tests (`swift test --package-path app`), and CI now builds, tests and bundles the converter and starts its `--check`.

**In the game**
- Turning MetalFX on in Quick settings no longer stores it as a choice. It is the Mac default, and the settings window stores only choices that differ from the default, so a later build's default reaches the game again.

**Project**
- **Played on NXForge**: a table in README.md of the games played on a Mac with an NXForge release (version, release, Mac, date, result), written from `docs/nxforge-games.tsv` by `dm/tools/nxforge_games.py`.
- **Releases from tags**: pushing a `vX.Y.Z` tag publishes the GitHub release with its CHANGELOG entry (`.github/workflows/release.yml`), after `scripts/release_check.py` checks the entry and that BACKLOG.md was updated; CHANGELOG headings are linted on every PR. UPSTREAM.md's Versions section lists the steps.
- **Nightly upstream check**: `.github/workflows/upstream-check.yml` test-merges nxnative's `main` every night and keeps one issue labelled `upstream` current with how far behind `main` is and which files would conflict.
- **Mac smoke test**: `scripts/smoke_mac.sh` runs the host and GPU tests, the converter's tests and a minute of each game build given, then prints the hands-on list in `docs/release-checklist.md`. `scripts/bench.py --idle <seconds>` runs a game without a route, and bench.py now opens the build's offline pipeline archive as the Mac app does (Super Mario Bros. Wonder spent its whole run building pipelines without it). The first run on an M4 Pro passed for Super Mario Bros. Wonder, Bloodstained: Curse of the Moon and Cyber Shadow.
- **Frame times per release**: `scripts/perf_release.py` stores each release's measurements in `docs/perf/<release>.tsv` and compares two releases ([docs/performance.md](docs/performance.md)); 0.8.0's are the first (the three games above, about 60 fps each on an M4 Pro).
- **Mac host warnings**: CI fails on a new Mac host compiler warning (`dm/tools/host_warnings.py`, a ratchet like the Python lint's).
- **Settings in one table**: docs/settings.md's new "Quick settings on the Mac" lists every Mac setting, where it is changed and the preference it is kept in; a test keeps it in step with the code.
- BACKLOG.md is up to date again, and each release PR updates it.

## 0.7.1 (2026-10-30)

Merges nxnative's `main` up to `6d880d2` (102 commits since `beea17c`, 2026-10-29 and 2026-10-30). The notes below are what changes for NXForge.

**From upstream**
- **Mac pipeline archives for this Mac's macOS**: the offline pipeline archive was stamped with the SDK's major version, and Metal 4 opens an archive only on the major version it was made for, so a Mac on macOS 26 building with Xcode 27's SDK made an archive it could not open and compiled every pipeline while playing (shader stutter). The Mac host's minimum macOS is now 26.6 on its compile lines (NXForge's Quick settings object too), so the app opens on macOS 26.
- **Cloud saves**: a game's Mac and iPhone apps can share one save through an iCloud Drive folder (the settings window's Cloud saves, `DM_SAVE_SYNC`). It syncs whichever save folder the game uses, the game folder's `Saves` included.
- **Nintendo controllers by their labels**: a Switch Pro Controller or Joy-Con maps A, B, X and Y by what is printed on them, other pads by position. In NXForge this holds while the face buttons are not remapped in Quick settings' Controls; a remap applies to every pad as before.
- **New game profiles**: Pokémon Violet, Super Monkey Ball Banana Rumble, Mario Party Superstars, Portal 2, Bastion, Batman: Arkham Knight, Team Sonic Racing, Need for Speed: Hot Pursuit Remastered, EA SPORTS FC 27, Streets of Rage 4, Baba Is You, Subnautica and Below Zero, the SteamWorld games and Well Dweller.
- Rendering and host fixes: sampler LOD bias, border colours Metal lacks, NVN logic operations and alpha test, same-pass feedback without per-game lists, render passes into storage-backed textures, DrawTexture, H.264 end of stream, movies held at 30 fps under the frame step, and SDK-wide address-space rules in place of most per-build SDK cuts.
- The NSP script removes the shader libraries of older chain versions after a successful build, reads the title ID of an untagged NSP without a ticket from its meta NCA, and stops on a 32-bit program with upstream's check (NXForge's own `need_aarch64` is gone). `DM_REC` records the player's input as `DM_KEYS` steps.

**Kept from NXForge on top**
- Cartridge (`.xci`) title IDs still come from the cartridge's NCA headers first, so a cartridge with several applications still builds the game; upstream's meta NCA reader is the fallback for other packages without a ticket or tag.
- FXAA's two red-line slots moved to 140 and 141, since upstream took 122 and 123. Anisotropic filtering keeps its floor next to upstream's LOD bias.
- Mina the Hollower keeps its SDK cut row until a build checks that the SDK-wide rules give the same.
- This changes the translation chain version, so each game's next build translates its shaders again.

**Converter**
- Check for updates works after a release branch has merged. The engine checkout could stay on a release branch (such as `release-0.7.0`) whose upstream it could not resolve, and the check failed. While that branch has work `main` lacks, updates follow it; once it is merged they follow `main`, and Update engine switches the checkout to `main`.

**Super Mario Bros. Wonder**
- The game's bundled prewarm list (`pso_manifest.tsv`) was empty, so a fresh build compiled and loaded every pipeline and shader library during play, with 100 ms hitches in the first minutes. It now holds a 30-minute Mac session's list (1,459 shaders, 1,444 render and 18 compute pipelines), prepared in about 0.11 s before the first frame.

## 0.7.0 (2026-10-30)

**Picture quality on the Mac**
- MetalFX upscaling is now on by default in Mac apps and has a live switch in Quick settings (Graphics & shaders), saved together with the settings window's Upscaling choice. Sharpen now works together with MetalFX, sharpening the scaled picture. A new Anti-aliasing row (Off, FXAA; `DM_PRESENT_AA`) smooths jagged edges in games without their own anti-aliasing. Anisotropic filtering defaults to 16x on the Mac until a game's choice is saved ("Game default" keeps the game's own).

**Converter**
- `app/install.sh` builds the converter into `~/Applications` and opens it, so it opens from Spotlight, Launchpad or the Dock; run it again to update.
- The game folder picker (and File > Choose Game Folder…) also takes a game file: pick an `.xci` or `.nsp` and its folder becomes the game folder.

**Faster shader builds**
- The Metal shader step runs its tools (spirv-cross, the Metal compiler) with `posix_spawn` instead of forking the build process: each fork held Python's lock for about 6 ms, so only about half of the compile workers ran at once. Kirby's Return to Dream Land Deluxe (47,099 shaders, M4 Pro): 25:31 → 14:20, with byte-identical libraries.
- Compiled Metal libraries go to one cache for every game, `~/Library/Caches/NXForge/metallib` (`DMSH_MTLCACHE`), kept under 4 GB by dropping the least recently used (`DMSH_MTLCACHE_GB`). It survives a Mac app's cleanup, so rebuilding a game after an NXForge update compiles only the shaders whose Metal source changed: Kirby's rebuild took 5:21. A game's own cache from earlier builds (`shader/cache/cas/metallib`) moves into it on its next build. Two workers compiling the same source now compile it once, and the fetch variants go through the cache too.
- This changes the translation chain version, so each game's next build translates its shaders again (the Metal compiles come from its moved cache).

**Fixes**
- Cartridge dumps (`.xci`) named without a `[title ID]` tag (`Game.xci`) build: the script read the title ID only from a ticket or the file name, and a cartridge has no ticket, so a lone untagged XCI stopped with "no NSP with a readable title ID". It now reads the title ID from the XCI's own NCA headers with prod.keys' `header_key`. Game file extensions match in any case (`Game.XCI`).
- A cartridge with its update on it (1G+1U) shows as the base game in the converter's file check, not as an update with "no base game in the folder".
- Cruis'n Blast no longer stops after a race: its name entry's China-region profanity check (`nn::ngc::CheckProfanityWordsInTextForPlatformRegionChina`, and the matching mask) went to the `ngct:u` service, which the host does not serve; the host now answers both itself (no profanity, nothing masked).
- The Mac pipeline archive step checks free disk space before metal-tt starts and names a full disk when metal-tt fails, instead of only "applegpu-nt command failed" (Cruis'n Blast's 33,858 bases failed with 366 MB free). A failed run's temporary files are cleared from `pso/mac-work`.
- A cartridge holding several applications builds the game, not the first title ID: Castlevania: Belmont's Curse's Midnight Edition holds the game (0100BA4026E94000) and its Digital Sound & Art Gallery (01005F4027E94000), and the gallery was built. The script now takes the application with the largest program and tells `nx_extract` which one (`--title`).
- Unity 6000.3 games whose player files carry no type trees and whose bundles hold no `Shader` (Castlevania: Belmont's Curse) split their shaders: the split stopped with "no bundle has a Shader type tree of the same hash to borrow". `unityfs.py` now has 6000.3's `Shader` layout (version 4 adds the object's local identifier) and `ComputeShader` layout (a resource type per resource), checked against AssetRipper's release dumps.

## 0.6.0 (2026-10-28)

Merges nxnative's `main` up to `beea17c` (245 commits since `9a56ecf`). Most of what this brings is upstream's own work; the notes below are what changes for NXForge.

**From upstream**
- **A settings window before the game** in Mac apps (`dm/mac/Launcher.swift`): frame rate, render scale, docked or handheld, game language, display mode, MetalFX upscaling and the rumble cutoff, saved per game. `DM_LAUNCHER=0` or `--no-launcher` starts the game without it.
- **About 30 new game profiles** (Kirby and the Forgotten Land, Xenoblade Chronicles 2, 3 and Definitive Edition, Pokémon Legends: Arceus, Scarlet and Shield, Super Mario Party Jamboree, Paper Mario: The Origami King, Mario + Rabbids Kingdom Battle and Sparks of Hope, Donkey Kong Country Returns HD and Tropical Freeze, Sea of Stars and others), NSZ executables, RomFS images instead of loose files, an offline pipeline archive in Mac apps, controller motion (gyro), DualShock 4 rumble, and many host, shader and frame-pacing fixes.
- Upstream fixed three things NXForge had fixed its own way, and its versions replace ours: rumble on controllers without advanced haptic players (NXForge's 8BitDo SN30 Pro fallback), the rewriter's copy-before-check search (NXForge's 128-instruction window for Curse of the Moon's GLSLC), and HAL's `.cmp` shader containers (NXForge's Kirby's Return to Dream Land Deluxe reader). The blocking wait in `oe::PopNotificationMessage` (Mina the Hollower) also uses upstream's native HLE wait now.

**Kept from NXForge on top**
- Quick settings, filters, anisotropic filtering, cheats, captures, controls, mods and game-folder saves work as before, alongside upstream's settings window.
- Rumble permission is still given before a controller connects (Bloodstained: Curse of the Moon asks only once at startup); upstream ties it to a connected controller.
- In fullscreen the display link stays off, as in NXForge's 60 fps fix, rather than upstream's frame latency 2 (which settled at about 42 fps on Mario vs. Donkey Kong here). `DM_PRESENT_LATENCY=<n>` keeps the link at that latency, to compare.
- MetalFX upscaling applies only while the present filter is off, since the filters work on the game's own pixels.

**Fixes**
- **Quit game** no longer stays armed after the sidebar is closed and opened again: the first press after reopening arms it again.
- The iPhone build compiles again: the cheats engine used `mach_vm.h`, which the iPhone SDK does not have (upstream's new CI caught it).

## 0.5.0 (2026-10-28)

Ideas from other nxnative front ends (NX Play, the NxNative Launcher and NX2Apple, all MIT), reimplemented for NXForge; no upstream merge.

**Converter**
- **Keep this build** (after NX Play): an app that plays well can be kept as it is. It shows a lock instead of the "older" badge, Rebuild all and its count pass it by, and Rebuild asks before replacing it. A switch in the build's detail panel, or the right-click menu on Builds.

**In the game**
- **Quit game** in Quick settings (after the NxNative Launcher's couch exit): Home opens the sidebar, and Quit game, pressed twice, ends the game as ⌘Q does.
- **Mods as downloaded**: a mod folder holding Atmosphere's layout (`atmosphere/contents/<title ID>/romfs`, or `contents/<title ID>/romfs`, or `<title ID>/romfs`) overlays that `romfs` folder, so a mod unzipped as it comes works without moving its files.

**Project**
- Issue forms for a game problem and a converter or build problem (after NX2Apple's), each asking for the log or Copy diagnostics and confirming nothing attached holds keys or game files.

## 0.4.0 (2026-10-27)

Build-cache cleanup in the converter and a clear stop on 32-bit game versions; no upstream merge.

**Converter**
- `--cleanup unused|all` (and *After a build* in the converter's settings) tidies `<id>_build/` after a successful build. `unused` deletes other versions' extracted files and rewritten modules (an update replaced by a newer one), half-written folders and the survey; `all` deletes the whole build cache but its logs and profile. The NSPs, `prod.keys`, the app and the save are never touched.
- A 32-bit (AArch32) game version stops the build with a message that names the versions the game's profile registers, instead of crashing in the symbol reader (`KeyError: 6`). Apple Silicon runs only 64-bit Arm code; Mario Kart 8 Deluxe 3.0.1 is one such version.

**Games**
- Mario Kart 8 Deluxe (`0100152000022000`): 4.0.1 packs from a profile derived from 4.0.0's and runs at 60 fps on the Mac; only 3.0.1 is ruled out.

## 0.3.0 (2026-10-27)

Mina the Hollower, the first Yacht Club Games title, and Kirby's Return to Dream Land Deluxe; no upstream merge.

**New games**
- Mina the Hollower (`0100DCD01F306000`, 1.0.5, SDK 21.4.3) converts and boots on the Mac: the intro and the menus, with input. Its profile cuts the 24 GB of address space it reserves at boot (malloc and two engine heaps) to fit the 5 GB block. In bring-up: gameplay is not tested yet.
- Kirby's Return to Dream Land Deluxe (`01006B601380E000`, base game without updates, SDK 13.3.5) converts from a provisional profile and plays on the Mac at 60 fps: the 3D intro, the title and gameplay, with its movies. The first minute of a first launch hitches while Metal builds pipelines. No hand-checked profile yet.

**Engine**
- The shader split reads Yacht Club Games' YCD paks (`.yc`): the shaders of `shaders.pak.yc`.
- A guest thread blocked in the host (the blocking `oe::PopNotificationMessage`) no longer counts as running on its core, so lower-priority threads on that core are no longer held after waking it. Mina the Hollower stayed on a black screen because of it.
- The node-area cut for the SDK 21.4.3 `sdk` build.
- The shader split reads HAL Laboratory's `.cmp` files (a u32 size, then a zstd or LZ4 frame), recognised by their content: Kirby's models, effects and layouts hold 47,099 shaders, where 133 were found before, and without them its title screen and intro were black.
- The survey names files packed that way instead of listing them as unknown, and the shader split prints a `[RED]` line for RomFS files that open with an LZ4 frame or a zlib stream it does not unpack, so a build with shaders missing that way no longer goes quietly to a black screen.

## 0.2.0 (2026-10-26)

The NXForge Converter release: everything since 0.1.0 is in the converter app (`app/`); the engine and the game profiles are as in 0.1.0, and there is no upstream merge.

**Engine versions you can read**
- Engines and builds show as releases: `0.2.0` at a release tag, `0.2.0+3` three commits after it, `pre-0.1.0` for anything built before the first release. The commit is in the tooltip.
- Build records from before release tags get their version from the engine's history, also when the checkout they were built from has moved (nxnative-src → NXForge).
- The converter checks the engine's branch for updates when it opens, and shows the newest release's first change from this changelog.
- The converter's own version is the engine's release tag.

**Rebuilding**
- Rebuild is the large blue button whenever an app was built on an older engine, on Convert and on Builds.
- Builds marks those apps with an "older" badge, and **Rebuild all** rebuilds them one after another; a failure stops the rest and says which game.
- A right-click on an app in Builds opens it, shows it in Finder, rebuilds it, removes it from the list or moves it to the Trash.

**Converting**
- A finished build clears the Convert page (folder, keys, file check, activity) and opens Builds on the new app; a failed build stays on Convert with its stages and log.
- Drop a game folder, or a file in it, on the window or the Dock icon to convert it.
- Convert shows the free disk space and what the build needs (a first build: about twice the game files plus 10 GB), in orange when it is short.
- The build's progress shows on the Dock icon, with the step number as a badge.
- An update NSP tagged with the base game's ID and only a version above v0 (Cyber Shadow) counts as an update.

**Setup and everyday use**
- **Set up** on Toolchain makes the converter's own Python (a venv in Application Support with lz4, capstone, fontTools, zstd and nsz), so it depends on no other copy of Python.
- A Build menu: Build Mac App (⌘B), Rebuild (⌘R), Rebuild All on Older Engines, Stop Build (⌘.), and ⌘O to choose a game folder.
- An app icon.

## 0.1.0 (2026-10-26)

The baseline release: nxnative's main branch as merged on 2026-10-25, plus:

- **Quick settings sidebar** on the Mac (Esc, ⇧⌘G or the Graphics menu; Liquid Glass on macOS 26 and later), with controller and keyboard navigation and remappable keys and buttons per game.
- **Picture filters:** Sharpen, Pixel-perfect, CRT, CRT-Lottes, LCD Grid and scanlines, saved per game.
- **Anisotropic filtering floor** for every game's samplers (`DM_ANISO`), with a per-game row in the sidebar.
- **Cheats:** Atmosphere dmnt cheat codes from Markdown files, one per game build ([docs/cheats.md](docs/cheats.md)).
- **Mods:** RomFS replacement folders per game.
- **Capture:** screenshots (⇧⌘S) and recordings with sound (⇧⌘R).
- **Game folder:** saves, screenshots and recordings beside the game's app.
- **Volume** control in the sidebar.
- **Rumble:** controller vibration handles opened before the controller connects, and a plain Core Haptics player for controllers that refuse the advanced one (8BitDo SN30 Pro).
- **Full screen at 60 fps** on 120 Hz ProMotion displays (no display link while full screen; also sent upstream as seedds/nxnative#194).
- **NXForge Converter:** a SwiftUI Mac app that checks the tools and game files, builds and rebuilds game apps, and shows which engine version each was built on.
- **NXForge name:** bundle IDs `org.nxforge.<title ID>` (Quick settings carried over from the old ID), NOTICE, and the upstream policy.
