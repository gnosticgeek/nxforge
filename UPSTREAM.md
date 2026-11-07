# Working with upstream

NXForge is a downstream of [nxnative](https://github.com/seedds/nxnative) (seedds and contributors). It follows nxnative rather than competing with it: the engine is shared, and NXForge adds Mac-focused features on top. This page is the policy for keeping the two in step.

## Downstream: taking nxnative's changes

- `main` merges nxnative's `main` regularly (a merge commit, never a rebase or squash, so every upstream commit keeps its author and hash). Resolve conflicts in favour of upstream unless an NXForge feature depends on the local change.
- Keep the diff against upstream small. The rebrand touches only user-facing text, the bundle ID prefix and these policy files. Internal names stay as they are: source and module names, the `dm/` layout, `DM_*` environment variables, the launcher's `Contents/MacOS/nxnative`, the `~/Library/Application Support/nxnative` and `~/Library/Logs/nxnative` folders (moving them would strand existing saves), and the `NxNative.xcworkspace` default.
- The NXForge Converter (`app/`) is NXForge's own, not a part of nxnative's tree, so it uses NXForge names throughout: its target and executable (`NXForgeConverter`), its settings folder (`~/Library/Application Support/NXForge Converter`, moved from `NxNative Converter` in 0.8.0) and its strings.
- The nightly `upstream-check` workflow (`.github/workflows/upstream-check.yml`) test-merges nxnative's `main` and keeps one open issue labelled `upstream` with how many commits `main` is behind and which files a merge would conflict in. It never pushes; the merge is still done on a branch with a Mac build and a play test.
- Add Mac-only features in new files where possible (as `quick_settings_mac.swift` and `capture_mac.m` are), with small hooks into shared files, so upstream merges stay easy.

## Thin fork (from 0.15.0)

NXForge is the NXForge Converter plus a Mac player layer (the Quick settings sidebar and what it drives) on nxnative's engine. The translator, the GPU core and game bring-up are nxnative's; NXForge takes them as they land. Rules:

1. Merge nxnative's `main` whole, never commit by commit: no hand-picked upstream commits on a release branch.
2. An open upstream pull request comes in early only when it fixes a game being played that week. It is listed in `.github/upstream-watch.tsv`, and once upstream lands its own version, that version replaces ours at the next merge.
3. A fix headed upstream stays in NXForge until upstream has landed it (or its own version of it); only then is NXForge's copy removed. Removal is gradual, merge by merge.
4. Player code lives in NXForge's own files: `quick_settings_mac.swift`, `capture_mac.m`, and the `nxforge/` folders beside nxnative's sources (`dm/host/nxforge/*.inc`, `dm/gfx/nvn/nxforge/*.inc`), which nxnative's files include at one line each. A new player feature goes there, with a hook, not into an nxnative function.
5. NXForge's own red lines use `NXF_RED_ONCE` (its own table in `nvn_mtl.m`), never a `RED_ONCE` key, so upstream's keys are never renumbered.
6. The nightly upstream check reports how many files a merge would conflict in. Above 10 is a signal to shrink the fork before the next release.

## Upstream: sending fixes back

- A fix that helps nxnative's users too goes upstream: crashes, rendering, shader, rewriter, frame pacing, input and haptics fixes, and new game profiles. Send it as a small pull request to seedds/nxnative, one fix per PR, from a branch based on upstream `main`, following nxnative's [AGENTS.md](AGENTS.md) rules (findings in the game note or `docs/reference`, `python3 dm/tools/tests/test_docs.py` passing).
- NXForge-only work stays here: the rebrand, Mac UI features nxnative has not asked for, and anything that depends on them. Offer a feature upstream when it is finished and tested, as its own PR, and land it in NXForge first if upstream wants changes.
- Credit is kept both ways. Commits are authored by the person (or tool) who wrote them, never as `seedds`. A fix ported from nxnative or another fork names its source commit or PR, as the reference docs already do.
- Track what is open in [BACKLOG.md](BACKLOG.md) under "Upstream contributions": PR number, branch and status.

## Versions

- NXForge releases are tags `vX.Y.Z` on `main`, following [semantic versioning](https://semver.org): the minor number for new features or an upstream merge that changes behaviour, the patch number for fixes. Before 1.0 a minor release may change how things work.
- Each release has an entry in [CHANGELOG.md](CHANGELOG.md) and a GitHub release with the same notes. The NXForge Converter shows the engine as the release it is: `0.2.0` at the tag, `0.2.0+3` three commits after it, `pre-0.1.0` before the first release (the commit is in its tooltip).
- The version is NXForge's own and says nothing about nxnative's; the changelog names the upstream merge each release includes.
- **The sidebar has its own version.** The in-game Quick settings sidebar is released on its own as tags `sidebar-vX.Y.Z` (from `sidebar-v0.1.0`), with its own history in [SIDEBAR_CHANGELOG.md](SIDEBAR_CHANGELOG.md) (same heading rules) and the version in `let SIDEBAR_VERSION` at the top of `dm/host/quick_settings_mac.swift`, shown under the sidebar's button legend ("NXForge Sidebar 0.1.0"). A change to the sidebar's files (listed at the top of SIDEBAR_CHANGELOG.md) bumps both in the release PR that carries it; a sidebar release does not need an NXForge release and the other way round. Before tagging: `python3 scripts/release_check.py check sidebar-vX.Y.Z`, which also wants the Swift constant to match. The `release` workflow publishes it as "NXForge Sidebar X.Y.Z", never marked Latest. NXForge's own version (git describe, the converter, `app/bundle.sh`) reads only the `v*` tags.
- How a release is made: work for it collects on one release branch and goes in as one PR (no PR per change). That PR adds the version's CHANGELOG entry (`## X.Y.Z (YYYY-MM-DD)`, newest first) and updates [BACKLOG.md](BACKLOG.md): the rows its changes touch and the "Last updated" date. `python3 scripts/release_check.py check X.Y.Z` checks both before the tag; CI lints them on every PR (`dm/tools/tests/test_release_check.py`).
- After the PR merges, tag the merge commit and push the tag: `git tag vX.Y.Z <merge commit> && git push origin vX.Y.Z`. The `release` workflow (`.github/workflows/release.yml`) then publishes the GitHub release, titled "NXForge X.Y.Z", with the CHANGELOG entry as its notes. Before tagging, run the Mac checks GitHub's runners cannot: `scripts/smoke_mac.sh` (and `scripts/bench.py` for a release that touches speed).

## Reporting problems

A problem that also happens with plain nxnative belongs in [nxnative's issues](https://github.com/seedds/nxnative/issues). A problem with an NXForge feature (the Quick settings sidebar, filters, cheats, capture, the Mac converter) belongs here.
