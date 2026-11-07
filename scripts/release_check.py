#!/usr/bin/env python3
"""NXForge release checks and notes (UPSTREAM.md, Versions).

  release_check.py lint                 CHANGELOG.md's headings are "## X.Y.Z (YYYY-MM-DD)" (or one "## Unreleased" on top),
                                        newest first, versions and dates never going up further down; BACKLOG.md has a
                                        "Last updated YYYY-MM-DD" line. CI runs this through dm/tools/tests/test_release_check.py.
  release_check.py check X.Y.Z          Before tagging vX.Y.Z: lint, and the newest CHANGELOG entry is X.Y.Z with a date, and
                                        BACKLOG.md was updated on or after the previous release's date.
  release_check.py notes X.Y.Z          Prints that version's CHANGELOG entry without its heading: the GitHub release's notes
                                        (.github/workflows/release.yml).
  release_check.py tag TAG              Prints what a tag releases, as "<changelog> <version> <title>": vX.Y.Z is NXForge,
                                        sidebar-vX.Y.Z the in-game sidebar.

The sidebar (Quick settings) has its own version and tags (UPSTREAM.md, Versions): its version is SIDEBAR_VERSION in
dm/host/quick_settings_mac.swift and its history SIDEBAR_CHANGELOG.md, with the same heading rules. Give check and notes
the version as sidebar-vX.Y.Z (or --sidebar X.Y.Z): check then also wants the Swift constant to be X.Y.Z and skips the
BACKLOG rule. lint checks both changelogs, and that the Swift constant is the sidebar's newest entry or newer.
No network, no git: it reads those files only.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HEADING = re.compile(r'^## (?P<version>\d+\.\d+\.\d+) \((?P<date>\d{4}-\d{2}-\d{2})\)$')
UNRELEASED = '## Unreleased'
BACKLOG_DATE = re.compile(r'Last updated (\d{4}-\d{2}-\d{2})')
SIDEBAR_LOG = 'SIDEBAR_CHANGELOG.md'
SIDEBAR_SWIFT = 'dm/host/quick_settings_mac.swift'
SIDEBAR_CONST = re.compile(r'^let SIDEBAR_VERSION = "(\d+\.\d+\.\d+)"', re.M)


class Entry:
    def __init__(self, version: str | None, day: date | None, line: int, body: list[str]):
        self.version, self.day, self.line, self.body = version, day, line, body

    @property
    def key(self) -> tuple[int, ...]:
        return tuple(int(p) for p in (self.version or '0.0.0').split('.'))


def entries(changelog: str, name: str = 'CHANGELOG.md') -> tuple[list[Entry], list[str]]:
    """The changelog's entries, newest first, and the problems with their headings."""
    out: list[Entry] = []
    problems: list[str] = []
    for n, line in enumerate(changelog.splitlines(), 1):
        if line.startswith('## '):
            m = HEADING.match(line)
            if m:
                try:
                    day = date.fromisoformat(m['date'])
                except ValueError:
                    problems.append(f'{name}:{n}: {m["date"]} is not a date')
                    day = None
                out.append(Entry(m['version'], day, n, []))
            elif line.strip() == UNRELEASED:
                if out:
                    problems.append(f'{name}:{n}: "{UNRELEASED}" must be the first entry')
                out.append(Entry(None, None, n, []))
            else:
                problems.append(f'{name}:{n}: heading is not "## X.Y.Z (YYYY-MM-DD)" or "{UNRELEASED}": {line!r}')
        elif out:
            out[-1].body.append(line)
    return out, problems


def lint_log(changelog: str, name: str = 'CHANGELOG.md') -> list[str]:
    found, problems = entries(changelog, name)
    released = [e for e in found if e.version]
    if not released:
        problems.append(f'{name}: no released entry')
    for newer, older in zip(released, released[1:]):
        if newer.key <= older.key:
            problems.append(f'{name}:{newer.line}: {newer.version} is not newer than {older.version} below it')
        if newer.day and older.day and newer.day < older.day:
            problems.append(f'{name}:{newer.line}: {newer.version} is dated before {older.version} below it')
    for e in found:
        if not any(line.strip() for line in e.body):
            problems.append(f'{name}:{e.line}: entry is empty')
    return problems


def lint(changelog: str, backlog: str) -> list[str]:
    problems = lint_log(changelog)
    if not BACKLOG_DATE.search(backlog):
        problems.append('BACKLOG.md: no "Last updated YYYY-MM-DD" line')
    return problems


