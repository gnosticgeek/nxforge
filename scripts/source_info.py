#!/usr/bin/env python3
# What the NXForge Converter shows about a game it needs no keys for: a NUP container (a .nup file, or a folder holding one and no game package) or a dump folder (scripts/pack_dump.py's
# layout), the two ways Switch 2 games come. Reads only the container's index and a few small files (main.npdm, the main module's NSO header, the NACP); nothing is unpacked.
# Prints one JSON object: {"kind": "nup" | "dump", "source": the path to give build_ipa_from_nsp.py, "folder": where <title ID>_build and the app go, "title_id", "name", "base": bool,
#   "updates": [versions], "dlc": count, "romfs_bytes": the newest version's RomFS, uncompressed, "file_bytes": the .nup's size or the dump's files, "zbic": whether the newest main module
#   has ZBIC segments (system 22.0.0 on: needs the zbic package), "zbic_installed", "profile": the dm/games profile's name or null, "notes": [...]}
# Exit 1 with {"error": "..."} when the path is neither (a folder of NSPs is the Converter's own check, with prod.keys).
# Usage: source_info.py <game.nup | folder>
import json, os, struct, sys
from pathlib import Path
from typing import Any

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here)); sys.path.insert(0, str(repo / 'dm/tools')); sys.path.insert(0, str(repo / 'dm/games'))
import pack_dump, pack_nup   # noqa: E402

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
        import game
        g = game.by_title(tid)
        return (g.get('name') or g.id) if g else None
    except Exception: return None   # a profile that does not load is the build's to report


def nacp_name(data):
    if not data: return ''
    import nacp, tempfile
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


def tree_bytes(d):
    total = 0
    for root, _, files in os.walk(d):
        for f in files:
            try: total += os.lstat(os.path.join(root, f)).st_size
            except OSError: pass
    return total


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
    return dict(kind='dump', source=str(folder), folder=str(folder), title_id=f'{app:016X}', name='', base=base is not None, updates=sorted(vers), dlc=len(dlc),
                romfs_bytes=tree_bytes(romfs) if romfs else 0, file_bytes=tree_bytes(folder), zbic=zb, notes=[])


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
