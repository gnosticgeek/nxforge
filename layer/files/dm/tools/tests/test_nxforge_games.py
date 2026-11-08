"""docs/nxforge-games.tsv (games played on NXForge) is well formed (dm/tools/nxforge_games.py --check)."""
from pathlib import Path
import subprocess
import sys
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/tools'))
import nxforge_games as ng  # noqa: E402

HEADER = '\t'.join(ng.COLUMNS) + '\n'


class NXForgeGames(unittest.TestCase):
    def test_table_is_well_formed(self):
        r = subprocess.run([sys.executable, str(REPO / 'dm/tools/nxforge_games.py'), '--check'], cwd=REPO, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_bad_rows_are_reported(self):
        text = HEADER + '0100b99019412000\tX\t1.0\t0.1\tM4\t2026-13-01\tfine\tn\n'
        _, problems = ng.rows(text)
        self.assertEqual(len(problems), 4, problems)   # lower-case ID, release, date, result

    def test_one_row_per_game(self):
        row = '0100B99019412000\tX\t1.0\t0.8.0\tM4\t2026-10-31\tplays\tn\n'
        _, problems = ng.rows(HEADER + row + row)
        self.assertTrue(any('has a row already' in p for p in problems))


if __name__ == '__main__':
    unittest.main()