def check(version: str, changelog: str, backlog: str) -> list[str]:
    problems = lint(changelog, backlog)
    found, _ = entries(changelog)
    released = [e for e in found if e.version]
    if not found or found[0].version != version:
        top = (found[0].version or 'Unreleased') if found else 'nothing'
        problems.append(f'CHANGELOG.md: the newest entry is {top}, not "## {version} (YYYY-MM-DD)"')
    elif len(released) > 1 and released[1].day:
        m = BACKLOG_DATE.search(backlog)
        if m and date.fromisoformat(m[1]) < released[1].day:
            problems.append(f'BACKLOG.md: last updated {m[1]}, before the previous release ({released[1].version}, '
                            f'{released[1].day}); update the rows this release touches and the date')
    return problems


def sidebar_const(swift: str) -> str | None:
    m = SIDEBAR_CONST.search(swift)
    return m[1] if m else None


def lint_sidebar(changelog: str, swift: str) -> list[str]:
    problems = lint_log(changelog, SIDEBAR_LOG)
    const = sidebar_const(swift)
    released = [e for e in entries(changelog, SIDEBAR_LOG)[0] if e.version]
    if const is None:
        problems.append(f'{SIDEBAR_SWIFT}: no line `let SIDEBAR_VERSION = "X.Y.Z"`')
    elif released and tuple(map(int, const.split('.'))) < released[0].key:
        problems.append(f'{SIDEBAR_SWIFT}: SIDEBAR_VERSION {const} is older than {SIDEBAR_LOG}\'s newest entry {released[0].version}')
    return problems


def check_sidebar(version: str, changelog: str, swift: str) -> list[str]:
    problems = lint_sidebar(changelog, swift)
    found, _ = entries(changelog, SIDEBAR_LOG)
    if not found or found[0].version != version:
        top = (found[0].version or 'Unreleased') if found else 'nothing'
        problems.append(f'{SIDEBAR_LOG}: the newest entry is {top}, not "## {version} (YYYY-MM-DD)"')
    const = sidebar_const(swift)
    if const is not None and const != version:
        problems.append(f'{SIDEBAR_SWIFT}: SIDEBAR_VERSION is {const}, not {version}')
    return problems


def parse_tag(tag: str) -> tuple[bool, str]:
    """(is the sidebar, X.Y.Z) for vX.Y.Z, X.Y.Z, sidebar-vX.Y.Z or sidebar-X.Y.Z."""
    sidebar = tag.startswith('sidebar-')
    return sidebar, tag.removeprefix('sidebar-').removeprefix('v')


def notes(version: str, changelog: str) -> str | None:
    found, _ = entries(changelog)
    for e in found:
        if e.version == version:
            return '\n'.join(e.body).strip() + '\n'
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=['lint', 'check', 'notes', 'tag'])
    ap.add_argument('version', nargs='?', help='X.Y.Z or vX.Y.Z (NXForge), sidebar-vX.Y.Z (the sidebar)')
    ap.add_argument('--sidebar', action='store_true', help='the version is the sidebar\'s')
    a = ap.parse_args(argv)
    read = lambda rel: (REPO / rel).read_text(encoding='utf-8')
    changelog, backlog = read('CHANGELOG.md'), read('BACKLOG.md')
    side_log, swift = read(SIDEBAR_LOG), read(SIDEBAR_SWIFT)
    sidebar, version = parse_tag(a.version or '')
    sidebar = sidebar or a.sidebar
    if a.command != 'lint' and not re.fullmatch(r'\d+\.\d+\.\d+', version):
        ap.error(f'{a.command} needs a version X.Y.Z')
    if a.command == 'tag':
        print(f'{SIDEBAR_LOG} {version} NXForge Sidebar {version}' if sidebar else f'CHANGELOG.md {version} NXForge {version}')
        return 0
    if a.command == 'notes':
        text = notes(version, side_log if sidebar else changelog)
        if text is None:
            print(f'{SIDEBAR_LOG if sidebar else "CHANGELOG.md"} has no entry for {version}', file=sys.stderr)
            return 1
        sys.stdout.write(text)
        return 0
    if a.command == 'lint':
        problems = lint(changelog, backlog) + lint_sidebar(side_log, swift)
    elif sidebar:
        problems = check_sidebar(version, side_log, swift)
    else:
        problems = check(version, changelog, backlog)
    for p in problems:
        print(f'✗ {p}')
    if not problems:
        done = f'CHANGELOG.md, BACKLOG.md and {SIDEBAR_LOG}' if a.command == 'lint' else \
            f'{"sidebar-v" if sidebar else "v"}{version} is ready to tag'
        print(f'✓ {done}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
