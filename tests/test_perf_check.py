#!/usr/bin/env python3
# scripts/perf_check.py: a session's numbers and causes from a game log, the history and the verdict (fake logs, a fake history file)
import sys, tempfile, unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'scripts'))
import perf_check as pc  # noqa: E402  # pyright: ignore[reportMissingImports]


def log(dropped, gpu=11.0, fixed=False, metalfx=False, n=12):
    out = ['launcher: Mario Kart World (0400C3F00006E000), host x', '[dm] build: commit 2ad969b50e24, shader chain 84995ea60469, profile 0400C3F00006E000']
    if metalfx: out.append('[dm] [nvn-mtl] present upscaling: MetalFX where the picture is shown larger than the game renders it')
    out.append('[dm] front end: full screen hides the menu bar, title bar and Dock')
    if fixed: out.append('[dm] front end: variable-refresh screen at 120 Hz switched to fixed 60 Hz for 60 fps in fullscreen (DM_SCREEN_MATCH=0 keeps it)')
    for i in range(1, n + 1):
        f = i * 300
        out.append(f'[dm] [nvn] timing up to frame {f}: frame time p50 16.70 / p95 18.00 / max 20.00 ms (300 frames); GPU p50 {gpu:.2f} / p95 {gpu + 1:.2f} / max 20.00 ms (300 frames);')
        out.append(f'[dm] [nvn] on-screen up to frame {f}: 300 frames, dropped {dropped} (discarded 0), p99 16.67 ms; footprint 9000 MiB; brightness -1.00; thermal 0')
    out.append('launcher: the host exited with 0')
    return '\n'.join(out) + '\n'


class PerfCheck(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory(); self.d = Path(self.td.name)
        self.p = [mock.patch.object(pc, 'HISTORY', self.d / 'hist.tsv'), mock.patch.object(pc, 'LOGS', self.d)]
        for p in self.p: p.start()

    def tearDown(self):
        for p in self.p: p.stop()
        self.td.cleanup()

    def write(self, name, text, t):
        f = self.d / name; f.write_text(text); import os; os.utime(f, (t, t)); return f

    def test_numbers_and_causes(self):
        f = self.write('0400C3F00006E000.log', log(60, gpu=13.5, fixed=True, metalfx=True), 1000)
        s = pc.check([str(f)])[0]
        self.assertEqual(s["frames"], 3000)   # the first two windows are skipped
        self.assertEqual(s['on_time'], 80.0)
        self.assertEqual(s['gpu_p50'], 13.5)
        self.assertEqual(s['screen'], 'fixed 60 Hz')
        self.assertTrue(s['fullscreen'])
        self.assertTrue(any('60 Hz' in c for c in s['causes']) and any('MetalFX' in c for c in s['causes']))

    def test_history_and_verdict(self):
        for k in range(3):
            pc.check([str(self.write(f'good{k}.log', log(1), 1000 + k))], rec=True)
        self.assertEqual(len(pc.history()), 3)
        good = self.write('again.log', log(1), 1000)   # same end time as an earlier log of another name: still recorded once per (title, end)
        pc.check([str(good)], rec=True)
        self.assertEqual(len(pc.history()), 3)
        bad = pc.check([str(self.write('bad.log', log(45, fixed=True), 2000))], rec=True)[0]
        self.assertEqual(bad['verdict'], 'slower'); self.assertEqual(bad['usual'], 99.7)
        self.assertTrue(bad['recorded'])
        self.assertEqual(pc.main([str(self.d / 'bad.log')]), 1)
        smooth = pc.check([str(self.write('ok.log', log(0), 3000))])[0]
        self.assertEqual(smooth['verdict'], 'smooth')

    def test_short_and_missing(self):
        self.assertEqual(pc.check([str(self.write('s.log', log(0, n=4), 5))])[0]['verdict'], 'too short')
        self.assertEqual(pc.check(['0100000000000000'])[0]['error'], 'no log')


if __name__ == '__main__':
    unittest.main()
