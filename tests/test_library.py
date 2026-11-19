#!/usr/bin/env python3
# scripts/library.py: collecting game folders' enhancements and cheats into library/, and checking it
import importlib.util, sys, tempfile, unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('library', REPO / 'scripts/library.py')
assert spec is not None and spec.loader is not None
lib = importlib.util.module_from_spec(spec); sys.modules['library'] = lib; spec.loader.exec_module(lib)

ENH = '---\nnxforge_enhancement: 1\nname: "Steady 60"\ntitle_id: "010019401051C000"\non: true\n---\n# Steady 60\n\nSummary.\n\n```env\nDM_X=1\n```\n'
CHEATS = '---\nnxforge_cheats: 1\ntitle_id: "010019401051C000"\nbuild_id: "2E90F0815B1F92A1"\n---\n## Inf. Coins\n```dmnt on\n580C0000 00FFE2E8\n```\n'


class Library(unittest.TestCase):
    def test_collect_switches_off_and_checks(self):
        with tempfile.TemporaryDirectory() as t:
            games, library = Path(t) / 'games', Path(t) / 'library'
            g = games / 'Mario Strikers'
            (g / 'enhancements').mkdir(parents=True); (g / 'cheats').mkdir()
            (g / 'enhancements' / 'steady-60.md').write_text(ENH)
            (g / 'cheats' / '2E90F0815B1F92A1.md').write_text(CHEATS)
            (g / 'cheats' / 'notes.md').write_text('# not a cheat file\n')
            done = lib.collect(games, library)
            self.assertEqual(sorted(done), ['010019401051C000/cheats/2E90F0815B1F92A1.md', '010019401051C000/enhancements/steady-60.md'])
            self.assertIn('on: false', (library / '010019401051C000/enhancements/steady-60.md').read_text())
            self.assertNotIn('```dmnt on', (library / '010019401051C000/cheats/2E90F0815B1F92A1.md').read_text())
            self.assertEqual(lib.collect(games, library), [])   # nothing new the second time
            self.assertEqual(lib.check(library), [])

    def test_check_finds_problems(self):
        with tempfile.TemporaryDirectory() as t:
            library = Path(t)
            (library / '010019401051C000' / 'enhancements').mkdir(parents=True)
            (library / '010019401051C000' / 'enhancements' / 'a.md').write_text(ENH)   # on: true, wrong in the library
            (library / '0100000000010000' / 'enhancements').mkdir(parents=True)
            (library / '0100000000010000' / 'enhancements' / 'b.md').write_text(lib.switched_off(ENH))   # another game's ID
            bad = lib.check(library)
            self.assertEqual(len(bad), 2, bad)

    def test_repo_library_is_valid(self):
        self.assertEqual(lib.check(REPO / 'library'), [])


if __name__ == '__main__':
    unittest.main()
