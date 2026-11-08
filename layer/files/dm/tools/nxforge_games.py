#!/usr/bin/env python3
# Checks docs/nxforge-games.tsv (the games someone played on a Mac, with the NXForge release, the Mac, the date and the result): fails when a row
# is malformed (dm/tools/tests/test_nxforge_games.py runs it in CI). The converter's Builds page reads the file
# (app/Sources/NXForgeConverter/VerifiedGames.swift).
import argparse, pathlib, re, sys
from datetime import date

REPO = pathlib.Path(__file__).resolve().parents[2]
TABLE = REPO / 'docs/nxforge-games.tsv'
COLUMNS = ['title_id', 'game', 'version', 'release', 'mac', 'date', 'result', 'note']
RESULTS = {'plays': '✅ plays', 'boots': '🟡 boots', 'broken': '❌ broken'}


def rows(text):
    """The table's rows as dicts, and the problems found in it."""
    out, problems, header = [], [], None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith('#'): continue
        cells = line.split('\t')
        if header is None:
            header = cells
            if header != COLUMNS: problems.append(f'nxforge-games.tsv:{n}: the header is not {"/".join(COLUMNS)}')
            continue
        if len(cells) != len(COLUMNS):
            problems.append(f'nxforge-games.tsv:{n}: {len(cells)} columns, not {len(COLUMNS)}'); continue
        r = dict(zip(COLUMNS, cells))
        if not re.fullmatch(r'[0-9A-F]{16}', r['title_id']): problems.append(f'nxforge-games.tsv:{n}: title ID {r["title_id"]!r} is not 16 upper-case hex digits')
        if not re.fullmatch(r'\d+\.\d+\.\d+|pre-\d+\.\d+\.\d+', r['release']): problems.append(f'nxforge-games.tsv:{n}: release {r["release"]!r} is not X.Y.Z or pre-X.Y.Z')
        try: date.fromisoformat(r['date'])
        except ValueError: problems.append(f'nxforge-games.tsv:{n}: {r["date"]!r} is not a YYYY-MM-DD date')
        if r['result'] not in RESULTS: problems.append(f'nxforge-games.tsv:{n}: result {r["result"]!r} is not one of {", ".join(RESULTS)}')
        if any(x['title_id'] == r['title_id'] for x in out): problems.append(f'nxforge-games.tsv:{n}: {r["title_id"]} has a row already (keep the newest play only)')
        out.append(r)
    return out, problems


def main(argv=None):
    ap = argparse.ArgumentParser(description='Check docs/nxforge-games.tsv, the games played on NXForge.')
    ap.add_argument('--check', action='store_true', help='kept for CI; checking is all this does')
    ap.parse_args(argv)
    rs, problems = rows(TABLE.read_text(encoding='utf-8'))
    for p in problems: print(f'✗ {p}')
    if problems: return 1
    print(f'✓ {len(rs)} game(s)'); return 0


if __name__ == '__main__':
    sys.exit(main())
