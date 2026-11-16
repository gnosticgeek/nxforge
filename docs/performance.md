# Performance across releases

NXForge keeps the frame times of each release in the repository, so a release that makes a game slower shows up as numbers
before players notice it. The measurements are made on a Mac with games its owner has (GitHub's runners have neither Metal 4
nor games) and stored one file per release in [docs/perf/](perf/).

## Measuring a release

```
python3 scripts/perf_release.py run <NSP folder>/<id>_build ... [--seconds 90] [--runs 2]
```

runs [`scripts/bench.py`](development.md#a-benchmark-on-the-mac) on each game build: along its first route when its profile
has a `bench.tsv`, otherwise left running without input for `--seconds` (`bench.py --idle`, measuring the last two thirds).
It takes the median over the runs and writes a row per game into `docs/perf/<release>.tsv`, the release being the checkout's
(`0.8.0` at its tag). A game measured again on the same Mac and route replaces its row. Commit the file with the release PR.

### Installed games, without a build folder

```
python3 scripts/perf_release.py run --app "<folder>/<Game>.app" ... --host tree/dm/host/dmhost [--route NAME] [--save FOLDER]
```

measures games as they are installed, for a Mac whose build folders were cleaned up. Each app starts as Play starts it. With
`--host` the release's own host (`make -C tree/dm/host GAME=<id> dmhost`) runs on the app's game files, so the row is the
release's and not that of the engine the app was built with; an app built with another shader chain is skipped with a line
that says so. Without a route the game is left alone and the frames from 20 s on count for `--seconds`; `--route` names one of
the game's `bench.tsv`, and `--save` the save it starts from. A run gets a copy of that save, or an empty one: the player's
own save is never touched. Close the game first if it is open.

For numbers that compare:

- the same Mac, on power, with other apps closed, and the same display at the same refresh rate as the release it is compared with;
- a game build made by the release being measured (rebuild it with the converter first when the shader chain changed);
- two runs or more (`--runs`), since load on the Mac moves single runs.

The columns: frames per second over the window, the frame time at p50 and p99 and its maximum (ms), the frames over 1.5 frame
times (`over_budget`), the GPU time at p50, and the run's `[RED]` lines; with the Mac, its macOS and the date.

## Comparing two releases

```
python3 scripts/perf_release.py compare 0.7.1 0.8.0
```

prints a table of the games both releases measured on the same Mac and route, with each change, and exits with status 1 when a
game's frame rate fell by more than 3 % or its p99 frame time rose by more than 15 %. Put the table in the release PR when it
shows a change, and say why if a game got slower on purpose. `dm/tools/tests/test_perf_release.py` checks the comparison and
that the stored files parse.

## A session's check

```
nxforge perf [title ID …] [--record]          # or python3 scripts/perf_check.py
```

reads each game's last log (`~/Library/Logs/nxnative/<title ID>.log`, the previous one is `.prev.log`) and says how smoothly it ran: the share of
frames shown on time over the session (the host's `on-screen up to frame` lines, the first 600 frames left out), GPU time, whether it went full
screen and what that did to the screen's refresh rate, the upscaler, the footprint, and the causes of lost frames the log shows (a ProMotion
screen switched to a fixed 60 Hz, MetalFX, the frame-step hold, heat, Low Power Mode, battery, a footprint big enough to swap). With `--record`
the session goes into `~/Library/Application Support/NXForge/perf-history.tsv`, once per log, and the verdict compares it with the game's last
five sessions: **slower** when its share of frames on time is more than 3 points under their median and under 97 % (exit status 1, so a routine
can notice), otherwise smooth (97 % or more), as usual or uneven. The MCP server has it as `nxforge_perf`.

It would have named 16 Nov 2026's Mario Kart World drop at once: every slow session had gone full screen mid-game, which switched the built-in
screen to a fixed 60 Hz (60-79 % of frames on time against 98-99 % at the screen's own 120 Hz; from 0.44 a ProMotion screen keeps 120 Hz).

## Which games

Two or three that cover different engines, built on the Mac doing the measuring: for example Bloodstained: Curse of the Moon (2D,
light), Super Mario 3D World + Bowser's Fury and Super Mario Bros. Wonder (NVN, heavy on pipelines). Breath of the Wild has
scripted routes (`dm/games/01007EF00011E000/bench.tsv`); a route for another game is a line in its profile's `bench.tsv`.
The first-play stutter (shaders and pipelines built during play) is measured from a fresh pipeline cache; see the
[regression harness](development.md#the-regression-harness) for comparing two revisions in depth.
