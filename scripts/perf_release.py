#!/usr/bin/env python3
"""Frame times per NXForge release, kept in the repository (docs/performance.md).

  perf_release.py run <id>_build ... [--release X.Y.Z] [--seconds 90] [--runs 2]
      Runs scripts/bench.py on each game build (its first bench.tsv route, or --idle for a game without routes), takes the median of the runs,
      and writes one row per game into docs/perf/<release>.tsv (a game measured again on the same Mac replaces its row). Close other apps,
      keep the Mac on power, and use the same display as the release it is compared with.
  perf_release.py run --app <Game>.app ... [--host tree/dm/host/dmhost] [--route NAME] [--save FOLDER] [--release X.Y.Z] [--seconds 90] [--runs 2]
      The same for games as they are installed, for a Mac that keeps no build folders. Each app is started as Play starts it, with the route's
      input (the route NAME of the game's bench.tsv; no route: the game is left alone and the frames from 20 s on count) and a copy of --save
      (without --save an empty save: the player's own is never touched). --host runs this checkout's host on the app's game files, so the
      release is what is measured and not the engine the app was built with; an app built with another shader chain is skipped, since
      the host loads only its own chain's shaders. Rebuild or repack that game first.
  perf_release.py compare <old release> <new release>
      A Markdown table of the games both measured on the same Mac and route, with the changes; exit status 1 when a game got slower
      past the thresholds (frame rate down more than 3 %, p99 frame time up more than 15 %).
Release defaults to the checkout's git describe (v0.8.0 → 0.8.0; v0.8.0-3-g… → 0.8.0+3).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import platform
import plistlib
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ENGINE = REPO / 'tree' if (REPO / 'layer/ENGINE').is_file() else REPO   # the assembled engine (scripts/layer.py) from 0.19.0
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
        cmd = [sys.executable, str(ENGINE / 'scripts/bench.py'), str(build), '--runs', str(a.runs), '--no-hud']
        if not (ENGINE / 'dm/games' / gid / 'bench.tsv').is_file(): cmd += ['--idle', str(a.seconds)]
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


BUDGET_MS = 1000 / 60
IDLE_FROM = 20.0   # an app without a route: its first 20 s (loading, the first pipelines) do not count


def pct(xs: list[float], p: float) -> float:
    s = sorted(xs)
    return s[min(len(s) - 1, max(0, math.ceil(p / 100 * len(s)) - 1))]


def tsv_stats(text: str, t0: float, t1: float) -> dict[str, float]:
    """The metrics of one run from the host's per-frame rows (DM_NVN_TSV: frame, @name, value), over the frames whose @t_s lies in [t0, t1). As scripts/bench.py counts them."""
    rows: dict[int, dict[str, float]] = {}
    for ln in text.splitlines():
        c = ln.split('\t')
        if len(c) != 3 or not c[1].startswith('@'): continue
        try: rows.setdefault(int(c[0]), {})[c[1]] = float(c[2])
        except ValueError: continue
    sel = [r for _, r in sorted(rows.items()) if '@t_s' in r and t0 <= r['@t_s'] < t1]
    ft = [r['@frame_ms'] for r in sel if r.get('@frame_ms', 0) > 0]
    gpu = [r['@gpu_ms'] for r in sel if r.get('@gpu_ms', -1) >= 0]
    if not sel or not ft: return {}
    d = {'fps': round(len(sel) / (t1 - t0), 1), 'frame_p50': round(pct(ft, 50), 2), 'frame_p99': round(pct(ft, 99), 2), 'frame_max': round(max(ft), 2),
         'over_budget': sum(1 for x in ft if x > BUDGET_MS * 1.5)}
    if gpu: d['gpu_p50'] = round(pct(gpu, 50), 2)
    return d


def app_title_id(app: Path) -> str:
    """The title ID of a game app NXForge built: the end of its bundle identifier (org.nxforge.<id>)."""
    with open(app / 'Contents/Info.plist', 'rb') as fh: ident = plistlib.load(fh).get('CFBundleIdentifier', '')
    last = ident.rsplit('.', 1)[-1].upper()
    return last if re.fullmatch(r'[0-9A-F]{16}', last) else ''


def route_of(gid: str, name: str | None) -> dict | None:
    """A route of the game's bench.tsv (name, DM_KEYS, the window's start and length in seconds): the named one, or none without a name."""
    if not name: return None
    f = ENGINE / 'dm/games' / gid / 'bench.tsv'
    for ln in f.read_text().splitlines() if f.is_file() else []:
        c = ln.split('\t')
        if len(c) >= 4 and c[0] == name: return {'name': c[0], 'keys': c[1], 'from': float(c[2]), 'secs': float(c[3])}
    return None


def host_chain() -> str:
    m = re.search(r'DMSH_CHAIN\s+"([0-9a-f]+)"', (ENGINE / 'dm/gfx/nvn/dmsh_chain.h').read_text())
    return m[1] if m else ''


