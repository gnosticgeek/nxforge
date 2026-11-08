"""scripts/perf_release.py: the per-release frame-time tables (docs/perf/) compare as described in docs/performance.md. No Mac or game needed."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
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


if __name__ == '__main__':
    unittest.main()
