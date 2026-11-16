#!/usr/bin/env python3
"""How smoothly a game's last session ran, read from its log, and whether that is worse than its usual (docs/performance.md, Session check).

  perf_check.py [TITLE_ID | LOG] ... [--all] [--record] [--json]
      Reads ~/Library/Logs/nxnative/<title ID>.log (or the log given), sums the host's per-300-frame lines (frames on time, GPU time, footprint)
      and names what is known to cost frames on a Mac: full screen that switched a ProMotion screen to a fixed 60 Hz, the MetalFX upscaler,
      the frame-step hold, heat, Low Power Mode, battery, swap-sized footprints. --record adds the session to the history
      (~/Library/Application Support/NXForge/perf-history.tsv, once per log); the verdict compares it with that game's earlier sessions:
      "slower" when the share of frames on time fell more than 3 points below the median of its last five and is under 97 %.
      --all: every game with a log. Exit status 1 when a session is "slower" (for a routine to notice).
The same report is `nxforge perf` and the nxforge_perf tool of the MCP server.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
import time
from pathlib import Path

LOGS = Path.home() / 'Library/Logs/nxnative'
HISTORY = Path.home() / 'Library/Application Support/NXForge/perf-history.tsv'
COLUMNS = ['title_id', 'ended', 'build', 'frames', 'on_time', 'gpu_p50', 'gpu_p95', 'footprint_mb', 'fullscreen', 'screen', 'upscale', 'causes']
SKIP_WINDOWS = 2          # the first 600 frames: boot, the title, the first loads
SLOWER_POINTS, GOOD_SHARE = 3.0, 97.0

R_ONSCREEN = re.compile(r'on-screen up to frame (\d+): (\d+) frames, dropped (\d+) \(discarded (\d+)\), p99 ([\d.]+) ms; footprint (\d+) MiB(?:; brightness [-\d.]+; thermal (-?\d+))?')
R_TIMING = re.compile(r'timing up to frame (\d+):.*?GPU p50 ([\d.]+) / p95 ([\d.]+)')
R_BUILD = re.compile(r'\[dm\] build: commit (\w+), shader chain (\w+)(?:, profile ([0-9A-Fa-f]{16}))?')
R_STEP = re.compile(r'frame step: .*held 1 / 2 / 3 vsyncs (\d+) / (\d+) / (\d+) frames')


def parse(path: Path) -> dict:
    """One log → the session's numbers and the settings and events that matter for frame pacing"""
    s = {'log': str(path), 'title_id': path.name.split('.')[0], 'ended': int(path.stat().st_mtime), 'build': '', 'chain': '',
         'windows': [], 'fullscreen': False, 'screen': 'own', 'upscale': '', 'fps_hold': '', 'thermal_max': 0, 'low_power': False,
         'battery': False, 'covered': 0, 'held2': 0, 'held3': 0, 'players': 1, 'exit': ''}
    gpu = {}
    with open(path, errors='replace') as f:
        for ln in f:
            if 'up to frame' in ln:
                if m := R_TIMING.search(ln): gpu[int(m[1])] = (float(m[2]), float(m[3])); continue
                if m := R_ONSCREEN.search(ln):
                    n = int(m[1]); g = gpu.get(n, (None, None))
                    s['windows'].append({'frame': n, 'frames': int(m[2]), 'dropped': int(m[3]), 'p99': float(m[5]), 'footprint': int(m[6]), 'gpu_p50': g[0], 'gpu_p95': g[1]})
                    if m[7] is not None: s['thermal_max'] = max(s['thermal_max'], int(m[7]))
                    continue
            if m := R_BUILD.search(ln):
                s['build'], s['chain'] = m[1], m[2]
                if m[3]: s['title_id'] = m[3].upper()
            elif 'front end: full screen' in ln or 'NSWindowDidEnterFullScreen' in ln: s['fullscreen'] = True
            elif 'switched to fixed' in ln and 'Hz' in ln: s['screen'] = 'fixed ' + (re.search(r'fixed (\d+) Hz', ln) or [None, '?'])[1] + ' Hz'
            elif 'switched to' in ln and 'in fullscreen' in ln: s['screen'] = 'switched ' + (re.search(r'switched to (\d+) Hz', ln) or [None, '?'])[1] + ' Hz'
            elif 'present upscaling: MetalFX' in ln and 'where the picture' in ln: s['upscale'] = 'metalfx'
            elif 'present upscaling: off' in ln and not s['upscale']: s['upscale'] = 'off'
            elif 'present upscaling:' in ln and 'MetalFX\'s GPU time saved' in ln: s['upscale'] = 'bilinear (enlargement under DM_FX_MIN_SCALE)'
            elif 'frames are not held longer' in ln: s['fps_hold'] = 'off'
            elif 'frame step:' in ln and (m := R_STEP.search(ln)): s['held2'], s['held3'] = int(m[2]), int(m[3])
            elif 'Low Power Mode on' in ln: s['low_power'] = True
            elif 'running on battery' in ln: s['battery'] = True
            elif 'window covered' in ln: s['covered'] += 1
            elif 'hid controller applet' in ln and (m := re.search(r'(\d+) connected', ln)): s['players'] = max(s['players'], int(m[1]))
            elif ln.startswith('launcher: the host exited'): s['exit'] = ln.strip().removeprefix('launcher: the host ')
    play = s['windows'][SKIP_WINDOWS:] or s['windows']
    frames = sum(w['frames'] for w in play); dropped = sum(w['dropped'] for w in play)
    g50 = [w['gpu_p50'] for w in play if w['gpu_p50'] is not None]; g95 = [w['gpu_p95'] for w in play if w['gpu_p95'] is not None]
    s.update(frames=frames, dropped=dropped, on_time=round(100.0 * (1 - dropped / frames), 1) if frames else None,
             gpu_p50=round(statistics.median(g50), 2) if g50 else None, gpu_p95=round(statistics.median(g95), 2) if g95 else None,
             footprint_mb=max((w['footprint'] for w in s['windows']), default=0),
             rough_windows=sum(1 for w in play if w['frames'] and w['dropped'] / w['frames'] > 0.05))
    s['causes'] = causes(s)
    return s


