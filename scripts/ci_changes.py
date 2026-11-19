#!/usr/bin/env python3
"""Which of tests.yml's jobs a change needs (.github/workflows/tests.yml, job "changes").

  ci_changes.py [BASE [HEAD]]   prints engine=true|false and converter=true|false (for $GITHUB_OUTPUT), from `git diff --name-only BASE HEAD`

engine: the jobs that assemble tree/ and build or test the engine (host, sanitizers, coverage, tool tests, build check, iOS). They read
only layer/, scripts/layer.py and the workflow files, so a change to nothing but the converter (app/), NXForge's own scripts and tests,
the docs and the changelogs leaves them out. converter: the Swift package's job, which also reads the layer (its tests read the
engine's docs/nxforge-games.tsv). With no BASE, or when git cannot tell, everything runs: a skipped job must never hide a break.
"""
from __future__ import annotations

import subprocess
import sys

# Paths no engine job reads. Anything not listed (a new top-level folder, .gitattributes, the workflows) runs the engine jobs.
NOT_ENGINE_DIRS = ('app/', 'docs/', 'tests/', 'library/', '.github/ISSUE_TEMPLATE/')
NOT_ENGINE_FILES = {'pyproject.toml', 'LICENSE', 'NOTICE', '.github/pull_request_template.md', '.github/upstream-watch.tsv'}
CONVERTER_DIRS = ('app/', 'layer/')
CONVERTER_FILES = {'CONVERTER_CHANGELOG.md', '.github/workflows/tests.yml'}


def needs_engine(path: str) -> bool:
    if path.startswith(NOT_ENGINE_DIRS) or path in NOT_ENGINE_FILES:
        return False
    if '/' not in path and path.endswith('.md'):   # README, the changelogs, BACKLOG, UPSTREAM, AGENTS
        return False
    if path.startswith('scripts/') and path != 'scripts/layer.py':   # NXForge's own scripts: the "scripts" job tests them
        return False
    return True


def needs_converter(path: str) -> bool:
    return path.startswith(CONVERTER_DIRS) or path in CONVERTER_FILES


def jobs(files: list[str] | None) -> dict[str, bool]:
    """{'engine': ..., 'converter': ...} for the changed paths; None (unknown) runs everything."""
    if files is None:
        return {'engine': True, 'converter': True}
    return {'engine': any(map(needs_engine, files)), 'converter': any(map(needs_converter, files))}


def changed(base: str, head: str = 'HEAD') -> list[str] | None:
    try:
        r = subprocess.run(['git', 'diff', '--name-only', '--no-renames', base, head], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return [line for line in r.stdout.splitlines() if line] if r.returncode == 0 else None


def main(argv: list[str]) -> int:
    files = changed(*argv[:2]) if argv else None
    for k, v in jobs(files).items():
        print(f'{k}={"true" if v else "false"}')
    if files is not None:
        print(f'{len(files)} file(s) changed', file=sys.stderr)
    else:
        print('changes unknown: every job runs', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
