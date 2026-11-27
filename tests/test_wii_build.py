"""scripts/wii_build.py, which makes a Mac app for a Wii or GameCube game (wii/README.md): what it reads from a disc image's header in each
image format, and the title ID and name it gives the game. The discs here are made up: a header and nothing else."""
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))
import wii_build  # pyright: ignore[reportMissingImports]  # scripts/ is on sys.path above


def disc(game_id=b'RTZE08', title=b'Zack and Wiki', wii=True, version=0):
    h = bytearray(0x400)
    h[0:6] = game_id
    h[7] = version
    if wii:
        h[0x18:0x1C] = struct.pack('>I', wii_build.WII_MAGIC)
    else:
        h[0x1C:0x20] = struct.pack('>I', wii_build.GC_MAGIC)
    h[0x20:0x20 + len(title)] = title
    return bytes(h)


class Formats(unittest.TestCase):
    def write(self, name, data):
        d = tempfile.mkdtemp()
        p = os.path.join(d, name)
        with open(p, 'wb') as f:
            f.write(data)
        return p

    def test_iso(self):
        i = wii_build.read_disc(self.write('Zack & Wiki (USA).iso', disc()))
        self.assertEqual((i['platform'], i['id'], i['title'], i['form']), ('wii', 'RTZE08', 'Zack and Wiki', 'disc'))

    def test_rvz_and_wia_keep_a_copy(self):
        for magic in (b'RVZ\x01', b'WIA\x01'):
            data = magic + bytes(0x54) + disc(b'GALE01', b'Melee', wii=False)
            i = wii_build.read_disc(self.write('Melee.rvz', data))
            self.assertEqual((i['platform'], i['id']), ('gamecube', 'GALE01'))

    def test_wbfs_and_ciso(self):
        i = wii_build.read_disc(self.write('a.wbfs', b'WBFS' + bytes(0x1FC) + disc(b'RK5E01')))
        self.assertEqual(i['id'], 'RK5E01')
        i = wii_build.read_disc(self.write('a.ciso', b'CISO' + bytes(0x7FFC) + disc(b'R7PE01')))
        self.assertEqual(i['id'], 'R7PE01')

    def test_gcz_compressed_first_block(self):
        block = zlib.compress(disc(b'GZ2E01', b'Twilight Princess', wii=False) + bytes(0x3C00))
        head = struct.pack('<IIQQII', 0xB10BC001, 0, len(block), 0x4000, 0x4000, 1) + struct.pack('<Q', 0) + struct.pack('<I', 0)
        i = wii_build.read_disc(self.write('tp.gcz', head + block + bytes(0x200)))
        self.assertEqual((i['platform'], i['id']), ('gamecube', 'GZ2E01'))

    def test_zip_holding_a_disc(self):
        import zipfile
        d = tempfile.mkdtemp()
        p = os.path.join(d, 'Elebits (USA).zip')
        with zipfile.ZipFile(p, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('Elebits (USA).rvz', b'RVZ\x01' + bytes(0x54) + disc(b'RELEA4', b'Elebits') + bytes(0x1000))
        i = wii_build.read_disc(p)
        self.assertEqual((i['id'], i['form']), ('RELEA4', 'disc in a zip'))
        self.assertEqual(wii_build.zip_member(p).filename, 'Elebits (USA).rvz')

    def test_wad_id_from_its_tmd(self):
        w = bytearray(0xC0 + 0x200)
        w[0:24] = struct.pack('>IIIIII', 0x20, 0, 0x40, 0, 0x40, 0x200)
        w[0xC0 + 0x18C + 4:0xC0 + 0x18C + 8] = b'WR9E'
        w[0xC0 + 0x18C + 12:0xC0 + 0x18C + 14] = b'08'
        i = wii_build.read_disc(self.write('Mega Man 9 (USA) (WiiWare).wad', bytes(w)))
        self.assertEqual((i['id'], i['form']), ('WR9E08', 'WiiWare'))

    def test_not_a_disc(self):
        with self.assertRaises(wii_build.Stop):
            wii_build.read_disc(self.write('notes.iso', bytes(0x400)))

    def test_homebrew_by_name(self):
        i = wii_build.read_disc(self.write('Snake (homebrew).dol', b'\0' * 64))
        self.assertEqual((i['form'], i['title']), ('homebrew', 'Snake'))


class Names(unittest.TestCase):
    def test_title_id(self):
        self.assertEqual(wii_build.title_id(dict(platform='wii', id='RTZE08')), '0E0052545A453038')
        self.assertEqual(wii_build.title_id(dict(platform='gamecube', id='GALE01')), '0C0047414C453031')

    def test_clean_name(self):
        self.assertEqual(wii_build.clean_name("Zack & Wiki - Quest for Barbaros' Treasure (USA).rvz"), "Zack & Wiki - Quest for Barbaros' Treasure")
        self.assertEqual(wii_build.clean_name('Legend of Zelda, The - Twilight Princess (USA).iso'), 'The Legend of Zelda - Twilight Princess')


if __name__ == '__main__':
    unittest.main()