def causes(s: dict) -> list[str]:
    """What is known to cost frames on a Mac, as found in the session (most likely first)"""
    out = []
    if s['screen'].startswith('fixed'): out.append(f'full screen switched the screen to {s["screen"].removeprefix("fixed ")} (a late frame waits a whole refresh; NXForge 0.44 keeps a ProMotion screen at 120 Hz)')
    if s['upscale'] == 'metalfx': out.append('MetalFX upscaler on (0.8-1.4 ms of GPU a present on an M4 Pro, against 0.24 for the bilinear pass)')
    if s['gpu_p50'] and s['gpu_p50'] > 14.5: out.append(f'GPU-bound: GPU p50 {s["gpu_p50"]} ms of the 16.7')
    if s['held2'] + s['held3'] and s['fps_hold'] != 'off': out.append(f'frame-step hold: {s["held2"] + s["held3"]} frames held at 30 or 20 fps')
    if s['thermal_max'] >= 2: out.append(f'heat: thermal state {s["thermal_max"]}')
    if s['low_power']: out.append('Low Power Mode')
    if s['battery']: out.append('on battery')
    if s['covered']: out.append(f'the game window was covered or lost focus {s["covered"]} time(s): frames around that do not measure the game')
    if s['footprint_mb'] > 14000: out.append(f'footprint {s["footprint_mb"] / 1024:.1f} GB (close other apps: swapping costs frames)')
    return out


def history() -> list[dict]:
    if not HISTORY.is_file(): return []
    lines = HISTORY.read_text().splitlines()
    head = next((ln.split('\t') for ln in lines if ln and not ln.startswith('#')), None)
    return [dict(zip(head, ln.split('\t'))) for ln in lines[1:] if ln and not ln.startswith('#') and ln.split('\t') != head] if head else []


