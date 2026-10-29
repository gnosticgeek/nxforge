"""NSP script: scan_nsps takes a file as a game package only when its header is one nx_extract opens (PFS0 at 0, or an XCI's HEAD at 0x100), whatever its name says: title_of falls
back to the name's [title ID], so a tagged file that is not a package would count as one. No game files or keys needed."""
import importlib.util
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', REPO / 'scripts/build_ipa_from_nsp.py')
if spec is None or spec.loader is None: raise ImportError('scripts/build_ipa_from_nsp.py')
nsp = importlib.util.module_from_spec(spec); spec.loader.exec_module(nsp)

APP = 0x010020D01AD24000


def pfs0(path, names):   # a PFS0 holding empty files with these names (enough for title_of)
    strs = b''.join(n.encode() + b'\0' for n in names); ent, o = b'', 0
    for n in names: ent += struct.pack('<QQII', 0, 0, o, 0); o += len(n) + 1
    path.write_bytes(b'PFS0' + struct.pack('<III', len(names), len(strs), 0) + ent + strs)


HEADER_KEY = bytes(range(32))


def nca(tid, kind=0):   # an NCA header naming this title and content type (0 Program, 1 Meta), encrypted as a console does: AES-128-XTS, 0x200-byte sectors, the sector number big-endian as the tweak
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    h = bytearray(0x400); h[0x200:0x204] = b'NCA3'; h[0x205] = kind; struct.pack_into('<Q', h, 0x210, tid)
    out = b''
    for sec in range(2):
        e = Cipher(algorithms.AES(HEADER_KEY), modes.XTS(sec.to_bytes(16, 'big'))).encryptor()
        out += e.update(bytes(h[sec * 0x200:(sec + 1) * 0x200])) + e.finalize()
    return out


def hfs0(files):   # an HFS0 partition holding these (name, data) files
    strs = b''.join(n.encode() + b'\0' for n, _ in files); ent, o, so = b'', 0, 0
    for n, d in files: ent += struct.pack('<QQII', o, len(d), so, 0) + bytes(0x28); o += len(d); so += len(n) + 1
    return b'HFS0' + struct.pack('<III', len(files), len(strs), 0) + ent + strs + b''.join(d for _, d in files)


def xci(path, tids, ncas=()):   # a cartridge dump: card header (HEAD at 0x100, root partition offset at 0x130), root HFS0 with a secure partition holding one NCA per title, then ncas: (title, type, body size)
    secure = hfs0([(f'{i:032x}.cnmt.nca', nca(t)) for i, t in enumerate(tids)] + [(f'{i:032x}.nca', nca(t, k) + bytes(n)) for i, (t, k, n) in enumerate(ncas, len(tids))])
    head = bytearray(0x200); head[0x100:0x104] = b'HEAD'; struct.pack_into('<Q', head, 0x130, 0x200)
    path.write_bytes(bytes(head) + hfs0([('update', b''), ('secure', secure)]))


class Scan(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()); self.addCleanup(shutil.rmtree, self.tmp)
        self.said = []
        cm = mock.patch.object(nsp, 'say', self.said.append); cm.__enter__(); self.addCleanup(cm.__exit__, None, None, None)

    def test_only_packages_count(self):
        base = self.tmp / f'Game [{APP:016X}][v0].xci'; base.write_bytes(bytes(0x100) + b'HEAD' + bytes(0x100))   # a cartridge dump: no ticket, the name's tag
        upd = self.tmp / f'Update [{APP | 0x800:016X}].nsp'; pfs0(upd, [])
        page = self.tmp / f'Update [{APP | 0x800:016X}] (1).nsp'; page.write_bytes(b'<!DOCTYPE html><title>404</title>')   # a failed download saved under the game's name
        short = self.tmp / f'DLC [{APP + 0x1001:016X}].xci'; short.write_bytes(b'\0' * 0x80)   # cut off before the card header
        app, fam = nsp.scan_nsps(self.tmp)
        self.assertEqual(app, APP)
        self.assertEqual(fam['base'], base)
        self.assertEqual([p for _, p in fam['updates']], [upd])   # with the page the untagged update was one of two and left out
        self.assertEqual(fam['dlc'], [])
        self.assertEqual(sorted(m.split(':')[0] for m in self.said), sorted(f'skipping {p.name}' for p in (page, short)))

    def test_appledouble_skipped_quietly(self):
        base = self.tmp / f'Game [{APP:016X}][v0].nsp'; pfs0(base, [f'{APP:016x}0000000000000011.tik'])
        (self.tmp / ('._' + base.name)).write_bytes(b'\0\x05\x16\x07' + b'\0' * 4092)
        self.assertEqual(nsp.scan_nsps(self.tmp)[1]['base'], base)
        self.assertEqual(self.said, [])

    @unittest.skipUnless(importlib.util.find_spec('cryptography'), 'needs the cryptography module to make the test cartridge')
    def test_untagged_xci_titled_from_its_ncas(self):   # Game.XCI: no ticket, no tags, upper-case extension, the update on the cartridge too (1G+1U)
        keys = self.tmp / 'prod.keys'; keys.write_text(f'header_key = {HEADER_KEY.hex()}\n')
        base = self.tmp / 'Game.XCI'; xci(base, [APP | 0x800, APP])
        self.assertEqual(nsp.xci_title(base, keys), APP)
        app, fam = nsp.scan_nsps(self.tmp, keys)
        self.assertEqual((app, fam['base']), (APP, base))


    @unittest.skipUnless(importlib.util.find_spec('cryptography'), 'needs the cryptography module to make the test cartridge')
    def test_cartridge_with_two_applications_gives_the_larger_program(self):   # Castlevania: Belmont's Curse's Midnight Edition: the game and its gallery, the gallery's title ID lower
        keys = self.tmp / 'prod.keys'; keys.write_text(f'header_key = {HEADER_KEY.hex()}\n')
        gallery, game = 0x01005F4027E94000, 0x0100BA4026E94000
        base = self.tmp / 'Game.xci'; xci(base, [], [(gallery, 1, 0), (gallery, 0, 0x200), (game, 1, 0), (game, 2, 0x800), (game, 0, 0x400)])
        self.assertEqual(nsp.xci_title(base, keys), game)
        self.assertEqual(nsp.title_opt(base, keys), ['--title', f'{game:016x}'])
        self.assertEqual(nsp.title_opt(self.tmp / 'Game.nsp', keys), [])


if __name__ == '__main__':
    unittest.main()
