"""NSP script (NXForge): a game folder's DLC/ subfolder, any letter case. scan_nsps reads its packages for DLC only: a base game or update there is reported and not used.
A Switch 2 dump's DLC/ is found in any letter case too (pack_dump.scan). No game files or keys needed."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from test_nsp_external_drive import nsp, pfs0, meta, fake_contents, APP   # noqa: E402

REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location('pack_dump', REPO / 'scripts/pack_dump.py')
if spec is None or spec.loader is None: raise ImportError('scripts/pack_dump.py')
pack_dump = importlib.util.module_from_spec(spec); spec.loader.exec_module(pack_dump)


class DlcFolder(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()); self.addCleanup(shutil.rmtree, self.tmp)
        self.said = []
        cm = mock.patch.object(nsp, 'say', self.said.append); cm.__enter__(); self.addCleanup(cm.__exit__, None, None, None)
        self.base = self.tmp / 'Game.nsp'; pfs0(self.base, [meta(APP)])

    def test_dlc_subfolder_any_case(self):
        for name in ('DLC', 'dlc', 'Dlcs'):
            with self.subTest(name=name):
                d = self.tmp / name; d.mkdir()
                a = d / 'Pack 1.nsp'; pfs0(a, [meta(APP + 0x1001)])
                b = d / 'Pack 2.NSZ'; pfs0(b, [meta(APP + 0x1002, 65536)])
                app, fam = nsp.scan_nsps(self.tmp, fake_contents)
                self.assertEqual(app, APP)
                self.assertEqual(fam['base'], self.base)
                self.assertEqual(fam['dlc'], [(APP + 0x1001, 0, a), (APP + 0x1002, 65536, b)])
                shutil.rmtree(d)

    def test_other_subfolders_ignored(self):
        d = self.tmp / 'Extras'; d.mkdir(); pfs0(d / 'Pack.nsp', [meta(APP + 0x1001)])
        self.assertEqual(nsp.scan_nsps(self.tmp, fake_contents)[1]['dlc'], [])

    def test_base_or_update_in_dlc_folder_not_used(self):
        d = self.tmp / 'DLC'; d.mkdir()
        pfs0(d / 'Other game.nsp', [meta(0x0100000000010000)])
        pfs0(d / 'Update.nsp', [meta(APP | 0x800, 65536)])
        merged = d / 'Update + DLC.nsp'; pfs0(merged, [meta(APP | 0x800, 131072), meta(APP + 0x1003)])
        app, fam = nsp.scan_nsps(self.tmp, fake_contents)   # without the filter: more than one game
        self.assertEqual(app, APP)
        self.assertEqual(fam['updates'], [])
        self.assertEqual(fam['dlc'], [(APP + 0x1003, 0, merged)])
        self.assertTrue(any('not used' in s and 'Other game.nsp' in s for s in self.said))

    def test_dump_dlc_folder_any_case(self):
        dump = self.tmp / 'dump'
        (dump / 'base/exefs').mkdir(parents=True); (dump / 'base/romfs').mkdir(); (dump / 'base/exefs/main.npdm').write_bytes(b'')
        tid = APP + 0x1001
        (dump / 'DLC' / f'{tid:016X}' / '0' / 'romfs').mkdir(parents=True)
        with mock.patch.object(pack_dump, 'program_id', return_value=APP):
            app, _, dlc = pack_dump.scan(dump)
        self.assertEqual(app, APP)
        self.assertEqual(dlc, {tid: dump / 'DLC' / f'{tid:016X}' / '0' / 'romfs'})


if __name__ == '__main__':
    unittest.main()