def with_host(app: Path, host: Path, tmp: Path) -> Path:
    """The app with another host: its bundle by symlink, its launcher and that host copied."""
    t = tmp / 'PerfRun.app'
    (t / 'Contents/MacOS').mkdir(parents=True)
    for f in (app / 'Contents').iterdir():
        if f.name not in ('MacOS', '_CodeSignature'): (t / 'Contents' / f.name).symlink_to(f)
    shutil.copy2(app / 'Contents/MacOS/nxnative', t / 'Contents/MacOS/nxnative')
    shutil.copy2(host, t / 'Contents/MacOS/dmhost')
    return t


def run_app_once(app: Path, gid: str, route: dict | None, seconds: float, save: Path | None, tmp: Path) -> dict[str, float]:
    t0, t1 = (route['from'], route['from'] + route['secs']) if route else (IDLE_FROM, IDLE_FROM + seconds)
    run_save = tmp / 'save'
    shutil.rmtree(run_save, ignore_errors=True)
    if save: shutil.copytree(save, run_save)
    else: run_save.mkdir()
    tsv = tmp / 'frames.tsv'
    tsv.unlink(missing_ok=True)
    env = dict(os.environ, DM_LAUNCHER='0', DM_NVN_TSV=str(tsv), DM_NVN_TSV_CALLS='0', DM_SAVE=str(run_save), DM_SAVE_SYNC='0', DM_METAL_HUD='0')
    if route and route['keys']: env['DM_KEYS'] = route['keys']
    p = subprocess.Popen([str(app / 'Contents/MacOS/nxnative')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        end = time.monotonic() + t1 + 2
        while time.monotonic() < end and p.poll() is None: time.sleep(0.5)
    finally:
        subprocess.run(['pkill', '-TERM', '-P', str(p.pid)], capture_output=True)
        if p.poll() is None: p.terminate()
        try: p.wait(timeout=8)
        except subprocess.TimeoutExpired:
            subprocess.run(['pkill', '-KILL', '-P', str(p.pid)], capture_output=True); p.kill()
    d = tsv_stats(tsv.read_text(errors='replace'), t0, t1) if tsv.is_file() else {}
    log = Path.home() / 'Library/Logs/nxnative' / f'{gid}.log'
    if d and log.is_file(): d['red_lines'] = sum(1 for ln in log.read_text(errors='replace').splitlines() if '[RED]' in ln)
    return d


def run_apps(a: argparse.Namespace) -> int:
    release = a.release or release_name()
    out = PERF / f'{release}.tsv'
    rows = read(out)
    mac, macos = mac_name(), sh('sw_vers', '-productVersion')
    host = Path(a.host).expanduser().resolve() if a.host else None
    chain = host_chain() if host else ''
    failed = 0
    for x in a.app:
        app = Path(x).expanduser().resolve()
        gid = app_title_id(app) if (app / 'Contents/Info.plist').is_file() else ''
        if not gid:
            print(f'✗ {app.name}: not a game app NXForge built (no org.nxforge.<title ID> identifier)'); failed = 1; continue
        if host and chain and chain.encode() not in (app / 'Contents/MacOS/dmhost').read_bytes():
            print(f'– {gid} {app.name}: built with another shader chain than this host ({chain}); skipped. Rebuild or repack it to measure this release'); continue
        route = route_of(gid, a.route)
        if a.route and not route:
            print(f'✗ {gid}: no route {a.route} in dm/games/{gid}/bench.tsv'); failed = 1; continue
        runs = []
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            target = with_host(app, host, tmp) if host else app
            for i in range(a.runs):
                d = run_app_once(target, gid, route, a.seconds, Path(a.save).expanduser() if a.save else None, tmp)
                print(f'  {gid} run {i + 1}: ' + (f'{d["fps"]} fps, p99 {d["frame_p99"]} ms' if d else 'no frames'), flush=True)
                if d: runs.append(d)
                time.sleep(3)
        if not runs:
            print(f'✗ {gid}: no frames in the measuring window'); failed = 1; continue
        new = {'title_id': gid, 'route': route['name'] if route else 'idle', 'mac': mac, 'macos': macos, 'date': date.today().isoformat(), 'runs': str(len(runs))}
        for k in METRICS: new[k] = median([r.get(k) for r in runs])
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
    r = sub.add_parser('run'); r.add_argument('builds', nargs='*'); r.add_argument('--release'); r.add_argument('--seconds', type=float, default=90); r.add_argument('--runs', type=int, default=2)
    r.add_argument('--app', action='append', default=[]); r.add_argument('--host'); r.add_argument('--route'); r.add_argument('--save')
    c = sub.add_parser('compare'); c.add_argument('old'); c.add_argument('new')
    a = ap.parse_args(argv)
    if a.command == 'run':
        if not a.builds and not a.app: ap.error('run: a build folder or --app <Game>.app')
        return (run(a) if a.builds else 0) | (run_apps(a) if a.app else 0)
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