def verdict(s: dict, past: list[dict]) -> dict:
    prev = [float(r['on_time']) for r in past if r['title_id'] == s['title_id'] and r['ended'] != str(s['ended']) and r.get('on_time') and int(r.get('frames') or 0) >= 3000][-5:]
    v = {'usual': round(statistics.median(prev), 1) if prev else None, 'sessions': len(prev)}
    if s['on_time'] is None or s['frames'] < 1500: v['verdict'] = 'too short'
    elif v['usual'] is not None and s['on_time'] < v['usual'] - SLOWER_POINTS and s['on_time'] < GOOD_SHARE: v['verdict'] = 'slower'
    elif s['on_time'] >= GOOD_SHARE: v['verdict'] = 'smooth'
    else: v['verdict'] = 'uneven' if v['usual'] is None or s['on_time'] < GOOD_SHARE else 'as usual'
    return v


def record(s: dict) -> bool:
    past = history()
    if any(r['title_id'] == s['title_id'] and r['ended'] == str(s['ended']) for r in past) or not s['frames']: return False
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    new = not HISTORY.is_file()
    with open(HISTORY, 'a') as f:
        if new: f.write('# NXForge session history (scripts/perf_check.py --record): one line per game log\n' + '\t'.join(COLUMNS) + '\n')
        row = dict(s, fullscreen='yes' if s['fullscreen'] else 'no', causes='; '.join(s['causes']).replace('\t', ' '))
        f.write('\t'.join(str(row.get(c, '') if row.get(c) is not None else '') for c in COLUMNS) + '\n')
    return True


def logs_for(targets: list[str], all_games: bool) -> list[Path]:
    if all_games: return sorted(p for p in LOGS.glob('*.log') if re.fullmatch(r'[0-9A-Fa-f]{16}\.log', p.name))
    out = []
    for t in targets:
        p = Path(t).expanduser()
        out.append(p if p.suffix == '.log' or p.is_file() else LOGS / f'{t.upper()}.log')
    return out


def check(targets: list[str] | None = None, all_games: bool = False, rec: bool = False) -> list[dict]:
    res = []
    for p in logs_for(targets or [], all_games or not targets):
        if not p.is_file(): res.append({'log': str(p), 'error': 'no log'}); continue
        s = parse(p); s.pop('windows')
        s.update(verdict(s, history()))
        if rec: s['recorded'] = record(s)
        res.append(s)
    return res


def human(res: list[dict]) -> str:
    out = []
    for s in res:
        if 'error' in s: out.append(f'{s["log"]}: {s["error"]}'); continue
        when = time.strftime('%d %b %H:%M', time.localtime(s['ended']))
        share = f'{s["on_time"]}% of frames on time' if s['on_time'] is not None else 'no frames counted'
        usual = f' (usually {s["usual"]}%)' if s.get('usual') is not None else ''
        out.append(f'{s["title_id"]}  {when}  {s["verdict"].upper()}: {share}{usual} over {s["frames"]} frames; GPU p50 {s["gpu_p50"]} ms; '
                   f'{"full screen" if s["fullscreen"] else "window"}, screen {s["screen"]}, upscaler {s["upscale"] or "?"}; footprint {s["footprint_mb"] / 1024:.1f} GB')
        out += [f'    - {c}' for c in s['causes']]
    return '\n'.join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('games', nargs='*', help='title IDs or log files (default: every game with a log)')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--record', action='store_true', help='add each session to the history once')
    ap.add_argument('--json', action='store_true')
    a = ap.parse_args(argv)
    res = check(a.games, a.all, a.record)
    print(json.dumps(res, indent=1) if a.json else human(res))
    return 1 if any(s.get('verdict') == 'slower' for s in res) else 0


if __name__ == '__main__':
    sys.exit(main())
