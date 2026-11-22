"""scripts/gba_build.py, which converts a Game Boy Advance game (gba/README.md): what it reads from a cartridge's header, the title ID and name it gives the game, and the
entry points it keeps between conversions. The cartridges here are made up: a header and nothing else."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))
import gba_build  # pyright: ignore[reportMissingImports]  # scripts/ is on sys.path above


def cart(title=b'GBAZELDA MC', code=b'BZMP', maker=b'01', version=0):
    rom = bytearray(0x200)
    rom[0xA0:0xA0 + len(title)] = title
    rom[0xAC:0xB0] = code
    rom[0xB0:0xB2] = maker
    rom[0xB2] = 0x96
    rom[0xBC] = version
    rom[0xBD] = (-(sum(rom[0xA0:0xBD]) + 0x19)) & 0xFF
    return bytes(rom)


class Header(unittest.TestCase):
    def test_fields_and_checksum(self):
        h = gba_build.header(cart())
        self.assertEqual((h['title'], h['code'], h['maker'], h['version']), ('GBAZELDA MC', 'BZMP', '01', 0))
        self.assertTrue(h['checksum_ok'] and h['fixed_ok'])
        bad = bytearray(cart()); bad[0xA0] ^= 1
        self.assertFalse(gba_build.header(bytes(bad))['checksum_ok'])

    def test_too_short_is_refused(self):
        with self.assertRaises(gba_build.Stop):
            gba_build.header(b'\0' * 0x40)

    def test_title_id(self):
        self.assertEqual(gba_build.title_id(gba_build.header(cart())), '0BA0425A4D500000')
        self.assertEqual(gba_build.title_id(gba_build.header(cart(code=b'AKRP', version=1))), '0BA0414B52500100')
        self.assertEqual(len(gba_build.title_id(gba_build.header(cart(code=b'\0\0\0\0')))), 16)   # a homebrew cartridge with no code


class Names(unittest.TestCase):
    def test_no_intro_names(self):
        for file, name in [('Legend of Zelda, The - The Minish Cap (Europe) (En,Fr,De,Es,It).gba', 'The Legend of Zelda - The Minish Cap'),
                           ('Kurukuru Kururin (Europe).zip', 'Kurukuru Kururin'),
                           ('Advance Wars (USA) (Rev 1).gba', 'Advance Wars'),
                           ('Incredibles, The (USA) [b].gba', 'The Incredibles'),
                           ('(Europe).gba', 'Game')]:
            self.assertEqual(gba_build.clean_name(file), name)


class Reading(unittest.TestCase):
    def test_zip_and_plain(self):
        with tempfile.TemporaryDirectory() as d:
            plain = os.path.join(d, 'a.gba')
            Path(plain).write_bytes(cart())
            z = os.path.join(d, 'a.zip')
            with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as f:
                f.writestr('Inner Name (Europe).gba', cart())
            self.assertEqual(gba_build.read_rom(plain), (cart(), 'a.gba'))
            self.assertEqual(gba_build.read_rom(z), (cart(), 'Inner Name (Europe).gba'))
            empty = os.path.join(d, 'e.zip')
            with zipfile.ZipFile(empty, 'w') as f:
                f.writestr('readme.txt', 'x')
            with self.assertRaises(gba_build.Stop):
                gba_build.read_rom(empty)

    def test_info_line(self):
        """--info is what the app lists a game from: one JSON line, no engine needed."""
        with tempfile.TemporaryDirectory() as d:
            z = os.path.join(d, 'Kurukuru Kururin (Europe).zip')
            with zipfile.ZipFile(z, 'w') as f:
                f.writestr('Kurukuru Kururin (Europe).gba', cart(title=b'KURURIN', code=b'AKRP'))
            r = subprocess.run([sys.executable, str(REPO / 'scripts/gba_build.py'), z, '--info'], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            j = json.loads(r.stdout.strip().splitlines()[-1])
            self.assertEqual(len(r.stdout.strip().splitlines()), 1)
            self.assertEqual((j['code'], j['titleID'], j['name']), ('AKRP', '0BA0414B52500000', 'Kurukuru Kururin'))


if __name__ == '__main__':
    unittest.main()
