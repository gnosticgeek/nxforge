#!/usr/bin/env python3
# What the NXForge Converter shows about a game it needs no keys for: a NUP container (a .nup file, or a folder holding one and no game package) or a dump folder (scripts/pack_dump.py's
# layout), the two ways Switch 2 games come. Reads only the container's index and a few small files (main.npdm, the main module's NSO header, the NACP); nothing is unpacked.
# Prints one JSON object: {"kind": "nup" | "dump", "source": the path to give build_ipa_from_nsp.py, "folder": where <title ID>_build and the app go, "title_id", "name", "base": bool,
#   "updates": [versions], "dlc": count, "romfs_bytes": the newest version's RomFS, uncompressed, "file_bytes": the .nup's size or the dump's files (a dump's two are -1 with NXF_SOURCE_SIZES=0, the quick read), "zbic": whether the newest main module
#   has ZBIC segments (system 22.0.0 on: needs the zbic package), "zbic_installed", "profile": the dm/games profile's name or null, "notes": [...]}
# Exit 1 with {"error": "..."} when the path is neither (a folder of NSPs is the Converter's own check, with prod.keys).
# Usage: source_info.py <game.nup | folder>
import json, os, struct, sys
from pathlib import Path
from typing import Any

repo = Path(__file__).resolve().parents[1]
engine = repo / 'tree' if (repo / 'layer/ENGINE').is_file() else repo   # the assembled engine (scripts/layer.py) from 0.19.0
sys.path.insert(0, str(engine / 'scripts')); sys.path.insert(0, str(engine / 'dm/tools')); sys.path.insert(0, str(engine / 'dm/games'))
import pack_dump, pack_nup   # noqa: E402  # pyright: ignore[reportMissingImports]  # the engine's dm/tools, on sys.path above

PACKAGE_SUFFIXES = ('.nsp', '.xci', '.nsz', '.xcz')   # build_ipa_from_nsp.py's: a folder with any of these is a folder of game packages, read with prod.keys


class Fail(Exception): pass


def packages_in(folder):
    return [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in PACKAGE_SUFFIXES]


def nup_of(path):   # build_ipa_from_nsp.nup_file without the script's imports
    if path.is_file():
        if not pack_nup.is_nup(path): raise Fail(f'not a NUP file: {path.name}')
        return path
    if packages_in(path): return None
    nups = [p for p in sorted(path.iterdir()) if p.is_file() and p.suffix.lower() == '.nup' and pack_nup.is_nup(p)]
    if len(nups) > 1: raise Fail(f'more than one NUP in {path}: {", ".join(p.name for p in nups)}; keep one game per folder, or choose the .nup file itself')
    return nups[0] if nups else None


def zbic_flag(head):   # NSO flags (0x0C) bit 7: its compressed segments are ZBIC
    return len(head) >= 0x10 and head[:4] == b'NSO0' and bool(struct.unpack_from('<I', head, 0x0C)[0] & 0x80)


def profile_name(tid):
    try:
        import game  # pyright: ignore[reportMissingImports]  # the engine's dm/games
        g = game.by_title(tid)
        return (g.get('name') or g.id) if g else None
    except Exception: return None   # a profile that does not load is the build's to report


def nacp_name(data):
    if not data: return ''
    import nacp, tempfile  # pyright: ignore[reportMissingImports]  # the engine's dm/tools
    with tempfile.NamedTemporaryFile(suffix='.nacp') as f:
        f.write(data); f.flush()
        return nacp.name(f.name)


def from_nup(path):
    with pack_nup.Nup(path) as n:
        app, base, vers, dlc = pack_nup.scan(n)
        k = vers[max(vers)] if vers else base
        if k is None: raise Fail(f'{path.name}: no base game and no update')
        notes = [] if base is not None else [pack_nup.NO_BASE]
        try: romfs = n.tree_bytes(pack_nup.romfs_of(k, base))
        except pack_nup.Error as e: romfs = 0; notes.append(str(e))
        main = n.child(k.exefs, b'main') if k.exefs != pack_nup.NO_DIR else None
        zb = False
        if main is not None:   # Nup.head reads only the first bytes; an older pack_nup without it reads the module
            head = getattr(n, 'head', None)
            zb = zbic_flag(head(main, 0x10) if head else n.read(main)[:0x10])
        meta = pack_nup.app_package(n).meta() if base is None else base.meta()
        meta.update(k.meta())
        name = nacp_name(meta.get(pack_nup.T_NACP))
        return dict(kind='nup', source=str(path), folder=str(path.parent), title_id=f'{app:016X}', name=name, base=base is not None, updates=sorted(vers), dlc=len(dlc),
                    romfs_bytes=romfs, file_bytes=path.stat().st_size, zbic=zb, notes=notes)


def tree_bytes(d, inner=()):
    """The size of the files under d, and of each folder in inner that sits under it, in one walk: {d: bytes, inner folder: bytes}. On macOS
    one getattrlistbulk call per folder gives every entry's size with the folder's listing, so there is no stat per file: Mario Kart World's
    dump (411,696 files) on an exFAT drive took over five minutes of os.lstat and takes 18 s. Elsewhere, os.scandir and a stat per file."""
    want = {str(Path(i)): 0 for i in inner}
    walk = _bulk_walk if sys.platform == 'darwin' and _bulk() else _scandir_walk
    try: total = walk(str(d), want)
    except OSError:
        want = {k: 0 for k in want}; total = _scandir_walk(str(d), want)
    return {str(d): total, **want}


