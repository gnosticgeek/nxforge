# Notes for agents

NXForge is the NXForge Converter (`app/`) and a Mac player layer (the in-game Quick settings sidebar and what it drives) on an untouched [nxnative](https://github.com/seedds/nxnative) engine. [UPSTREAM.md](UPSTREAM.md) has the layout and the rules; the short version:

- **The engine is not in this repository.** `layer/ENGINE` pins an nxnative commit. NXForge's changes to nxnative's files are `layer/patches/*.patch`; files NXForge adds to the engine are in `layer/files/` at their engine paths. `python3 scripts/layer.py assemble` makes `tree/` (git-ignored), the engine as builds see it.
- **Engine work happens in `tree/`**, and `tree/AGENTS.md` (nxnative's) is the guide there: games, profiles, the shader chain, debugging, docs. Run builds and engine tests in `tree/` (`make -C tree/dm/host/tests GAME=<id> run`, `python3 -m unittest tree/dm/tools/tests/test_*.py`).
- **Never leave an edit only in `tree/`.** Commit it there, fold it into the patch it belongs to (or let it become a new patch), then `python3 scripts/layer.py export` writes it back to `layer/`, and the `layer/` change is what you commit here. `layer.py status` says whether `tree/` has work not exported.
- **Taking nxnative's changes is `python3 scripts/layer.py update`**, whole, never commit by commit (`layer.py try` first shows which patches would conflict). Do it on a release branch with a Mac build and a play test.
- New player features go in layer files (`dm/host/nxforge/`, `dm/gfx/nvn/nxforge/`, `quick_settings_mac.swift`, `capture_mac.m`) with a one-line hook in a patch, not into an nxnative function. NXForge's red lines use `NXF_RED_ONCE`.
- NXForge's own scripts are in `scripts/` (`nxforge.py`, `layer.py`, `release_check.py`, `perf_release.py`, `source_info.py`, `smoke_mac.sh`) with tests in `tests/`; the converter's are in `app/Tests` (`swift test --package-path app`).
- Releases: one release branch and one PR per release (UPSTREAM.md, Versions); the sidebar and the converter have versions of their own, bumped with their changelogs when their files change.
- Commit only when asked, as yourself, never as seedds. Game files, keys and anything extracted from them never go into this repository.
