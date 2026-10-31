#!/usr/bin/env python3
"""Frame times per NXForge release, kept in the repository (docs/performance.md).

  perf_release.py run <id>_build ... [--release X.Y.Z] [--seconds 90] [--runs 2]
      Runs scripts/bench.py on each game build (its first bench.tsv route, or --idle for a game without routes), takes the median of the runs,
      and writes one row per game into docs/perf/<release>.tsv (a game measured again on the same Mac replaces its row). Close other apps,
      keep the Mac on power, and use the same display as the release it is compared with.
  perf_release.py compare <old release> <new release>
      A Markdown table of the games both measured on the same Mac and route, with the changes; exit status 1 when a game got slower
      past the thresholds (frame rate down more than 3 %, p99 frame time up more than 15 %).
Release defaults to the checkout's git describe (v0.8.0 → 0.8.0; v0.8.0-3-g… → 0.8.0+3).
"""
from __future__ import annotations

import argparse
import json
import platform
import re
import statistics
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PERF = REPO / 'docs/perf'
COLUMNS = ['title_id', 'route', 'mac', 'macos', 'date', 'runs', 'fps', 'frame_p50', 'frame_p99', 'frame_max', 'over_budget', 'gpu_p50', 'red_lines']
METRICS = COLUMNS[6:]
FPS_DROP, P99_RISE = 0.03, 0.15


def sh(*cmd: str) -> str:
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def release_name() -> str:
    d = sh('git', '-C', str(REPO), 'describe', '--tags', '--match', 'v[0-9]*')
    m = re.fullmatch(r'v(\d+\.\d+\.\d+)(?:-(\d+)-g[0-9a-f]+)?', d)
    if not m: return 'pre-0.1.0'
    return m[1] + (f'+{m[2]}' if m[2] else '')


def mac_name() -> str:
    chip = sh('sysctl', '-n', 'machdep.cpu.brand_string').removeprefix('Apple ')
    return chip or platform.machine()


def read(path: Path) -> list[dict[str, str]]:
    if not path.is_file(): return []
    lines = [ln for ln in path.read_text().splitlines() if ln and not ln.startswith('#')]
    if not lines: return []
    head = lines[0].split('\t')
    return [dict(zip(head, ln.split('\t'))) for ln in lines[1:]]


def write(path: Path, rows: list[dict[str, str]], release: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = sorted(rows, key=lambda r: (r['title_id'], r['route'], r['mac']))
    text = (f'# Frame times of NXForge {release} (scripts/perf_release.py run; docs/performance.md). Times in ms, medians over the runs.\n'
            + '\t'.join(COLUMNS) + '\n' + ''.join('\t'.join(r.get(c, '') for c in COLUMNS) + '\n' for r in rows))
    path.write_text(text)


def median(values: list) -> str:
    xs = [v for v in values if isinstance(v, (int, float))]
    if not xs: return ''
    m = statistics.median(xs)
    return str(round(m, 2))


def row_from(results: dict, mac: str, macos: str) -> dict[str, str]:
    runs = results['results']['base']
    r = {'title_id': results['game'], 'route': results['route'], 'mac': mac, 'macos': macos, 'date': date.today().isoformat(), 'runs': str(len(runs))}
    for k in METRICS: r[k] = median([x.get(k) for x in runs])
    return r


def run(a: argparse.Namespace) -> int:
    release = a.release or release_name()
    out = PERF / f'{release}.tsv'
    rows = read(out)
    mac, macos = mac_name(), sh('sw_vers', '-productVersion')
    failed = 0
    for b in a.builds:
        build = Path(b).expanduser().resolve()
        gid = build.name.split('_')[0].upper()
        cmd = [sys.executable, str(REPO / 'scripts/bench.py'), str(build), '--runs', str(a.runs), '--no-hud']
        if not (REPO / 'dm/games' / gid / 'bench.tsv').is_file(): cmd += ['--idle', str(a.seconds)]
        with tempfile.TemporaryDirectory() as tmp:
            cmd += ['--out', tmp]
            print('$', ' '.join(cmd), flush=True)
            rc = subprocess.run(cmd).returncode
            res = Path(tmp) / 'results.json'
            if rc != 0 or not res.is_file():
                print(f'✗ {gid}: bench.py failed (exit {rc})'); failed = 1; continue
            new = row_from(json.loads(res.read_text()), mac, macos)
        rows = [r for r in rows if (r['title_id'], r['route'], r['mac']) != (new['title_id'], new['route'], new['mac'])] + [new]
        print(f'✓ {gid} {new["route"]}: {new["fps"]} fps, p99 {new["frame_p99"]} ms')
    write(out, rows, release)
    print(f'{out.relative_to(REPO)}: {len(rows)} row(s)')
    return failed


def num(s: str | None) -> float | None:
    try: return float(s) if s else None
    except ValueError: return None


def change(before: str | None, after: str | None) -> str:
    a, b = num(before), num(after)
    if a is None or b is None: return after or '–'
    pct = f' ({(b - a) / a * 100:+.0f} %)' if a else ''
    return f'{a:g} → {b:g}{pct}'


def compare(old: list[dict[str, str]], new: list[dict[str, str]]) -> tuple[str, list[str]]:
    """A Markdown table of the pairs measured in both, and the regressions past the thresholds."""
    key = lambda r: (r['title_id'], r['route'], r['mac'])  # noqa: E731
    before = {key(r): r for r in old}
    lines = ['| Game | Route | Mac | fps | p50 ms | p99 ms | max ms |', '|---|---|---|---|---|---|---|']
    bad: list[str] = []
    for r in sorted(new, key=key):
        o = before.get(key(r))
        if not o: continue
        cells = ' | '.join(change(o.get(k), r.get(k)) for k in ('fps', 'frame_p50', 'frame_p99', 'frame_max'))
        lines.append(f'| {r["title_id"]} | {r["route"]} | {r["mac"]} | {cells} |')
        fa, fb, pa, pb = num(o.get('fps')), num(r.get('fps')), num(o.get('frame_p99')), num(r.get('frame_p99'))
        if fa and fb is not None and fb < fa * (1 - FPS_DROP): bad.append(f'{r["title_id"]} {r["route"]}: {fa:g} → {fb:g} fps')
        if pa and pb is not None and pb > pa * (1 + P99_RISE): bad.append(f'{r["title_id"]} {r["route"]}: p99 {pa:g} → {pb:g} ms')
    return '\n'.join(lines), bad


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='command', required=True)
    r = sub.add_parser('run'); r.add_argument('builds', nargs='+'); r.add_argument('--release'); r.add_argument('--seconds', type=float, default=90); r.add_argument('--runs', type=int, default=2)
    c = sub.add_parser('compare'); c.add_argument('old'); c.add_argument('new')
    a = ap.parse_args(argv)
    if a.command == 'run': return run(a)
    old, new = read(PERF / f'{a.old}.tsv'), read(PERF / f'{a.new}.tsv')
    if not old or not new:
        print(f'no measurements for {a.old if not old else a.new} in docs/perf/', file=sys.stderr); return 2
    table, bad = compare(old, new)
    print(f'NXForge {a.old} → {a.new}\n\n{table}\n')
    for b in bad: print(f'✗ slower: {b}')
    if not bad: print('✓ no game slower past the thresholds')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