def _scandir_walk(d, want):
    total = 0
    try: entries = list(os.scandir(d))
    except OSError: return 0
    for e in entries:
        try:
            if e.is_dir(follow_symlinks=False): total += _scandir_walk(e.path, want)
            elif e.is_file(follow_symlinks=False): total += e.stat(follow_symlinks=False).st_size   # regular files only, as getattrlistbulk counts
        except OSError: pass
    if d in want: want[d] = total
    return total


_libc = None


def _bulk():
    global _libc
    if _libc is None:
        try:
            import ctypes
            lib = ctypes.CDLL(None, use_errno=True)
            f = lib.getattrlistbulk
            f.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint64]
            f.restype = ctypes.c_int
            _libc = (ctypes, f)
        except (OSError, AttributeError): _libc = False
    return _libc


# <sys/attr.h>: the entry's returned-attributes set, its name and type; a file's data length
_ATTR_CMN_NAME, _ATTR_CMN_OBJTYPE, _ATTR_CMN_RETURNED_ATTRS, _ATTR_FILE_DATALENGTH = 0x1, 0x8, 0x80000000, 0x200
_VREG, _VDIR = 1, 2


def _bulk_walk(d, want):
    ctypes, getattrlistbulk = _bulk()
    al = struct.pack('<HHIIIII', 5, 0, _ATTR_CMN_RETURNED_ATTRS | _ATTR_CMN_NAME | _ATTR_CMN_OBJTYPE, 0, 0, _ATTR_FILE_DATALENGTH, 0)
    alist = ctypes.create_string_buffer(al, len(al))
    buf = ctypes.create_string_buffer(256 * 1024)

    def walk(fd, path):
        total = 0
        while True:
            n = getattrlistbulk(fd, alist, buf, len(buf), 0)
            if n < 0: raise OSError(ctypes.get_errno(), f'getattrlistbulk: {path}')
            if n == 0: break
            raw = buf.raw; p = 0
            for _ in range(n):
                length, = struct.unpack_from('<I', raw, p)
                file_set, = struct.unpack_from('<I', raw, p + 16)   # attribute_set_t: common, vol, dir, file, fork
                off, nlen = struct.unpack_from('<iI', raw, p + 24)
                name = raw[p + 24 + off:p + 24 + off + nlen].rstrip(b'\0')
                kind, = struct.unpack_from('<I', raw, p + 32)
                if kind == _VREG and file_set & _ATTR_FILE_DATALENGTH: total += struct.unpack_from('<q', raw, p + 36)[0]
                elif kind == _VDIR:
                    sub = os.path.join(path, os.fsdecode(name))
                    try: cfd = os.open(name, os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
                    except OSError: pass
                    else:
                        try: total += walk(cfd, sub)
                        finally: os.close(cfd)
                p += length
        if path in want: want[path] = total
        return total

    fd = os.open(d, os.O_RDONLY | os.O_DIRECTORY)
    try: return walk(fd, d)
    finally: os.close(fd)


def from_dump(folder):
    try: app, vers, dlc = pack_dump.scan(folder)
    except pack_dump.Error as e: raise Fail(str(e)) from None
    base_of = getattr(pack_dump, 'base_of', None)   # the newer layout, where the folder may be the version itself
    base = base_of(folder) if base_of else folder / 'base' if (folder / 'base/exefs/main.npdm').is_file() else None
    v = vers[max(vers)] if vers else base
    if v is None: raise Fail(f'{folder.name}: no base game and no update')
    romfs = v / 'romfs' if (v / 'romfs').is_dir() else base / 'romfs' if base else None
    main = v / 'exefs/main'
    zb = False
    if main.is_file():
        with open(main, 'rb') as f: zb = zbic_flag(f.read(0x10))
    if os.environ.get('NXF_SOURCE_SIZES') == '0': romfs_bytes = file_bytes = -1   # the Converter's first, quick read: sizes come in a second one
    else:   # one walk of the folder gives both when the RomFS is inside it, as it is in a dump
        inside = romfs is not None and folder.resolve() in romfs.resolve().parents
        sizes = tree_bytes(folder, [romfs] if inside else [])
        file_bytes = sizes[str(folder)]
        romfs_bytes = sizes[str(romfs)] if inside else tree_bytes(romfs)[str(romfs)] if romfs else 0
    return dict(kind='dump', source=str(folder), folder=str(folder), title_id=f'{app:016X}', name='', base=base is not None, updates=sorted(vers), dlc=len(dlc),
                romfs_bytes=romfs_bytes, file_bytes=file_bytes, zbic=zb, notes=[])


def info(path):
    path = path.expanduser().resolve()
    if not path.exists(): raise Fail(f'no such file or folder: {path}')
    try:
        nup = nup_of(path); out: dict[str, Any]
        if nup: out = from_nup(nup)
        elif path.is_dir() and not packages_in(path) and pack_dump.is_dump(path): out = from_dump(path)
        elif path.is_dir() and packages_in(path): raise Fail('a folder of game packages (.nsp, .xci): it is checked with prod.keys')
        else: raise Fail(f'neither a NUP nor a dump folder: {path}')
    except (pack_nup.Error, pack_dump.Error, OSError) as e: raise Fail(str(e)) from None
    out['profile'] = profile_name(int(out['title_id'], 16))
    try: import zbic  # noqa: F401  # pyright: ignore[reportMissingImports]
    except ImportError: out['zbic_installed'] = False
    else: out['zbic_installed'] = True
    return out


def main():
    if len(sys.argv) != 2: print('usage: source_info.py <game.nup | folder>', file=sys.stderr); sys.exit(2)
    try: print(json.dumps(info(Path(sys.argv[1]))))
    except Fail as e: print(json.dumps({'error': str(e)})); sys.exit(1)


if __name__ == '__main__':
    main()
