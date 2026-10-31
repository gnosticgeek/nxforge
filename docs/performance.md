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

## Which games

Two or three that cover different engines, built on the Mac doing the measuring: for example Bloodstained: Curse of the Moon (2D,
light), Super Mario 3D World + Bowser's Fury and Super Mario Bros. Wonder (NVN, heavy on pipelines). Breath of the Wild has
scripted routes (`dm/games/01007EF00011E000/bench.tsv`); a route for another game is a line in its profile's `bench.tsv`.
The first-play stutter (shaders and pipelines built during play) is measured from a fresh pipeline cache; see the
[regression harness](development.md#the-regression-harness) for comparing two revisions in depth.
