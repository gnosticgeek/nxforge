#!/usr/bin/env python3
# Writes README.md's "Played on NXForge" table from docs/nxforge-games.tsv (the games someone played on a Mac, with the NXForge release, the Mac,
# the date and the result), between its two marker comments. --check fails when the README is not what the table gives, or a row is malformed
# (dm/tools/tests/test_nxforge_games.py runs it in CI). The converter reads the same file (app/Sources/NXForgeConverter/VerifiedGames.swift).
import argparse, pathlib, re, sys
from datetime import date

REPO = pathlib.Path(__file__).resolve().parents[2]
TABLE = REPO / 'docs/nxforge-games.tsv'
README = REPO / 'README.md'
START = '<!-- nxforge-games: written by dm/tools/nxforge_games.py from docs/nxforge-games.tsv; change the table, then run it -->'
END = '<!-- end of nxforge-games -->'
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


def table(rs):
    lines = [START, '| Game | Version | Result | NXForge | Mac | Played | Notes |', '|---|---|---|---|---|---|---|']
    for r in sorted(rs, key=lambda r: r['game'].lower()):
        game = f'[{r["game"]}](dm/games/{r["title_id"]}/README.md)' if (REPO / 'dm/games' / r['title_id'] / 'README.md').is_file() else r['game']
        lines.append(f'| {game} | {"–" if r["version"] == "-" else r["version"]} | {RESULTS[r["result"]]} | {r["release"]} | {r["mac"]} | {r["date"]} | {r["note"]} |')
    lines.append(END)
    return '\n'.join(lines)


def render(readme, rs):
    if START not in readme or END not in readme: raise SystemExit(f'README.md lacks the markers {START!r} … {END!r}')
    a, rest = readme.split(START, 1)
    _, b = rest.split(END, 1)
    return a + table(rs) + b


def main(argv=None):
    ap = argparse.ArgumentParser(description='Write README.md\'s "Played on NXForge" table from docs/nxforge-games.tsv.')
    ap.add_argument('--check', action='store_true', help='fail when README.md is out of date or the table has a problem; change nothing')
    a = ap.parse_args(argv)
    rs, problems = rows(TABLE.read_text(encoding='utf-8'))
    for p in problems: print(f'✗ {p}')
    if problems: return 1
    readme = README.read_text(encoding='utf-8')
    new = render(readme, rs)
    if a.check:
        if new != readme: print('✗ README.md\'s "Played on NXForge" table is out of date: run python3 dm/tools/nxforge_games.py'); return 1
        print(f'✓ {len(rs)} game(s)'); return 0
    if new != readme: README.write_text(new, encoding='utf-8')
    print(f'README.md: {len(rs)} game(s) played on NXForge'); return 0


if __name__ == '__main__':
    sys.exit(main())
