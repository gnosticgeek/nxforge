#!/usr/bin/env python3
"""NXForge release checks and notes (UPSTREAM.md, Versions).

  release_check.py lint                 CHANGELOG.md's headings are "## X.Y.Z (YYYY-MM-DD)" (or one "## Unreleased" on top),
                                        newest first, versions and dates never going up further down; BACKLOG.md has a
                                        "Last updated YYYY-MM-DD" line. CI runs this through dm/tools/tests/test_release_check.py.
  release_check.py check X.Y.Z          Before tagging vX.Y.Z: lint, and the newest CHANGELOG entry is X.Y.Z with a date, and
                                        BACKLOG.md was updated on or after the previous release's date.
  release_check.py notes X.Y.Z          Prints that version's CHANGELOG entry without its heading: the GitHub release's notes
                                        (.github/workflows/release.yml).
No network, no git: it reads the two files only.
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


class Entry:
    def __init__(self, version: str | None, day: date | None, line: int, body: list[str]):
        self.version, self.day, self.line, self.body = version, day, line, body

    @property
    def key(self) -> tuple[int, ...]:
        return tuple(int(p) for p in (self.version or '0.0.0').split('.'))


def entries(changelog: str) -> tuple[list[Entry], list[str]]:
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
                    problems.append(f'CHANGELOG.md:{n}: {m["date"]} is not a date')
                    day = None
                out.append(Entry(m['version'], day, n, []))
            elif line.strip() == UNRELEASED:
                if out:
                    problems.append(f'CHANGELOG.md:{n}: "{UNRELEASED}" must be the first entry')
                out.append(Entry(None, None, n, []))
            else:
                problems.append(f'CHANGELOG.md:{n}: heading is not "## X.Y.Z (YYYY-MM-DD)" or "{UNRELEASED}": {line!r}')
        elif out:
            out[-1].body.append(line)
    return out, problems


def lint(changelog: str, backlog: str) -> list[str]:
    found, problems = entries(changelog)
    released = [e for e in found if e.version]
    if not released:
        problems.append('CHANGELOG.md: no released entry')
    for newer, older in zip(released, released[1:]):
        if newer.key <= older.key:
            problems.append(f'CHANGELOG.md:{newer.line}: {newer.version} is not newer than {older.version} below it')
        if newer.day and older.day and newer.day < older.day:
            problems.append(f'CHANGELOG.md:{newer.line}: {newer.version} is dated before {older.version} below it')
    for e in found:
        if not any(line.strip() for line in e.body):
            problems.append(f'CHANGELOG.md:{e.line}: entry is empty')
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


def notes(version: str, changelog: str) -> str | None:
    found, _ = entries(changelog)
    for e in found:
        if e.version == version:
            return '\n'.join(e.body).strip() + '\n'
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=['lint', 'check', 'notes'])
    ap.add_argument('version', nargs='?', help='X.Y.Z (a leading v is dropped)')
    a = ap.parse_args(argv)
    changelog = (REPO / 'CHANGELOG.md').read_text(encoding='utf-8')
    backlog = (REPO / 'BACKLOG.md').read_text(encoding='utf-8')
    version = (a.version or '').removeprefix('v')
    if a.command != 'lint' and not re.fullmatch(r'\d+\.\d+\.\d+', version):
        ap.error(f'{a.command} needs a version X.Y.Z')
    if a.command == 'notes':
        text = notes(version, changelog)
        if text is None:
            print(f'CHANGELOG.md has no entry for {version}', file=sys.stderr)
            return 1
        sys.stdout.write(text)
        return 0
    problems = lint(changelog, backlog) if a.command == 'lint' else check(version, changelog, backlog)
    for p in problems:
        print(f'✗ {p}')
    if not problems:
        print(f'✓ {"CHANGELOG.md and BACKLOG.md" if a.command == "lint" else version + " is ready to tag"}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
