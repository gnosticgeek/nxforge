# Working with upstream

NXForge is a downstream of [nxnative](https://github.com/seedds/nxnative) (seedds and contributors). It follows nxnative rather than competing with it: the engine is shared, and NXForge adds Mac-focused features on top. This page is the policy for keeping the two in step.

## Engine and layer (from 0.19.0)

NXForge is the NXForge Converter plus a Mac player layer on an **untouched** nxnative engine. This repository does not hold a copy of nxnative to edit: it pins one nxnative commit and keeps NXForge's changes beside it.

| Path | What it is |
|---|---|
| `layer/ENGINE` | The nxnative commit NXForge is built on (`url`, `commit`). Moving it is how NXForge takes nxnative's changes, all of them at once. |
| `layer/patches/NNNN-<name>.patch` | NXForge's changes to nxnative's own files, one patch per purpose (`0001-host-player`, `0004-gfx-metal`, ...), applied in order with `git am -3`. |
| `layer/files/` | Files NXForge adds to the engine, at their engine paths: the sidebar (`dm/host/quick_settings_mac.swift`, `dm/host/nxforge/`), capture, the present filters (`dm/gfx/nvn/nxforge/`), NXForge's game profiles and tools. |
| `tree/` | Git-ignored. `python3 scripts/layer.py assemble` makes it: a worktree at the pinned commit, one commit per patch, then the layer files. Builds, the converter, the `nxforge` CLI and CI run here. |
| `app/`, `scripts/`, `tests/`, `docs/` | NXForge's own: the converter, its scripts (`nxforge.py`, `layer.py`, `release_check.py`, ...) and their tests, NXForge's docs. Engine docs are nxnative's, in `tree/docs`. |

`scripts/layer.py`:

- `assemble`: make `tree/` match the layer (a quick no-op when it already does). The converter and the CLI run it before a build.
- `status`: the pin, how far nxnative's `main` is past it, whether `tree/` is current.
- `try [REF]`: a dry run against nxnative's `main` (or REF): which patches apply, which nxnative already has, which conflict and where. Changes nothing. The nightly `upstream-check` workflow posts this.
- `update [REF]`: move the pin to nxnative's `main` (or REF) and reassemble. A patch nxnative now has is dropped; a patch that no longer applies stops in `tree/` (`git am`) for fixing, then `git -C tree am --continue` and `layer.py export`.
- `export`: write `tree/`'s commits back to the layer. To change a patch, edit in `tree/` and fold the change into that patch's commit (`git -C tree commit --fixup <commit>`, `git -C tree rebase -i --autosquash <pin>`); a new commit becomes a new patch. Layer files can be edited in `layer/files/` or in `tree/` (export copies them back).

Rules:

1. Never edit nxnative's files in place: a change to one is a patch, a new file is a layer file. Prefer a layer file with a one-line hook in a patch over a patch that rewrites an nxnative function.
2. Take nxnative whole: `layer.py update` moves the pin to its `main`, never to a hand-picked set of commits. An open upstream pull request comes in early only when it fixes a game being played that week, as a patch of its own (`NNNN-upstream-pr-1234`), listed in `.github/upstream-watch.tsv`, and dropped once nxnative lands it.
3. A fix headed upstream stays a patch until nxnative has landed it (or its own version); `update` then drops it, or it is removed by hand when nxnative's version replaces it. Each patch removed is a step toward an engine with no patches at all.
4. Keep the patches small and by purpose, so one that stops applying names the feature it belongs to. Split a patch that grows past one purpose.
5. NXForge's own red lines use `NXF_RED_ONCE` (its own table in `nvn_mtl.m`), never a `RED_ONCE` key, so upstream's keys are never renumbered.
6. Internal names stay nxnative's: the `dm/` layout, `DM_*` environment variables, the launcher's `Contents/MacOS/nxnative`, the `~/Library/Application Support/nxnative` and `~/Library/Logs/nxnative` folders (moving them would strand existing saves). The converter (`app/`) is NXForge's own and uses NXForge names.

A checkout from before 0.19.0 has the engine at its root (`dm/`, `scripts/build_ipa_from_nsp.py`). The converter and the CLI handle both layouts, so updating an old checkout just works: after the update, the converter assembles `tree/` itself.

## Upstream: sending fixes back

- A fix that helps nxnative's users too goes upstream: crashes, rendering, shader, rewriter, frame pacing, input and haptics fixes, and new game profiles. Send it as a small pull request to seedds/nxnative, one fix per PR, from a branch based on upstream `main`, following nxnative's AGENTS.md rules (`tree/AGENTS.md`: findings in the game note or `docs/reference`, `python3 dm/tools/tests/test_docs.py` passing). A patch is a good starting point: `git -C tree format-patch -1 <its commit>` applies to nxnative's `main` as it is.
- NXForge-only work stays here: the rebrand, Mac UI features nxnative has not asked for, and anything that depends on them. Offer a feature upstream when it is finished and tested, as its own PR, and land it in NXForge first if upstream wants changes.
- Credit is kept both ways. Commits are authored by the person (or tool) who wrote them, never as `seedds`. A fix ported from nxnative or another fork names its source commit or PR, as the reference docs already do.
- Track what is open in [BACKLOG.md](BACKLOG.md) under "Upstream contributions": PR number, branch and status.

## Versions

- NXForge releases are tags `vX.Y.Z` on `main`, following [semantic versioning](https://semver.org): the minor number for new features or an upstream merge that changes behaviour, the patch number for fixes. Before 1.0 a minor release may change how things work.
- Each release has an entry in [CHANGELOG.md](CHANGELOG.md) and a GitHub release with the same notes. The NXForge Converter shows the engine as the release it is: `0.2.0` at the tag, `0.2.0+3` three commits after it, `pre-0.1.0` before the first release (the commit is in its tooltip).
- The version is NXForge's own and says nothing about nxnative's; the changelog names the nxnative commit each release is built on (`layer/ENGINE`).
- **The sidebar has its own version.** The in-game Quick settings sidebar is released on its own as tags `sidebar-vX.Y.Z` (from `sidebar-v0.1.0`), with its own history in [SIDEBAR_CHANGELOG.md](SIDEBAR_CHANGELOG.md) (same heading rules) and the version in `let SIDEBAR_VERSION` at the top of `layer/files/dm/host/quick_settings_mac.swift`, shown under the sidebar's button legend ("NXForge Sidebar 0.1.0"). A change to the sidebar's files (listed at the top of SIDEBAR_CHANGELOG.md) bumps both in the release PR that carries it; a sidebar release does not need an NXForge release and the other way round. Before tagging: `python3 scripts/release_check.py check sidebar-vX.Y.Z`, which also wants the Swift constant to match. The `release` workflow publishes it as "NXForge Sidebar X.Y.Z", never marked Latest. NXForge's own version (git describe, the converter's engine row, `app/bundle.sh`'s build number) reads only the `v*` tags.
- **The Converter has its own version too**, the same way: tags `converter-vX.Y.Z` (from `converter-v0.1.0`), history in [CONVERTER_CHANGELOG.md](CONVERTER_CHANGELOG.md), the version in `let CONVERTER_VERSION` in `app/Sources/NXForgeConverter/Version.swift`. The app shows it under the NXForge name in its sidebar, in About and in Copy diagnostics, and it is the app's `CFBundleShortVersionString` (its `CFBundleVersion` is the NXForge release it was built from). A change under `app/` bumps both in the release PR that carries it. Before tagging: `python3 scripts/release_check.py check converter-vX.Y.Z`. The `release` workflow publishes it as "NXForge Converter X.Y.Z", never marked Latest.
- How a release is made: work for it collects on one release branch and goes in as one PR (no PR per change). That PR adds the version's CHANGELOG entry (`## X.Y.Z (YYYY-MM-DD)`, newest first) and updates [BACKLOG.md](BACKLOG.md): the rows its changes touch and the "Last updated" date. `python3 scripts/release_check.py check X.Y.Z` checks both before the tag; CI lints them on every PR (`tests/test_release_check.py`).
- After the PR merges, tag the merge commit and push the tag: `git tag vX.Y.Z <merge commit> && git push origin vX.Y.Z`. The `release` workflow (`.github/workflows/release.yml`) then publishes the GitHub release, titled "NXForge X.Y.Z", with the CHANGELOG entry as its notes. Before tagging, run the Mac checks GitHub's runners cannot: `scripts/smoke_mac.sh` (and `scripts/bench.py` for a release that touches speed).

## Reporting problems

A problem that also happens with plain nxnative belongs in [nxnative's issues](https://github.com/seedds/nxnative/issues). A problem with an NXForge feature (the Quick settings sidebar, filters, cheats, capture, the Mac converter) belongs here.
