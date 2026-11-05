"""scripts/source_info.py, which the NXForge Converter runs on a game it needs no keys for: a NUP (the file, or a folder holding one) and a dump folder are each described from their index and a
few small files; a folder of NSPs, or of nothing, is refused. The NUPs are written as test_nsp_nup.py writes them."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(REPO / 'scripts'))
import source_info  # pyright: ignore[reportMissingImports]  # scripts/ is on sys.path above
import test_nsp_nup as t


def nso(flags):   # an NSO header, flags at 0x0C
    return b'NSO0' + struct.pack('<III', 0, 0, flags) + b'\0' * 0x100


@unittest.skipIf(t.zstd is None, 'no zstd module')
class Nup(unittest.TestCase):
    def setUp(self):
        td = tempfile.TemporaryDirectory(); self.addCleanup(td.cleanup)
        self.dir = Path(td.name).resolve() / 'game'; self.dir.mkdir()
        self.path = self.dir / 'Test Game [040074A01BF12000][v458752].nup'

    def write(self, main=b'code', base=True):
        pk = [(1, t.TID, t.VER, t.version(main=main, marker='new'), b''), (2, t.TID + 0x1001, 0, {'romfs': {'dlcfile': b'dlc'}}, b'')]
        if base: pk.insert(0, (0, t.TID, 0, t.version(marker='old'), t.META))
        t.write_nup(self.path, pk, update_flags=0 if base else 1)

    def test_file_and_folder(self):
        self.write(main=nso(0x80))
        for p in (self.path, self.dir):
            with self.subTest(p=p.name):
                i = source_info.info(p)
                self.assertEqual((i['kind'], i['source'], i['folder'], i['title_id']), ('nup', str(self.path), str(self.dir), '040074A01BF12000'))
                self.assertEqual((i['base'], i['updates'], i['dlc'], i['name']), (True, [t.VER], 1, 'Test Game'))
                self.assertTrue(i['zbic'])
                self.assertEqual(i['romfs_bytes'], 400)   # the update's own RomFS: dir/new and the empty file
                self.assertEqual(i['file_bytes'], self.path.stat().st_size)
                self.assertIsNotNone(i['profile'])   # TID has a profile in dm/games

    def test_lz4_code_needs_no_zbic(self):
        self.write(main=nso(0x07))
        self.assertFalse(source_info.info(self.path)['zbic'])

    def test_no_base_is_noted(self):
        self.write(base=False)
        i = source_info.info(self.path)
        self.assertFalse(i['base'])
        self.assertIn('no base game', i['notes'][0])

    def test_packages_win_over_the_nup(self):
        self.write()
        (self.dir / 'game.nsp').write_bytes(b'x')
        with self.assertRaisesRegex(source_info.Fail, 'prod.keys'): source_info.info(self.dir)
        self.assertEqual(source_info.info(self.path)['kind'], 'nup')   # the file itself is still a NUP

    def test_two_nups_ask_for_the_file(self):
        self.write()
        (self.dir / 'other.nup').write_bytes(self.path.read_bytes())
        with self.assertRaisesRegex(source_info.Fail, 'more than one NUP'): source_info.info(self.dir)

    def test_command_line(self):
        self.write()
        r = subprocess.run([sys.executable, str(REPO / 'scripts/source_info.py'), str(self.path)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)['title_id'], '040074A01BF12000')
        r = subprocess.run([sys.executable, str(REPO / 'scripts/source_info.py'), str(self.dir / 'missing')], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn('no such file', json.loads(r.stdout)['error'])


class Dump(unittest.TestCase):
    def test_dump_folder(self):
        with tempfile.TemporaryDirectory() as td:
            d = Path(td).resolve() / 'Game'
            for sub, main in (('base', nso(0x07)), (f'updates/{t.VER}', nso(0x87))):
                (d / sub / 'exefs').mkdir(parents=True); (d / sub / 'romfs').mkdir()
                (d / sub / 'exefs/main').write_bytes(main); (d / sub / 'exefs/main.npdm').write_bytes(t.npdm(t.TID))
                (d / sub / 'romfs/file').write_bytes(b'x' * 1000)
            i = source_info.info(d)
            self.assertEqual((i['kind'], i['source'], i['folder'], i['title_id'], i['base'], i['updates'], i['dlc']), ('dump', str(d), str(d), '040074A01BF12000', True, [t.VER], 0))
            self.assertTrue(i['zbic'])   # the newest version's main module
            self.assertEqual(i['romfs_bytes'], 1000)

    def test_empty_folder_refused(self):
        with tempfile.TemporaryDirectory() as td, self.assertRaisesRegex(source_info.Fail, 'neither'): source_info.info(Path(td))


if __name__ == '__main__':
    unittest.main()
