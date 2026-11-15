"""scripts/perf_release.py: the per-release frame-time tables (docs/perf/) compare as described in docs/performance.md. No Mac or game needed."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('perf_release', REPO / 'scripts/perf_release.py')
assert spec and spec.loader
pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pr)


def row(fps, p99, gid='0100B99019412000', route='idle', mac='M4 Pro'):
    return {'title_id': gid, 'route': route, 'mac': mac, 'fps': str(fps), 'frame_p50': '16.67', 'frame_p99': str(p99), 'frame_max': '40'}


class Compare(unittest.TestCase):
    def test_same_numbers_pass(self):
        table, bad = pr.compare([row(60, 17)], [row(60, 17)])
        self.assertEqual(bad, [])
        self.assertIn('60 → 60 (+0 %)', table)

    def test_slower_frame_rate_and_p99_flagged(self):
        _, bad = pr.compare([row(60, 17)], [row(55, 25)])
        self.assertEqual(len(bad), 2, bad)

    def test_within_thresholds(self):
        _, bad = pr.compare([row(60, 20)], [row(59, 22)])
        self.assertEqual(bad, [])

    def test_other_mac_or_route_not_compared(self):
        table, bad = pr.compare([row(60, 17)], [row(30, 50, mac='M1'), row(30, 50, route='zora-pan')])
        self.assertEqual(bad, [])
        self.assertEqual(len(table.splitlines()), 2)   # header only

    def test_table_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / '0.8.0.tsv'
            r = {c: 'x' for c in pr.COLUMNS}
            pr.write(p, [r], '0.8.0')
            self.assertEqual(pr.read(p), [r])

    def test_stored_tables_parse(self):
        for f in sorted((REPO / 'docs/perf').glob('*.tsv')):
            rows = pr.read(f)
            for r in rows: self.assertEqual(set(r), set(pr.COLUMNS), f.name)



class AppRuns(unittest.TestCase):
    def tsv(self, frames):
        return ''.join(f'{i}\t@t_s\t{t}\n{i}\t@frame_ms\t{ms}\n{i}\t@gpu_ms\t{g}\n' for i, (t, ms, g) in enumerate(frames))

    def test_stats_count_the_window_only(self):
        frames = [(19.9, 300.0, 9.0)] + [(20 + i / 60, 16.67, 4.0) for i in range(600)] + [(30.5, 200.0, 9.0)]
        d = pr.tsv_stats(self.tsv(frames), 20, 30)
        self.assertEqual(d['fps'], 60.0)
        self.assertEqual((d['frame_p50'], d['frame_max'], d['over_budget'], d['gpu_p50']), (16.67, 16.67, 0, 4.0))

    def test_stats_count_spikes(self):
        frames = [(20 + i / 60, 40.0 if i % 100 == 0 else 16.67, -1) for i in range(600)]
        d = pr.tsv_stats(self.tsv(frames), 20, 30)
        self.assertEqual(d['over_budget'], 6)
        self.assertEqual(d['frame_max'], 40.0)
        self.assertNotIn('gpu_p50', d)

    def test_no_frames_no_stats(self):
        self.assertEqual(pr.tsv_stats('junk\nline\n', 20, 30), {})
        self.assertEqual(pr.tsv_stats(self.tsv([(5, 16.67, 1.0)]), 20, 30), {})

    def test_title_id_from_the_bundle_identifier(self):
        import plistlib
        with tempfile.TemporaryDirectory() as t:
            app = Path(t) / 'Game.app'
            (app / 'Contents').mkdir(parents=True)
            for ident, want in (('org.nxforge.04008e001f098000', '04008E001F098000'), ('com.apple.Safari', '')):
                (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': ident}))
                self.assertEqual(pr.app_title_id(app), want)

    def test_other_host_keeps_the_bundle_by_link(self):
        with tempfile.TemporaryDirectory() as t:
            app, host = Path(t) / 'Game.app', Path(t) / 'dmhost'
            (app / 'Contents/MacOS').mkdir(parents=True); (app / 'Contents/Resources').mkdir()
            (app / 'Contents/MacOS/nxnative').write_text('launcher'); (app / 'Contents/MacOS/dmhost').write_text('old'); host.write_text('new')
            (app / 'Contents/Info.plist').write_text('x')
            out = Path(t) / 'run'; out.mkdir()
            run = pr.with_host(app, host, out)
            self.assertEqual((run / 'Contents/MacOS/dmhost').read_text(), 'new')
            self.assertTrue((run / 'Contents/Resources').is_symlink())
            self.assertEqual((app / 'Contents/MacOS/dmhost').read_text(), 'old')

if __name__ == '__main__':
    unittest.main()
